#!/bin/sh
# ============================================================================
# Файл: install.sh
# Назначение: автоматическая установка KeenDash одной командой.
#
# Логика простая и одинаковая для всех:
# 1) Если в Entware уже работает веб-сервер — установщик сам определяет его
#    порт и папку из конфига и кладёт файлы туда, где они реально откроются.
# 2) Если рабочего сервера нет — установщик сам ставит стандартный lighttpd
#    (порт 8081, папка /opt/share/www), запускает его и прописывает в
#    автозагрузку. Так у любого нового пользователя один и тот же адрес.
# 3) В конце установщик сам проверяет по HTTP, что страница отдаётся.
#
# Ручной настройки нет. Новые порты не придумываются: 8081 — стандартный
# порт lighttpd в Entware. Веб-часть живёт в подпапке keendash/, скрипты —
# в /opt/etc/keendash/, оперативка — в /tmp/keendash/. Чужие файлы не трогаем.
# ============================================================================

REPO_URL="https://raw.githubusercontent.com/YaPA24/KeenDash/main"

echo "🚀 Начинаем установку KeenDash..."

# 0. Проверяем, что curl вообще установлен
command -v curl >/dev/null 2>&1 || { echo "❌ curl не найден. Установи: opkg install curl"; exit 1; }

# ----------------------------------------------------------------------------
# 1. Парсеры конфигов: узнаём порт и корневую папку сервера
# ----------------------------------------------------------------------------
WEB_SERVER="none"
WEB_ROOT=""
WEB_PORT=""

# nginx: первый незакомментированный listen (ssl-строки пропускаем) и первый
# root, начинающийся с "/" (комментарии не совпадают с шаблоном начала строки)
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

# lighttpd: server.document-root и server.port
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

# Гарантируем конфиг и автозагрузку lighttpd, запускаем, при сбое печатаем ответ
try_start_lighttpd() {
  [ -f /opt/etc/lighttpd/lighttpd.conf ] || {
    mkdir -p /opt/etc/lighttpd
    printf 'server.port = 8081\nserver.document-root = "/opt/share/www/"\n' > /opt/etc/lighttpd/lighttpd.conf
  }
  if [ ! -x /opt/etc/init.d/S80lighttpd ]; then
    mkdir -p /opt/etc/init.d
    printf '#!/bin/sh\nCONF=/opt/etc/lighttpd/lighttpd.conf\ncase "$1" in\n  start) /opt/sbin/lighttpd -f "$CONF" ;;\n  stop) kill $(pgrep -f "lighttpd -f $CONF") 2>/dev/null ;;\n  restart) $0 stop; sleep 1; $0 start ;;\n  *) echo "Использование: $0 {start|stop|restart}" ;;\nesac\n' > /opt/etc/init.d/S80lighttpd
    chmod +x /opt/etc/init.d/S80lighttpd
  fi
  ERR=$(/opt/etc/init.d/S80lighttpd start 2>&1)
  [ -n "$ERR" ] && echo "   init-скрипт ответил: $ERR"
  sleep 2
  if ! pgrep -f "/opt/etc/lighttpd/lighttpd.conf" >/dev/null 2>&1; then
    ERR=$(/opt/sbin/lighttpd -f /opt/etc/lighttpd/lighttpd.conf 2>&1)
    [ -n "$ERR" ] && echo "   прямой запуск ответил: $ERR"
    sleep 2
  fi
  pgrep -f "/opt/etc/lighttpd/lighttpd.conf" >/dev/null 2>&1 && use_lighttpd
}

# ----------------------------------------------------------------------------
# 2. Ищем УЖЕ работающий сервер (чужие рабочие настройки уважаем)
# ----------------------------------------------------------------------------
echo "🔎 Ищу работающий веб-сервер..."
if pgrep -f "/opt/sbin/nginx" >/dev/null 2>&1; then
  use_nginx
elif pgrep -f "/opt/etc/lighttpd/lighttpd.conf" >/dev/null 2>&1; then
  use_lighttpd
fi

# ----------------------------------------------------------------------------
# 3. Сервера нет — поднимаем lighttpd (сначала найденный, потом свежеустановленный)
# ----------------------------------------------------------------------------
if [ "$WEB_SERVER" = "none" ] && [ -x /opt/sbin/lighttpd ]; then
  echo "ℹ️ lighttpd установлен, но не запущен — запускаю..."
  try_start_lighttpd
fi

# Совсем нет lighttpd — ставим его сами (это стандартный путь для нового пользователя)
if [ "$WEB_SERVER" = "none" ] && [ ! -x /opt/sbin/lighttpd ]; then
  echo "📦 Веб-сервера нет. Ставлю стандартный lighttpd Entware (порт 8081)... это займёт до минуты."
  opkg update >/dev/null 2>&1
  OPKG_ERR=$(opkg install lighttpd 2>&1)
  if [ -x /opt/sbin/lighttpd ]; then
    echo "✅ lighttpd установлен"
    echo "ℹ️ Запускаю..."
    try_start_lighttpd
  else
    echo "❌ Не удалось установить lighttpd:"
    echo "$OPKG_ERR" | tail -n 4
  fi
fi

