#!/bin/sh
# ============================================================================
# Файл: /opt/etc/ndm/netfilter.d/200-sysinfo-loop.sh
# Назначение: фоновый цикл обновления датчиков каждые 3 секунды
# Запускается автоматически при старте NDM (Keenetic)
# ============================================================================

PIDFILE=/var/run/sysinfo-loop.pid

# Защита от дублей
if [ -f "$PIDFILE" ] && kill -0 "$(cat $PIDFILE)" 2>/dev/null; then
  exit 0
fi

# Очистка кеша при старте для пересчета статики
rm -f /tmp/sysinfo-static.env /tmp/cpu-stat.prev

# Вывод в никуда, чтобы не мешать ndm держать свой канал
while true; do
  /opt/bin/sysinfo.sh >/dev/null 2>&1
  sleep 3
done >/dev/null 2>&1 &

echo $! > "$PIDFILE"