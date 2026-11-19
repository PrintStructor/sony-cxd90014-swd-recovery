#!/bin/zsh
# Wartet (nur lesend) bis zu 5 Minuten, bis der Debug-Port der Kamera antwortet,
# und startet dann die angegebene LESE-Stufe (Standard 1). Aufruf: ./warte_stufe1.sh [1|2|2b|2c|2d|2e|2f]
set -u
ST="${1:-1}"
case "$ST" in 1|2|2b|2c|2d|2e|2f|2g) ;; *) echo "Nur Lese-Stufen erlaubt (1, 2, 2b-2f)."; exit 1;; esac
cd "$(dirname "$0")"
if pgrep -x openocd >/dev/null; then echo "OpenOCD läuft schon."; exit 1; fi
echo "$(date +%H:%M:%S) Warte auf Debug-Port (Kamera einschalten) ..."
for i in {1..300}; do
  r=$(timeout 4 openocd -c "adapter driver cmsis-dap; adapter speed 100; transport select swd; swd newdap a5 cpu -enable; dap create a5.dap -chain-position a5.cpu; gdb_port disabled; tcl_port disabled; telnet_port disabled; init; shutdown" 2>&1 | grep -o -E "DPIDR 0x[0-9a-f]+")
  if [[ -n "$r" ]]; then
    echo "$(date +%H:%M:%S) Debug-Port antwortet: $r (Versuch $i). Starte Stufe $ST."
    exec ./start_stufe.sh "$ST"
  fi
  sleep 0.5
done
echo "$(date +%H:%M:%S) Keine Antwort in 5 Minuten. Verdrahtung/Pad-Seite/GND prüfen."
