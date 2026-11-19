#!/usr/bin/env python3
# Größenerhaltender Patch für ein Sony-LZPT/TPZL-Abbild (nflasha15).
# Idee: Nur der 4-KB-Record, der die geänderten Bytes enthält, wird neu mit dem
# Sony-LZ77-Format (Typ 0xF0) kodiert. Alle anderen Records, alle Blöcke und die
# TOC bleiben byte-gleich. Passt der neue Record nicht in die 512-Byte-Reserve des
# Blocks, bricht das Skript ab, statt etwas zu verschieben.
#
# Aufruf: tpzl_patch.py <nflasha15.orig> <ext2.orig> <ext2.patched> <ausgabe.nflasha15>
#   ext2.orig/ext2.patched: entpacktes ext2-Abbild vor/nach dem Patch (gleiche Größe)
import struct, sys

LENGTHS = list(range(3, 17)) + [32, 64]          # Längencodes 0..15
LEN2CODE = {l: i for i, l in enumerate(LENGTHS)}
MAXDIST = 0xfff

def inflate_record(buf, p):
    """Dekodiert einen Record ab buf[p]; liefert (daten, neues_p)."""
    t = buf[p]
    if t == 0x0f:
        l = buf[p + 2] | buf[p + 3] << 8
        return bytes(buf[p + 4:p + 4 + l]), p + 4 + l
    if t != 0xf0:
        raise ValueError('unbekannter Recordtyp %#x bei %#x' % (t, p))
    p += 1
    out = bytearray()
    while True:
        flags = buf[p]; p += 1
        for i in range(8):
            if (flags >> i) & 1:
                b0, b1 = buf[p], buf[p + 1]; p += 2
                l = LENGTHS[b0 >> 4]; bd = (b0 & 0xf) << 8 | b1
                if bd == 0:
                    return bytes(out), p
                s = len(out) - bd
                for k in range(l):
                    out.append(out[s + k])
            else:
                out.append(buf[p]); p += 1

def deflate_record(data):
    """Kodiert data im Sony-LZ77-Format (0xF0), gierig mit Hash-Ketten."""
    out = bytearray([0xf0])
    tokens = []
    i, n = 0, len(data)
    heads = {}
    def add_pos(j):
        if j + 3 <= n:
            heads.setdefault(data[j:j + 3], []).append(j)
    while i < n:
        best_l, best_d = 0, 0
        if i + 3 <= n:
            for j in reversed(heads.get(data[i:i + 3], [])):
                d = i - j
                if d > MAXDIST:
                    break
                m = 0
                while i + m < n and m < 64 and data[j + m] == data[i + m]:
                    m += 1
                if m > best_l:
                    best_l, best_d = m, d
                    if m == 64:
                        break
        allowed = [l for l in LENGTHS if l <= best_l]
        if allowed:
            l = allowed[-1]
            tokens.append(('M', l, best_d))
            for k in range(l):
                add_pos(i + k)
            i += l
        else:
            tokens.append(('L', data[i]))
            add_pos(i)
            i += 1
    tokens.append(('E',))
    for k in range(0, len(tokens), 8):
        grp = tokens[k:k + 8]
        flags = 0
        body = bytearray()
        for b, tok in enumerate(grp):
            if tok[0] == 'L':
                body.append(tok[1])
            else:
                flags |= 1 << b
                if tok[0] == 'M':
                    _, l, d = tok
                    body += bytes([LEN2CODE[l] << 4 | d >> 8, d & 0xff])
                else:
                    body += b'\x00\x00'
        out.append(flags); out += body
    return bytes(out)

def main(orig_lzpt, ext2_orig, ext2_new, out_path):
    c = bytearray(open(orig_lzpt, 'rb').read())
    a = open(ext2_orig, 'rb').read()
    b = open(ext2_new, 'rb').read()
    assert len(a) == len(b), 'ext2-Abbilder unterschiedlich groß'
    magic, bsz, tocoff, tocsize = struct.unpack_from('<4sIII', c, 0)
    assert magic == b'TPZL'
    bsize = 1 << bsz
    toc = [struct.unpack_from('<II', c, tocoff + i) for i in range(0, tocsize, 8)]
    diffs = [i for i in range(len(a)) if a[i] != b[i]] if len(a) < 1 << 20 else None
    if diffs is None:
        # schnell: blockweise vergleichen
        diffs = []
        for k in range(0, len(a), bsize):
            if a[k:k + bsize] != b[k:k + bsize]:
                diffs += [k + i for i in range(bsize) if a[k + i] != b[k + i]]
    print('geänderte ext2-Bytes:', ['%#x' % x for x in diffs])
    for blk in sorted({x // bsize for x in diffs}):
        off, size = toc[blk]
        recs, p, got = [], off, 0
        while got < bsize:
            data, q = inflate_record(c, p)
            recs.append([p - off, q - p, data]); got += len(data); p = q
        used = p - off
        print('Block %d: %d Records, belegt %d von %d (Reserve %d)' % (blk, len(recs), used, size, size - used))
        base = blk * bsize
        newrecs = []
        pos = 0
        for r_off, r_len, data in recs:
            lo, hi = base + pos, base + pos + len(data)
            if any(lo <= x < hi for x in diffs):
                target = b[lo:hi]
                enc = deflate_record(target)
                chk, _ = inflate_record(enc, 0)
                assert chk == target, 'Neukodierung fehlerhaft'
                print('  Record bei %#x: alt %d Bytes, neu %d Bytes' % (r_off, r_len, len(enc)))
                newrecs.append(enc)
            else:
                newrecs.append(bytes(c[off + r_off:off + r_off + r_len]))
            pos += len(data)
        body = b''.join(newrecs)
        if len(body) > size:
            sys.exit('ABBRUCH: Block %d bräuchte %d Bytes, verfügbar %d – würde verschieben.' % (blk, len(body), size))
        pad = bytes(c[off + used:off + size])
        fill = pad[:1] * (size - len(body)) if pad and pad.count(pad[:1]) == len(pad) else b'\x00' * (size - len(body))
        c[off:off + size] = body + fill
        print('  Block bleibt %d Bytes, Rest %d Bytes aufgefüllt mit %r' % (size, size - len(body), fill[:1]))
    open(out_path, 'wb').write(c)
    print('geschrieben:', out_path, len(c), 'Bytes')

if __name__ == '__main__':
    main(*sys.argv[1:5])
