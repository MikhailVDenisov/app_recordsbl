-- Когда сторонняя система забрала файл из Object Storage (обработка/выгрузка наружу).
-- NULL = ещё не забрано; NOT NULL = забрано в указанный момент.

-- Примечание: SQLite не везде поддерживает `ADD COLUMN IF NOT EXISTS`,
-- поэтому идемпотентность обеспечивается кодом мигратора (src/migrate.ts).
ALTER TABLE meetings
  ADD COLUMN external_consumed_at TEXT NULL;

CREATE INDEX IF NOT EXISTS idx_meetings_external_pending
  ON meetings (status, created_at)
  WHERE external_consumed_at IS NULL AND status = 'uploaded';
