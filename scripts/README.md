# Проверка PostgreSQL и Object Storage перед приложением

Скрипты проверяют **PostgreSQL** и **Object Storage (S3 API)** так же, как их использует `server/` (переменные из `server/.env`).

## Что установить на машине

| Проверка   | Инструмент |
|------------|------------|
| PostgreSQL | `psql` (клиент) — [macOS](https://formulae.brew.sh/formula/libpq): `brew install libpq` |
| S3         | **AWS CLI v2** — ключи доступа к Object Storage (см. документацию провайдера, например [Cloud.ru](https://cloud.ru/docs/s3e/)) |

## Переменные

Скопируйте `server/.env.example` в `server/.env` и заполните значениями из консоли облака.

- **PostgreSQL**: хост, порт, пользователь, пароль, БД. Для Managed PostgreSQL в строке обычно нужен **`?sslmode=require`**.
- **S3**: бакет, ключи с правами на `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject`, `s3:ListBucket`.

## Запуск

```bash
chmod +x scripts/*.sh

# Всё подряд (читает server/.env)
./scripts/yc-check-all.sh
```

По отдельности:

```bash
set -a && source server/.env && set +a
./scripts/yc-check-postgres.sh
./scripts/yc-check-s3.sh
```

**Только S3**, подставляя значения из `server/.env`:

```bash
./scripts/check-s3-from-env.sh
```

Если `source server/.env` падает из‑за символов в пароле — задайте переменные вручную:

```bash
export DATABASE_URL='postgres://...'
export S3_ENDPOINT=https://s3.cloud.ru
export S3_REGION=ru-central1
export S3_BUCKET=your-bucket
export S3_ACCESS_KEY_ID=...
export S3_SECRET_ACCESS_KEY=...
./scripts/yc-check-postgres.sh
./scripts/yc-check-s3.sh
```

## Ожидаемый результат

- **PostgreSQL**: вывод `version`, `current_database`, без ошибки подключения.
- **S3**: успешный `head-bucket`, затем тестовый объект загружается и удаляется в бакете.

После этого можно поднимать API (`server/`) и проверять выгрузку из мобильного приложения.
