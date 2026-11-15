#!/bin/zsh
# Liest im Normalmodus (Bootschleife) die alog-Puffer stückweise, nur lesend.
# Wartet, bis der Debug-Port antwortet, dann WARTE Sekunden, dann bis zu
# 2 Durchläufe von Stufe 2f (jeweils mit Wiederholungen pro Stück).
set -u
cd "$(dirname "$0")"
WARTE=${1:-12}
pkill -x openocd 2>/dev/null
echo "Warte auf Debug-Port ..."
for i in {1..120}; do
  r=$(timeout 5 openocd -c "adapter driver cmsis-dap; adapter speed 1000; transport select swd; swd newdap a7 cpu -enable; dap create a7.dap -chain-position a7.cpu; gdb_port disabled; tcl_port disabled; telnet_port disabled; init; shutdown" 2>&1 | grep -o "DPIDR 0x3ba02477")
  [[ -n "$r" ]] && { echo "$(date +%H:%M:%S) Debug-Port da."; break; }
  sleep 0.3
done
echo "Warte ${WARTE} s, damit mehrere Zyklen im Log stehen ..."; sleep $WARTE
for lauf in 1 2; do
  echo "== Durchlauf $lauf $(date +%H:%M:%S)"
  timeout 60 ./start_stufe.sh 2f 2>&1 | grep -E "FEHLT|Trailer|Ordner|nach ([2-9]|1[0-5]) Versuch"
  pkill -x openocd 2>/dev/null
done
