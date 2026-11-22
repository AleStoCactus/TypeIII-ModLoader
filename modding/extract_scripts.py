#!/usr/bin/env python3
"""Extracts Type III's scripts from the executable as readable .gd sources.

Meant as a REFERENCE for writing mods: to know which functions, variables
and res:// paths exist. Run it again after every game update.

Usage:  python3 extract_scripts.py [executable] [output_folder]
        (default: ../TypeIII_linux_0.0.7  ->  ./game_scripts)
Requires Python 3.14+ (compression.zstd module).

Reads the embedded .pck (Godot 4.6 format, PCK v3) and decompiles the .gdc
files (GDScript tokens v101). The logic is faithful; spacing may differ
slightly from the original and comments are gone.
"""
import struct, sys, os
from compression import zstd

TOKENS = """EMPTY ANNOTATION IDENTIFIER LITERAL
< <= > >= == !=
and or not && || !
& | ~ ^ << >>
+ - * ** / %
= += -= *= **= /= %= <<= >>= &= |= ^=
if elif else for while break continue pass return match when
as assert await breakpoint class class_name const enum extends func in is namespace preload self signal static super trait var void yield
[ ] { } ( ) , ; . .. ... : $ -> _
NEWLINE INDENT DEDENT
PI TAU INF NAN
VCS_CONFLICT_MARKER ` ?
ERROR EOF""".split()

KEYWORDS_SPACED = {"and", "or", "not", "if", "elif", "else", "for", "while", "return", "match", "when", "as",
                   "assert", "await", "class", "class_name", "const", "enum", "extends", "func", "in", "is",
                   "preload", "signal", "static", "var", "<", "<=", ">", ">=", "==", "!=", "&&", "||", "&", "|",
                   "^", "<<", ">>", "+", "-", "*", "**", "/", "%", "=", "+=", "-=", "*=", "**=", "/=", "%=",
                   "<<=", ">>=", "&=", "|=", "^=", "->"}


def decode_variant(b, p):
    hdr, = struct.unpack_from("<I", b, p); p += 4
    t = hdr & 0xFF
    f64 = hdr & (1 << 16)
    if t == 0:
        return None, p
    if t == 1:
        v, = struct.unpack_from("<I", b, p); return bool(v), p + 4
    if t == 2:
        if f64:
            v, = struct.unpack_from("<q", b, p); return v, p + 8
        v, = struct.unpack_from("<i", b, p); return v, p + 4
    if t == 3:
        if f64:
            v, = struct.unpack_from("<d", b, p); return v, p + 8
        v, = struct.unpack_from("<f", b, p); return v, p + 4
    if t in (4, 21):
        l, = struct.unpack_from("<I", b, p); p += 4
        s = b[p:p + l].decode("utf-8", "replace"); p += l + ((4 - l % 4) % 4)
        return (s if t == 4 else ("&", s)), p
    if t == 22:  # NodePath
        n, = struct.unpack_from("<I", b, p); p += 4
        if n & 0x80000000:
            names = n & 0x7FFFFFFF
            sub, flags = struct.unpack_from("<II", b, p); p += 8
            parts = []
            for _ in range(names + sub):
                l, = struct.unpack_from("<I", b, p); p += 4
                parts.append(b[p:p + l].decode()); p += l + ((4 - l % 4) % 4)
            s = ("/" if flags & 1 else "") + "/".join(parts[:names])
            if sub:
                s += ":" + ":".join(parts[names:])
            return ("^", s), p
    raise ValueError(f"variant type {t} at {p}")


def lit_repr(v):
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, tuple):
        return v[0] + '"' + v[1].replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t") + '"'
    if isinstance(v, float):
        r = repr(v)
        return r if ("." in r or "e" in r or "inf" in r or "nan" in r) else r + ".0"
    return str(v)


