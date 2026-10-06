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
#   4. Strips streamingData.serverAbr* from the /player response AND the /watch
#      HTML's inline player response -- forcing legacy segmented streaming.
#      MUST live here, not in the page: YouTube's service worker (sw.js) runs
#      innertube fetches in its own realm where userScripts never reach, so
#      every JS-level /player cleaner was silently bypassed (verified 2026-10-06:
#      two loadVideoById conversions ran, live response still had the SABR url).
#      get_watch is deliberately NEVER touched: its payload is attestation-
#      sealed -- any edit (bytes or parsed object) kills player boot.
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
import json
import re
import time
import urllib.request

import adblock  # extra/python-adblock -- Brave's adblock-rs crate in Python
from mitmproxy import http

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


# serverAbr* members of a streamingData object. Observed key order puts them
# last (expiresInSeconds, formats, adaptiveFormats, serverAbr...), so eating
# the LEADING comma keeps the JSON valid; a first-position key would need the
# trailing-comma variant -- add it only if a capture ever shows that shape.
SABR_RE = re.compile(
    r',\s*"serverAbr[^"]*"\s*:\s*(?:"(?:[^"\\]|\\.)*"'
    r'|-?\d+(?:\.\d+)?|true|false|null)')


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


# The launcher's shield toggle persists here; when adblock is OFF the proxy
# must degrade to UA-rewrite ONLY (the pre-adblock baseline that never died):
# no engine blocks, no midroll stub, no adSlots gutting, no cosmetics.
STATE_PATH = os.path.expanduser(
    "~/.local/share/hyprcandy/websearch-startup-state.json")


def _adblock_on():
    try:
        mt = os.stat(STATE_PATH).st_mtime
        if mt != _adblock_on._mt:
            _adblock_on._mt = mt
            with open(STATE_PATH) as f:
                _adblock_on._on = json.load(f).get("adblock", True) is True
    except Exception:
        return True
    return _adblock_on._on


_adblock_on._mt = 0.0
_adblock_on._on = True


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
        # 0. Debug-beacon channel: adblock.js mirrors every page-side decision
        #    on YouTube player endpoints as a GET to hcdebug.invalid, answered
        #    here locally (no DNS). Journal lines then prove what the player
        #    attempted at the 12:09 boundary -- incl. requests the page-side
        #    patches swallowed before they ever hit the network.
        if flow.request.pretty_host == "hcdebug.invalid":
            # mitmdump's own request-line log truncates at terminal width in
            # non-TTY mode, so echo the full beacon path ourselves instead.
            _log("BEACON", flow.request.path)
            flow.response = http.Response.make(200, b"")
            return
        # 1. Clean Chrome identity on the wire (fixes WhatsApp's server gate).
        h["User-Agent"] = CHROME_UA
        h["sec-ch-ua"] = CHROME_BRANDS
        h["sec-ch-ua-mobile"] = "?0"
        h["sec-ch-ua-platform"] = '"Linux"'

        # 2. Legacy YouTube midroll probes must be ANSWERED with an empty
        #    ad-break JSON: a failed get_midroll_info makes the old player wait
        #    forever at the scheduled break. Modern innertube /player/ad_break
        #    is NOT stubbed here -- its schema differs and a wrong-shaped 200
        #    kills the break module's promise chain (buffer freezes at the
        #    midroll marker); it must fail like any blocked request instead.
        ph = flow.request.pretty_host
        if _adblock_on():
            if "youtube.com" in ph and ("get_midroll_info" in ph
                                        or "get_midroll_info" in (flow.request.path or "")):
                flow.response = http.Response.make(
                    200, b'{"emptyBookmarks":[]}',
                    {"content-type": "application/json"})
                return

        # 3. EasyList network match. source_url is approximated as the request's
        #    own origin (mitmproxy does not carry the initiator), so pure-domain
        #    rules (||doubleclick.net^) still block; $third-party-only rules are
        #    matched less precisely. The in-page script + cosmetics cover the gap.
        if self.engine is None or not _adblock_on():
            return
        try:
            res = self.engine.check_network_urls(
                flow.request.url, flow.request.url,
                _req_type(flow.request.path or ""),
            )
            if res and res.matched:
                # NOT flow.kill(): kill tears down the entire client CONNECTION,
                # and Chromium multiplexes qoe/watchtime/innertube/media over ONE
                # HTTP/2 connection per host — a kill every 30s (EasyPrivacy
                # matches api/stats/qoe) randomly destroys in-flight media
                # requests => "stuck on loading" minutes later. A 204 rejects
                # the single ad ping and leaves the connection intact.
                flow.response = http.Response.make(204, b"")
        except Exception as e:
            _log("check_network_urls error:", repr(e))

    # ── response: adSlots emptying + SABR kill + cosmetic injection ────────
    def response(self, flow):
        try:
            host = flow.request.pretty_host
            path = flow.request.path or ""
            url = flow.request.url
            # 4. SABR kill: unconditional (shield state is about ads, and a
            #    SABR playback death is not an ad outcome we can trade).
            #    /player JSON responses ONLY. RETIRED 2026-10-06: the tape
            #    proved stripped /player responses kill playback seconds in
            #    ("An error occurred (Playback ID ...)") -- innertube FETCH
            #    responses are attestation-verified. Legacy is enforced
            #    page-side instead (inline trap + full-document navigation,
            #    see webscripts/sabrkill.js). Code kept dark as a map of
            #    the dead end.
            if False and "youtube.com" in host and "youtubei/v1/player" in url:
                self._desabr(flow)
            # Shield OFF: never touch response bodies. Rewriting player
            # responses (adSlots gutting) is exactly the tier the pre-adblock
            # baseline never had and the 720s renewal consumes.
            if not _adblock_on():
                return
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

    def _desabr(self, flow):
        try:
            body = flow.response.get_text()
        except Exception:
            return
        if not body or '"serverAbr' not in body:
            return
        new = SABR_RE.sub("", body)
        if new != body:
            flow.response.set_text(new)
            flow.response.headers.pop("content-length", None)
            _log("stripped serverAbr")

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
