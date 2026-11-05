#!/bin/sh
# ============================================================================
# Файл: /opt/etc/ndm/netfilter.d/200-keendash.sh
# Назначение: автозапуск KeenDash при старте роутера (Keenetic NDM)
#   1) фоновый цикл обновления датчиков каждые 3 секунды
#   2) собственный веб-сервер KeenDash (lighttpd / busybox httpd), если
#      установщик его создал — порт берётся из /opt/etc/keendash/install.env
# ============================================================================

# --- Веб-сервер KeenDash: если молчит — поднимаем ---------------------------
if [ -f /opt/etc/keendash/install.env ]; then
  . /opt/etc/keendash/install.env
  if [ -n "${WEB_PORT:-}" ] && ! curl -s -o /dev/null -m 2 "http://127.0.0.1:$WEB_PORT/" 2>/dev/null; then
    if [ "$WEB_SERVER" = "lighttpd-keendash" ] && [ -x /opt/sbin/lighttpd ] && [ -f /opt/etc/keendash/lighttpd.conf ]; then
      /opt/sbin/lighttpd -f /opt/etc/keendash/lighttpd.conf >/dev/null 2>&1
    elif [ "$WEB_SERVER" = "busybox-httpd" ] && [ -d "${WEB_ROOT:-/opt/share/www}" ]; then
      busybox httpd -p "0.0.0.0:$WEB_PORT" -h "$WEB_ROOT" >/dev/null 2>&1
    fi
  fi
fi

# --- Демон сбора данных -----------------------------------------------------
PIDFILE=/var/run/keendash.pid

# Защита от дублей
if [ -f "$PIDFILE" ] && kill -0 "$(cat $PIDFILE)" 2>/dev/null; then
  exit 0
fi

# Рабочая папка в оперативке
mkdir -p /tmp/keendash

# Очистка кеша при старте для пересчета статики
rm -f /tmp/keendash/sysinfo-static.env /tmp/keendash/cpu-stat.prev

# Вывод в никуда, чтобы не мешать ndm держать свой канал
while true; do
  /opt/etc/keendash/sysinfo.sh >/dev/null 2>&1
  sleep 3
done >/dev/null 2>&1 &

echo $! > "$PIDFILE"
