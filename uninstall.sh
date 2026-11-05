#!/bin/sh
# ============================================================================
# Файл: uninstall.sh
# Назначение: полное удаление KeenDash (демон + файлы + временные данные)
# Удаляет только файлы проекта — чужие файлы не трогаются.
# ============================================================================

echo "🧹 Удаляем KeenDash..."

# 1. Останавливаем демон KeenDash
[ -f /var/run/keendash.pid ] && kill "$(cat /var/run/keendash.pid)" 2>/dev/null
pkill -f '200-keendash' 2>/dev/null
pkill -f '/opt/etc/keendash/sysinfo.sh' 2>/dev/null
sleep 1

# 2. Папка веб-части: точный путь берём из install.env (его пишет установщик),
#    плюс на всякий случай чистим оба стандартных места. Там только наши папки.
if [ -f /opt/etc/keendash/install.env ]; then
  WEB_ROOT=$(sed -n 's/^WEB_ROOT=//p' /opt/etc/keendash/install.env | head -n 1)
  [ -n "$WEB_ROOT" ] && rm -rf "${WEB_ROOT%/}/keendash"
fi
rm -rf /opt/share/www/keendash
rm -rf /opt/share/nginx/html/keendash

# 3. Остальное хозяйство проекта
rm -rf /opt/etc/keendash
rm -rf /tmp/keendash
rm -f /opt/etc/ndm/netfilter.d/200-keendash.sh
rm -f /var/run/keendash.pid

echo "✅ KeenDash полностью удалён. После перезагрузки роутера ничего не вернётся."
