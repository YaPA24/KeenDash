#!/bin/sh
# ============================================================================
# Файл: install.sh
# Назначение: Автоматическая установка KeenDash с умным определением веб-папки
# Изменено: добавлены проверки скачивания, чтобы не было "успеха" с пустыми файлами
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

# 2. Создаем нужные директории
mkdir -p /opt/bin
mkdir -p /opt/etc/ndm/netfilter.d

# 3. Скачиваем основные файлы — КАЖДЫЙ с проверкой
echo "⬇️ Загрузка файлов..."
get() {
  curl -fLsS --max-time 30 "$REPO_URL/$1" -o "$2" || { echo "❌ Не удалось скачать $1"; exit 1; }
  [ -s "$2" ] || { echo "❌ Файл $1 скачался пустым. Проверь REPO_URL и расположение файлов в репозитории"; exit 1; }
}
get sysinfo.sh          /opt/bin/sysinfo.sh
get 200-sysinfo-loop.sh /opt/etc/ndm/netfilter.d/200-sysinfo-loop.sh
get index.html          "$WEB_ROOT/index.html"
get dash.html           "$WEB_ROOT/dash.html"
get favicon.svg         "$WEB_ROOT/favicon.svg"

# 4. Даем права на исполнение
chmod +x /opt/bin/sysinfo.sh
chmod +x /opt/etc/ndm/netfilter.d/200-sysinfo-loop.sh

# 5. Очищаем старые версии
echo "🧹 Очистка старых процессов..."
kill $(cat /var/run/sysinfo-loop.pid 2>/dev/null) 2>/dev/null
pkill -f "sysinfo-loop" 2>/dev/null
rm -f /var/run/sysinfo-loop.pid /tmp/sysinfo-static.env /tmp/cpu-stat.prev /tmp/data.json /tmp/sysinfo-history.json

# 6. Создаем СИМЛИНК (ярлык) из веб-папки в оперативную память
echo "🔗 Создание симлинка в $WEB_ROOT..."
ln -sf /tmp/data.json "$WEB_ROOT/data.json"
ln -sf /tmp/sysinfo-history.json "$WEB_ROOT/sysinfo-history.json"

# 7. Запускаем демон
echo "▶️ Запуск демона..."
/opt/etc/ndm/netfilter.d/200-sysinfo-loop.sh

echo ""
echo "✅ Установка успешно завершена!"
echo "🌐 Открой в браузере: http://<IP-роутера>/dash.html"
echo "(Используй порт твоего веб-сервера, если он отличается от 80, например: http://192.168.1.1:81/dash.html)"
