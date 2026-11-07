#!/bin/sh
# ============================================================================
# Файл: install.sh
# Назначение: автоматическая установка KeenDash одной командой.
#
# Инсталлятор сам делает ВСЁ правильно — никакой ручной настройки. У KeenDash
# теперь СВОЙ веб-сервер на выделенном порту 8321, поэтому результат один и
# тот же на любом роутере, что бы там ни было настроено руками раньше:
#
#  0) Прежняя установка ещё жива и порт отвечает? → используем её, адрес
#     не меняется (переустановка не ломает работающее).
#  1) lighttpd установлен? → поднимаем СОБСТВЕННЫЙ экземпляр KeenDash:
#     отдельный конфиг /opt/etc/keendash/lighttpd.conf, порт 8321
#     (резерв 8322–8330), корень /opt/share/www. Чужие конфиги (nginx,
#     системный lighttpd, панели вроде zapret) не трогаем вообще.
#  2) lighttpd нет? → установщик сам ставит его (opkg install lighttpd)
#     и поднимает свой экземпляр на том же порту 8321.
#  3) И это не вышло? → используем УЖЕ РАБОТАЮЩИЙ системный nginx или
#     lighttpd: порт и папку вычисляем из его конфига и просто кладём
#     файлы туда. Спящие серверы не будим, чтобы не ловить «Address
#     already in use» (порт может быть занят панелью zapret и т.п.).
#  4) Совсем резерв: встроенный в KeeneticOS busybox httpd на порту 8321.
#  5) Ничего не помогло? → честная ошибка с диагностикой, без выдуманных
#     адресов (именно так появлялся ERR_CONNECTION_REFUSED).
#
# Почему 8321: 80/443 всегда заняты KeeneticOS, 8081/8088 часто заняты
# панелями (zapret и т.п.), 7777 остался у кого-то от старых ручных настроек.
# 8321 — выделенный порт проекта, у нового пользователя адрес всегда
# http://IP:8321/keendash/dash.html. Свой сервер переживает перезагрузку:
# хук 200-keendash.sh при старте роутера проверяет порт и поднимает сервер.
#
# В конце установщик сам проверяет по HTTP, что страница реально отдаётся.
# ============================================================================

REPO_URL="https://raw.githubusercontent.com/YaPA24/KeenDash/main"

echo "Начинаем установку KeenDash..."

# 0. Проверяем, что curl вообще установлен
command -v curl >/dev/null 2>&1 || { echo "❌ curl не найден. Установи: opkg install curl"; exit 1; }

WEB_SERVER="none"
WEB_ROOT=""
WEB_PORT=""
KD_PORTS="8321 8322 8323 8324 8325 8326 8327 8328 8329 8330"
KD_CONF="/opt/etc/keendash/lighttpd.conf"

# ----------------------------------------------------------------------------
# 1. Помощники: проверка HTTP и занятости порта
# ----------------------------------------------------------------------------

# Любой HTTP-ответ (хоть 403/404) = сервер жив и умеет отдавать файлы.
# (Раньше требовали код 200 — и браковали живой сервер с пустым корнем.)
http_ok() {
  CODE=$(curl -s -o /dev/null -m 3 -w '%{http_code}' "http://127.0.0.1:$1$2" 2>/dev/null)
  case "$CODE" in [1-5][0-9][0-9]) return 0 ;; *) return 1 ;; esac
}

# Занят ли порт: подключиться НЕ удалось (refused) → свободен; любой ответ
# или зависание → занят кем-то другим.
port_busy() {
  curl -s -o /dev/null -m 1 "http://127.0.0.1:$1/" 2>/dev/null
  [ "$?" -ne 7 ]
}

# ----------------------------------------------------------------------------
# 2. Парсеры чужих конфигов (нужны только для шага 3; сами конфиги не меняем)
# ----------------------------------------------------------------------------

# nginx: первый незакомментированный listen (ssl-строки пропускаем) и первый
# root, начинающийся с "/"
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

# ----------------------------------------------------------------------------
# 3. Шаг 0: прежняя установка ещё работает? — используем её (адрес сохранится)
# ----------------------------------------------------------------------------
if [ -f /opt/etc/keendash/install.env ]; then
  OLD_SERVER=$(sed -n 's/^WEB_SERVER=//p' /opt/etc/keendash/install.env | head -n 1)
  OLD_ROOT=$(sed  -n 's/^WEB_ROOT=//p'  /opt/etc/keendash/install.env | head -n 1)
  OLD_PORT=$(sed  -n 's/^WEB_PORT=//p'  /opt/etc/keendash/install.env | head -n 1)
  if [ -n "$OLD_PORT" ] && [ -n "$OLD_ROOT" ] && [ "$OLD_SERVER" != "none" ] && http_ok "$OLD_PORT" /; then
    WEB_SERVER="$OLD_SERVER"
    WEB_ROOT="${OLD_ROOT%/}"
    WEB_PORT="$OLD_PORT"
    echo "✅ Прошлая установка жива: сервер $WEB_SERVER отвечает на порту $WEB_PORT — переиспользую."
  fi
