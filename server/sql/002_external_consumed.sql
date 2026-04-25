-- Когда сторонняя система забрала файл из Object Storage (обработка/выгрузка наружу).
-- NULL = ещё не забрано; NOT NULL = забрано в указанный момент.

ALTER TABLE meetings
  ADD COLUMN IF NOT EXISTS external_consumed_at TIMESTAMPTZ NULL;

COMMENT ON COLUMN meetings.external_consumed_at IS
  'Метка времени: файл забран сторонней системой из хранилища';

CREATE INDEX IF NOT EXISTS idx_meetings_external_pending
  ON meetings (status, created_at)
  WHERE external_consumed_at IS NULL AND status = 'uploaded';
