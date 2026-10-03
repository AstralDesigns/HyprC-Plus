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
        "youtube.com/api/stats/ads", "youtube.com/ptracking",
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
            return _open.apply(this, arguments);
        };
        XMLHttpRequest.prototype.send = function () {
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
        setInterval(function () {
            try {
                // The player container carries .ad-showing ONLY while an ad plays;
                // this is the canonical, stable signal. Jump the ad to its end and
                // click Skip so it is perceptually instant and the UI never lingers.
                var ad = document.querySelector(
                    ".html5-video-player.ad-showing, #movie_player.ad-showing");
                if (ad) {
                    var v = ad.querySelector("video");
                    if (v && v.duration > 0 && isFinite(v.duration))
                        v.currentTime = v.duration + 1;
                    var s = ad.querySelector(
                        ".ytp-ad-skip-button, .ytp-ad-skip-button-modern, " +
                        ".ytp-skip-ad-button, [button-title*=\"Skip\"]");
                    if (s) s.click();
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
