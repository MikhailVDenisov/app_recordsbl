#!/usr/bin/env bash
# Проверка S3 с переменными из server/.env (как у API).
#
# Из корня репозитория:
#   ./scripts/check-s3-from-env.sh
#
# Требуется: AWS CLI (aws), заполненный server/.env с S3_*.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/server/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Нет файла $ENV_FILE — скопируйте server/.env.example и заполните S3_*." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

exec "$ROOT/scripts/yc-check-s3.sh"
