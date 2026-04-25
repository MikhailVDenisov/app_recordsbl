import pg from "pg";

const { Pool } = pg;

export const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 10,
  // Чтобы API не "висло" бесконечно при проблемах с БД/сетью.
  connectionTimeoutMillis: 5_000,
  idleTimeoutMillis: 30_000,
  // Таймаут выполнения SQL на стороне PostgreSQL (мс).
  // Важно: это серверный statement_timeout, он реально прерывает зависшие запросы.
  statement_timeout: 20_000,
});

export async function query<T extends pg.QueryResultRow>(
  text: string,
  params?: unknown[]
): Promise<pg.QueryResult<T>> {
  return pool.query<T>(text, params);
}
