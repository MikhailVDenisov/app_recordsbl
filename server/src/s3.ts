import {
  CompleteMultipartUploadCommand,
  CreateMultipartUploadCommand,
  ListPartsCommand,
  PutObjectCommand,
  S3Client,
  UploadPartCommand,
} from "@aws-sdk/client-s3";
import { NodeHttpHandler } from "@aws-sdk/node-http-handler";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const endpoint = process.env.S3_ENDPOINT;
const region = process.env.S3_REGION ?? "ru-central1";
const bucket = process.env.S3_BUCKET ?? "";

export const s3 = new S3Client({
  region,
  endpoint,
  requestHandler: new NodeHttpHandler({
    connectionTimeout: 5_000,
    socketTimeout: 20_000,
  }),
  credentials: {
    accessKeyId: process.env.S3_ACCESS_KEY_ID ?? "",
    secretAccessKey: process.env.S3_SECRET_ACCESS_KEY ?? "",
  },
  forcePathStyle: false,
});

export function buildObjectKey(meetingId: string, filename: string): string {
  return `meetings/${meetingId}/${filename}`;
}

export async function createMultipartUpload(key: string, contentType: string) {
  const out = await s3.send(
    new CreateMultipartUploadCommand({
      Bucket: bucket,
      Key: key,
      ContentType: contentType,
    })
  );
  return { uploadId: out.UploadId!, key };
}

export async function presignUploadPart(
  key: string,
  uploadId: string,
  partNumber: number
): Promise<string> {
  const cmd = new UploadPartCommand({
    Bucket: bucket,
    Key: key,
    UploadId: uploadId,
    PartNumber: partNumber,
  });
  return getSignedUrl(s3, cmd, { expiresIn: 3600 });
}

export async function listParts(key: string, uploadId: string) {
  const out = await s3.send(
    new ListPartsCommand({
      Bucket: bucket,
      Key: key,
      UploadId: uploadId,
    })
  );
  return (out.Parts ?? []).map((p) => ({
    PartNumber: p.PartNumber!,
    ETag: p.ETag!,
    Size: p.Size ?? 0,
  }));
}

export async function completeMultipartUpload(
  key: string,
  uploadId: string,
  parts: { ETag: string; PartNumber: number }[]
) {
  await s3.send(
    new CompleteMultipartUploadCommand({
      Bucket: bucket,
      Key: key,
      UploadId: uploadId,
      MultipartUpload: {
        Parts: parts
          .slice()
          .sort((a, b) => a.PartNumber - b.PartNumber)
          .map((p) => ({ ETag: p.ETag, PartNumber: p.PartNumber })),
      },
    })
  );
}

/** Small JSON sidecar without multipart */
export async function putJsonSidecar(key: string, body: string) {
  await s3.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      Body: Buffer.from(body, "utf8"),
      ContentType: "application/json",
    })
  );
}
