#!/usr/bin/env python3
"""One-shot CDP vitals probe: asks the live (or dead) YouTube tab what the
video element thinks its state is. Usage: python3 vitals.py [port]"""
import json
import socket
import base64
import os
import struct
import sys
import time
from urllib.request import build_opener, ProxyHandler

PORT = sys.argv[1] if len(sys.argv) > 1 else "9223"

# NEVER route the DevTools endpoint through $http_proxy (hcproxy would swallow
# or hang the loopback request).
_opener = build_opener(ProxyHandler({}))

EXPR = (
    "(function(){"
    "var v=document.querySelector('video');"
    "if(!v){return 'novideo';}"
    "var b=[];"
    "for(var i=0;i<v.buffered.length;i++){b.push([v.buffered.start(i),v.buffered.end(i)]);}"
    "var out={t:v.currentTime,dur:v.duration,buf:b,rs:v.readyState,"
    "ns:v.networkState,paused:v.paused,ended:v.ended,"
    "vis:document.visibilityState,title:document.title};"
    "if(v.error){out.errcode=v.error.code;out.errmsg=v.error.message;}"
    "var p=document.getElementById('movie_player');"
    "if(p&&p.getPlayerState){out.pstate=p.getPlayerState();}"
    "try{var d=window.yt&&ytplayer&&ytplayer.config;"
    "if(d){out.ytst=d.args&&d.args.status;}}catch(e){}"
    "return JSON.stringify(out);"
    "})()"
)


def connect():
    try:
        raw = _opener.open("http://127.0.0.1:%s/json/list" % PORT, timeout=3).read()
    except (TimeoutError, OSError) as e:
        raise SystemExit(
            "DevTools port %s unresponsive (%s). Classic cause: a ZOMBIE "
            "listener -- old wallpaper/helper processes inherited the dead "
            "browser core's LISTEN fd and block rebinding. Fix: "
            "bash devfix.sh %s, then fully restart qs." % (PORT, e, PORT))
    tabs = json.loads(raw)
    yt = [t for t in tabs
          if t.get("type") == "page" and "youtube" in t.get("url", "")]
    if not yt:
        raise SystemExit("no youtube tab; tabs=" +
                         json.dumps([t.get("url", "")[:60] for t in tabs]))
    url = yt[0]["webSocketDebuggerUrl"]
    hp, path = url[5:].split("/", 1)
    host, port = hp.split(":")
    s = socket.create_connection((host, int(port)), timeout=5)
    key = base64.b64encode(os.urandom(16)).decode()
    s.sendall(("GET /%s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\n"
               "Connection: Upgrade\r\nSec-WebSocket-Key: %s\r\n"
               "Sec-WebSocket-Version: 13\r\n\r\n"
               % (path, host, key)).encode())
    buf = b""
    while b"\r\n\r\n" not in buf:
        buf += s.recv(4096)
    return s, [buf.split(b"\r\n\r\n", 1)[1]]


def main():
    s, cb = connect()

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
        s.sendall(bytes(h) + m + bytes(b ^ m[i % 4] for i, b in enumerate(d)))

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

    s.settimeout(6)
    send({"id": 2, "method": "Runtime.evaluate",
          "params": {"expression": EXPR, "returnByValue": True}})
    t0 = time.time()
    while time.time() - t0 < 10:
        try:
            m = readf()
        except socket.timeout:
            break
        except ConnectionError:
            break
        if m and m.get("id") == 2:
            r = m.get("result", {}).get("result", {})
            if "value" in r:
                if r["value"] == "novideo":
                    print("novideo")
                else:
                    v = json.loads(r["value"])
                    for k in sorted(v):
                        print(k, "=", v[k])
            else:
                print("RAW:", json.dumps(m)[:500])
            return
    print("no reply within 10s (renderer wedged?)")


if __name__ == "__main__":
    main()
