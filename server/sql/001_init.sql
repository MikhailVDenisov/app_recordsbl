-- =============================================================================
-- Схема БД для сервиса записей встреч (RecordsBL API)
-- Применение: из корня server — npm run db:migrate
--             или: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f server/sql/001_init.sql
-- =============================================================================
-- Таблица meetings — метаданные записи, статус выгрузки в Object Storage,
-- идентификатор multipart-загрузки S3 для возобновления.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS meetings (
  -- UUID записи, создаётся на клиенте (для идемпотентной регистрации и multipart)
  id UUID PRIMARY KEY,

  -- Логин пользователя из настроек приложения (компания)
  user_id TEXT NOT NULL,

  -- Жизненный цикл: draft → pending → uploading → uploaded; error; далее processing/ready (ASR)
  status TEXT NOT NULL CHECK (status IN (
    'draft', 'pending', 'uploading', 'uploaded', 'error', 'processing', 'ready'
  )),

  -- Ключ объекта в Object Storage (путь внутри бакета)
  s3_key TEXT,

  -- Multipart upload ID в S3 (для ListParts / продолжения загрузки)
  upload_id TEXT,

  uploaded_bytes BIGINT NOT NULL DEFAULT 0,
  file_size_bytes BIGINT,

  meeting_place TEXT,
  duration_seconds INTEGER,
  recording_started_at TIMESTAMPTZ,

  -- JSON: распознавание (id, meetingPlace, timestamps, offset для диаризации)
  metadata JSONB NOT NULL DEFAULT '{}',

  -- JSON: модель устройства, свободное место, логин и т.д.
  device_info JSONB NOT NULL DEFAULT '{}',

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_meetings_user ON meetings(user_id);
CREATE INDEX IF NOT EXISTS idx_meetings_status ON meetings(status);
