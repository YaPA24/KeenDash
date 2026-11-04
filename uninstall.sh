#!/bin/sh
# ============================================================================
# Файл: uninstall.sh
# Назначение: полное удаление KeenDash (демон + файлы + временные данные)
# ============================================================================

echo "🧹 Удаляем KeenDash..."

# 1. Останавливаем фоновый цикл
[ -f /var/run/sysinfo-loop.pid ] && kill "$(cat /var/run/sysinfo-loop.pid)" 2>/dev/null
pkill -f 'sysinfo-loop'      2>/dev/null
pkill -f '/opt/bin/sysinfo.sh' 2>/dev/null

# 2. Удаляем файлы проекта
rm -f /opt/bin/sysinfo.sh
rm -f /opt/etc/ndm/netfilter.d/200-sysinfo-loop.sh
rm -f /opt/share/nginx/html/index.html
rm -f /opt/share/nginx/html/dash.html
rm -f /opt/share/nginx/html/favicon.svg
rm -f /opt/share/nginx/html/data.json   # симлинк (ярлык)

# 3. Чистим временные данные в оперативке
rm -f /tmp/sysinfo-static.env /tmp/cpu-stat.prev /tmp/data.json
rm -f /var/run/sysinfo-loop.pid

echo "✅ KeenDash удалён. После перезагрузки роутера ничего не вернётся."