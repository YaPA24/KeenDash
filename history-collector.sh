#!/bin/sh
HIST_FILE=/tmp/sysinfo-history.json

# Инициализация файла
if [ ! -f "$HIST_FILE" ]; then
  echo '[]' > "$HIST_FILE"
fi

while true; do
  # Читаем текущие данные
  CPU=$(awk '/^cpu /{print int(($2+$3+$4)*100/($2+$3+$4+$5))}' /proc/stat)
  RAM=$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{print int((t-a)*100/t)}' /proc/meminfo)
  
  # Добавляем точку в историю (храним последние 600 точек = 30 мин при тике 3 сек)
  TEMP=$(mktemp)
  jq --arg cpu "$CPU" --arg ram "$RAM" --arg ts "$(date +%s)" \
    '. += [{ts:($ts|tonumber), cpu:($cpu|tonumber), ram:($ram|tonumber)}] | .[-600:]' \
    "$HIST_FILE" > "$TEMP" && mv "$TEMP" "$HIST_FILE"
  
  sleep 3
done &