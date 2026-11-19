# Vergleicht den Loader3-RAM-Dump aus Stufe 2 mit den Sollwerten von Stufe 3.
# Aufruf: python3 pruefbloecke.py logs/loader3_ram_defekt.bin
# Die Sollblöcke werden direkt aus stufe3_updater_erzwingen.cfg gelesen,
# damit Prüfung und Stufe 3 garantiert dieselben Werte nutzen.
import os, re, struct, sys

hier = os.path.dirname(os.path.abspath(__file__))
cfg = open(os.path.join(hier, 'stufe3_updater_erzwingen.cfg'), encoding='utf-8').read()
bloecke = re.findall(r'\{(0x[0-9a-f]{8}) \{([0-9a-fx ]+)\}\}', cfg)
dump = open(sys.argv[1], 'rb').read()
BASIS = 0xc01f0000
fehler = 0
for adr, worte in bloecke:
    a = int(adr, 16); soll = [int(w, 16) for w in worte.split()]
    o = a - BASIS
    if o + 4 * len(soll) > len(dump):
        print('0x%08x: Dump zu kurz' % a); fehler += 1; continue
    ist = struct.unpack_from('<%dI' % len(soll), dump, o)
    abw = [(a + 4 * i, x, y) for i, (x, y) in enumerate(zip(ist, soll)) if x != y]
    if abw:
        fehler += 1
        print('0x%08x: %d Abweichung(en), erste bei 0x%08x: ist %08x, soll %08x' % ((a, len(abw)) + abw[0]))
    else:
        print('0x%08x: %2d Worte identisch' % (a, len(soll)))
print('ERGEBNIS: %s' % ('alle Prüfblöcke identisch mit Spender-Loader3' if not fehler
                        else '%d Block/Blöcke abweichend -> Stufe 3 NICHT starten' % fehler))
sys.exit(1 if fehler else 0)
