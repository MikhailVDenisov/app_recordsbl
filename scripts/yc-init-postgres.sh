#!/usr/bin/env bash
# Инициализация БД в связке с веб-консолью (по умолчанию Cloud.ru):
#   1) открывает в браузере консоль или раздел документации;
#   2) по флагу --migrate применяет схему (server/npm run db:migrate).
#
# В консоли вручную: создать кластер, БД, пользователя, при необходимости публичный
# доступ и группу безопасности — см. docs/postgresql-cloud-ru.md
#
# Использование:
#   export CLOUD_CONSOLE_URL=https://console.cloud.ru/   # опционально — другой URL консоли
#   ./scripts/yc-init-postgres.sh                 # только открыть консоль + подсказки
#   ./scripts/yc-init-postgres.sh --migrate       # миграция (нужен DATABASE_URL или server/.env)
#   ./scripts/yc-init-postgres.sh --migrate --no-open
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="$REPO_ROOT/server"

MIGRATE=false
OPEN_BROWSER=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --migrate) MIGRATE=true ;;
    --no-open) OPEN_BROWSER=false ;;
    -h | --help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Неизвестный аргумент: $1 (ожидаются --migrate, --no-open)" >&2
      exit 1
      ;;
  esac
  shift
done

open_in_browser() {
  local url=$1
  if [[ "$OPEN_BROWSER" != true ]]; then
    echo "URL: $url"
    return
  fi
  if command -v open >/dev/null 2>&1; then
    open "$url"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url"
  else
    echo "Откройте в браузере: $url"
  fi
}

CONSOLE_URL="${CLOUD_CONSOLE_URL:-https://console.cloud.ru/}"
open_in_browser "$CONSOLE_URL"

cat <<'EOF'

--- Дальше в веб-консоли облака (например Cloud.ru) ---
  • Managed PostgreSQL → создать кластер (или выбрать существующий).
  • Задать БД (например recordsbl), пользователя и пароль; при доступе с Mac/интернета —
    включить публичный доступ и разрешить TCP к порту БД в правилах безопасности.
  • Строка подключения: postgres://USER:PASSWORD@HOST:PORT/DBNAME?sslmode=require
    (порт и SSL — как в карточке кластера; спецсимволы в пароле — URL-кодировать.)

Подробности: docs/postgresql-cloud-ru.md

Запишите DATABASE_URL в server/.env, затем из корня репозитория:
  ./scripts/yc-init-postgres.sh --migrate

Проверка подключения:
  ./scripts/yc-check-postgres.sh

EOF

if [[ "$MIGRATE" != true ]]; then
  exit 0
fi

if [[ ! -d "$SERVER_DIR" ]]; then
  echo "Не найден каталог server/" >&2
  exit 1
fi

if [[ ! -f "$SERVER_DIR/.env" ]] && [[ -z "${DATABASE_URL:-}" ]]; then
  echo "Ошибка: задайте DATABASE_URL или создайте server/.env с DATABASE_URL=..." >&2
  exit 1
fi

cd "$SERVER_DIR"
if [[ ! -d node_modules ]]; then
  echo ">>> npm install в server/..."
  npm install
fi

echo ">>> npm run db:migrate"
npm run db:migrate

echo ""
echo "Готово: схема применена к базе."
