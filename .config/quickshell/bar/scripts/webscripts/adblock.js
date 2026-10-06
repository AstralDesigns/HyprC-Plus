// ── HyprCandy launcher ad / tracker blocker (script layer) ──────────────────
// Injected as a DocumentCreation, MainWorld user script into every web-search
// tab view (LauncherWindow.qml -> win._applyUserScripts). This QtWebEngine
// build exposes NO QML request-interceptor, so all blocking happens in-page:
//   * network  : fetch / XHR / sendBeacon / WebSocket and the src setter of
//                script|img|iframe|video|source|embed|frame are patched to drop
//                any request whose URL matches BLOCK.
//   * DOM      : a MutationObserver removes already-injected matching elements.
//   * cosmetic : a stylesheet hides well-known ad slots that are same-origin.
// Edit BLOCK / COSMETIC freely — the launcher re-reads this file on start.
// Toggling the shield button re-injects this script and reloads the live tabs.
(function () {
    if (window.__hcAB) return;
    window.__hcAB = 1;

    // Third-party ad networks / exchanges / trackers (matched as URL substrings).
    // Deliberately excludes the Facebook / WhatsApp property so WhatsApp Web and
    // FB-embedded logins keep working.
    // ── page visibility spoof ───────────────────────────────────────────────
    // When the launcher closes, its window is UNMAPPED and QtWebEngine tells
    // every page visibilityState=hidden. Chromium and YouTube then defer the
    // media pipeline (video decode first, then segment loads) and audio dies
    // ~11 minutes into hidden playback -- the exact stall we kept chasing.
    // Report "visible" forever and swallow visibilitychange so the player
    // behaves like a foreground tab (standard kiosk-embed workaround).
    try {
        Object.defineProperty(document, "visibilityState",
            { configurable: true, get: function () { return "visible"; } });
        Object.defineProperty(document, "hidden",
            { configurable: true, get: function () { return false; } });
        Object.defineProperty(document, "webkitVisibilityState",
            { configurable: true, get: function () { return "visible"; } });
        var _docAel = Document.prototype.addEventListener;
        Document.prototype.addEventListener = function (t, f, o) {
            if (t === "visibilitychange") return;
            return _docAel.call(this, t, f, o);
        };
        var _winAel = window.addEventListener;
        window.addEventListener = function (t, f, o) {
            if (t === "visibilitychange") return;
            return _winAel.call(this, t, f, o);
        };
    } catch (e) {}

    // ── rAF lifeline (the "12:09 freeze" root cause) ──────────────────────
    // While the launcher window is unmapped, Chromium stops producing frames,
    // so EVERY requestAnimationFrame callback halts -- below the page, invisible
    // to the visibilityState spoof above. YouTube's HTML5 player drives buffer
    // top-ups through rAF: hide the launcher a couple of minutes before the 720s
    // streaming-cache boundary and segment fetching silently dies (proven in the
    // hcproxy journal: qoe/watchtime/videoplayback ALL stop at the same second,
    // ~2 min before the playhead crawls to the buffer edge at 12:09). The shim
    // races each rAF against a 120ms timer: visible windows keep real vsync
    // cadence (rAF wins the race); hidden ones keep the media loop alive on
    // timers, which do run (--disable-background-timer-throttling).
    try {
        if (/(^|\.)(youtube\.com|youtu\.be)$/.test(location.hostname)) {
            var _raf = window.requestAnimationFrame.bind(window);
            var _caf = window.cancelAnimationFrame.bind(window);
            var _rp = {}, _rs = 0;
            window.requestAnimationFrame = function (cb) {
                var key = "hc" + (_rs++), done = false;
                var rafId = _raf(function (ts) {
                    if (done) return; done = true;
                    delete _rp[key]; cb(ts);
                });
                var tid = setTimeout(function () {
                    if (done) return; done = true;
                    try { _caf(rafId); } catch (e) {}
                    delete _rp[key];
                    cb(typeof performance !== "undefined" ? performance.now() : Date.now());
                }, 120);
                _rp[key] = function () {
                    done = true;
                    try { _caf(rafId); } catch (e) {}
                    clearTimeout(tid);
                };
                return key;
            };
            window.cancelAnimationFrame = function (k) {
                if (_rp[k]) { _rp[k](); delete _rp[k]; return; }
                try { _caf(k); } catch (e) {}
            };
        }
    } catch (e) {}

    var BLOCK = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com",
        "adservice.google", "google.com/ads", "pagead",
        "google-analytics.com", "googletagmanager.com", "analytics.google.com",
        "adnxs.com", "amazon-adsystem.com", "criteo.com", "criteo.net",
        "pubmatic.com", "rubiconproject.com", "openx.net", "smartadserver.com",
        "casalemedia.com", "indexww.com", "yieldmo.com", "adform.net",
        "spotxchange.com", "spotx.tv", "adsafeprotected.com", "innovid.com",
        "teads.tv", "mathtag.com", "media.net", "bidswitch.net", "adstir.com",
        "taboola.com", "outbrain.com", "zergnet.com", "infolinks.com",
        "scorecardresearch.com", "quantserve.com", "chartbeat.com", "moatads.com",
        "bluekai.com", "crwdcntrl.net", "permutive.com", "segment.com",
        "segment.io", "mixpanel.com", "branch.io", "hotjar.com", "fullstory.com",
        "taplytics.com", "adscale.de",
        // YouTube ad endpoints (stable for years). They are same-origin XHR/img
        // pings driven by the player JS, so the fetch/XHR/src patches above catch
        // them; blocking them makes the player skip straight to content.
        "youtube.com/pagead/", "youtube.com/get_midroll_info",
        "youtube.com/api/stats/ads",
        "youtube.com/pcs/activeview", "youtube.com/player/ad_break",
        "googlevideo.com/videostats"
    ];

    function bad(u) {
        if (!u) return false;
        u = ("" + u).toLowerCase();
        for (var i = 0; i < BLOCK.length; i++) {
            if (u.indexOf(BLOCK[i]) > -1) return true;
        }
        return false;
    }

    var count = 0;
    function blocked() { count++; try { window.__hcABCount = count; } catch (e) {} }

    // ── network: fetch ──────────────────────────────────────────────────────
    // Two jobs: (1) drop any request matching BLOCK; (2) for YouTube's InnerTube
    // player config, strip adSlots from the JSON *response* so the player never
    // schedules a break at all. The abort + fast-forward path alone still lets a
    // frame flash because the ad is announced inside the legitimate player
    // response (adSlots), not a separate ad request -- pruning it here is what
    // makes pre/mid-rolls truly seamless (uBlock's yt-player-adslots trick).
    var YT_PLAYER = "youtubei/v1/player";
    // Midroll probes MUST be answered, not killed: when get_midroll_info /
    // player/ad_break fail, the player waits forever at the scheduled break
    // (~12 min into long videos) -- infinite spinner, content video paused.
    // A valid empty ad-break response tells it there is no break; continue.
    // (uBlock's youtube getMidrollInfo stub trick.)
    var MIDROLL_STUB = '{"emptyBookmarks":[]}';
    function isMidroll(u) {
        u = "" + u;
        return u.indexOf("get_midroll_info") > -1 ||
               u.indexOf("/player/ad_break") > -1;
    }
    // ptracking is the ad beacon the player WAITS on during ad transitions;
    // uBlock answers it with empty text (nooptext) rather than erroring.
    // NOTE: modern innertube /player/ad_break is deliberately NOT stubbed --
    // {"emptyBookmarks":[]} is the LEGACY get_midroll_info schema; serving it
    // to the modern API throws inside the break module's response handler and
    // kills its promise chain, which freezes buffer extension at the first
    // midroll marker (the "12:09 death"). uBlock lets ad_break FAIL like any
    // blocked network request (player handles that path gracefully), so we
    // fall through to bad(u) -> reject above.
    function stubFor(u) {
        u = "" + u;
        if (u.indexOf("get_midroll_info") > -1) return MIDROLL_STUB;
        if (u.indexOf("/ptracking") > -1) return "";
        return null;
    }
    function hcFakeJsonXhr(xhr, body) {
        try {
            Object.defineProperty(xhr, "readyState",   { configurable: true, get: function () { return 4; } });
            Object.defineProperty(xhr, "status",       { configurable: true, get: function () { return 200; } });
            Object.defineProperty(xhr, "statusText",   { configurable: true, get: function () { return "OK"; } });
            Object.defineProperty(xhr, "responseText", { configurable: true, get: function () { return body; } });
            Object.defineProperty(xhr, "response",     { configurable: true, get: function () { return body; } });
        } catch (e) { return; }
        setTimeout(function () {
            try {
                if (xhr.onreadystatechange) xhr.onreadystatechange();
                xhr.dispatchEvent(new Event("load"));
                xhr.dispatchEvent(new Event("loadend"));
            } catch (e) {}
        }, 0);
    }
    function pruneAds(j) {
        var hit = false;
        if (j && typeof j === "object") {
            if (j.adSlots) { delete j.adSlots; hit = true; }
            if (j.ads) { delete j.ads; hit = true; }
            if (j.playerResponse && j.playerResponse.adSlots) { delete j.playerResponse.adSlots; hit = true; }
        }
        return hit;
    }
    if (window.fetch) {
        var _fetch = window.fetch;
        window.fetch = function (a) {
            var u = (a && a.url) || a;
            var sb = stubFor(u);
            if (sb !== null) {
                blocked();
                return Promise.resolve(new Response(sb,
                    { status: 200, statusText: "OK",
                      headers: { "content-type": "application/json" } }));
            }
            if (bad(u)) { blocked(); return Promise.reject(new Error("hc-ab")); }
            var p = _fetch.apply(this, arguments);
            if (u && ("" + u).indexOf(YT_PLAYER) > -1) {
                return p.then(function (res) {
                    try {
                        return res.clone().json().then(function (j) {
                            if (!pruneAds(j)) return res;
                            blocked();
                            var h = new Headers();
                            try { res.headers.forEach(function (v, k) {
                                k = k.toLowerCase();
                                if (k !== "content-length" && k !== "content-encoding" &&
                                    k !== "transfer-encoding" && k !== "content-type") h.set(k, v);
                            }); } catch (e) {}
                            h.set("content-type", "application/json");
                            return new Response(JSON.stringify(j), { status: 200, statusText: "OK", headers: h });
                        }).catch(function () { return res; });
                    } catch (e) { return res; }
                });
            }
            return p;
        };
    }

    // ── network: XMLHttpRequest ─────────────────────────────────────────────
    if (window.XMLHttpRequest) {
        var _open = XMLHttpRequest.prototype.open;
        var _send = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.open = function (m, u) {
            this.__hcU = u; this.__hcB = bad(u); if (this.__hcB) blocked();
            this.__hcM = stubFor(u);
            return _open.apply(this, arguments);
        };
        XMLHttpRequest.prototype.send = function () {
            if (this.__hcM !== null && this.__hcM !== undefined) {
                hcFakeJsonXhr(this, this.__hcM); return;
            }
            if (this.__hcB) { try { this.abort(); } catch (e) {} return; }
            return _send.apply(this, arguments);
        };
    }

    // ── network: sendBeacon ─────────────────────────────────────────────────
    if (navigator.sendBeacon) {
        var _beacon = navigator.sendBeacon.bind(navigator);
        navigator.sendBeacon = function (u, d) {
            if (bad(u)) { blocked(); return false; }
            return _beacon(u, d);
        };
    }

    // ── network: WebSocket ──────────────────────────────────────────────────
    if (window.WebSocket) {
        var _WS = window.WebSocket;
        var WS = function (u, p) {
            if (bad(u)) { blocked(); throw new Error("hc-ab"); }
            return new _WS(u, p);
        };
        WS.prototype = _WS.prototype;
        WS.CONNECTING = 0; WS.OPEN = 1; WS.CLOSING = 2; WS.CLOSED = 3;
        window.WebSocket = WS;
    }

    // ── network: element .src setters ───────────────────────────────────────
    function patchSrc(ctorName) {
        var C = window[ctorName];
        if (!C || !C.prototype) return;
        var d = Object.getOwnPropertyDescriptor(C.prototype, "src");
        if (!d || !d.set) return;
        Object.defineProperty(C.prototype, "src", {
            configurable: true, enumerable: d.enumerable, get: d.get,
            set: function (v) {
                if (bad(v)) { blocked(); return; }
                return d.set.call(this, v);
            }
        });
    }
    ["HTMLScriptElement", "HTMLImageElement", "HTMLIFrameElement",
     "HTMLVideoElement", "HTMLSourceElement", "HTMLEmbedElement",
     "HTMLFrameElement"].forEach(patchSrc);

    // ── cosmetic: hide same-origin ad slots ─────────────────────────────────
    var COSMETIC = [
        "iframe[src*=\"doubleclick\"]", "ins.adsbygoogle",
        "div[id^=\"google_ads\"]", "div[id^=\"div-gpt-ad\"]",
        "iframe[id^=\"google_ads\"]", "[class*=\"adsbygoogle\"]",
        "[data-ad-slot]", "[data-ad-client]", "[data-testid=\"ad\"]",
        "[aria-label=\"Advertisement\"]", ".google-auto-placed",
        "iframe[title*=\"advertisement\"]",
        // YouTube cosmetic. Chromium 140 supports :has(), so procedural hiding is
        // plain CSS. These selectors only exist on YouTube, safe to keep global.
        "#masthead-ad", "ytd-ad-slot-renderer", "ytd-promoted-video-renderer",
        "ytd-in-feed-ad-layout-renderer", "ytd-banner-promo-renderer",
        "ytd-promoted-sparkles-web-renderer", "#player-ads",
        "ytd-companion-slot-renderer", "ytd-paused-companion-ad-renderer",
        "ytd-paused-overlay-primary-format-ad-renderer",
        "ytd-rich-item-renderer:has(ytd-ad-slot-renderer)",
        "ytd-video-renderer:has(ytd-ad-slot-renderer)",
        "ytd-item-section-renderer:has(> ytd-ad-slot-renderer)",
        "ytd-video-primary-info-renderer:has(.ad-badge)",
        ".ytp-ad-module", ".ytp-ad-overlay-slot", ".ytp-ad-player-overlay",
        ".ytp-ad-player-overlay-layout", ".ytp-ad-text-image-layout",
        ".ytp-ad-overlay-container", ".ytp-ad-survey",
        ".ytp-suggestion-set:has(.ad-badge)"
    ].join(",") + "{display:none!important;height:0!important;width:0!important;overflow:hidden!important}";

    function injectCss() {
        try {
            var root = document.head || document.documentElement;
            if (!root) return;   // too early (DocumentCreation); DOMContentLoaded retries
            if (document.getElementById("__hcab")) return;
            var s = document.createElement("style");
            s.id = "__hcab";
            s.textContent = COSMETIC;
            root.appendChild(s);
        } catch (e) {}
    }

    // ── DOM scrub of already-injected matching elements ─────────────────────
    function scrub(node) {
        try {
            if (!node || node.nodeType !== 1) return;
            if (node.src && bad(node.src)) { blocked(); try { node.remove(); } catch (e) {} }
            var q = node.querySelectorAll ? node.querySelectorAll("iframe,script,img,video,source,embed") : [];
            for (var i = 0; i < q.length; i++) {
                if (q[i].src && bad(q[i].src)) { blocked(); try { q[i].remove(); } catch (e) {} }
            }
        } catch (e) {}
    }

    // ── YouTube in-stream guard: auto-skip / fast-forward past ads ───────────
    // Belt-and-braces for any pre/mid-roll that slips the network block: when an
    // ad overlay is showing, jump the video to its end and click Skip if present,
    // so the ad is perceptually instant and the Skip UI never lingers.
    function ytGuard() {
        var h = location.hostname;
        if (!/(^|\.)(youtube\.com|youtu\.be)$/.test(h)) return;
        // Ad and content share ONE <video> element. Fast-forwarding the ad to
        // duration+1 (and clicking Skip) can leave that element paused/ended, and
        // YouTube does not always auto-play the content back — the tab looks frozen
        // until reload. So we watch for the ad->content transition and nudge play()
        // for a short window until the main video is actually running.
        var wasAd = false, resumeTries = 0;
        setInterval(function () {
            try {
                // The player container carries .ad-showing ONLY while an ad plays;
                // this is the canonical, stable signal. Jump the ad to its end and
                // click Skip so it is perceptually instant and the UI never lingers.
                var ad = document.querySelector(
                    ".html5-video-player.ad-showing, #movie_player.ad-showing");
                if (ad) {
                    wasAd = true; resumeTries = 0;
                    var v = ad.querySelector("video");
                    if (v && v.duration > 0 && isFinite(v.duration))
                        v.currentTime = v.duration + 1;
                    var s = ad.querySelector(
                        ".ytp-ad-skip-button, .ytp-ad-skip-button-modern, " +
                        ".ytp-skip-ad-button, [button-title*=\"Skip\"]");
                    if (s) s.click();
                } else {
                    if (wasAd) { wasAd = false; resumeTries = 1; }
                    // ~12 * 300ms window for the content stream to attach and start.
                    if (resumeTries > 0 && resumeTries <= 12) {
                        resumeTries++;
                        var mv = document.querySelector(
                            "video.html5-main-video, #movie_player video.html5-main-video, " +
                            "#movie_player video");
                        if (mv && !mv.paused) {
                            resumeTries = 0;                 // playing again — done
                        } else if (mv) {
                            if (mv.ended) { try { mv.currentTime = 0; } catch (e) {} }
                            var pr = mv.play && mv.play();
                            if (pr && pr.catch) pr.catch(function () {});
                        }
                    }
                }
                var close = document.querySelector(".ytp-ad-overlay-close-button");
                if (close) close.click();
            } catch (e) {}
        }, 300);
    }

    function start() {
        injectCss();
        ytGuard();
        if (document.documentElement) {
            var mo = new MutationObserver(function (ms) {
                for (var i = 0; i < ms.length; i++) {
                    var an = ms[i].addedNodes;
                    for (var j = 0; j < an.length; j++) scrub(an[j]);
                }
            });
            mo.observe(document.documentElement, { childList: true, subtree: true });
        }
        if (document.readyState === "loading")
            document.addEventListener("DOMContentLoaded", injectCss, true);
    }
    start();
})();
