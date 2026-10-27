#!/usr/bin/env bash
set -u

failed=0
CERT_MIN_SECONDS="${CERT_MIN_SECONDS:-2592000}"

check() {
    local description="$1"
    shift

    if "$@"; then
        printf 'PASS: %s\n' "$description"
    else
        printf 'FAIL: %s\n' "$description" >&2
        failed=1
    fi
}

check_nginx_active() {
    systemctl is-active --quiet nginx
}

check_nginx_config() {
    sudo nginx -t >/dev/null
}

check_certificate_expiry() {
    openssl x509 \
        -checkend "$CERT_MIN_SECONDS" \
        -noout \
        -in /etc/ssl/certs/devops.crt
}

check_web_permissions() {
    local key_mode

    if find /var/www/devops-site -perm -o+w -print -quit |
        grep -q .; then
        return 1
    fi

    key_mode="$(sudo stat -c '%a' /etc/ssl/private/devops.key)" || return 1
    [[ "$key_mode" == "600" ]]
}

printf '[4] Веб-сервер\n'
check 'служба nginx активна' check_nginx_active
check 'конфигурация nginx синтаксически корректна' check_nginx_config
check 'сертификат действителен не менее заданного срока' check_certificate_expiry
check 'ресурс и закрытый ключ имеют безопасные права' check_web_permissions

exit "$failed"