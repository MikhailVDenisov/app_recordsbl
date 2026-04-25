# Схема SQLite

## Файл миграции

| Файл | Назначение |
|------|------------|
| `001_init.sql` | Таблица `meetings` и индексы |
| `002_external_consumed.sql` | Поле `external_consumed_at` (забор файла сторонней системой) |

## Таблица `meetings`

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | TEXT (UUID) | Идентификатор записи (генерируется на клиенте). |
| `user_id` | TEXT | Логин пользователя в сети компании. |
| `status` | TEXT | См. ограничение CHECK в SQL: черновик, выгрузка, ошибка, обработка ASR и т.д. |
| `s3_key` | TEXT | Путь к объекту в S3-совместимом бакете (Object Storage). |
| `upload_id` | TEXT | ID multipart-загрузки в S3 для восстановления. |
| `uploaded_bytes` | BIGINT | Сколько байт уже учтено (прогресс). |
| `file_size_bytes` | BIGINT | Ожидаемый размер файла. |
| `meeting_place` | TEXT | Место встречи (строка из списка в приложении). |
| `duration_seconds` | INTEGER | Длительность записи. |
| `recording_started_at` | TEXT | Время начала записи (как прислал клиент). |
| `metadata` | TEXT (JSON) | Доп. данные для распознавания / диаризации. |
| `device_info` | TEXT (JSON) | Информация об устройстве. |
| `created_at` / `updated_at` | TEXT | Служебные метки времени (CURRENT_TIMESTAMP). |
| `external_consumed_at` | TEXT | `NULL` — файл ещё не забран сторонней системой; иначе — когда забрали. |

## Применение

```bash
cd server
cp .env.example .env   # заполните SQLITE_PATH
npm install
npm run db:migrate
```

Задайте `SQLITE_PATH` в `server/.env` (по умолчанию `./data/recordsbl.sqlite`).
