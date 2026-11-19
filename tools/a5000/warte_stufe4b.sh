#!/bin/zsh
# Wartet auf den Debug-Port und startet Stufe 4b (Kaltstart erzwingen, schreibt nur r0).
set -u
[[ "${1:-}" == "JA" ]] || { echo "Nur mit Freigabe: ./warte_stufe4b.sh JA"; exit 1; }
cd "$(dirname "$0")"
if pgrep -x openocd >/dev/null; then echo "OpenOCD läuft schon."; exit 1; fi
echo "$(date +%H:%M:%S) Warte auf Debug-Port (Kamera jetzt einschalten) ..."
for i in {1..400}; do
  r=$(timeout 4 openocd -c "adapter driver cmsis-dap; adapter speed 100; transport select swd; swd newdap a5 cpu -enable; dap create a5.dap -chain-position a5.cpu; gdb_port disabled; tcl_port disabled; telnet_port disabled; init; shutdown" 2>&1 | grep -o "DPIDR 0x3ba02477")
  if [[ -n "$r" ]]; then echo "$(date +%H:%M:%S) Debug-Port da, starte Stufe 4b."; exec ./start_stufe.sh 4b JA; fi
  sleep 0.2
done
echo "Kein Debug-Port innerhalb der Wartezeit."
