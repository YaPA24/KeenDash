#!/bin/sh
# ============================================================================
# Файл: install.sh
# Назначение: автоматическая установка KeenDash.
# Установщик САМ находит работающий веб-сервер Entware (nginx или lighttpd),
# определяет его порт и корневую папку из конфига, кладёт файлы туда, где они
# реально откроются, и в конце печатает готовый адрес дашборда.
# Новые порты и новые серверы не создаются — используем то, что уже есть.
# Вся веб-часть живёт в подпапке keendash/, скрипты — в /opt/etc/keendash/,
# оперативка — в /tmp/keendash/. Чужие файлы проект не трогает.
# ============================================================================

REPO_URL="https://raw.githubusercontent.com/YaPA24/KeenDash/main"

echo "🚀 Начинаем установку KeenDash..."

# 0. Проверяем, что curl вообще установлен
command -v curl >/dev/null 2>&1 || { echo "❌ curl не найден. Установи: opkg install curl"; exit 1; }

# ----------------------------------------------------------------------------
# 1. Определяем работающий веб-сервер, его порт и корневую папку
# ----------------------------------------------------------------------------
WEB_SERVER="none"
WEB_ROOT=""
WEB_PORT=""

# Из nginx-конфига берём первый незакомментированный listen и первый root,
# который начинается с "/" (строки с # пропускаются сами — они не совпадают
# с шаблоном начала строки)
parse_nginx_conf() {
  [ -f "$1" ] || return 0
  if [ -z "$WEB_PORT" ]; then
    WEB_PORT=$(sed -n 's/^[[:space:]]*listen[[:space:]][[:space:]]*\([^;]*\);.*/\1/p' "$1" \
      | grep -v 'ssl' \
      | awk '{print $1}' \
      | sed 's/.*://' \
      | grep -E '^[0-9]+$' \
      | head -n 1)
  fi
  if [ -z "$WEB_ROOT" ]; then
    for r in $(sed -n 's/^[[:space:]]*root[[:space:]][[:space:]]*\([^;]*\);.*/\1/p' "$1"); do
      r=$(echo "$r" | sed 's/^"//; s/"$//')
      case "$r" in /*) WEB_ROOT="$r"; break ;; esac
    done
  fi
}

# Из lighttpd-конфига берём server.document-root и server.port
parse_lighttpd_conf() {
  [ -f "$1" ] || return 0
  if [ -z "$WEB_ROOT" ]; then
    WEB_ROOT=$(sed -n 's/^[[:space:]]*server\.document-root[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n 1)
  fi
  if [ -z "$WEB_PORT" ]; then
    WEB_PORT=$(sed -n 's/^[[:space:]]*server\.port[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$1" | head -n 1)
  fi
}

use_nginx() {
  WEB_SERVER="nginx"
  WEB_ROOT=""; WEB_PORT=""
  for f in /opt/etc/nginx/nginx.conf /opt/etc/nginx/conf.d/*.conf; do
    parse_nginx_conf "$f"
  done
  [ -n "$WEB_ROOT" ] || WEB_ROOT="/opt/share/nginx/html"
  [ -n "$WEB_PORT" ] || WEB_PORT="80"
  echo "✅ Работает nginx (Entware): папка $WEB_ROOT, порт $WEB_PORT"
}

use_lighttpd() {
  WEB_SERVER="lighttpd"
  WEB_ROOT=""; WEB_PORT=""
  parse_lighttpd_conf "/opt/etc/lighttpd/lighttpd.conf"
  [ -n "$WEB_ROOT" ] || WEB_ROOT="/opt/share/www"
  [ -n "$WEB_PORT" ] || WEB_PORT="8081"
  echo "✅ Работает lighttpd (Entware): папка $WEB_ROOT, порт $WEB_PORT"
}

echo "🔎 Ищу работающий веб-сервер..."
if pgrep -f "/opt/sbin/nginx" >/dev/null 2>&1; then
  use_nginx
elif pgrep -f "/opt/etc/lighttpd/lighttpd.conf" >/dev/null 2>&1; then
  use_lighttpd
else
  # Сервер установлен, но не запущен — пробуем аккуратно запустить сами
  if [ -x /opt/sbin/nginx ] && [ -f /opt/etc/nginx/nginx.conf ]; then
    echo "ℹ️ nginx установлен, но не запущен — запускаю..."
    [ -x /opt/etc/init.d/S80nginx ] && /opt/etc/init.d/S80nginx start >/dev/null 2>&1
    sleep 2
    pgrep -f "/opt/sbin/nginx" >/dev/null 2>&1 || /opt/sbin/nginx >/dev/null 2>&1
    sleep 2
    pgrep -f "/opt/sbin/nginx" >/dev/null 2>&1 && use_nginx
  fi
  if [ "$WEB_SERVER" = "none" ] && [ -x /opt/sbin/lighttpd ] && [ -f /opt/etc/lighttpd/lighttpd.conf ]; then
    echo "ℹ️ lighttpd установлен, но не запущен — запускаю..."
    [ -x /opt/etc/init.d/S80lighttpd ] && /opt/etc/init.d/S80lighttpd start >/dev/null 2>&1
    sleep 2
    pgrep -f "/opt/etc/lighttpd/lighttpd.conf" >/dev/null 2>&1 && use_lighttpd
  fi
  if [ "$WEB_SERVER" = "none" ]; then
    mkdir -p /opt/share/www
    WEB_ROOT="/opt/share/www"; WEB_PORT="8081"
    echo "⚠️ Работающего веб-сервера в Entware не нашлось."
    echo "   Файлы положу в /opt/share/www/keendash — но чтобы открыть дашборд,"
    echo "   потом понадобится любой веб-сервер (установи и просто перезапусти установку)."
  fi
fi

[ -n "$WEB_ROOT" ] && WEB_ROOT="${WEB_ROOT%/}"   # срезаем лишний завершающий слеш
APP_WEB="$WEB_ROOT/keendash"

# ----------------------------------------------------------------------------
# 2. Подготовка папок проекта
# ----------------------------------------------------------------------------

# Убираем наши старые копии из обоих стандартных мест — чтобы не осталось
# дашборда в папке, которую никто не показывает (только наши папки!)
rm -rf /opt/share/www/keendash /opt/share/nginx/html/keendash

mkdir -p "$APP_WEB" /opt/etc/keendash /opt/etc/ndm/netfilter.d /tmp/keendash

# ----------------------------------------------------------------------------
# 3. Скачиваем файлы — каждый с проверкой
# ----------------------------------------------------------------------------
echo "⬇️ Загрузка файлов..."
get() {
  curl -fLsS --max-time 30 "$REPO_URL/$1" -o "$2" || { echo "❌ Не удалось скачать $1"; exit 1; }
  [ -s "$2" ] || { echo "❌ Файл $1 скачался пустым. Проверь REPO_URL и расположение файлов в репозитории"; exit 1; }
}
get sysinfo.sh      /opt/etc/keendash/sysinfo.sh
get 200-keendash.sh /opt/etc/ndm/netfilter.d/200-keendash.sh
get index.html      "$APP_WEB/index.html"
get dash.html       "$APP_WEB/dash.html"

# ----------------------------------------------------------------------------
# 4. Права на исполнение
# ----------------------------------------------------------------------------
chmod +x /opt/etc/keendash/sysinfo.sh
chmod +x /opt/etc/ndm/netfilter.d/200-keendash.sh

# ----------------------------------------------------------------------------
# 5. Останавливаем работающий демон KeenDash (если это переустановка)
# ----------------------------------------------------------------------------
echo "🧹 Остановка работающего демона (если запущен)..."
kill $(cat /var/run/keendash.pid 2>/dev/null) 2>/dev/null
pkill -f "200-keendash" 2>/dev/null
pkill -f "/opt/etc/keendash/sysinfo.sh" 2>/dev/null
sleep 1

# ----------------------------------------------------------------------------
# 6. Свежий старт данных в оперативке (история начинается заново)
# ----------------------------------------------------------------------------
rm -rf /tmp/keendash
mkdir -p /tmp/keendash

# ----------------------------------------------------------------------------
# 7. Симлинки (ярлыки) из папки проекта в оперативную память
# ----------------------------------------------------------------------------
echo "🔗 Создание симлинков в $APP_WEB..."
rm -f "$APP_WEB/data.json" "$APP_WEB/sysinfo-history.json"
ln -sf /tmp/keendash/data.json "$APP_WEB/data.json"
ln -sf /tmp/keendash/sysinfo-history.json "$APP_WEB/sysinfo-history.json"

# ----------------------------------------------------------------------------
# 8. Запускаем демон
# ----------------------------------------------------------------------------
echo "▶️ Запуск демона..."
/opt/etc/ndm/netfilter.d/200-keendash.sh

# ----------------------------------------------------------------------------
# 9. Готовый адрес и памятка для uninstall
# ----------------------------------------------------------------------------
DASH_IP=$(ip -4 addr show br0 2>/dev/null | sed -n 's/^[[:space:]]*inet \([0-9.]*\).*/\1/p' | head -n 1)
[ -n "$DASH_IP" ] || DASH_IP=$(ip -4 addr show Br0 2>/dev/null | sed -n 's/^[[:space:]]*inet \([0-9.]*\).*/\1/p' | head -n 1)
[ -n "$DASH_IP" ] || DASH_IP="192.168.1.1"

if [ "$WEB_PORT" = "80" ]; then
  DASH_URL="http://$DASH_IP/keendash/dash.html"
else
  DASH_URL="http://$DASH_IP:$WEB_PORT/keendash/dash.html"
fi

# Параметры установки сохраняем — uninstall и памятки берут их отсюда
cat > /opt/etc/keendash/install.env <<EOF
WEB_SERVER=$WEB_SERVER
WEB_ROOT=$WEB_ROOT
WEB_PORT=$WEB_PORT
DASH_URL=$DASH_URL
EOF

echo ""
echo "✅ Установка успешно завершена!"
echo "──────────────────────────────────────────────"
echo "🌐 Дашборд с графиками:  $DASH_URL"
echo "📇 Компактная карточка:  ${DASH_URL%dash.html}index.html"
echo "──────────────────────────────────────────────"
echo "ℹ️ Сервер: $WEB_SERVER · папка: $APP_WEB · порт: $WEB_PORT"
echo "ℹ️ Адрес сохранён в /opt/etc/keendash/install.env"
[ "$WEB_SERVER" = "none" ] && echo "⚠️ Веб-сервер не найден — пока адрес не откроется, см. примечание выше."
exit 0