fi

# ----------------------------------------------------------------------------
# 4. Собственный экземпляр lighttpd KeenDash (порт 8321, резерв 8322–8330)
# ----------------------------------------------------------------------------
write_own_lighttpd_conf() {
  mkdir -p /opt/etc/keendash /opt/share/www
  cat > "$KD_CONF" <<EOF
# Собственный веб-сервер KeenDash. Управляется установщиком; при загрузке
# роутера поднимается хуком /opt/etc/ndm/netfilter.d/200-keendash.sh.
server.port          = $1
server.bind          = "0.0.0.0"
server.document-root = "/opt/share/www/"
server.upload-dirs   = ( "/tmp" )
server.pid-file      = "/tmp/keendash-lighty.pid"
index-file.names     = ( "index.html", "dash.html" )
mimetype.assign      = (
  ".html" => "text/html; charset=utf-8",
  ".htm"  => "text/html; charset=utf-8",
  ".js"   => "text/javascript",
  ".css"  => "text/css",
  ".json" => "application/json",
  ".png"  => "image/png",
  ".svg"  => "image/svg+xml",
  ".ico"  => "image/x-icon",
  ".txt"  => "text/plain"
)
EOF
}

try_own_lighttpd() {
  [ -x /opt/sbin/lighttpd ] || return 1

  # Уже запущен (хук поднял после ребута, а install.env затёрся)?
  if [ -f "$KD_CONF" ] && pgrep -f "lighttpd -f $KD_CONF" >/dev/null 2>&1; then
    P=$(sed -n 's/^[[:space:]]*server\.port[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$KD_CONF" | head -n 1)
    if [ -n "$P" ] && http_ok "$P" /; then
      WEB_SERVER="lighttpd-keendash"; WEB_ROOT="/opt/share/www"; WEB_PORT="$P"
      echo "✅ Собственный lighttpd KeenDash уже работает на порту $P."
      return 0
    fi
  fi

  echo "Поднимаю собственный веб-сервер KeenDash (выделенный порт 8321)..."
  for P in $KD_PORTS; do
    port_busy "$P" && continue
    write_own_lighttpd_conf "$P"
    ERR=$(/opt/sbin/lighttpd -f "$KD_CONF" 2>&1)
    sleep 1
    if ! http_ok "$P" /; then sleep 1; fi
    if http_ok "$P" /; then
      WEB_SERVER="lighttpd-keendash"; WEB_ROOT="/opt/share/www"; WEB_PORT="$P"
      echo "✅ Собственный lighttpd KeenDash запущен на порту $P."
      return 0
    fi
    [ -n "$ERR" ] && echo "   порт $P не подошёл: $ERR"
  done
  echo "⚠️Свой lighttpd поднять не получилось (порты 8321–8330 заняты или сервер не стартует)."
  return 1
}

# Шаг 1: lighttpd установлен — поднимаем свой экземпляр
if [ "$WEB_SERVER" = "none" ] && [ -x /opt/sbin/lighttpd ]; then
  try_own_lighttpd
fi

# Шаг 2: lighttpd нет — установщик сам его ставит и поднимает свой экземпляр
if [ "$WEB_SERVER" = "none" ] && [ ! -x /opt/sbin/lighttpd ]; then
  echo "lighttpd не установлен — ставлю сам (opkg install lighttpd), это займёт до минуты..."
  OPKG_ERR=""
  opkg install lighttpd >/dev/null 2>&1
  if [ ! -x /opt/sbin/lighttpd ]; then
    opkg update >/dev/null 2>&1
    OPKG_ERR=$(opkg install lighttpd 2>&1)
  fi
  if [ -x /opt/sbin/lighttpd ]; then
    echo "✅ lighttpd установлен."
    try_own_lighttpd
  else
    echo "⚠️opkg не смог установить lighttpd:"
    echo "${OPKG_ERR:-нет ответа opkg}" | tail -n 4
  fi
fi

# ----------------------------------------------------------------------------
# 5. Шаг 3: используем уже РАБОТАЮЩИЙ системный сервер (спящих не будим!)
# ----------------------------------------------------------------------------
try_reuse_running() {
  if [ -d /opt/etc/nginx ]; then
    WEB_ROOT=""; WEB_PORT=""
    parse_nginx_conf /opt/etc/nginx/nginx.conf
    for f in /opt/etc/nginx/conf.d/*.conf; do parse_nginx_conf "$f"; done
    if [ -n "$WEB_PORT" ] && http_ok "$WEB_PORT" /; then
      WEB_ROOT="${WEB_ROOT:-/opt/share/nginx/html}"
      WEB_ROOT="${WEB_ROOT%/}"
      WEB_SERVER="nginx"
      echo "✅ Использую уже работающий nginx: порт $WEB_PORT, папка $WEB_ROOT."
      return 0
    fi
  fi
  # lighttpd берём только со стандартной папкой, чтобы не залезть в чужие
  # сервисы (панель zapret и т.п.), у которых конфиг/папка свои.
  if [ -f /opt/etc/lighttpd/lighttpd.conf ]; then
    WEB_ROOT=""; WEB_PORT=""
    parse_lighttpd_conf /opt/etc/lighttpd/lighttpd.conf
    if [ -n "$WEB_PORT" ] && http_ok "$WEB_PORT" / && [ "${WEB_ROOT%/}" = "/opt/share/www" ]; then
      WEB_ROOT="/opt/share/www"
      WEB_SERVER="lighttpd"
      echo "✅ Использую уже работающий lighttpd: порт $WEB_PORT, папка $WEB_ROOT."
      return 0
    fi
  fi
  return 1
}

if [ "$WEB_SERVER" = "none" ]; then
  try_reuse_running || true
fi

# ----------------------------------------------------------------------------
# 6. Шаг 4: совсем резерв — встроенный busybox httpd (он есть в KeeneticOS)
# ----------------------------------------------------------------------------
try_busybox_httpd() {
  command -v busybox >/dev/null 2>&1 || return 1
  busybox 2>&1 | grep -qw httpd || return 1
  mkdir -p /opt/share/www
  echo "Резерв: поднимаю встроенный busybox httpd (порт 8321)..."
  for P in $KD_PORTS; do
    port_busy "$P" && continue
    ERR=$(busybox httpd -p "0.0.0.0:$P" -h /opt/share/www 2>&1)
    sleep 1
    if ! http_ok "$P" /; then sleep 1; fi
    if http_ok "$P" /; then
      WEB_SERVER="busybox-httpd"; WEB_ROOT="/opt/share/www"; WEB_PORT="$P"
      echo "✅ busybox httpd запущен на порту $P."
      return 0
    fi
    [ -n "$ERR" ] && echo "   порт $P не подошёл: $ERR"
  done
  return 1
}

if [ "$WEB_SERVER" = "none" ]; then
  try_busybox_httpd || true
fi

# ----------------------------------------------------------------------------
# 7. Шаг 5: ничего не вышло — честно признаёмся (без выдуманных адресов)
# ----------------------------------------------------------------------------
if [ "$WEB_SERVER" = "none" ]; then
  mkdir -p /opt/share/www
  WEB_ROOT="/opt/share/www"
  echo ""
  echo "❌ Не получилось поднять ни один веб-сервер."
  echo "   Пробовали: свой lighttpd на 8321–8330, установку lighttpd через opkg,"
  echo "   уже работающие nginx/lighttpd, встроенный busybox httpd."
  echo "   Чаще всего причина — недоступен репозиторий Entware: проверь «opkg update»."
  echo "   Устрани причину и повтори установку той же командой."
fi

[ -n "$WEB_ROOT" ] && WEB_ROOT="${WEB_ROOT%/}"   # срезаем лишний завершающий слеш
APP_WEB="$WEB_ROOT/keendash"

# ----------------------------------------------------------------------------
# 8. Подготовка папок проекта
# ----------------------------------------------------------------------------

# Убираем наши старые копии из обоих стандартных мест — чтобы не осталось
# дашборда в папке, которую никто не показывает (только наши папки!)
rm -rf /opt/share/www/keendash /opt/share/nginx/html/keendash

mkdir -p "$APP_WEB" /opt/etc/keendash /opt/etc/ndm/netfilter.d /tmp/keendash

# ----------------------------------------------------------------------------
# 9. Скачиваем файлы — каждый с проверкой
# ----------------------------------------------------------------------------
echo "Загрузка файлов..."
get() {
  curl -fLsS --max-time 30 "$REPO_URL/$1" -o "$2" || { echo "❌ Не удалось скачать $1"; exit 1; }
  [ -s "$2" ] || { echo "❌ Файл $1 скачался пустым. Проверь REPO_URL и расположение файлов в репозитории"; exit 1; }
}
get sysinfo.sh      /opt/etc/keendash/sysinfo.sh
get 200-keendash.sh /opt/etc/ndm/netfilter.d/200-keendash.sh
get index.html      "$APP_WEB/index.html"
get dash.html       "$APP_WEB/dash.html"

# ----------------------------------------------------------------------------
# 10. Права на исполнение
# ----------------------------------------------------------------------------
chmod +x /opt/etc/keendash/sysinfo.sh
chmod +x /opt/etc/ndm/netfilter.d/200-keendash.sh

# ----------------------------------------------------------------------------
# 11. Останавливаем работающий демон KeenDash (если это переустановка)
# ----------------------------------------------------------------------------
echo "Остановка работающего демона (если запущен)..."
kill "$(cat /var/run/keendash.pid 2>/dev/null)" 2>/dev/null
pkill -f "200-keendash" 2>/dev/null
pkill -f "/opt/etc/keendash/sysinfo.sh" 2>/dev/null
sleep 1

# ----------------------------------------------------------------------------
# 12. Свежий старт данных в оперативке (история начинается заново)
# ----------------------------------------------------------------------------
rm -rf /tmp/keendash
mkdir -p /tmp/keendash

# ----------------------------------------------------------------------------
# 13. Симлинки (ярлыки) из папки проекта в оперативную память
# ----------------------------------------------------------------------------
echo "Создание симлинков в $APP_WEB..."
rm -f "$APP_WEB/data.json" "$APP_WEB/sysinfo-history.json"
ln -sf /tmp/keendash/data.json "$APP_WEB/data.json"
ln -sf /tmp/keendash/sysinfo-history.json "$APP_WEB/sysinfo-history.json"

# ----------------------------------------------------------------------------
# 14. Запускаем демон
# ----------------------------------------------------------------------------
echo "Запуск демона..."
/opt/etc/ndm/netfilter.d/200-keendash.sh

# ----------------------------------------------------------------------------
# 15. Готовый адрес и памятка для uninstall
# ----------------------------------------------------------------------------
DASH_IP=$(ip -4 addr show br0 2>/dev/null | sed -n 's/^[[:space:]]*inet \([0-9.]*\).*/\1/p' | head -n 1)
[ -n "$DASH_IP" ] || DASH_IP=$(ip -4 addr show Br0 2>/dev/null | sed -n 's/^[[:space:]]*inet \([0-9.]*\).*/\1/p' | head -n 1)
[ -n "$DASH_IP" ] || DASH_IP="192.168.1.1"

DASH_URL=""; OPEN_URL=""
if [ "$WEB_PORT" = "80" ]; then
  DASH_URL="http://$DASH_IP/keendash/dash.html"
  OPEN_URL="http://$DASH_IP/keendash/"
elif [ -n "$WEB_PORT" ]; then
  DASH_URL="http://$DASH_IP:$WEB_PORT/keendash/dash.html"
  OPEN_URL="http://$DASH_IP:$WEB_PORT/keendash/"
fi

# Параметры установки сохраняем — uninstall, хук и памятки берут их отсюда
cat > /opt/etc/keendash/install.env <<EOF
WEB_SERVER=$WEB_SERVER
WEB_ROOT=$WEB_ROOT
WEB_PORT=$WEB_PORT
DASH_URL=$DASH_URL
EOF

# ----------------------------------------------------------------------------
# 16. Итог: баннер и самопроверка — страница должна реально отдаваться
# ----------------------------------------------------------------------------
sleep 1

if [ "$WEB_SERVER" = "none" ]; then
  echo ""
  echo "⚠️Установка завершена ЧАСТИЧНО: файлы и демон на месте, но веб-сервера нет —"
  echo "   страница не откроется. Устрани причину (см. выше) и повтори установку."
  exit 1
fi

CHECK=$(curl -fsS -m 5 "http://127.0.0.1:$WEB_PORT/keendash/index.html" 2>/dev/null | head -c 20)

echo ""
echo "✅ Установка успешно завершена!"
echo "──────────────────────────────────────────────"
echo "Открыть:              $OPEN_URL"
echo "Дашборд с графиками:  $DASH_URL"
echo "──────────────────────────────────────────────"
echo "Сервер: $WEB_SERVER · папка: $APP_WEB · порт: $WEB_PORT"
echo "Адрес сохранён в /opt/etc/keendash/install.env"

if [ "$WEB_SERVER" = "lighttpd-keendash" ] || [ "$WEB_SERVER" = "busybox-httpd" ]; then
  echo "Веб-сервер KeenDash поднимется сам после перезагрузки роутера (хук 200-keendash.sh)."
fi

if [ -n "$CHECK" ]; then
  echo "✅ Самопроверка прошла: страница реально отдаётся."
else
  echo "⚠️Самопроверка не прошла: страница пока не отвечает. Диагностика:"
  netstat -ltn 2>/dev/null | grep -E "[:.]${WEB_PORT}[[:space:]]" || echo "   • порт $WEB_PORT никто не слушает"
  for L in /opt/var/log/lighttpd/error.log /opt/var/log/nginx/error.log; do
    [ -f "$L" ] && { echo "   журнал $L (последние строки):"; tail -n 3 "$L" | sed 's/^/     /'; }
  done
  echo "   Пришли этот вывод автору проекта — разберёмся."
fi
exit 0
