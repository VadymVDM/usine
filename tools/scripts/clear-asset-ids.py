"""Vide les proprietes string d'un .rbxm binaire qui contiennent des ids interdits.
# Outil (2026-11-23) : python tools/scripts/clear-asset-ids.py src/gui/X.rbxm <id> [<id>...]
Usage : python patch_rbxm.py fichier.rbxm id1 id2 ...  (ecrit le fichier en place, garde une copie .bak)
Les chunks modifies sont reecrits non compresses (autorise par le format : compressedLength = 0)."""
import struct, sys, shutil

def lz4_block(src: bytes, size: int) -> bytes:
    out = bytearray(); i = 0
    while i < len(src):
        token = src[i]; i += 1
        lit = token >> 4
        if lit == 15:
            while True:
                b = src[i]; i += 1; lit += b
                if b != 255: break
        out += src[i:i + lit]; i += lit
        if i >= len(src): break
        off = src[i] | (src[i + 1] << 8); i += 2
        ml = token & 15
        if ml == 15:
            while True:
                b = src[i]; i += 1; ml += b
                if b != 255: break
        ml += 4
        start = len(out) - off
        for k in range(ml):
            out.append(out[start + k])
    assert len(out) == size, (len(out), size)
    return bytes(out)

def main():
    path = sys.argv[1]; bad = [a.encode() for a in sys.argv[2:]]
    data = open(path, 'rb').read()
    assert data[:8] == b'<roblox!'
    header_len = 32
    out = bytearray(data[:header_len]); pos = header_len
    classes = {}; changed = 0
    while pos < len(data):
        name = data[pos:pos + 4]
        clen, ulen, _res = struct.unpack('<III', data[pos + 4:pos + 16])
        body_raw = data[pos + 16:pos + 16 + (clen if clen else ulen)]
        nxt = pos + 16 + (clen if clen else ulen)
        body = lz4_block(body_raw, ulen) if clen else body_raw
        new_body = None
        if name == b'INST':
            cid, nlen = struct.unpack('<II', body[:8])
            cname = body[8:8 + nlen].decode()
            count = struct.unpack('<I', body[9 + nlen:13 + nlen])[0]
            classes[cid] = (cname, count)
        elif name == b'PROP':
            cid, plen = struct.unpack('<II', body[:8])
            pname = body[8:8 + plen].decode()
            ptype = body[8 + plen]
            if ptype in (0x01, 0x1D) and any(b in body for b in bad):  # String / Content
                cname, count = classes[cid]
                p = 9 + plen; values = []
                if ptype == 0x01:
                    for _ in range(count):
                        n = struct.unpack('<I', body[p:p + 4])[0]; values.append(body[p + 4:p + 4 + n]); p += 4 + n
                    assert p == len(body), 'parse String'
                    for k, v in enumerate(values):
                        if any(b in v for b in bad):
                            print(f'  {cname}.{pname}[{k}] : {v.decode()} -> ""'); values[k] = b''; changed += 1
                    new_body = body[:9 + plen] + b''.join(struct.pack('<I', len(v)) + v for v in values)
                else:
                    # Content (0x1D ici = verifie plus bas) : non gere
                    raise SystemExit(f'type 0x1D non gere pour {cname}.{pname}')
            elif ptype == 0x22 and any(b in body for b in bad):
                cname, count = classes[cid]
                p = 9 + plen
                planes = body[p:p + 4 * count]; p += 4 * count
                types = []
                for k in range(count):
                    x = (planes[k] << 24) | (planes[count + k] << 16) | (planes[2 * count + k] << 8) | planes[3 * count + k]
                    types.append((x >> 1) ^ -(x & 1))
                ucount = struct.unpack('<I', body[p:p + 4])[0]; p += 4
                uris = []
                for _ in range(ucount):
                    n = struct.unpack('<I', body[p:p + 4])[0]; uris.append(body[p + 4:p + 4 + n]); p += 4 + n
                rest = body[p:]  # objets / externes : inchanges
                assert types.count(1) == ucount, ('uris', types.count(1), ucount)
                ui = 0; keep = []
                for k in range(count):
                    if types[k] == 1:
                        uri = uris[ui]; ui += 1
                        if any(b in uri for b in bad):
                            print(f'  {cname}.{pname}[{k}] : {uri.decode()} -> (aucune)'); types[k] = 0; changed += 1
                        else:
                            keep.append(uri)
                zz = [((t << 1) ^ (t >> 31)) & 0xFFFFFFFF for t in types]
                new_planes = bytes((v >> s) & 0xFF for s in (24, 16, 8, 0) for v in zz)
                new_body = (body[:9 + plen] + new_planes + struct.pack('<I', len(keep))
                            + b''.join(struct.pack('<I', len(u)) + u for u in keep) + rest)
        if new_body is not None:
            out += name + struct.pack('<III', 0, len(new_body), 0) + new_body
        else:
            out += data[pos:nxt]
        if name == b'END\x00':
            out += data[nxt:]; break
        pos = nxt
    if changed:
        open(path, 'wb').write(bytes(out))
    print(f'{path} : {changed} valeur(s) videe(s)')

main()
