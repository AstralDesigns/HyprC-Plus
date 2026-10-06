#!/usr/bin/env python3
"""Ask the live player for its own nerd stats + cache policy."""
import json
import os
import struct
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vitals  # noqa: E402

EXPR = (
    "(function(){"
    "var o={};"
    "var p=document.getElementById('movie_player');"
    "if(!p){return 'noplayer';}"
    "try{o.nerds=p.getStatsForNerds();}catch(e){o.e1=String(e).slice(0,80);}"
    "try{var r=p.getPlayerResponse&&p.getPlayerResponse();"
    "if(r&&r.playbackTracking){o.pt=Object.keys(r.playbackTracking);}"
    "if(r&&r.streamingData){o.sd=Object.keys(r.streamingData);}"
    "if(r){o.csc=r.playerConfig?1:0;}}"
    "catch(e){o.e2=String(e).slice(0,80);}"
    "try{if(window.ytcfg){o.cachemax="
    "window.ytcfg.get?window.ytcfg.get('CACHING_MAX'):null;}}catch(e){}"
    "return JSON.stringify(o);})()"
)

s, cb = vitals.connect()


def rd(n):
    while len(cb[0]) < n:
        c = s.recv(65536)
        if not c:
            raise ConnectionError
        cb[0] += c
    o, cb[0] = cb[0][:n], cb[0][n:]
    return o


def send(o):
    d = json.dumps(o).encode()
    h = bytearray([0x81])
    n = len(d)
    if n < 126:
        h.append(0x80 | n)
    elif n < 65536:
        h += bytes([0x80 | 126]) + struct.pack(">H", n)
    else:
        h += bytes([0x80 | 127]) + struct.pack(">Q", n)
    m = os.urandom(4)
    s.sendall(bytes(h) + m +
              bytes(b ^ m[i % 4] for i, b in enumerate(d)))


def readf():
    b0, b1 = rd(2)
    op = b0 & 0x0F
    n = b1 & 0x7F
    if n == 126:
        n = struct.unpack(">H", rd(2))[0]
    elif n == 127:
        n = struct.unpack(">Q", rd(8))[0]
    p = rd(n) if n else b""
    if op == 9:
        return None
    try:
        return json.loads(p)
    except Exception:
        return None


s.settimeout(8)
send({"id": 4, "method": "Runtime.evaluate",
      "params": {"expression": EXPR, "returnByValue": True}})
t0 = time.time()
while time.time() - t0 < 10:
    try:
        m = readf()
    except Exception:
        break
    if m and m.get("id") == 4:
        r = m.get("result", {}).get("result", {})
        v = r.get("value")
        if v and v != "noplayer":
            d = json.loads(v)
            nerds = d.pop("nerds", None)
            print("meta:", json.dumps(d)[:300])
            if nerds:
                if isinstance(nerds, str):
                    lines = nerds.replace("<br>", "\n").split("\n")
                else:
                    lines = [k + ": " + str(nerds[k]) for k in nerds]
                for ln in lines:
                    if "samples" in str(ln).lower():
                        continue
                    print("  |", str(ln)[:200])
        else:
            print("RAW:", json.dumps(m)[:400])
        break
