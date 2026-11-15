# Steuert die pmca-Updater-Shell über eine Befehls-FIFO, damit die Sitzung
# zwischen einzelnen Schritten offen bleibt (Beenden = Kamera startet neu).
# Aufruf (mit tools/venv/bin/python): updatershell_steuerung.py <pmca-ordner> <fifo>
# Befehle (je eine Zeile in die FIFO):
#   info | mount | umount <0|1> | pull <remote> <lokal> | sh <befehl> | quit
import sys, os, socket, threading, io, time
PMCA, FIFO = sys.argv[1], sys.argv[2]
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
            elif cmd == 'mount': p('Android-Daten eingehängt unter: ' + b.mountAndroidData())
            elif cmd == 'umount': b.unmountAndroidData(int(rest or '0')); p('ausgehängt')
            elif cmd == 'pull':
                r, l = rest.split(' ', 1)
                with open(l, 'wb') as f: b.readFile(r, f)
                p('gesichert: %s -> %s (%d Bytes)' % (r, l, os.path.getsize(l)))
            elif cmd == 'sh': p(run_sh(b, rest))
            elif cmd == 'quit': b.stop(); p('Shell beendet'); break
            else: p('unbekannter Befehl')
        except Exception as e:
            p('FEHLER: %r' % e)
        p('<<< fertig')

with importDriver('libusb') as driver:
    device = getDevice(driver)
    if device:
        fdat = getFdat('ILCE-7RM2')
        p('fdat %d Bytes, Gerät %s' % (len(fdat), type(device).__name__))
        firmwareUpdateCommandInternal(driver, device, io.BytesIO(fdat), 0, len(fdat), complete)
p('Programm beendet')
