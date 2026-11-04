#!/bin/sh
# ============================================================================
# Файл: 200-sysinfo-loop.sh
# Назначение: фоновый цикл обновления датчиков каждые 3 секунды
# ============================================================================

PIDFILE=/var/run/sysinfo-loop.pid

# Защита от дублей
if [ -f "$PIDFILE" ] && kill -0 "$(cat $PIDFILE)" 2>/dev/null; then
  exit 0
fi

# Очистка кеша при старте
rm -f /tmp/sysinfo-static.env /tmp/cpu-stat.prev

while true; do
  /opt/bin/sysinfo.sh
  sleep 3
done &

echo $! > "$PIDFILE"