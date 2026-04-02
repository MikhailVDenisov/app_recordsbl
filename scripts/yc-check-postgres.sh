#!/usr/bin/env bash
# Проверка доступа к PostgreSQL (Managed PostgreSQL в облаке или локально).
# Требуется: клиент psql (brew install libpq / пакет postgresql-client).
#
# Использование:
#   export DATABASE_URL='postgres://user:pass@host:6432/db?sslmode=require'
#   ./scripts/yc-check-postgres.sh
#
# Или:  set -a && source server/.env && set +a && ./scripts/yc-check-postgres.sh

set -euo pipefail

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "Ошибка: не задана переменная DATABASE_URL." >&2
  echo "Пример с SSL:" >&2
  echo "  export DATABASE_URL='postgres://USER:PASS@HOST:5432/DB?sslmode=require'" >&2
  exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "Ошибка: не найден psql. Установите клиент PostgreSQL." >&2
  echo "  macOS: brew install libpq && brew link --force libpq" >&2
  exit 1
fi

echo ">>> Подключение и простые запросы..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL'
SELECT current_database() AS database, current_user AS user, inet_server_addr() AS server_addr, now() AS server_time;
SELECT version();
SQL

echo ""
echo "OK: PostgreSQL отвечает, строка DATABASE_URL рабочая."
