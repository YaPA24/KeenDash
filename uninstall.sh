#!/bin/sh
# ============================================================================
# Файл: uninstall.sh
# Назначение: полное удаление KeenDash (демон + файлы + временные данные)
# Удаляет и новую раскладку (папки keendash), и файлы старой версии.
# Чужие файлы не трогает: удаляются только файлы с маркерами KeenDash.
# ============================================================================

echo "🧹 Удаляем KeenDash..."

# 1. Останавливаем фоновые циклы (новые и старые имена)
[ -f /var/run/keendash.pid ] && kill "$(cat /var/run/keendash.pid)" 2>/dev/null
[ -f /var/run/sysinfo-loop.pid ] && kill "$(cat /var/run/sysinfo-loop.pid)" 2>/dev/null
pkill -f '200-keendash' 2>/dev/null
pkill -f 'sysinfo-loop' 2>/dev/null
pkill -f '/opt/etc/keendash/sysinfo.sh' 2>/dev/null
pkill -f '/opt/bin/sysinfo.sh' 2>/dev/null
sleep 1

# 2. Папки проекта (новая раскладка) — сносим целиком, там только наше
rm -rf /opt/share/www/keendash
rm -rf /opt/share/nginx/html/keendash
rm -rf /opt/etc/keendash
rm -rf /tmp/keendash
rm -f /opt/etc/ndm/netfilter.d/200-keendash.sh
rm -f /var/run/keendash.pid

# 3. Файлы старой версии — только наши, каждая проверка по маркеру
rm -f /opt/bin/sysinfo.sh
rm -f /opt/etc/ndm/netfilter.d/200-sysinfo-loop.sh
rm -f /var/run/sysinfo-loop.pid
rm -f /tmp/sysinfo-static.env /tmp/cpu-stat.prev /tmp/data.json /tmp/sysinfo-history.json
for W in /opt/share/www /opt/share/nginx/html; do
  [ -d "$W" ] || continue
  # index.html и dash.html — только если это карточка/дашборд KeenDash
  for F in "$W/index.html" "$W/dash.html"; do
    grep -q "Система · " "$F" 2>/dev/null && rm -f "$F"
  done
  # favicon — только наш (зелёная иконка #2ea043)
  grep -q "2ea043" "$W/favicon.svg" 2>/dev/null && rm -f "$W/favicon.svg"
  # data.json / sysinfo-history.json — только наши симлинки в /tmp
  [ -L "$W/data.json" ] && rm -f "$W/data.json"
  [ -L "$W/sysinfo-history.json" ] && rm -f "$W/sysinfo-history.json"
done

echo "✅ KeenDash полностью удалён. После перезагрузки роутера ничего не вернётся."
