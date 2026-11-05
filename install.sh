#!/bin/sh
# ============================================================================
# Файл: install.sh
# Назначение: Автоматическая установка KeenDash с умным определением веб-папки
# Вся веб-часть живёт в подпапке keendash/, скрипты — в /opt/etc/keendash/,
# оперативка — в /tmp/keendash/. Чужие файлы проект не трогает.
# При установке поверх старой версии сам переносит файлы в новую раскладку.
# ============================================================================

REPO_URL="https://raw.githubusercontent.com/YaPA24/KeenDash/main"

echo "🚀 Начинаем установку KeenDash..."

# 0. Проверяем, что curl вообще установлен
command -v curl >/dev/null 2>&1 || { echo "❌ curl не найден. Установи: opkg install curl"; exit 1; }

# 1. Умное определение корневой папки веб-сервера
WEB_ROOT=""
if [ -d "/opt/share/www" ]; then
    WEB_ROOT="/opt/share/www"
    echo "✅ Обнаружен Lighttpd / стандартный Entware веб-сервер (/opt/share/www)"
elif [ -d "/opt/share/nginx/html" ]; then
    WEB_ROOT="/opt/share/nginx/html"
    echo "✅ Обнаружен Nginx (/opt/share/nginx/html)"
else
    mkdir -p /opt/share/www || { echo "❌ Нет папки /opt — похоже, не установлен Entware"; exit 1; }
    WEB_ROOT="/opt/share/www"
    echo "⚠️ Веб-сервер не найден. Создана стандартная папка /opt/share/www"
fi
APP_WEB="$WEB_ROOT/keendash"

# 2. Создаем директории проекта
mkdir -p "$APP_WEB"
mkdir -p /opt/etc/keendash
mkdir -p /opt/etc/ndm/netfilter.d
mkdir -p /tmp/keendash

# 3. Скачиваем основные файлы — КАЖДЫЙ с проверкой
echo "⬇️ Загрузка файлов..."
get() {
  curl -fLsS --max-time 30 "$REPO_URL/$1" -o "$2" || { echo "❌ Не удалось скачать $1"; exit 1; }
  [ -s "$2" ] || { echo "❌ Файл $1 скачался пустым. Проверь REPO_URL и расположение файлов в репозитории"; exit 1; }
}
get sysinfo.sh      /opt/etc/keendash/sysinfo.sh
get 200-keendash.sh /opt/etc/ndm/netfilter.d/200-keendash.sh
get index.html      "$APP_WEB/index.html"
get dash.html       "$APP_WEB/dash.html"

# 4. Даем права на исполнение
chmod +x /opt/etc/keendash/sysinfo.sh
chmod +x /opt/etc/ndm/netfilter.d/200-keendash.sh

# 5. Останавливаем старые процессы (и новые, и старые имена)
echo "🧹 Остановка старых процессов..."
kill $(cat /var/run/keendash.pid 2>/dev/null) 2>/dev/null
kill $(cat /var/run/sysinfo-loop.pid 2>/dev/null) 2>/dev/null
pkill -f "200-keendash" 2>/dev/null
pkill -f "sysinfo-loop" 2>/dev/null
pkill -f "/opt/etc/keendash/sysinfo.sh" 2>/dev/null
pkill -f "/opt/bin/sysinfo.sh" 2>/dev/null
sleep 1

# 6. Переход со старой версии: убираем файлы старой раскладки.
#    Чужие файлы НЕ трогаем: index.html/dash.html удаляем только если это
#    карточка KeenDash (маркер в заголовке), favicon — только наш зелёный,
#    data.json/sysinfo-history.json — только если это наши симлинки в /tmp.
echo "🧹 Чистка файлов старой версии (если были)..."
rm -f /opt/bin/sysinfo.sh
rm -f /opt/etc/ndm/netfilter.d/200-sysinfo-loop.sh
rm -f /var/run/sysinfo-loop.pid
rm -f /tmp/sysinfo-static.env /tmp/cpu-stat.prev /tmp/data.json /tmp/sysinfo-history.json
for W in /opt/share/www /opt/share/nginx/html; do
  [ -d "$W" ] || continue
  for F in "$W/index.html" "$W/dash.html"; do
    grep -q "Система · " "$F" 2>/dev/null && rm -f "$F"
  done
  grep -q "2ea043" "$W/favicon.svg" 2>/dev/null && rm -f "$W/favicon.svg"
  [ -L "$W/data.json" ] && rm -f "$W/data.json"
  [ -L "$W/sysinfo-history.json" ] && rm -f "$W/sysinfo-history.json"
done

# 7. Симлинки (ярлыки) из папки проекта в оперативную память
echo "🔗 Создание симлинков в $APP_WEB..."
ln -sf /tmp/keendash/data.json "$APP_WEB/data.json"
ln -sf /tmp/keendash/sysinfo-history.json "$APP_WEB/sysinfo-history.json"

# 8. Запускаем демон
echo "▶️ Запуск демона..."
/opt/etc/ndm/netfilter.d/200-keendash.sh

echo ""
echo "✅ Установка успешно завершена!"
echo "🌐 Открой в браузере: http://<IP-роутера>/keendash/dash.html"
echo "(Используй порт твоего веб-сервера, если он отличается от 80, например: http://192.168.1.1:81/keendash/dash.html)"
