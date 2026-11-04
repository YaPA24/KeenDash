#!/bin/sh
# ============================================================================
# Файл: /opt/bin/sysinfo.sh
# Назначение: сбор системных данных роутера в JSON (оптимизировано)
# ============================================================================

STATIC=/tmp/sysinfo-static.env
if [ ! -f "$STATIC" ]; then
  jget() { echo "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"; }
  VJSON=""
  command -v curl >/dev/null 2>&1 && VJSON=$(curl -s --max-time 2 "http://127.0.0.1:79/rci/show/version" 2>/dev/null)
  
  DEVICE=$(jget "$VJSON" device)
  HW_ID=$(jget "$VJSON" hw_id)
  REGION=$(jget "$VJSON" region)
  FW_TITLE=$(jget "$VJSON" title)
  FW_RELEASE=$(jget "$VJSON" release)
  
  [ -z "$DEVICE" ] && DEVICE=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null)
  [ -z "$DEVICE" ] && DEVICE=$(cat /proc/sys/kernel/hostname 2>/dev/null)
  
  MODEL_STR="$DEVICE"
  [ -n "$HW_ID" ]  && MODEL_STR="$MODEL_STR ($HW_ID)"
  [ -n "$REGION" ] && MODEL_STR="$MODEL_STR ($REGION)"
  
  if [ -n "$FW_TITLE" ] && [ -n "$FW_RELEASE" ] && [ "$FW_TITLE" != "$FW_RELEASE" ]; then
    OS_STR="$FW_TITLE ($FW_RELEASE)"
  elif [ -n "$FW_RELEASE" ]; then OS_STR="$FW_RELEASE"
  elif [ -n "$FW_TITLE" ];  then OS_STR="$FW_TITLE"
  else OS_STR=$(uname -r 2>/dev/null); fi
  
  SLOT=$(cat /proc/dual_image/boot_current 2>/dev/null)
  
  CPU=$(strings /lib/libndmMwsController.so 2>/dev/null | grep -oE 'MT76[0-9A-Za-z]+|MT79[0-9A-Za-z]+|EN75[0-9A-Za-z]+' | head -n 1)
  [ -z "$CPU" ] && CPU=$(tr -d '\0' < /proc/device-tree/compatible 2>/dev/null | grep -oE 'mt[0-9]+' | head -n 1 | tr '[:lower:]' '[:upper:]')
  [ -z "$CPU" ] && CPU="$DEVICE"
  CPU_STR="$CPU ($(uname -m))"
  
  cat <<ENV > "$STATIC"
MODEL_STR="$MODEL_STR"
OS_STR="$OS_STR"
SLOT="$SLOT"
CPU_STR="$CPU_STR"
ENV
fi
. "$STATIC"

# --- Динамика: Загрузка CPU + память (один вызов awk для скорости) ---
eval $(awk '
  /^cpu /          { print "STAT_T="$2+$3+$4+$5+$6+$7+$8+$9" STAT_I="$5+$6; next }
  /^MemTotal:/     { print "MEM_T="int($2/1024); next }
  /^MemAvailable:/ { print "MEM_A="int($2/1024); next }
  /^MemFree:/      { print "MEM_F="int($2/1024); next }
' /proc/stat /proc/meminfo)
[ -z "$MEM_A" ] && MEM_A=$MEM_F

CPU_PCT=""
if [ -f /tmp/cpu-stat.prev ]; then
  read -r OT OI < /tmp/cpu-stat.prev
  DT=$((STAT_T - OT)); DI=$((STAT_I - OI))
  [ "$DT" -gt 0 ] && CPU_PCT=$(( (DT - DI) * 100 / DT ))
fi
echo "$STAT_T $STAT_I" > /tmp/cpu-stat.prev

MEM_PCT=0; RAM_STR="N/D"
if [ -n "$MEM_T" ] && [ "$MEM_T" -gt 0 ]; then
  MEM_USED=$((MEM_T - MEM_A))
  MEM_PCT=$((MEM_USED * 100 / MEM_T))
  RAM_STR="${MEM_USED} / ${MEM_T} MB"
fi

# --- Температуры (умная раскладка зон) ---
# Порядок thermal-зон на разных чипах разный:
#   3 зоны  -> CPU, 2.4G, 5G            (MT7622, MT7981, MT7986...)
#   2 зоны  -> обе Wi-Fi: 2.4G, 5G      (MT7620, MT7621 - у них нет датчика CPU)
#   1 зона  -> единственное радио 2.4G
CPU_C="N/D"; G24_C="N/D"; G5_C="N/D"
TZ1=""; TZ2=""; TZ3=""; NZ=0
for z in 0 1 2; do
  T=$(cat "/sys/class/thermal/thermal_zone$z/temp" 2>/dev/null)
  case "$T" in ''|*[!0-9]*) continue ;; esac
  NZ=$((NZ+1))
  eval "TZ$NZ=$T"
