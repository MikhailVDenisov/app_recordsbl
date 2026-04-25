import "dotenv/config";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { db } from "./db.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

async function main() {
  const files = ["001_init.sql", "002_external_consumed.sql"];
  for (const name of files) {
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
