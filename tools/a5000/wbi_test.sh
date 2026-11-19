#!/bin/zsh
# WBI-Test für den dauerhaften Clean-HDMI-Patch. Voraussetzung: updatershell läuft
# (./updatershell_starten.sh), Befehle gehen über die FIFO /tmp/ushell_a5000.fifo.
#
#   ./wbi_test.sh pruefen          nur lesen: dd vorhanden? Kopf von nflasha5 holen und vergleichen
#   ./wbi_test.sh sichern          komplettes nflasha5 (60 MB) auf den Mac holen + Kopfkopie
#                                  als /setting/wbi_kopf.bin auf der Kamera ablegen (512 Bytes)
#   ./wbi_test.sh drop JA          ersten Sektor von nflasha5 nullen (wie Sonys ud_wbi_drop.elf)
#   ./wbi_test.sh rueckweg JA      Kopf aus /setting/wbi_kopf.bin zurückschreiben
#   ./wbi_test.sh beenden          Shell beenden (Kamera startet neu)
set -u
cd "$(dirname "$0")"
F=/tmp/ushell_a5000.fifo
S=$PWD/sicherung_updatershell
PAKET_KOPF=${SONY_NFLASHA5:-}   # optional: entpacktes nflasha5 aus dem Sony-Paket (fwtool), nur zum Vergleich
[[ -p $F ]] || { echo "Keine updatershell-FIFO. Erst ./updatershell_starten.sh"; exit 1; }
LOG=$(ls -t $S/sitzung_*.log | head -1)

befehl() {   # $1 = Befehlszeile, wartet auf "<<< fertig"
  local n0=$(grep -c "<<< fertig" "$LOG")
  print -r -- "$1" > $F
  for i in {1..600}; do
    [[ $(grep -c "<<< fertig" "$LOG") -gt $n0 ]] && break
    sleep 0.5
  done
  tail -n 15 "$LOG" | sed -n "/>>> /,\$p"
}

kopf_vergleich() {   # $1 = lokale Datei
  python3 -I - "$1" "$PAKET_KOPF" <<'EOF'
import sys
a=open(sys.argv[1],'rb').read(512)
b=open(sys.argv[2],'rb').read(512) if len(sys.argv) > 2 and sys.argv[2] else None
print('Kopf: %d Bytes, beginnt mit %r, %d Bytes ungleich null' % (len(a), a[:4], sum(1 for x in a if x)))
print('ALLES NULL (gedroppt)' if not any(a) else ('identisch mit Sonys Paket-Abbild' if a==b else ('Kopf WBI1/WBI0 vorhanden' if a[:4] in (b'WBI1', b'WBI0') else 'WEICHT AB')))
EOF
}

case "${1:-}" in
  pruefen)
    befehl 'sh type dd; ls -la /dev/nflasha5; dd if=/dev/nflasha5 of=/setting/wbi_kopf_jetzt.bin bs=512 count=1; sync; ls -la /setting/wbi_kopf_jetzt.bin'
    befehl 'pull /setting/wbi_kopf_jetzt.bin wbi_kopf_jetzt.bin'
    befehl 'sh rm -f /setting/wbi_kopf_jetzt.bin; sync'
    kopf_vergleich $S/wbi_kopf_jetzt.bin ;;
  sichern)
    befehl 'pull /dev/nflasha5 nflasha5_vor_drop.img'
    ls -la $S/nflasha5_vor_drop.img
    [[ -n "$PAKET_KOPF" ]] && cmp -n $(stat -f %z $PAKET_KOPF) $S/nflasha5_vor_drop.img $PAKET_KOPF && echo "nflasha5-Sicherung beginnt byte-gleich mit Sonys Abbild"
    befehl 'sh dd if=/dev/nflasha5 of=/setting/wbi_kopf.bin bs=512 count=1; sync; ls -la /setting/wbi_kopf.bin'
    befehl 'pull /setting/wbi_kopf.bin wbi_kopf.bin'
    kopf_vergleich $S/wbi_kopf.bin ;;
  drop)
    [[ "${2:-}" == "JA" ]] || { echo "Schreibt nflasha5. Nur mit: ./wbi_test.sh drop JA"; exit 1; }
    [[ -s $S/wbi_kopf.bin ]] || { echo "Erst ./wbi_test.sh sichern"; exit 1; }
    befehl 'sh ls -la /setting/wbi_kopf.bin && dd if=/dev/zero of=/dev/nflasha5 bs=512 count=1; sync; dd if=/dev/nflasha5 of=/setting/wbi_kopf_nachher.bin bs=512 count=1; sync'
    befehl 'pull /setting/wbi_kopf_nachher.bin wbi_kopf_nachher.bin'
    befehl 'sh rm -f /setting/wbi_kopf_nachher.bin; sync'
    kopf_vergleich $S/wbi_kopf_nachher.bin ;;
  rueckweg)
    [[ "${2:-}" == "JA" ]] || { echo "Schreibt nflasha5. Nur mit: ./wbi_test.sh rueckweg JA"; exit 1; }
    befehl 'sh ls -la /setting/wbi_kopf.bin && dd if=/setting/wbi_kopf.bin of=/dev/nflasha5 bs=512 count=1; sync; dd if=/dev/nflasha5 of=/setting/wbi_kopf_jetzt.bin bs=512 count=1; sync'
    befehl 'pull /setting/wbi_kopf_jetzt.bin wbi_kopf_jetzt.bin'
    befehl 'sh rm -f /setting/wbi_kopf_jetzt.bin; sync'
    kopf_vergleich $S/wbi_kopf_jetzt.bin ;;
  beenden)
    print -r -- quit > $F; sleep 3; tail -n 3 "$LOG" ;;
  *) echo "Bitte pruefen | sichern | drop JA | rueckweg JA | beenden"; exit 1 ;;
esac
