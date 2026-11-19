# Fragt den Kamera-Updater, ob er ein Paket annehmen würde – OHNE zu schreiben.
# Ablauf wie pmca vor dem Flashen: init -> checkGuard (Modell/Region/Version) ->
# getFirmwareVersion. Danach Ende, es wird keine Firmware übertragen.
# Aufruf (root, tools/venv/bin/python): versionspruefung.py <pmca-ordner> <paket.dat>
import sys, os
PMCA, DAT = sys.argv[1], os.path.abspath(sys.argv[2])
sys.path.insert(0, PMCA); os.chdir(PMCA)
from pmca.commands.usb import *
from pmca import firmware

with open(DAT, 'rb') as f:
    offset, size = firmware.readDat(f)
    with importDriver('libusb') as driver:
        device = getDevice(driver)
        if device:
            dev = SonyUpdaterCamera(device)
            print('Paket:', DAT)
            dev.init()
            f.seek(offset)
            try:
                dev.checkGuard(f, size)
                alt, neu = dev.getFirmwareVersion()
                print('ERGEBNIS: Kamera nimmt das Paket an (Version %s -> %s). Nichts geschrieben.' % (alt, neu))
            except Exception as e:
                print('ERGEBNIS: Kamera lehnt ab: %s. Nichts geschrieben.' % e)
