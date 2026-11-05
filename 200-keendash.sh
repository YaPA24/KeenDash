#!/bin/sh
# ============================================================================
# Файл: /opt/etc/ndm/netfilter.d/200-keendash.sh
# Назначение: фоновый цикл обновления датчиков KeenDash каждые 3 секунды
# Запускается автоматически при старте NDM (Keenetic)
# ============================================================================

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
