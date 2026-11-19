# Prüft und flasht das UNVERÄNDERTE Sony-Paket v1.10 in einem Durchgang.
# 1) init + checkGuard + getFirmwareVersion (nichts geschrieben)
# 2) nur wenn die Kamera annimmt und die neue Version 1.10 ist: Firmware schreiben
# Aufruf (root, tools/venv/bin/python): flash_110.py <pmca-ordner> <ILCE5000_V110_ORIGINAL.dat>
import sys, os
PMCA, DAT = sys.argv[1], os.path.abspath(sys.argv[2])
sys.path.insert(0, PMCA); os.chdir(PMCA)
from pmca.commands.usb import *
from pmca import firmware

with open(DAT, 'rb') as f:
    offset, size = firmware.readDat(f)
    with importDriver('libusb') as driver:
        device = getDevice(driver)
        if not device:
            sys.exit('Kein Gerät')
        dev = SonyUpdaterCamera(device)
        print('Paket:', DAT, flush=True)
        dev.init()
        f.seek(offset)
        try:
            dev.checkGuard(f, size)
            alt, neu = dev.getFirmwareVersion()
        except Exception as e:
            sys.exit('PRUEFUNG: Kamera lehnt ab: %s. Nichts geschrieben.' % e)
        print('PRUEFUNG: Kamera nimmt an, Version %s -> %s' % (alt, neu), flush=True)
        if neu != '1.10':
            sys.exit('Neue Version ist nicht 1.10 – Abbruch, nichts geschrieben.')
        print('Starte Flash ...', flush=True)
        firmwareUpdateCommandInternal(driver, device, f, offset, size)