# lighttpd не получился, но стоит nginx — пробуем поднять его (чужой ручной сервер)
if [ "$WEB_SERVER" = "none" ] && [ -x /opt/sbin/nginx ] && [ -f /opt/etc/nginx/nginx.conf ]; then
  echo "ℹ️ Пробую поднять установленный nginx..."
  if [ -x /opt/etc/init.d/S80nginx ]; then
    ERR=$(/opt/etc/init.d/S80nginx start 2>&1)
    [ -n "$ERR" ] && echo "   init-скрипт ответил: $ERR"
  fi
  sleep 2
  if ! pgrep -f "/opt/sbin/nginx" >/dev/null 2>&1; then
    ERR=$(/opt/sbin/nginx 2>&1)
    [ -n "$ERR" ] && echo "   прямой запуск ответил: $ERR"
    sleep 2
  fi
  if pgrep -f "/opt/sbin/nginx" >/dev/null 2>&1; then
    use_nginx
    if [ ! -x /opt/etc/init.d/S80nginx ]; then
      mkdir -p /opt/etc/init.d
      printf '#!/bin/sh\ncase "$1" in\n  start) /opt/sbin/nginx ;;\n  stop) /opt/sbin/nginx -s stop ;;\n  restart) $0 stop; sleep 1; $0 start ;;\n  *) echo "Использование: $0 {start|stop|restart}" ;;\nesac\n' > /opt/etc/init.d/S80nginx
      chmod +x /opt/etc/init.d/S80nginx
    fi
  fi
fi

# Совсем ничего не получилось — честно говорим об этом
if [ "$WEB_SERVER" = "none" ]; then
  mkdir -p /opt/share/www
  WEB_ROOT="/opt/share/www"; WEB_PORT="8081"
  echo "⚠️ Веб-сервер поднять не удалось. Файлы лежат в /opt/share/www/keendash."
  echo "   Проверь интернет на роутере и выполни вручную:"
  echo "   opkg update && opkg install lighttpd"
  echo "   — затем просто повтори установку той же командой."
fi

[ -n "$WEB_ROOT" ] && WEB_ROOT="${WEB_ROOT%/}"   # срезаем лишний завершающий слеш
APP_WEB="$WEB_ROOT/keendash"

# ----------------------------------------------------------------------------
# 4. Подготовка папок проекта
# ----------------------------------------------------------------------------

# Убираем наши старые копии из обоих стандартных мест — чтобы не осталось
# дашборда в папке, которую никто не показывает (только наши папки!)
rm -rf /opt/share/www/keendash /opt/share/nginx/html/keendash

mkdir -p "$APP_WEB" /opt/etc/keendash /opt/etc/ndm/netfilter.d /tmp/keendash

# ----------------------------------------------------------------------------
# 5. Скачиваем файлы — каждый с проверкой
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
# 6. Права на исполнение
# ----------------------------------------------------------------------------
chmod +x /opt/etc/keendash/sysinfo.sh
chmod +x /opt/etc/ndm/netfilter.d/200-keendash.sh

# ----------------------------------------------------------------------------
# 7. Останавливаем работающий демон KeenDash (если это переустановка)
# ----------------------------------------------------------------------------
echo "🧹 Остановка работающего демона (если запущен)..."
kill $(cat /var/run/keendash.pid 2>/dev/null) 2>/dev/null
pkill -f "200-keendash" 2>/dev/null
pkill -f "/opt/etc/keendash/sysinfo.sh" 2>/dev/null
sleep 1

# ----------------------------------------------------------------------------
# 8. Свежий старт данных в оперативке (история начинается заново)
# ----------------------------------------------------------------------------
rm -rf /tmp/keendash
mkdir -p /tmp/keendash

# ----------------------------------------------------------------------------
# 9. Симлинки (ярлыки) из папки проекта в оперативную память
# ----------------------------------------------------------------------------
echo "🔗 Создание симлинков в $APP_WEB..."
rm -f "$APP_WEB/data.json" "$APP_WEB/sysinfo-history.json"
ln -sf /tmp/keendash/data.json "$APP_WEB/data.json"
ln -sf /tmp/keendash/sysinfo-history.json "$APP_WEB/sysinfo-history.json"

# ----------------------------------------------------------------------------
# 10. Запускаем демон
# ----------------------------------------------------------------------------
echo "▶️ Запуск демона..."
/opt/etc/ndm/netfilter.d/200-keendash.sh

# ----------------------------------------------------------------------------
# 11. Готовый адрес и памятка для uninstall
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

# ----------------------------------------------------------------------------
# 12. Самопроверка: реально ли страница отдаётся
# ----------------------------------------------------------------------------
sleep 1
CHECK=$(curl -fsS -m 5 "http://127.0.0.1:$WEB_PORT/keendash/index.html" 2>/dev/null | head -c 20)

echo ""
echo "✅ Установка успешно завершена!"
echo "──────────────────────────────────────────────"
echo "🌐 Дашборд с графиками:  $DASH_URL"
echo "📇 Компактная карточка:  ${DASH_URL%dash.html}index.html"
echo "──────────────────────────────────────────────"
echo "ℹ️ Сервер: $WEB_SERVER · папка: $APP_WEB · порт: $WEB_PORT"
echo "ℹ️ Адрес сохранён в /opt/etc/keendash/install.env"

if [ -n "$CHECK" ]; then
  echo "✅ Самопроверка прошла: страница реально отдаётся."
else
  if [ "$WEB_SERVER" = "none" ]; then
    echo "⚠️ Самопроверка не прошла: веб-сервера нет — см. блокировку выше."
  else
    echo "⚠️ Самопроверка не прошла: страница пока не отвечает. Диагностика:"
    netstat -ltn 2>/dev/null | grep -E "[:.]$WEB_PORT[[:space:]]" || echo "   • порт $WEB_PORT никто не слушает"
    for L in /opt/var/log/lighttpd/error.log /opt/var/log/nginx/error.log; do
      [ -f "$L" ] && { echo "   журнал $L (последние строки):"; tail -n 3 "$L" | sed 's/^/     /'; }
    done
    echo "   Пришли этот вывод автору проекта — разберёмся."
  fi
fi
exit 0
