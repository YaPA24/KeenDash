#!/bin/sh
# ============================================================================
# Файл: uninstall.sh
# Назначение: полное удаление KeenDash (демон + файлы + временные данные)
# ============================================================================

echo "🧹 Удаляем KeenDash..."

# 1. Останавливаем фоновый цикл
[ -f /var/run/sysinfo-loop.pid ] && kill "$(cat /var/run/sysinfo-loop.pid)" 2>/dev/null
pkill -f 'sysinfo-loop' 2>/dev/null
pkill -f '/opt/bin/sysinfo.sh' 2>/dev/null

# 2. Удаляем файлы проекта
rm -f /opt/bin/sysinfo.sh
rm -f /opt/etc/ndm/netfilter.d/200-sysinfo-loop.sh

# Удаляем из возможных веб-папок (Nginx)
rm -f /opt/share/nginx/html/index.html
rm -f /opt/share/nginx/html/dash.html
rm -f /opt/share/nginx/html/favicon.svg
rm -f /opt/share/nginx/html/data.json

# Удаляем из возможных веб-папок (Lighttpd/стандарт)
rm -f /opt/share/www/index.html
rm -f /opt/share/www/dash.html
rm -f /opt/share/www/favicon.svg
rm -f /opt/share/www/data.json

# 3. Чистим временные данные в оперативке
rm -f /tmp/sysinfo-static.env /tmp/cpu-stat.prev /tmp/data.json
rm -f /var/run/sysinfo-loop.pid

echo "✅ KeenDash полностью удалён. После перезагрузки роутера ничего не вернётся."