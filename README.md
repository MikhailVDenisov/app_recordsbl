# RecordsBL — запись встреч и выгрузка в S3-совместимое хранилище

Монорепозиторий: **API (Node.js + SQLite + S3-compatible)** и **мобильное приложение (Flutter)** с возобновляемой multipart-загрузкой.

## Сервер

**SQLite на диске ВМ с API:** файл БД задаётся через `SQLITE_PATH` в `server/.env`. Схема таблиц и описание полей — [server/sql/README.md](server/sql/README.md).

**ВМ в Evolution для API:** ОС, vCPU/RAM, диск, порты, Node.js — [docs/vm-api-evolution-cloud-ru.md](docs/vm-api-evolution-cloud-ru.md).

1. Скопируйте `server/.env.example` в `server/.env`, укажите `SQLITE_PATH` и креды **Object Storage** (например [Cloud.ru Object Storage](https://cloud.ru/docs/s3e/) — S3-совместимый API).
3. Установите зависимости и миграции:

```bash
cd server && npm install && npm run db:migrate && npm run dev
```

API: `POST /api/v1/meetings/register` (идемпотентная регистрация + `UploadId` в S3), `POST .../presign-part`, `GET .../parts`, `POST .../complete`, `PATCH .../progress`.

**Событийная обработка (транскрипция / диаризация):** после `complete` объект доступен в бакете; отдельный воркер (очередь сообщений / PostgreSQL `NOTIFY` / serverless) читает метаданные из `metadata.json` и БД и запускает ASR — в репозитории задана только серверная часть загрузки и схема данных.

## Мобильное приложение (Flutter)

В каталоге `mobile` уже есть `lib/` и `pubspec.yaml`. Сгенерируйте платформенные проекты (один раз):

```bash
cd mobile
flutter create . --project-name recordsbl --org com.company.recordsbl
flutter pub get
```

### Обязательная настройка платформ

- **iOS** (`ios/Runner/Info.plist`): `NSMicrophoneUsageDescription`; **Background Modes** — Audio (Xcode → Signing & Capabilities). Для фоновой выгрузки через `NSURLSession` добавьте Background fetch / Processing по необходимости и нативный слой (см. документацию Apple).
- **Android** (`AndroidManifest.xml`): `RECORD_AUDIO`, `INTERNET`, при длительной выгрузке в фоне — `FOREGROUND_SERVICE` и сервис по гайдам Android 14+.

### Поведение, реализованное в коде

- Запись **PCM → WAV** (24 kHz, стерео), **RMS** по блокам PCM, обновление индикатора с периодом 50 ms.
- `audio_session`: категория playAndRecord, режим measurement, Android `USAGE_VOICE_RECOGNITION`.
- Пауза при **прерывании аудиосессии** (в т.ч. звонок на многих устройствах).
- Диск: предупреждение &lt; 100 МБ, жёсткая остановка &lt; 10 МБ.
- Выгрузка: чанки 5 МБ, presigned PUT, список частей с сервера, возобновление; прогресс и ETA (оценка).
- Повтор выгрузки при ошибке: задержки **5 / 15 / 60 минут** + автоповтор при возврате приложения на передний план.
- Настройки: логин (латиница) и URL API.

### Что доработать под продакшен

- Воспроизведение записей: подключить `just_audio` / `audioplayers`.
- **iOS Background URLSession** и **Android WorkManager** для выгрузки при закрытом UI — сейчас загрузка идёт через `dio` и переживает сворачивание ограниченно; для полного соответствия ТЗ нужен нативный фоновый транспорт.
- Сохранение незавершённой записи при OOM: периодический сброс PCM на диск (сейчас — сохранение при остановке и при критическом диске).

## Формат файла

В ТЗ упомянут FLAC; для стабильного стриминга и точного RMS в Dart используется **несжатый WAV (PCM16)** — тот же сценарий для ASR. При необходимости FLAC можно кодировать на сервере или подключить нативный энкодер.
