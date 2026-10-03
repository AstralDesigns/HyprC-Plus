# ── HyprCandy launcher MITM proxy add-on (opt-in, additive) ─────────────────
# Run headless with mitmdump; the launcher points QtWebEngine at it via
#   --proxy-server=http://127.0.0.1:8888
# so ONLY the launcher's browsing is proxied (system browsers are untouched).
#
# It does three things the in-page script blocker (scripts/webscripts/adblock.js)
# cannot, which is why this layer exists:
#   1. Rewrites the HTTP *request* headers (User-Agent + Sec-CH-UA* Client Hints)
#      to a clean Chrome 140 identity. This is the ONLY way to get past WhatsApp
#      Web's "works with Chrome 100+" wall: it gates server-side on the request
#      headers, and this QtWebEngine build cannot set httpUserAgent (isFinal /
#      absent on the profile prototype), so JS navigator overrides are invisible
#      to it. Everything else keeps working because we only touch these headers.
#   2. Applies the REAL EasyList (+ EasyPrivacy, Fanboy) through Brave's compiled
#      adblock engine (extra/python-adblock): efficient network matching with
#      exception rules, plus cosmetic hiding + injected scriptlets per document.
#   3. Strips adSlots from YouTube's youtubei/v1/player response at the network
#      layer (more reliable than the in-page fetch patch).
#
# The in-page script stays the always-on baseline: if this proxy is not running,
# the launcher still blocks YouTube + top trackers. This layer only ADDS to it.
#
# API verified against ArniDagur/python-adblock master (src/lib.rs):
#   FilterSet(); fs.add_filter_list(text); Engine(fs, optimize=True)
#   engine.check_network_urls(url, source_url, request_type).matched
#   engine.url_cosmetic_resources(url) -> .hide_selectors/.style_selectors/.injected_script
# Lists are cached under ~/.cache/hcproxy and refreshed lazily (TTL below).

import os
import re
import time
import urllib.request

import adblock  # extra/python-adblock -- Brave's adblock-rs crate in Python

CACHE_DIR = os.path.expanduser("~/.cache/hcproxy")
LIST_TTL = 60 * 60 * 24 * 7  # re-download weekly

LIST_URLS = [
    ("easylist.txt",
     "https://easylist-downloads.adblockplus.org/easylist.txt"),
    ("easyprivacy.txt",
     "https://easylist-downloads.adblockplus.org/easyprivacy.txt"),
    ("fanboy-social.txt",
     "https://easylist-downloads.adblockplus.org/fanboy-social.txt"),
]

CHROME_UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
             "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36")
CHROME_BRANDS = '"Not_A Brand";v="8", "Chromium";v="140", "Google Chrome";v="140"'

_EXT_TYPE = {
    "js": "script", "mjs": "script", "css": "stylesheet",
    "png": "image", "jpg": "image", "jpeg": "image", "gif": "image",
    "webp": "image", "svg": "image", "ico": "image",
    "woff": "font", "woff2": "font", "ttf": "font", "otf": "font",
    "mp4": "media", "webm": "media", "mp3": "media",
}


def _log(*a):
    # mitmproxy captures stdout in the journal when run as a service.
    print("[hcproxy]", *a, flush=True)


def _req_type(path):
    if path in ("", "/"):
        return "document"
    m = re.search(r"\.([A-Za-z0-9]{2,5})(?:\?|#|$)", path)
    if m:
        return _EXT_TYPE.get(m.group(1).lower(), "xmlhttprequest")
    return "xmlhttprequest"


def _empty_key(text, key):
    """Replace every `"key":[...]` with `"key":[]` in JSON-ish text using a
    bracket-balanced scan that respects string literals and escapes. Used to
    gut YouTube's adSlots array wherever it is embedded (incl. inside the
    /watch HTML's ytInitialPlayerResponse, which no fetch/XHR hook can reach)."""
    needle = '"' + key + '":'
    out = []
    i = 0
    n = len(text)
    while True:
        j = text.find(needle, i)
        if j < 0:
            out.append(text[i:])
            break
        k = j + len(needle)
        out.append(text[i:k])
        if k < n and text[k] == "[":
            depth = 0
            in_s = False
            esc = False
            m = k
            while m < n:
                c = text[m]
                if in_s:
                    if esc:
                        esc = False
                    elif c == "\\":
                        esc = True
                    elif c == '"':
                        in_s = False
                else:
                    if c == '"':
                        in_s = True
                    elif c == "[":
                        depth += 1
                    elif c == "]":
                        depth -= 1
                        if depth == 0:
                            m += 1
                            break
                m += 1
            out.append("[]")
            i = m
        else:
            i = k
    return "".join(out)


