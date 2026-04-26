import "dotenv/config";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { db } from "./db.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

function columnExists(table: string, column: string): boolean {
  const rows = db
    .prepare(`PRAGMA table_info(${table})`)
    .all() as { name: string }[];
  return rows.some((r) => r.name === column);
}

async function main() {
  {
    const name = "001_init.sql";
    const sql = await readFile(join(__dirname, "../sql", name), "utf8");
    db.exec(sql);
    console.log(`Applied ${name}`);
  }

  // SQLite compatibility: avoid ALTER TABLE ... ADD COLUMN IF NOT EXISTS
  // (not supported on older SQLite versions).
  {
    const name = "002_external_consumed.sql";
    if (!columnExists("meetings", "external_consumed_at")) {
      db.exec(
        `ALTER TABLE meetings ADD COLUMN external_consumed_at TEXT NULL;`
      );
    }
    db.exec(
      `CREATE INDEX IF NOT EXISTS idx_meetings_external_pending
       ON meetings (status, created_at)
       WHERE external_consumed_at IS NULL AND status = 'uploaded';`
    );
    console.log(`Applied ${name}`);
  }

  {
    const name = "003_meeting_places.sql";
    const sql = await readFile(join(__dirname, "../sql", name), "utf8");
    db.exec(sql);
    console.log(`Applied ${name}`);
  }

  console.log("Migrations done.");
  db.close();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
