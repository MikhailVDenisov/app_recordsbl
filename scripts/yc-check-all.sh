#!/usr/bin/env bash
# Подряд: SQLite + S3 (Object Storage). Подхватывает server/.env из корня репозитория, если файл есть.
#
#   chmod +x scripts/*.sh
#   ./scripts/yc-check-all.sh
#
# Если в .env есть символы, мешающие source — экспортируйте переменные вручную
# и запускайте yc-check-sqlite.sh и yc-check-s3.sh по отдельности.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ROOT}/server/.env"

if [[ -f "$ENV_FILE" ]]; then
  echo ">>> Загрузка переменных из ${ENV_FILE}"
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
else
  echo "Файл ${ENV_FILE} не найден — используйте уже экспортированные переменные окружения." >&2
fi

echo ""
"${ROOT}/scripts/yc-check-sqlite.sh"
echo ""
"${ROOT}/scripts/yc-check-s3.sh"
echo ""
echo "=== Все проверки завершены ==="
