#!/bin/zsh
# Sony A5000 – SWD-Stufen starten.
# Aufruf: ./start_stufe.sh 1 | 2 | 2b | 2c | 2d | 2e | 2f   (alle nur lesend)
# Stufe 3 (Halt, r0 setzen) nur mit ausdrücklicher Freigabe: ./start_stufe.sh 3 JA
# Schreibt das vollständige OpenOCD-Protokoll nach logs/.
set -u
cd "$(dirname "$0")"
case "${1:-}" in
  1)  CFG=stufe1_identifizieren.cfg ;;
  2)  CFG=stufe2_nur_lesen.cfg ;;
  2b) CFG=stufe2b_kernel_log.cfg ;;
  2c) CFG=stufe2c_klog_alog.cfg ;;
  2d) CFG=stufe2d_normal_schleife.cfg ;;
  2e) CFG=stufe2e_pc_verlauf.cfg ;;
  2f) CFG=stufe2f_alog_stueckweise.cfg ;;
  2g) CFG=stufe2g_robust.cfg ;;
  2h) CFG=stufe2h_pc_start.cfg ;;
  4a) CFG=stufe4a_modus_beobachten.cfg ;;   # hält kurz an, ändert nichts
  4b) [[ "${2:-}" == "JA" ]] || { echo "Stufe 4b schreibt r0. Start nur mit: ./start_stufe.sh 4b JA"; exit 1; }
      CFG=stufe4b_kaltstart_erzwingen.cfg ;;
  3)  [[ "${2:-}" == "JA" ]] || { echo "Stufe 3 ist SCHREIBEND (r0). Start nur mit: ./start_stufe.sh 3 JA"; exit 1; }
      CFG=stufe3_updater_erzwingen.cfg ;;
  *)  echo "Bitte 1, 2, 2b-2g, 3 oder 4a angeben."; exit 1 ;;
esac
if pgrep -x openocd >/dev/null; then
  echo "Es läuft bereits ein OpenOCD. Bitte zuerst beenden (nie zwei Instanzen auf einer Sonde)."; exit 1
fi
mkdir -p logs
LOG="logs/stufe${1}_$(date +%Y%m%d_%H%M%S).log"
echo "Sonde am USB:"; system_profiler SPUSBDataType 2>/dev/null | grep -i -A2 -E "debugprobe|CMSIS" | head -6
openocd -d2 -f "$CFG" 2>&1 | tee "$LOG"
echo; echo "Protokoll: $LOG"
if [[ "$1" == 2 ]]; then
  if [[ -s logs/bootrom_defekt.bin ]]; then
    echo "BootROM defekt : $(shasum -a 256 logs/bootrom_defekt.bin | cut -c1-64)"
    echo "BootROM Spender: 81a17e039a2debfe589b127e12384ed4d7c2ba0d0c819238d0b021b466246026"
  fi
  if [[ -s logs/loader3_ram_defekt.bin ]]; then
    echo "Prüfblöcke für Stufe 3 (Loader3-RAM gegen Spender):"
    python3 -I pruefbloecke.py logs/loader3_ram_defekt.bin
    echo "(Im Werksmodus kann Linux den Bereich überschrieben haben; dann in der Bootschleife wiederholen.)"
  fi
fi
