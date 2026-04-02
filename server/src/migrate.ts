import "dotenv/config";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { pool } from "./db.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

async function main() {
  const sql = await readFile(join(__dirname, "../sql/001_init.sql"), "utf8");
  await pool.query(sql);
  console.log("Migration applied.");
  await pool.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