def decompile(data):
    assert data[:4] == b"GDSC"
    ver, dsz = struct.unpack_from("<II", data, 4)
    c = zstd.decompress(data[12:]) if dsz else data[12:]
    nid, nconst, nlines, ntok = struct.unpack_from("<4I", c, 0)
    p = 16
    ids = []
    for _ in range(nid):
        l, = struct.unpack_from("<I", c, p); p += 4
        raw = bytes(x ^ 0xB6 for x in c[p:p + l * 4]); p += l * 4
        ids.append(raw.decode("utf-32-le"))
    consts = []
    for _ in range(nconst):
        v, p = decode_variant(c, p)
        consts.append(v)
    lines = {}
    for _ in range(nlines):
        ti, ln = struct.unpack_from("<II", c, p); p += 8; lines[ti] = ln
    cols = {}
    for _ in range(nlines):
        ti, cl = struct.unpack_from("<II", c, p); p += 8; cols[ti] = cl
    toks = []
    for _ in range(ntok):
        if c[p] & 0x80:
            v, = struct.unpack_from("<I", c, p); p += 4
        else:
            v = c[p]; p += 1
        p += 4  # start line
        toks.append((v & 0x7F, v >> 8))
    if p != len(c):
        print(f"# WARNING: {len(c) - p} trailing bytes", file=sys.stderr)

    out = []
    cur = ""
    indent = 0
    prev = None
    cur_line = 1
    for i, (t, idx) in enumerate(toks):
        name = TOKENS[t] if t < len(TOKENS) else f"<T{t}>"
        if i in lines:
            if cur:
                out.append(cur.rstrip())
            ln = lines[i]
            while cur_line + (1 if out else 0) < ln and out:
                out.append(""); cur_line += 1
            cur_line = ln
            col = cols.get(i, 1)
            cur = "\t" * max(0, (col - 1) // 4) if col > 1 else ""
            cur += "\x00"  # line-start marker
            prev = None
        if name == "NEWLINE":
            continue
        if name == "INDENT":
            indent += 1; continue
        if name == "DEDENT":
            indent -= 1; continue
        if name == "EOF":
            break
        if name == "IDENTIFIER":
            s = ids[idx]
        elif name == "ANNOTATION":
            s = ids[idx]
        elif name in ("LITERAL", "ERROR"):
            s = lit_repr(consts[idx])
        else:
            s = name
        if cur.endswith("\x00") or cur == "":
            cur = cur.rstrip("\x00")
        else:
            if s in KEYWORDS_SPACED or prev in KEYWORDS_SPACED or prev in (",", ":"):
                if not (s in ("-", "+", "!", "~", "not") and prev in ("(", "[", ",", "=", None) and False):
                    cur += " "
            elif prev in ("IDENT", "LIT") and s not in ("(", ")", "[", "]", ".", ",", ":", "{", "}"):
                cur += " "
        if name == "-" and prev in ("(", "[", ",", "=", "return", ":", "+", "-", "*", "/", "==", "<", ">", None):
            cur += "-"; prev = "unary"; continue
        cur += s
        prev = "IDENT" if name in ("IDENTIFIER", "ANNOTATION") or name in ("PI", "TAU", "INF", "NAN", "self", "super", "void") else ("LIT" if name == "LITERAL" else s)
    if cur:
        out.append(cur)
    # collapse trailing whitespace-only lines
    return "\n".join(l.rstrip() for l in out) + "\n"


def read_embedded_pck(exe_path):
    with open(exe_path, "rb") as f:
        end = f.seek(0, 2)
        f.seek(-12, 2)
        size, magic = struct.unpack("<Q4s", f.read(12))
        if magic != b"GDPC":
            raise SystemExit("No embedded .pck found in " + exe_path)
        start = end - 12 - size
        f.seek(start)
        if f.read(4) != b"GDPC":
            raise SystemExit("Invalid PCK header")
        fmt, ma, mi, pa, flags, file_base, dir_off = struct.unpack("<IIIIIQQ", f.read(36))
        if flags & 1:
            raise SystemExit("The PCK directory is encrypted: cannot extract")
        f.seek(start + dir_off)
        n, = struct.unpack("<I", f.read(4))
        entries = []
        for _ in range(n):
            l, = struct.unpack("<I", f.read(4))
            p = f.read(l).rstrip(b"\0").decode()
            off, sz = struct.unpack("<QQ", f.read(16))
            f.read(16)
            fl, = struct.unpack("<I", f.read(4))
            entries.append((p[6:] if p.startswith("res://") else p, off, sz, fl))
        for p, off, sz, fl in entries:
            f.seek(start + file_base + off)
            yield p, fl, f.read(sz)


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    exe = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "TypeIII_linux_0.0.7")
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, "game_scripts")
    listing, n_gd, n_fail = [], 0, 0
    for path, flags, data in read_embedded_pck(exe):
        listing.append(path)
        if path.startswith(".godot/") or flags & 1:
            continue
        dest = None
        if path.endswith(".gdc"):
            try:
                data = decompile(data).encode()
                dest = path[:-4] + ".gd"
                n_gd += 1
            except Exception as e:
                print("ERROR", path, e, file=sys.stderr)
                n_fail += 1
        elif path.endswith((".json", ".cfg", ".gdshader", ".gdshaderinc")):
            dest = path
        if dest:
            dp = os.path.join(out, dest)
            os.makedirs(os.path.dirname(dp), exist_ok=True)
            with open(dp, "wb") as fh:
                fh.write(data)
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "_res_file_list.txt"), "w") as fh:
        fh.write("\n".join(sorted("res://" + p for p in listing)) + "\n")
    print(f"Decompiled scripts: {n_gd} (errors: {n_fail}) -> {out}")
    print("List of every res:// path in _res_file_list.txt")
