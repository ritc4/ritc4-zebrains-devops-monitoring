#!/bin/bash

# ================= CONFIGURATION =================
URL="http://localhost"
LOG_DIR="/var/log/nginx-checker"
LOG_FILE="${LOG_DIR}/check.log"
METRICS_FILE="${LOG_DIR}/metrics.prom" # Для интеграции с Prometheus/Grafana
# =================================================

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S %Z")

# Проверка доступности с жесткими таймаутами (Cloud-Native подход)
HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" --connect-timeout 3 --max-time 5 "$URL")

send_telegram() {
    local text="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${text}" \
        -d "parse_mode=Markdown" > /dev/null
}

# Генерация метрик и логирование
if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "[$TIMESTAMP] SUCCESS: Nginx is responding perfectly. Status: $HTTP_STATUS" >> "$LOG_FILE"
    # Экспортируем метрику успешности (1 - работает, 0 - упал)
    echo "nginx_site_available{url=\"$URL\"} 1" > "$METRICS_FILE"
else
    echo "[$TIMESTAMP] ERROR: Web server is down or slow! Status-code: $HTTP_STATUS" >> "$LOG_FILE"
    echo "nginx_site_available{url=\"$URL\"} 0" > "$METRICS_FILE"
    
    # Отправка структурированного алерта
    MESSAGE="🚨 *ALERT: Nginx web-server incident!* 🚨%0A%0A⏰ *Время:* $TIMESTAMP%0A❌ *Статус-код:* $HTTP_STATUS%0A⚠️ *Статус:* Требуется вмешательство первой линии."
    send_telegram "$MESSAGE"
fi
