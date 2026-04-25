#!/usr/bin/env bash
# Проверка доступа к SQLite (файл на диске ВМ/машины).
#
# Использование:
#   export SQLITE_PATH='./data/recordsbl.sqlite'
#   ./scripts/yc-check-sqlite.sh
#
# Или:  set -a && source server/.env && set +a && ./scripts/yc-check-sqlite.sh

set -euo pipefail

if [[ -z "${SQLITE_PATH:-}" ]]; then
  echo "Ошибка: не задана переменная SQLITE_PATH." >&2
  echo "Пример:" >&2
  echo "  export SQLITE_PATH='./data/recordsbl.sqlite'" >&2
  exit 1
fi

echo ">>> SQLite: SQLITE_PATH=${SQLITE_PATH}"

if [[ -f "${SQLITE_PATH}" ]]; then
  echo "OK: файл БД существует."
  exit 0
fi

echo "Файл БД пока не найден. Обычно он создаётся после миграций:" >&2
echo "  cd server && npm install && npm run db:migrate" >&2
exit 1

