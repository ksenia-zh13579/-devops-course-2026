#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"
        ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
sshd_config="$(sudo sshd -T)"
check "Вход от имени root запрещён" \
    "no" "$(awk '/^permitrootlogin/{print $2}' <<< "$sshd_config")"
check "Парольная аутентификация отключена" \
    "no" "$(awk '/^passwordauthentication/{print $2}' <<< "$sshd_config")"

ssh_port="$(awk '/^port/{print $2; exit}' <<< "$sshd_config")"
if [[ "$ssh_port" == "22" ]]; then
    ssh_port_result="22"
else
    ssh_port_result="non-22"
fi
check "SSH работает на нестандартном порту" "non-22" "$ssh_port_result"

check "Максимальное число попыток аутентификации равно 3" \
    "3" "$(awk '/^maxauthtries/{print $2}' <<< "$sshd_config")"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" \
    "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"

incoming_policy="$(
    sudo ufw status verbose |
        awk '/^Default:/ {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^\(incoming\)/) {
                    print $(i - 1)
                    exit
                }
            }
        }'
)"
check "Политика входящего трафика по умолчанию — deny" \
    "deny" "$incoming_policy"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"
check "Служба nginx активна" \
    "active" "$(systemctl is-active nginx 2>/dev/null)"

nginx_config_status=0
sudo nginx -t >/dev/null 2>&1 || nginx_config_status=$?
check "Конфигурация nginx синтаксически корректна" \
    "0" "$nginx_config_status"

certificate_threshold="${CERT_MIN_SECONDS:-2592000}"
certificate_status=0
openssl x509 \
    -checkend "$certificate_threshold" \
    -noout \
    -in /etc/ssl/certs/devops.crt >/dev/null 2>&1 ||
    certificate_status=$?
check "Сертификат действителен не менее заданного срока" \
    "0" "$certificate_status"

web_permissions_status="ok"
writable_resource="$(find /var/www/devops-site -perm -o+w -print -quit 2>/dev/null)" ||
    web_permissions_status="fail"
if [[ -n "$writable_resource" ]]; then
    web_permissions_status="fail"
fi
key_mode="$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null)" ||
    web_permissions_status="fail"
if [[ "$key_mode" != "600" ]]; then
    web_permissions_status="fail"
fi
check "Права веб-ресурса и закрытого ключа безопасны" \
    "ok" "$web_permissions_status"

echo "[5] Контейнеризация"
check "Служба docker активна" \
    "active" "$(systemctl is-active docker 2>/dev/null)"

check "Контейнер СУБД находится в состоянии healthy" \
    "healthy" "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null)"

published_ports_status="ok"
unexpected_port_binding="$(
    ss -tln 2>/dev/null |
        awk '
            $1 == "LISTEN" {
                local_address = $4
                port = local_address
                sub(/^.*:/, "", port)
                if ((port == "5000" || port == "5432") &&
                    local_address !~ /^127\.0\.0\.1:/) {
                    print local_address
                    found = 1
                }
            }
            END { exit found }
        '
)" || published_ports_status="fail"
if [[ -n "$unexpected_port_binding" ]]; then
    published_ports_status="fail"
fi
check "Порты 5000 и 5432 прослушиваются только на 127.0.0.1" \
    "ok" "$published_ports_status"

env_file="${AUDIT_ENV_FILE:-/home/devops/app/.env}"
check "Файл .env имеет права 600" \
    "600" "$(stat -c '%a' "$env_file" 2>/dev/null)"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
