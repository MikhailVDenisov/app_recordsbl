import "dotenv/config";
import cors from "@fastify/cors";
import Fastify from "fastify";
import { z } from "zod";
import { query } from "./db.js";
import {
  buildObjectKey,
  completeMultipartUpload,
  createMultipartUpload,
  listParts,
  presignUploadPart,
  putJsonSidecar,
} from "./s3.js";

const app = Fastify({ logger: true });

await app.register(cors, { origin: true });

const deviceInfoSchema = z.object({
  model: z.string().optional(),
  freeDiskBytes: z.number().optional(),
  login: z.string().min(1),
});

const recognitionMetaSchema = z.object({
  id: z.string().uuid(),
  meetingPlace: z.string(),
  startTimestamp: z.string(),
  durationSeconds: z.number().nonnegative(),
  recordingStartOffsetMs: z.number().nonnegative(),
});

const registerBody = z.object({
  id: z.string().uuid(),
  userLogin: z.string().min(1).regex(/^[a-zA-Z0-9._@-]+$/),
  device: deviceInfoSchema,
  recognition: recognitionMetaSchema,
  fileName: z.string().default("recording.flac"),
  fileSizeBytes: z.number().positive(),
  contentType: z.string().default("audio/flac"),
});

app.get("/health", async () => ({ ok: true }));

/** Step 1: register meeting + init multipart on S3 (идемпотентно по id) */
app.post("/api/v1/meetings/register", async (req, reply) => {
  const body = registerBody.safeParse(req.body);
  if (!body.success) {
    return reply.code(400).send({ error: body.error.flatten() });
  }
  const b = body.data;
  const key = buildObjectKey(b.id, b.fileName);
  const metaKey = buildObjectKey(b.id, "metadata.json");

  const existing = await query<{
    s3_key: string | null;
    upload_id: string | null;
  }>(`SELECT s3_key, upload_id FROM meetings WHERE id = $1`, [b.id]);

  let uploadId: string;
  let s3KeyOut = key;

  if (existing.rows.length > 0 && existing.rows[0].upload_id) {
    uploadId = existing.rows[0].upload_id!;
    s3KeyOut = existing.rows[0].s3_key ?? key;
  } else {
    const created = await createMultipartUpload(key, b.contentType);
    uploadId = created.uploadId;
    await query(
      `INSERT INTO meetings (
      id, user_id, status, s3_key, upload_id, uploaded_bytes, file_size_bytes,
      meeting_place, duration_seconds, recording_started_at, metadata, device_info
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
    ON CONFLICT (id) DO UPDATE SET
      status = EXCLUDED.status,
      s3_key = COALESCE(meetings.s3_key, EXCLUDED.s3_key),
      upload_id = COALESCE(meetings.upload_id, EXCLUDED.upload_id),
      file_size_bytes = EXCLUDED.file_size_bytes,
      meeting_place = EXCLUDED.meeting_place,
      duration_seconds = EXCLUDED.duration_seconds,
      recording_started_at = EXCLUDED.recording_started_at,
      metadata = EXCLUDED.metadata,
      device_info = EXCLUDED.device_info,
      updated_at = NOW()`,
      [
        b.id,
        b.userLogin,
        "pending",
        key,
        uploadId,
        0,
        b.fileSizeBytes,
        b.recognition.meetingPlace,
        b.recognition.durationSeconds,
        b.recognition.startTimestamp,
        JSON.stringify(b.recognition),
        JSON.stringify({ ...b.device, login: b.device.login }),
      ]
    );
  }

  const sidecar = {
    ...b.recognition,
    userId: b.userLogin,
    device: b.device,
    s3AudioKey: key,
  };
  await putJsonSidecar(metaKey, JSON.stringify(sidecar));

  return {
    meetingId: b.id,
    uploadId,
    s3Key: s3KeyOut,
    metadataKey: metaKey,
  };
});

const partUrlBody = z.object({
  partNumber: z.number().int().min(1).max(10000),
});

app.post("/api/v1/meetings/:id/presign-part", async (req, reply) => {
  const id = z.string().uuid().parse((req.params as { id: string }).id);
  const parsed = partUrlBody.safeParse(req.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: parsed.error.flatten() });
  }
  const { rows } = await query<{ s3_key: string; upload_id: string }>(
    `SELECT s3_key, upload_id FROM meetings WHERE id = $1`,
    [id]
  );
  if (!rows.length || !rows[0].upload_id) {
    return reply.code(404).send({ error: "Meeting not found" });
  }
  const url = await presignUploadPart(
    rows[0].s3_key,
    rows[0].upload_id,
    parsed.data.partNumber
  );
  return { url, partNumber: parsed.data.partNumber };
});

app.get("/api/v1/meetings/:id/parts", async (req, reply) => {
  const id = z.string().uuid().parse((req.params as { id: string }).id);
  const { rows } = await query<{ s3_key: string; upload_id: string }>(
    `SELECT s3_key, upload_id FROM meetings WHERE id = $1`,
    [id]
  );
  if (!rows.length || !rows[0].upload_id) {
    return reply.code(404).send({ error: "Meeting not found" });
  }
  const parts = await listParts(rows[0].s3_key, rows[0].upload_id);
  return { parts };
});

const completeBody = z.object({
  parts: z.array(
    z.object({
      PartNumber: z.number(),
      ETag: z.string(),
    })
  ),
});

app.post("/api/v1/meetings/:id/complete", async (req, reply) => {
  const id = z.string().uuid().parse((req.params as { id: string }).id);
  const parsed = completeBody.safeParse(req.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: parsed.error.flatten() });
  }
  const { rows } = await query<{ s3_key: string; upload_id: string; file_size_bytes: number }>(
    `SELECT s3_key, upload_id, file_size_bytes FROM meetings WHERE id = $1`,
    [id]
  );
  if (!rows.length || !rows[0].upload_id) {
    return reply.code(404).send({ error: "Meeting not found" });
  }
  await completeMultipartUpload(rows[0].s3_key, rows[0].upload_id, parsed.data.parts);
  await query(
    `UPDATE meetings SET status = 'uploaded', uploaded_bytes = $2, updated_at = NOW() WHERE id = $1`,
    [id, rows[0].file_size_bytes ?? 0]
  );
  return { ok: true, status: "uploaded" };
});

const progressBody = z.object({
  uploadedBytes: z.number().nonnegative(),
});

app.patch("/api/v1/meetings/:id/progress", async (req, reply) => {
  const id = z.string().uuid().parse((req.params as { id: string }).id);
  const parsed = progressBody.safeParse(req.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: parsed.error.flatten() });
  }
  await query(
    `UPDATE meetings SET status = 'uploading', uploaded_bytes = $2, updated_at = NOW() WHERE id = $1`,
    [id, parsed.data.uploadedBytes]
  );
  return { ok: true };
});

const statusBody = z.object({
  status: z.enum(["error", "uploading", "pending"]),
  message: z.string().optional(),
});

app.patch("/api/v1/meetings/:id/status", async (req, reply) => {
  const id = z.string().uuid().parse((req.params as { id: string }).id);
  const parsed = statusBody.safeParse(req.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: parsed.error.flatten() });
  }
  await query(
    `UPDATE meetings SET status = $2, metadata = metadata || $3::jsonb, updated_at = NOW() WHERE id = $1`,
    [id, parsed.data.status, JSON.stringify({ lastError: parsed.data.message ?? null })]
  );
  return { ok: true };
});

const port = Number(process.env.PORT ?? 3000);
await app.listen({ port, host: "0.0.0.0" });
