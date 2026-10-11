#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"                     # псевдоним из ~/.ssh/config
REMOTE_DIR="/var/www/devops-site"
HTTP_URL="http://devops.local"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"

dry_run=false
case "$#" in
    0)
        ;;
    1)
        if [[ "$1" == "--dry-run" ]]; then
            dry_run=true
        else
            echo "Ошибка: неизвестный аргумент: $1" >&2
            exit 2
        fi
        ;;
    *)
        echo "Использование: $0 [--dry-run]" >&2
        exit 2
        ;;
esac

repo_root="$(git rev-parse --show-toplevel)"
local_dir="${repo_root}/site/"

if [[ ! -f "${local_dir}index.html" ]]; then
    echo "Ошибка: файл site/index.html отсутствует" >&2
    exit 1
fi

if [[ -n "$(git -C "$repo_root" status --porcelain --untracked-files=all)" ]]; then
    echo "Ошибка: репозиторий содержит незафиксированные изменения" >&2
    exit 1
fi

rsync_options=(
    --archive
    --compress
    --verbose
    --delete
    --itemize-changes
    --chmod=D755,F644
    -e 'ssh -o BatchMode=yes -o ConnectTimeout=5'
)
if [[ "$dry_run" == true ]]; then
    rsync_options+=(--dry-run)
fi

rsync "${rsync_options[@]}" "$local_dir" "${REMOTE}:${REMOTE_DIR}/"

if [[ "$dry_run" == true ]]; then
    exit 0
fi

redirect_headers="$(
    curl --silent --show-error --head --dump-header - --output /dev/null \
        "$HTTP_URL"
)"
redirect_status="$(printf '%s\n' "$redirect_headers" | awk 'NR == 1 { print $2 }')"
redirect_location="$(
    printf '%s\n' "$redirect_headers" |
        awk 'tolower($1) == "location:" { print $2; exit }' |
        tr -d '\r'
)"
if [[ "$redirect_status" != "301" ||
      "$redirect_location" != "https://devops.local/" ]]; then
    echo "Ошибка: HTTP не перенаправляет на https://devops.local/" >&2
    exit 1
fi

set +e
curl --silent --show-error --head --output /dev/null "$SITE_URL"
tls_check_status=$?
set -e
if [[ "$tls_check_status" -eq 0 ]]; then
    echo "Ошибка: проверка сертификата без CA неожиданно завершилась успешно" >&2
    exit 1
fi

insecure_status="$(
    curl --fail --silent --show-error --insecure --head \
        --write-out '%{http_code}' --output /dev/null "$SITE_URL"
)"
if [[ "$insecure_status" != "200" ]]; then
    echo "Ошибка: HTTPS с отключенной проверкой сертификата вернул ${insecure_status}" >&2
    exit 1
fi

curl --fail --silent --show-error --cacert "$CA_CERT" "$SITE_URL" >/dev/null

not_found_status="$(
    curl --silent --show-error --head \
        --write-out '%{http_code}' --output /dev/null \
        --cacert "$CA_CERT" "$SITE_URL/no-such-page"
)"
if [[ "$not_found_status" != "404" ]]; then
    echo "Ошибка: для несуществующей страницы ожидался HTTP 404, получен ${not_found_status}" >&2
    exit 1
fi

echo "Доставлен коммит $(git -C "$repo_root" rev-parse --short HEAD)"