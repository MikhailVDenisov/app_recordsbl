import Database from "better-sqlite3";
import { mkdirSync } from "node:fs";
import { dirname, isAbsolute, resolve } from "node:path";

export type SqliteQueryResult<T> = {
  rows: T[];
  rowCount: number;
};

function resolveSqlitePath(): string {
  const p = process.env.SQLITE_PATH ?? "./data/recordsbl.sqlite";
  return isAbsolute(p) ? p : resolve(process.cwd(), p);
}

const sqlitePath = resolveSqlitePath();
mkdirSync(dirname(sqlitePath), { recursive: true });

export const db = new Database(sqlitePath);
db.pragma("journal_mode = WAL");
db.pragma("foreign_keys = ON");

export async function query<T extends Record<string, unknown>>(
  text: string,
  params?: unknown[]
): Promise<SqliteQueryResult<T>> {
  const stmt = db.prepare(text);

  // Heuristic: treat leading WITH/SELECT as read query.
  const isSelect = /^\s*(with|select)\b/i.test(text);
  if (isSelect) {
    const rows = (params ? stmt.all(params) : stmt.all()) as T[];
    return { rows, rowCount: rows.length };
  }

  const info = params ? stmt.run(params) : stmt.run();
  return { rows: [], rowCount: info.changes };
}
