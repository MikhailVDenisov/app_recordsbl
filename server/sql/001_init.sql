-- =============================================================================
-- Схема БД для сервиса записей встреч (RecordsBL API)
-- Применение: из корня server — npm run db:migrate
--             (SQLite) файл задаётся через SQLITE_PATH в server/.env
-- =============================================================================
-- Таблица meetings — метаданные записи, статус выгрузки в Object Storage,
-- идентификатор multipart-загрузки S3 для возобновления.
-- =============================================================================

CREATE TABLE IF NOT EXISTS meetings (
  -- UUID записи, создаётся на клиенте (для идемпотентной регистрации и multipart)
  id TEXT PRIMARY KEY,

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
  recording_started_at TEXT,

  -- JSON: распознавание (id, meetingPlace, timestamps, offset для диаризации)
  metadata TEXT NOT NULL DEFAULT '{}',

  -- JSON: модель устройства, свободное место, логин и т.д.
  device_info TEXT NOT NULL DEFAULT '{}',

  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_meetings_user ON meetings(user_id);
CREATE INDEX IF NOT EXISTS idx_meetings_status ON meetings(status);
