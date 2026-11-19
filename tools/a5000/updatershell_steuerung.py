# Steuert die pmca-Updater-Shell der A5000 über eine Befehls-FIFO, damit die
# Sitzung zwischen einzelnen Schritten offen bleibt (Beenden = Kamera startet neu).
# Übernommen vom α7R-II-Lauf, Modell ILCE-5000.
# Aufruf (mit tools/venv/bin/python, als root): updatershell_steuerung.py <pmca-ordner> <fifo> <sicherungsordner>
# Befehle (je eine Zeile in die FIFO):
#   info                      Modell, Version (dat4) usw. – nur lesen
#   pull <remote> <lokal>     Datei von der Kamera holen – nur lesen
#   bootloader                Loader-Abbilder boot1..N in den Sicherungsordner – nur lesen
#   sh <befehl>               Shell-Befehl auf der Kamera (kann schreiben!)
#   quit                      Shell beenden (Kamera startet neu)
import sys, os, socket, threading, io, time
PMCA, FIFO, SICHERUNG = sys.argv[1], sys.argv[2], os.path.abspath(sys.argv[3])
sys.path.insert(0, PMCA); os.chdir(PMCA)
from pmca.commands.usb import *
from pmca.platform.properties import PropertyInterface

def p(*a): print(*a, flush=True)

def run_sh(b, cmd, timeout=30):
    a, c = socket.socketpair()
    t = threading.Thread(target=b.interactiveShell, args=(c,), daemon=True); t.start()
    time.sleep(0.5)
    a.sendall((cmd + '\nexit\n').encode('latin1'))
    a.settimeout(timeout); out = b''
    try:
        while True:
            d = a.recv(4096)
            if not d: break
            out += d
    except socket.timeout:
        out += b'\n[Zeitueberschreitung]'
    a.close(); t.join(10)
    return out.decode('latin1', 'replace')

def complete(device):
    b = UsbPlatformBackend(device); b.start()
    p('SHELL BEREIT')
    while True:
        with open(FIFO) as f: line = f.readline().strip()
        if not line: continue
        p('>>> ' + line)
        cmd, _, rest = line.partition(' ')
        try:
            if cmd == 'info':
                for id, desc, value in PropertyInterface(b).getProps(): p('%-20s%s' % (desc + ': ', value))
            elif cmd == 'pull':
                r, l = rest.split(' ', 1)
                l = os.path.join(SICHERUNG, l)
                with open(l, 'wb') as f: b.readFile(r, f)
                p('gesichert: %s -> %s (%d Bytes)' % (r, l, os.path.getsize(l)))
            elif cmd == 'bootloader':
                for i, data in enumerate(b.readBootloader()):
                    l = os.path.join(SICHERUNG, 'boot%d' % (i + 1))
                    with open(l, 'wb') as f: f.write(data)
                    p('gesichert: %s (%d Bytes)' % (l, len(data)))
            elif cmd == 'sh': p(run_sh(b, rest))
            elif cmd == 'quit': b.stop(); p('Shell beendet'); break
            else: p('unbekannter Befehl')
        except Exception as e:
            p('FEHLER: %r' % e)
        p('<<< fertig')

with importDriver('libusb') as driver:
    device = getDevice(driver)
    if device:
        fdat = getFdat('ILCE-5000')
        p('fdat %d Bytes, Gerät %s' % (len(fdat), type(device).__name__))
        firmwareUpdateCommandInternal(driver, device, io.BytesIO(fdat), 0, len(fdat), complete)
p('Programm beendet')
