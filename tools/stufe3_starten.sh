#!/bin/zsh
# Wartet, bis der Debug-Port der Kamera antwortet, und startet dann Stufe 3.
# Stufe 3 ist SCHREIBEND (nur r0). Aufruf nur nach Freigabe: ./stufe3_starten.sh JA
set -u
cd "$(dirname "$0")"
[[ "${1:-}" == "JA" ]] || { echo "Nur mit Freigabe: ./stufe3_starten.sh JA"; exit 1; }
pkill -x openocd 2>/dev/null
echo "$(date +%H:%M:%S) Warte auf Debug-Port (Kamera jetzt einschalten) ..."
for i in {1..400}; do
  r=$(timeout 5 openocd -c "adapter driver cmsis-dap; adapter speed 1000; transport select swd; swd newdap a7 cpu -enable; dap create a7.dap -chain-position a7.cpu; gdb_port disabled; tcl_port disabled; telnet_port disabled; init; shutdown" 2>&1 | grep -o "DPIDR 0x3ba02477")
  if [[ -n "$r" ]]; then echo "$(date +%H:%M:%S) Debug-Port da, starte Stufe 3."; exec ./start_stufe.sh 3 JA; fi
  sleep 0.2
done
echo "Kein Debug-Port innerhalb der Wartezeit."
