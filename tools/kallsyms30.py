# Minimaler kallsyms-Leser für ARM-Kernel 3.0 (absolute 32-bit-Adressen)
import struct, sys
d = open(sys.argv[1], 'rb').read(); BASE = int(sys.argv[2], 16); out = sys.argv[3]
u32 = lambda o: struct.unpack_from('<I', d, o)[0]
u16 = lambda o: struct.unpack_from('<H', d, o)[0]
digits = b'0\x001\x002\x003\x004\x005\x006\x007\x008\x009\x00'
p = 0
while True:
    p = d.find(digits, p + 1)
    if p < 0: sys.exit('Token-Tabelle nicht gefunden')
    # Token-Index suchen: 256 u16, idx[0]=0, steigend, kurz hinter p
    for q in range((p + 3) & ~3, min(p + 4096, len(d) - 512), 2):
        idx = struct.unpack_from('<256H', d, q)
        if idx[0] != 0 or any(idx[i] >= idx[i+1] for i in range(255)): continue
        T = p - idx[0x30]
        if T < 0 or T + idx[255] >= q: continue
        if d[T + idx[0x31]:T + idx[0x31] + 2] != b'1\x00': continue
        tokens = [d[T+idx[i]:d.index(b'\x00', T+idx[i])] for i in range(256)]
        break
    else: continue
    break
print('token_table', hex(BASE + T), 'token_index', hex(BASE + q))
# Marker rückwärts ab T
m = (T - 4) & ~3
while u32(m) == 0 and m > 0: m -= 4   # Padding überspringen
end_m = m + 4
while u32(m - 4) < u32(m): m -= 4
assert u32(m) == 0, 'Marker-Start nicht 0'
nm = (end_m - m) // 4
print('markers', hex(BASE + m), 'Anzahl', nm)
# num_syms rückwärts suchen
for s in range(m - 4, m - 0x400000, -4):
    N = u32(s)
    if (nm - 1) * 256 < N <= nm * 256:
        o = s + 4; names = []
        ok = True
        for i in range(N):
            if o >= m: ok = False; break
            L = d[o]; names.append(b''.join(tokens[c] for c in d[o+1:o+1+L])); o += 1 + L
        if ok and 0 <= m - o < 0x100:
            break
else: sys.exit('num_syms nicht gefunden')
A = s - 4 * N - 4 * int(sys.argv[4] if len(sys.argv) > 4 else 0)
addrs = struct.unpack_from('<%dI' % N, d, A)
print('num_syms', N, 'bei', hex(BASE + s), 'addresses', hex(BASE + A))
with open(out, 'w') as f:
    for a, n in zip(addrs, names):
        f.write('%08x %s %s\n' % (a, chr(n[0]) if n else '?', n[1:].decode('latin1')))
print('geschrieben', out)
