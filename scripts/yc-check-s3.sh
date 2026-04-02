#!/usr/bin/env bash
# Проверка Object Storage через S3 API (совместим с AWS CLI).
# Требуется: AWS CLI v2 (https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
#
# Переменные (как в server/.env):
#   S3_ENDPOINT         — например https://s3.cloud.ru или https://storage.yandexcloud.net
#   S3_REGION         — ru-central1
#   S3_BUCKET         — имя бакета
#   S3_ACCESS_KEY_ID / S3_SECRET_ACCESS_KEY — статический ключ сервисного аккаунта
#
# Использование:
#   set -a && source server/.env && set +a && ./scripts/yc-check-s3.sh

set -euo pipefail

: "${S3_ENDPOINT:?Задайте S3_ENDPOINT (например https://s3.cloud.ru)}"
: "${S3_BUCKET:?Задайте S3_BUCKET}"
: "${S3_ACCESS_KEY_ID:?Задайте S3_ACCESS_KEY_ID}"
: "${S3_SECRET_ACCESS_KEY:?Задайте S3_SECRET_ACCESS_KEY}"

REGION="${S3_REGION:-ru-central1}"

if ! command -v aws >/dev/null 2>&1; then
  echo "Ошибка: не найден aws. Установите AWS CLI v2." >&2
  exit 1
fi

export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="$REGION"

echo ">>> Проверка бакета (head-bucket)..."
aws --endpoint-url="$S3_ENDPOINT" s3api head-bucket --bucket "$S3_BUCKET"
echo "OK: бакет существует, ключи подходят."

echo ""
echo ">>> Список объектов (первые записи, префикс meetings/ если есть)..."
aws --endpoint-url="$S3_ENDPOINT" s3 ls "s3://${S3_BUCKET}/" 2>/dev/null | head -20 || true
aws --endpoint-url="$S3_ENDPOINT" s3 ls "s3://${S3_BUCKET}/meetings/" 2>/dev/null | head -20 || true

echo ""
echo ">>> Пробная загрузка и удаление маленького объекта..."
TEST_KEY="health-check/$(date +%s).txt"
echo "yc-check $(date -u +%Y-%m-%dT%H:%M:%SZ)" | aws --endpoint-url="$S3_ENDPOINT" s3 cp - "s3://${S3_BUCKET}/${TEST_KEY}"
aws --endpoint-url="$S3_ENDPOINT" s3 rm "s3://${S3_BUCKET}/${TEST_KEY}"
echo "OK: запись и удаление объекта в бакете прошли успешно."
