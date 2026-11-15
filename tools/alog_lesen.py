# Dekodiert einen Android-Logger-Puffer (logger_entry v1) aus einem RAM-Dump.
# Aufruf: python3 alog_lesen.py <datei> [<datei2> ...]  (Stücke werden aneinandergehängt)
import sys, struct
d = b''.join(open(f, 'rb').read() for f in sys.argv[1:])
PRIO = 'VVVDIWEFS'
o = 0; n = 0
while o + 20 <= len(d):
    ln, pad, pid, tid, sec, nsec = struct.unpack_from('<HHiiii', d, o)
    if not (2 < ln <= 4076) or not (0 < pid < 100000) or not (0 <= sec < 10**6) or not (0 <= nsec < 10**9):
        o += 4; continue
    m = d[o+20:o+20+ln]
    if len(m) < ln: break
    p = m[0]; rest = m[1:].split(b'\0')
    tag = rest[0].decode('latin1', 'replace'); msg = rest[1].decode('latin1', 'replace') if len(rest) > 1 else ''
    print('%5d.%06d %4d/%-4d %s/%s: %s' % (sec, nsec // 1000, pid, tid, PRIO[p] if p < 9 else '?', tag, msg.rstrip()))
    o += 20 + ln; n += 1
print('--- %d Einträge' % n, file=sys.stderr)
