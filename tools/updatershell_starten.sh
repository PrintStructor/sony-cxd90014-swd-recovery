#!/bin/zsh
# Startet die pmca-Updater-Shell mit Administratorrechten (macOS gibt die
# USB-Schnittstelle des Updaters sonst nicht frei). Gesteuert wird sie über
# eine Befehls-FIFO; die Ausgabe landet zusätzlich in sicherung_updatershell/sitzung.log.
cd "$(dirname "$0")/.."
FIFO=/tmp/ushell.fifo
sudo $HOME/Downloads/a5000-hdmi-mod/tools/venv/bin/python -u swd/updatershell_steuerung.py \
  $HOME/Downloads/a5000-hdmi-mod/tools/pmca "$FIFO" 2>&1 | tee sicherung_updatershell/sitzung.log