def _load_lists():
    os.makedirs(CACHE_DIR, exist_ok=True)
    texts = []
    for name, url in LIST_URLS:
        path = os.path.join(CACHE_DIR, name)
        fresh = (os.path.exists(path)
                 and (time.time() - os.path.getmtime(path)) < LIST_TTL)
        if not fresh:
            try:
                data = urllib.request.urlopen(url, timeout=60).read()
                with open(path, "wb") as f:
                    f.write(data)
                _log("refreshed", name)
            except Exception as e:  # keep any stale copy we already have
                _log("download failed", name, repr(e))
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                texts.append(f.read())
    return texts


class HCProxy:
    def __init__(self):
        self.engine = None
        try:
            fs = adblock.FilterSet()
            for text in _load_lists():
                fs.add_filter_list(text)
            self.engine = adblock.Engine(fs, optimize=True)
            _log("engine ready (EasyList + EasyPrivacy + Fanboy loaded)")
        except Exception as e:
            # Never let engine setup take the whole proxy down; the header
            # rewrite (WhatsApp fix) still works without the lists.
            _log("ENGINE SETUP FAILED:", repr(e))
            self.engine = None

    # ── request: header rewrite + network blocking ──────────────────────────
    def request(self, flow):
        h = flow.request.headers
        # 1. Clean Chrome identity on the wire (fixes WhatsApp's server gate).
        h["User-Agent"] = CHROME_UA
        h["sec-ch-ua"] = CHROME_BRANDS
        h["sec-ch-ua-mobile"] = "?0"
        h["sec-ch-ua-platform"] = '"Linux"'

        # 2. EasyList network match. source_url is approximated as the request's
        #    own origin (mitmproxy does not carry the initiator), so pure-domain
        #    rules (||doubleclick.net^) still block; $third-party-only rules are
        #    matched less precisely. The in-page script + cosmetics cover the gap.
        if self.engine is None:
            return
        try:
            res = self.engine.check_network_urls(
                flow.request.url, flow.request.url,
                _req_type(flow.request.path or ""),
            )
            if res and res.matched:
                flow.kill()
        except Exception as e:
            _log("check_network_urls error:", repr(e))

    # ── response: adSlots emptying + cosmetic injection ─────────────────────
    def response(self, flow):
        try:
            host = flow.request.pretty_host
            path = flow.request.path or ""
            url = flow.request.url
            # YouTube's pre-roll is announced by adSlots in TWO places: the
            # youtubei/v1/player XHR *and* the ytInitialPlayerResponse JSON baked
            # into the /watch HTML document. The in-page fetch patch only sees the
            # former; emptying the array in the HTML is what kills the 0:00
            # load-time flash -- the player never learns a break exists.
            if "youtube.com" in host and (
                    "youtubei/v1/player" in url or "youtubei/v1/watch" in url
                    or "/watch" in path):
                self._empty_adslots(flow)
            if self.engine is None:
                return
            ctype = flow.response.headers.get("content-type", "")
            if "text/html" in ctype:
                self._inject_cosmetics(flow)
        except Exception as e:
            _log("response error:", repr(e))

    def _empty_adslots(self, flow):
        try:
            body = flow.response.get_text()
        except Exception:
            return
        if not body or '"adSlots"' not in body:
            return
        new = _empty_key(body, "adSlots")
        if new != body:
            flow.response.set_text(new)
            flow.response.headers.pop("content-length", None)
            _log("emptied adSlots")

    def _inject_cosmetics(self, flow):
        r = self.engine.url_cosmetic_resources(flow.request.url)
        parts = [sel + "{display:none!important}" for sel in r.hide_selectors]
        for sel, styles in r.style_selectors.items():
            parts.append(sel + "{" + ";".join(styles) + "}")
        css = "\n".join(parts)
        js = r.injected_script or ""
        if not css and not js:
            return
        head = ""
        if css:
            head += "<style id='hcproxy-cosmetic'>" + css + "</style>"
        if js:
            head += "<script>" + js + "</script>"
        body = flow.response.get_text()
        if body is None:
            return
        # Inject as early as possible so hidden elements never flash.
        if "<head" in body:
            body = re.sub(r"(?i)<head[^>]*>",
                          lambda m: m.group(0) + head, body, count=1)
        else:
            body = head + body
        flow.response.set_text(body)
        flow.response.headers.pop("content-length", None)


addons = [HCProxy()]