done
if [ "$NZ" -ge 3 ]; then
  CPU_C="$((TZ1/1000))°C"; G24_C="$((TZ2/1000))°C"; G5_C="$((TZ3/1000))°C"
elif [ "$NZ" -eq 2 ]; then
  G24_C="$((TZ1/1000))°C"; G5_C="$((TZ2/1000))°C"
elif [ "$NZ" -eq 1 ]; then
  G24_C="$((TZ1/1000))°C"
fi

# --- Аптайм ---
read -r UP_S _ < /proc/uptime
UP_SEC=${UP_S%%.*}
D=$((UP_SEC/86400)); H=$(((UP_SEC%86400)/3600))
M=$(((UP_SEC%3600)/60));  S=$((UP_SEC%60))
if [ "$D" -gt 0 ]; then UPTIME_STR=$(printf "%dd %02d:%02d:%02d" "$D" "$H" "$M" "$S")
else UPTIME_STR=$(printf "%02d:%02d:%02d" "$H" "$M" "$S"); fi

# --- OPKG ---
OPKG_STR=$(df -k /opt 2>/dev/null | awk 'NR==2{
  u=$3*1024; t=$2*1024; mb=1048576; gb=mb*1024;
  if (t>=gb) printf "%d MB / %.2f GB", u/mb, t/gb;
  else       printf "%d MB / %d MB",   u/mb, t/mb}')
[ -z "$OPKG_STR" ] && OPKG_STR="N/D"

DATETIME=$(date "+%d.%m.%Y %H:%M:%S")

# ========== JSON: атомарная запись в tmpfs (бережём флешку!) ==========
cat <<JSON > /tmp/data.json.tmp
{
  "datetime": "${DATETIME}",
  "model": "${MODEL_STR}",
  "os": "${OS_STR}",
  "slot": "${SLOT}",
  "cpu": "${CPU_STR}",
  "cpu_pct": "${CPU_PCT}",
  "cpu_temp": "${CPU_C}",
  "g24_temp": "${G24_C}",
  "g5_temp": "${G5_C}",
  "ram": "${RAM_STR}",
  "ram_pct": ${MEM_PCT},
  "opkg": "${OPKG_STR}",
  "uptime": "${UPTIME_STR}"
}
JSON
mv -f /tmp/data.json.tmp /tmp/data.json

# ========== ИСТОРИЯ ГРАФИКОВ: построчный JSON в оперативке ==========
# Одна строка = одна точка. Никаких jq и перезаписи всего файла:
# точка просто дописывается в конец (доли миллисекунды при любом размере).
# Хвост подрезаем до 3600 строк = 3 часа при тике 3 секунды.
HIST=/tmp/sysinfo-history.json
[ -f "$HIST" ] || : > "$HIST"
num() { echo "$1" | tr -dc '0-9'; }
jn()  { case "$1" in "") echo null ;; *) echo "$1" ;; esac; }
echo "{\"ts\":$(date +%s),\"cpu\":${CPU_PCT:-null},\"ram\":${MEM_PCT:-0},\"tcpu\":$(jn "$(num "$CPU_C")"),\"t24\":$(jn "$(num "$G24_C")"),\"t5\":$(jn "$(num "$G5_C")")}" >> "$HIST"
if [ "$(wc -l < "$HIST")" -gt 3600 ]; then
  tail -n 3600 "$HIST" > "$HIST.tmp" && mv -f "$HIST.tmp" "$HIST"
fi