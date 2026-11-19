#!/bin/zsh
# Startet die pmca-Updater-Shell der A5000 mit Administratorrechten (macOS gibt
# die USB-Schnittstelle des Updaters sonst nicht frei). Gesteuert wird sie über
# die Befehls-FIFO /tmp/ushell_a5000.fifo; die Ausgabe landet zusätzlich in
# sicherung_updatershell/sitzung_<zeit>.log.
cd "$(dirname "$0")"
FIFO=/tmp/ushell_a5000.fifo
[[ -p $FIFO ]] || mkfifo $FIFO
mkdir -p sicherung_updatershell
LOG=sicherung_updatershell/sitzung_$(date +%Y%m%d_%H%M%S).log
sudo $HOME/Downloads/a5000-hdmi-mod/tools/venv/bin/python -u updatershell_steuerung.py \
  $HOME/Downloads/a5000-hdmi-mod/tools/pmca "$FIFO" "$PWD/sicherung_updatershell" 2>&1 | tee "$LOG"
