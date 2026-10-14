#!/bin/bash

# Включаем строгий режим продакшена (DevOps Best Practices)
set -u
set -o pipefail

# ================= CONFIGURATION =================
URL="http://localhost"
LOG_DIR="/var/log/nginx-checker"
LOG_FILE="${LOG_DIR}/check.log"
METRICS_FILE="${LOG_DIR}/metrics.prom"
# =================================================

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S %Z")

# Cloud-Native подход: делаем 3 повторные попытки (--retry 3) с интервалом в 1 секунду (--retry-delay 1)
# Это исключает ложные алерты при кратковременных сетевых колебаниях (Network Flapping)
HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" \
    --connect-timeout 3 \
    --max-time 5 \
    --retry 3 \
    --retry-delay 1 \
    "$URL")

send_telegram() {
    local text="$1"
    
    # Проверяем, заданы ли секреты в окружении, чтобы не тратить ресурсы на пустой запрос
    if [[ -z "${TELEGRAM_TOKEN:-}" || -z "${CHAT_ID:-}" ]]; then
        echo "[$TIMESTAMP] CRITICAL: Telegram credentials are missing in Systemd Environment!" >&2
        return 1
    fi

    # Выполняем запрос к Telegram API и проверяем его код возврата
    if ! curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${text}" \
        -d "parse_mode=Markdown" > /dev/null; then
        
        # Если Telegram недоступен, пишем в стандартный поток ошибок (уйдет в systemd journald)
        echo "[$TIMESTAMP] ALERT_FAILURE: Failed to send notification via Telegram Bot API!" >&2
    fi
}

# Генерация метрик для Prometheus и системное логирование
if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "[$TIMESTAMP] SUCCESS: Nginx is responding perfectly. Status: $HTTP_STATUS" >> "$LOG_FILE"
    echo "nginx_site_available{url=\"$URL\"} 1" > "$METRICS_FILE"
else
    echo "[$TIMESTAMP] ERROR: Web server is down or slow! Status-code: $HTTP_STATUS" >> "$LOG_FILE"
    echo "nginx_site_available{url=\"$URL\"} 0" > "$METRICS_FILE"
    
    # Формируем и отправляем структурированный алерт первой линии
    MESSAGE="🚨 *ALERT: Nginx web-server incident!* 🚨%0A%0A⏰ *Время:* $TIMESTAMP%0A❌ *Статус-код:* $HTTP_STATUS%0A⚠️ *Статус:* Требуется вмешательство первой линии."
    send_telegram "$MESSAGE"
fi