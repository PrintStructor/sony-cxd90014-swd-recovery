#!/usr/bin/env python3
# Baut firmware.tar neu: ersetzt nur dev/nflasha15 und die zugehörige Zeile in
# 0701_part_image_sum/part_image.sum (CRC32 + Größe). Reihenfolge, Kopfdaten und
# alle übrigen Mitglieder bleiben unverändert.
# Aufruf: paket_bauen.py <firmware.tar.orig> <nflasha15.neu> <firmware.tar.neu> [--identitaet]
import sys, tarfile, zlib, io

def crc32_file(path):
    c = 0
    with open(path, 'rb') as f:
        while True:
            b = f.read(1 << 20)
            if not b:
                return c & 0xffffffff
            c = zlib.crc32(b, c)

def main(src, nfl, dst, ident=False):
    with tarfile.open(src, 'r:') as tin:
        fmt = tin.format
        members = tin.getmembers()
        sumtext = tin.extractfile('0701_part_image_sum/part_image.sum').read().decode('ascii')
    if not ident:
        import os
        size = os.path.getsize(nfl)
        crc = crc32_file(nfl)
        lines = sumtext.split('\n')
        for i, l in enumerate(lines):
            f = l.split(',')
            if len(f) > 10 and f[10] == 'dev/nflasha15':
                assert int(f[2], 16) == size, 'Größe weicht ab – Abbruch'
                f[1] = '%08x' % crc
                lines[i] = ','.join(f)
                print('part_image.sum: nflasha15 CRC %s, Größe %s' % (f[1], f[2]))
        sumtext = '\n'.join(lines)
    with tarfile.open(src, 'r:') as tin, tarfile.open(dst, 'w:', format=fmt) as tout:
        for m in tin.getmembers():
            if not m.isfile():
                tout.addfile(m); continue
            if not ident and m.name == '0700_part_image/dev/nflasha15':
                with open(nfl, 'rb') as f:
                    tout.addfile(m, f)
            elif not ident and m.name == '0701_part_image_sum/part_image.sum':
                data = sumtext.encode('ascii')
                assert len(data) == m.size
                tout.addfile(m, io.BytesIO(data))
            else:
                tout.addfile(m, tin.extractfile(m))
    # Python füllt das Archiv auf volle 10-KB-Records auf; das Original endet früher.
    # Da alle Mitglieder gleich groß bleiben, auf Originallänge kürzen, sofern nur Nullen wegfallen.
    import os
    n_src, n_dst = os.path.getsize(src), os.path.getsize(dst)
    if n_dst > n_src:
        with open(dst, 'r+b') as f:
            f.seek(n_src)
            rest = f.read()
            assert rest.count(0) == len(rest), 'Überhang enthält Daten – nicht gekürzt'
            f.truncate(n_src)
    print('geschrieben:', dst, os.path.getsize(dst), 'Bytes')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3], '--identitaet' in sys.argv)
