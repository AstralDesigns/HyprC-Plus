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

    // ── ytInitialPlayerResponse interceptor ─────────────────────────────────
    // YouTube's primary ad-block detection: the inline <script> on /watch pages
    // sets `var ytInitialPlayerResponse = {...}` with adPlacements/adSlots/
    // playerAds/ssapConfig. The player JS reads these to schedule breaks; if
    // they exist but ad network requests fail, the detection fires the
    // "Ad blockers violate ToS" enforcement page.
    //
    // Fix: intercept the property DEFINITION via Object.defineProperty on window
    // and strip ad-related keys BEFORE any page script reads them. This is the
    // same technique as Zen Desktop's $remove-js-constant and uBlock's
    // set-constant scriptlet, but done in-page since we have no proxy layer.
    (function interceptPlayerResponse() {
        var STRIP = ["adPlacements", "adSlots", "playerAds"];
        function prunePR(j) {
            if (!j || typeof j !== "object") return j;
            for (var i = 0; i < STRIP.length; i++) delete j[STRIP[i]];
            // ssapConfig (Server-Side Ad Placement) is the detection flag
            if (j.playerConfig && j.playerConfig.args) delete j.playerConfig.args.ssapConfig;
            if (j.playerConfig) delete j.playerConfig.ssapConfig;
            // playabilityStatus with LOGIN_REQUIRED is the enforcement trigger
            if (j.playabilityStatus && j.playabilityStatus.status
                && j.playabilityStatus.status !== "OK"
                && /ad.block|Terms of Service/i.test(j.playabilityStatus.reason || "")) {
                j.playabilityStatus = { status: "OK", playableInEmbeds: true };
            }
            return j;
        }
        try {
            var _val = undefined;
            Object.defineProperty(window, "ytInitialPlayerResponse", {
                configurable: true,
                enumerable: true,
                get: function () { return _val; },
                set: function (v) {
                    var pruned = prunePR(v);
                    // After the first assignment, swap the accessor for a
                    // plain writable data property so YouTube's fab probe
                    // (which reads `Object.getOwnPropertyDescriptor(window,
                    // 'ytInitialPlayerResponse')` and rejects on `get`/`set`
                    // being present) sees a shape identical to a native
                    // inline `var ytInitialPlayerResponse = {...}` write.
                    // The strip-once semantic is enough because the property
                    // is only assigned once per page load.
                    try {
                        Object.defineProperty(window, "ytInitialPlayerResponse", {
                            configurable: true, enumerable: true,
                            writable: true, value: pruned
                        });
                    } catch (e) { _val = pruned; }
                }
            });
        } catch (e) {}
        // Expose prunePR for the fetch interceptor below
        window.__hcPrunePR = prunePR;
    })();

    // ── anti-adblock-detection spoof ────────────────────────────────────────
    // Secondary detection vectors (Brave/uBlock counter these the same way):
    //   (a) `window.adsbygoogle` must exist with .loaded/.push/.exec shape
    //   (b) `<ins class="adsbygoogle">` test element must NOT be display:none
    //   (c) `pagead/lvz` + `videostats` beacon fetches must resolve with 200
    // We satisfy all three: define globals as no-op shims, leave the test
    // element visible (real ads blocked at network), stub beacons with 200.
    (function spoofAdGlobals() {
        var noop = function () {};
        var shim = { loaded: true, exec: noop, pausing: false, policy: {},
                     push: noop, container_id_counter: function () { return 0 } };
        // adsbygoogle is sometimes read before the shim installs; use a getter
        // that lazily materialises the object so any read path succeeds.
        try {
            var _adbg = shim;
            Object.defineProperty(window, "adsbygoogle", {
                configurable: true,
                get: function () { return _adbg; },
                set: function (v) { if (v && v !== _adbg) { try { Object.assign(_adbg, v); } catch (e) {} } }
            });
        } catch (e) { try { window.adsbygoogle = shim; } catch (_) {} }
        // Google ad-related globals the probe checks (existence only).
        var globals = {
            _gads: { canAdsRun: true, loaded: true },
            google_jobad: noop,
            google_cbt: noop, google_cache_bg: noop,
            google_rum: noop, google_cl: noop, google_iafv: noop,
            google_pa: noop,
            google_reactive_ads_config: {},
            google_esf: function () { return noop }
        };
        for (var k in globals) {
            if (typeof window[k] === "undefined") { try { window[k] = globals[k]; } catch (e) {} }
        }
        // google_reactive_ads_global_state: probe checks .product configuration
        if (typeof window.google_reactive_ads_global_state === "undefined") {
            try {
                window.google_reactive_ads_global_state = {
                    product: 1, adFormats: ["link","banner"], adsEnabled: true,
                    googleHtmlNocache: noop, googleNs: noop
                };
            } catch (e) {}
        }
    })();

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
        "adservice.google", "google.com/ads",
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
        // YouTube midroll scheduling: stubbed via stubFor() before reaching bad().
        // ad_break intentionally rejected (SABR: stubbing it freezes buffer).
        "youtube.com/get_midroll_info",
        "youtube.com/player/ad_break"
    ];

    // ── YouTube ad/detection endpoints: STUB with 200, never reject ───────
    // These are the endpoints YouTube's fab (anti-adblock) detection monitors.
    // Rejecting them is the strongest "ad blocker present" signal that triggers
    // the full-page "Ad blockers violate ToS" enforcement. Stubbing with 200 +
    // empty body makes the player think ads loaded successfully while showing
    // nothing (same technique as uBlock's redirect=nooptext and Brave's rules).
    // ── YouTube ad/detection endpoints: PASS THROUGH, STUB RESPONSE ───────
    // These are the endpoints YouTube's fab (anti-adblock) detection monitors
    // for beacon traffic. Two failure modes matter:
    //   * Rejecting (our old BLOCK behaviour) = strongest adblock signal.
    //   * Locally stubbing WITHOUT network = server sees zero beacons = still
    //     triggers the flag (this was the bug behind "loaded directly into
    //     enforcement page" even with the shield on).
    // Correct pattern (uBlock `redirect=nooptext`, Brave `important`): let the
    // request physically hit Google/YouTube's servers so the server's beacon
    // log is satisfied, then hand the JS caller an empty 200 body so no ad
    // creative renders or executes.
    var FAB = [
        "youtube.com/pagead/",          // ad delivery + lvz detection beacon
        "youtube.com/api/stats/ads",    // ad playback tracking
        "youtube.com/pcs/activeview",   // Google ActiveView measurement
        "googlevideo.com/videostats",   // playback telemetry (ad + content)
        "youtube.com/ytranking",
        "youtube.com/ytooffers",
        "/adsid/", "/abstatus", "/antiadblock",
        "youtube.com/ptracking",        // ad beacon player waits on
        "youtube.com/api/stats",        // generic playback telemetry
        "youtube.com/watch_time"        // watch-time beacon
    ];
    var FAB_EMPTY = "";
    function isFab(u) {
        if (!u) return false;
        u = ("" + u).toLowerCase();
        for (var i = 0; i < FAB.length; i++)
            if (u.indexOf(FAB[i]) > -1) return true;
        return false;
    }
    // FAB exceptions: patterns that MUST still hard-block (never hit network)
    // even if they'd otherwise match a FAB entry. Anything under
    // `googlesyndication.com/` other than the two beacon paths above is a
    // third-party ad delivery endpoint we reject silently.
    var FAB_EXCEPT = [
        "googlesyndication.com/pagead/ads",
        "googlesyndication.com/iframe",
        "googlesyndication.com/dai/",
        "googlesyndication.com/bundle/"
    ];
    function isFabExcept(u) {
        if (!u) return false;
        u = ("" + u).toLowerCase();
        for (var i = 0; i < FAB_EXCEPT.length; i++)
            if (u.indexOf(FAB_EXCEPT[i]) > -1) return true;
        return false;
    }

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
            if (j.adPlacements) { delete j.adPlacements; hit = true; }
            if (j.playerAds) { delete j.playerAds; hit = true; }
            if (j.ads) { delete j.ads; hit = true; }
            if (j.playerResponse) {
                if (j.playerResponse.adSlots) { delete j.playerResponse.adSlots; hit = true; }
                if (j.playerResponse.adPlacements) { delete j.playerResponse.adPlacements; hit = true; }
                if (j.playerResponse.playerAds) { delete j.playerResponse.playerAds; hit = true; }
            }
            if (j.playerConfig) {
                if (j.playerConfig.ssapConfig) { delete j.playerConfig.ssapConfig; hit = true; }
                if (j.playerConfig.args && j.playerConfig.args.ssapConfig) {
                    delete j.playerConfig.args.ssapConfig; hit = true;
                }
            }
        }
        return hit;
    }
    if (window.fetch) {
        var _fetch = window.fetch;
        window.fetch = function (a) {
            var u = (a && a.url) || a;
            var sb = stubFor(u);
            // FAB: let the beacon physically hit Google/YouTube's servers so
            // their ad-handling telemetry log is satisfied, but hand the
            // caller an empty 200 body so no ad creative is parsed. Only
            // skip the network if it also matches a hard-block exception
            // (third-party ad delivery) or `bad()` on top of FAB.
            if (isFab(u) && !isFabExcept(u)) {
                blocked();
                var args = arguments;
                try {
                    return _fetch.apply(this, args).then(function () {
                        return new Response(FAB_EMPTY,
                            { status: 200, statusText: "OK",
                              headers: { "content-type": "text/plain" } });
                    }).catch(function () {
                        return new Response(FAB_EMPTY,
                            { status: 200, statusText: "OK",
                              headers: { "content-type": "text/plain" } });
                    });
                } catch (e) {
                    return Promise.resolve(new Response(FAB_EMPTY,
                        { status: 200, statusText: "OK",
                          headers: { "content-type": "text/plain" } }));
                }
            }
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
                            // Strip ad keys AND fix playabilityStatus enforcement
                            var changed = pruneAds(j);
                            if (j.playabilityStatus && j.playabilityStatus.status
                                && j.playabilityStatus.status !== "OK"
                                && /ad.block|Terms of Service/i.test(j.playabilityStatus.reason || "")) {
                                j.playabilityStatus = { status: "OK", playableInEmbeds: true };
                                changed = true;
                            }
                            if (!changed) return res;
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
            this.__hcU = u;
            this.__hcF = isFab(u) && !isFabExcept(u);
            this.__hcFx = isFabExcept(u);
            this.__hcB = (!this.__hcF && !this.__hcFx) && bad(u);
            if (this.__hcB) blocked();
            // Non-FAB stubs (get_midroll_info etc.) still short-circuit send().
            this.__hcM = this.__hcF ? null : stubFor(u);
            if (this.__hcF) blocked();
            return _open.apply(this, arguments);
        };
        XMLHttpRequest.prototype.send = function () {
            // FAB: let the real network call fire so Google/YouTube's servers
            // see the beacon, but shadow `response`/`responseText` getters on
            // this instance so any read (sync or in onload) returns empty.
            if (this.__hcF) {
                var self = this;
                try {
                    Object.defineProperty(self, "response",
                        { configurable: true, get: function () { return FAB_EMPTY; } });
                    Object.defineProperty(self, "responseText",
                        { configurable: true, get: function () { return FAB_EMPTY; } });
                } catch (e) {}
                return _send.apply(self, arguments);
            }
            if (this.__hcFx || this.__hcB) { try { this.abort(); } catch (e) {} return; }
            if (this.__hcM !== null && this.__hcM !== undefined) {
                hcFakeJsonXhr(this, this.__hcM); return;
            }
            return _send.apply(this, arguments);
        };
    }

    // ── network: sendBeacon ─────────────────────────────────────────────────
    if (navigator.sendBeacon) {
        var _beacon = navigator.sendBeacon.bind(navigator);
        navigator.sendBeacon = function (u, d) {
            // FAB beacons physically reach the server (this is the whole point
            // of the pass-through design). Only hard-block matches are dropped.
            if (isFabExcept(u)) { blocked(); return false; }
            if (isFab(u)) { blocked(); return _beacon(u, d); }
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
        // NOTE: `[class*="adsbygoogle"]` is DELIBERATELY OMITTED -- YouTube's
        // fab probe creates a hidden <ins class="adsbygoogle"> test element
        // and reads its computed style; a display:none answer triggers the
        // warning. Real ad iframes inside it are already blocked at the network
        // layer, so leaving the container visible only renders an empty slot.
        "iframe[src*=\"doubleclick\"]", "ins.adsbygoogle[data-ad-client]",
        "div[id^=\"google_ads\"]", "div[id^=\"div-gpt-ad\"]",
        "iframe[id^=\"google_ads\"]",
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
        ".ytp-suggestion-set:has(.ad-badge)",
        // ── YouTube "ad blocker detected" enforcement dialog ────────────
        // If the probe slips past the spoof, hide the dialog itself so the
        // user is never interrupted. These selectors cover the renderers
        // used through 2024-2025 (yt-*, ytd-* variants + modal backdrop).
        "ytd-enforcement-message-renderer",
        "yt-enforcement-message-view-model",
        "ytd-yto-offer-renderer",
        "#dialog[aria-label*=\"blocker\"]",
        "tp-ytd-app .yt-enforcement-message"
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

    // ── fab-dialog scrub ──────────────────────────────────────────────────
    // CSS above hides known renderer tags; if YouTube introduces a new variant
    // (rotating class names / role=dialog with adblock copy) this catches it
    // generically by content match and removes the dialog before it paints.
    var FAB_TEXT_RE = /ad blocker|adblocker|ad-blocker|unblock our ads|disable.{0,20}adblock|whitelist us|ad blocker detected/i;
    function scrubFabDialogs(root) {
        try {
            if (!root || root.nodeType !== 1) return;
            // Only inspect dialogs / overlays / banners (cheap).
            var nodes = [];
            if (root.matches && root.matches('[role="dialog"],tp-ytd-app,tp-material-dialog,.ytd-enforcement-message,yt-enforcement-message-view-model'))
                nodes.push(root);
            if (root.querySelectorAll) {
                var q = root.querySelectorAll('[role="dialog"],tp-material-dialog,.ytd-enforcement-message,yt-enforcement-message-view-model,ytd-enforcement-message-renderer');
                for (var i = 0; i < q.length; i++) nodes.push(q[i]);
            }
            for (var n = 0; n < nodes.length; n++) {
                var el = nodes[n];
                if (FAB_TEXT_RE.test(el.textContent || "")) {
                    try { el.remove(); } catch (e) {}
                    // Also close any backdrop left behind.
                    var bd = document.querySelector('tp-ytd-app#ytd-main-content ~ .scrim, ytd-backdrop');
                    if (bd) { try { bd.remove(); } catch (e) {} }
                }
            }
        } catch (e) {}
    }

    function ytGuard() {
        // ── YouTube in-stream guard: auto-skip / fast-forward past ads ──────
        // Belt-and-braces for any pre/mid-roll that slips the network block:
        // when an ad overlay is showing, jump the video to its end and click
        // Skip so the ad is perceptually instant and the Skip UI never lingers.
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
        fabRecovery();
        if (document.documentElement) {
            var mo = new MutationObserver(function (ms) {
                for (var i = 0; i < ms.length; i++) {
                    var an = ms[i].addedNodes;
                    for (var j = 0; j < an.length; j++) {
                        scrub(an[j]);
                        scrubFabDialogs(an[j]);
                    }
                }
            });
            mo.observe(document.documentElement, { childList: true, subtree: true });
        }
        if (document.readyState === "loading")
            document.addEventListener("DOMContentLoaded", injectCss, true);
    }

    // ── Enforcement page auto-recovery ─────────────────────────────────────
    // YouTube's server tracks whether the client acknowledged adSlots. Our
    // ytInitialPlayerResponse interceptor strips them before the player reads
    // them, so the player never makes ad requests. The server notices "adSlots
    // were served but no ad requests followed" and on the NEXT page load may
    // serve the full-page "Ad blockers violate ToS" enforcement instead of the
    // watch page (no player, no ytInitialPlayerResponse to intercept).
    //
    // Recovery: detect the enforcement page by its unique DOM signature,
    // signal QML to clear YouTube cookies from the on-disk Chromium profile,
    // destroy + recreate the view, and re-navigate with a `_hcR=<ts>`
    // cache-buster. The cache-buster doubles as a counter reset: our attempt
    // history lives in sessionStorage keyed by `_hcR` timestamp, so any
    // QML-driven reload starts fresh (the counter only bounds loops when
    // QML is *not* reloading, i.e. when the view is broken).
    function fabRecovery() {
        var h = location.hostname;
        if (!/(^|\.)(youtube\.com|youtu\.be)$/.test(h)) return;
        // QML appends `_hcR=<ms>` on every cache-busted reload. Any URL that
        // already contains it means "this navigation is a fresh attempt" so
        // we clear the local counter before starting again.
        try {
            if (/[?&]_hcR=\d+/.test(location.href)) sessionStorage.removeItem("__hcFabR");
        } catch (e) {}
        var RELOAD_KEY = "__hcFabR";
        var attempts = 0;
        try { attempts = parseInt(sessionStorage.getItem(RELOAD_KEY) || "0"); } catch (e) {}
        // Recursive walker that pierces every shadow root so text inside
        // <ytd-app>#shadowRoot > <yt-enforcement-message-view-model> is
        // actually inspected. body.innerText stops at shadow boundaries,
        // which is why the previous detection silently failed.
        function deepScanText(node, out) {
            if (!node) return out;
            if (node.nodeType === 3) { out.push(node.nodeValue || ""); return out; }
            if (node.shadowRoot) deepScanText(node.shadowRoot, out);
            var c = node.firstChild;
            while (c) { deepScanText(c, out); c = c.nextSibling; }
            return out;
        }
        function deepQuery(sel) {
            // Breadth-first including shadow roots; returns array of matches.
            var found = [];
            var queue = [document.documentElement];
            while (queue.length) {
                var n = queue.shift();
                if (!n) continue;
                try {
                    if (n.querySelectorAll) {
                        var m = n.querySelectorAll(sel);
                        for (var i = 0; i < m.length; i++) found.push(m[i]);
                    }
                } catch (e) {}
                if (n.shadowRoot) queue.push(n.shadowRoot);
                var c = n.firstChild;
                while (c) { if (c.nodeType === 1) queue.push(c); c = c.nextSibling; }
            }
            return found;
        }
        function isEnforcementPage() {
            // Positive signal: any of the known enforcement renderers, in
            // light or shadow DOM. Negative signal: a live player element
            // means we're on a watch page, not the wall.
            if (document.querySelector("#movie_player, .html5-video-player")) return false;
            var renderers = deepQuery(
                "ytd-enforcement-message-renderer," +
                "yt-enforcement-message-view-model," +
                "ytd-yto-offer-renderer," +
                "tp-ytd-app .yt-enforcement-message");
            if (renderers.length) return true;
            var body = document.body;
            if (!body) return false;
            var chunks = deepScanText(body, []);
            var t = chunks.join(" ");
            return /ad.blockers?.{0,40}violate|Allow YouTube Ads|disable.{0,20}ad blocker/i.test(t);
        }
        function recover() {
            if (attempts >= 3) return; // hard cap: 3 tries per URL before we give up
            attempts++;
            try { sessionStorage.setItem(RELOAD_KEY, String(attempts)); } catch (e) {}
            // Signal QML to clear HttpOnly cookies from the profile DB and
            // destroy/recreate the view (the only reliable way to flush
            // Chromium's in-memory cookie jar after an external DB write).
            // QML handles the reload; we do NOT navigate here (avoids race).
            console.error("__HC_FAB_CLEAR__");
        }
        // Check after DOM is ready
        function check() {
            if (isEnforcementPage()) recover();
        }
        if (document.readyState === "loading") {
            document.addEventListener("DOMContentLoaded", function () {
                setTimeout(check, 800); // let the page fully render
            });
        } else {
            setTimeout(check, 800);
        }
    }

    // ── Proactive ad acknowledgement beacon ─────────────────────────────────
    // Fire a real network GET to youtube.com/api/stats/ads on every YouTube
    // page load, regardless of whether a player initialised. This is the
    // "beacon traffic is flowing" signal YouTube's fab (anti-adblock) server
    // looks for. If we only fire when a video plays, sessions that hit
    // "An error occurred" (e.g. after the launcher hid the view and drained
    // the buffer) never emit the beacon -> next navigation lands on the
    // full-page enforcement wall. `mode: "no-cors"` lets the request reach
    // YouTube's servers without needing CORS; we don't read the response.
    function fabAck() {
        var h = location.hostname;
        if (!/(^|\.)(youtube\.com|youtu\.be)$/.test(h)) return;
        function send() {
            var vid = "";
            try {
                var m = location.href.match(/[?&]v=([A-Za-z0-9_-]{6,})/);
                vid = m ? m[1] : ((window.ytInitialPlayerResponse || {}).videoId || "hc");
            } catch (e) { vid = "hc"; }
            try {
                var url = "https://www.youtube.com/api/stats/ads?docid=" + vid +
                    "&event=adimp&ad_id=0&num_ads=0&ads_skipped=0";
                if (typeof _fetch === "function") {
                    _fetch(url, { method: "GET", mode: "no-cors", keepalive: true,
                                  credentials: "include" });
                } else if (typeof _beacon === "function") {
                    _beacon(url);
                }
            } catch (e) {}
            // Also fire a pagead/lvz viewable-impression beacon so Google's
            // ad framework sees the request; use native src setter to bypass
            // our own HTMLImageElement patch (which would reject third-party
            // doubleclick/googlesyndication URLs).
            try {
                var img = new Image(1, 1);
                var d = Object.getOwnPropertyDescriptor(
                    HTMLImageElement.prototype, "src");
                if (d && d.set) d.set.call(img,
                    "https://www.youtube.com/pagead/lvz?ai=0&v=" + vid + "&sz=1x1");
            } catch (e) {}
        }
        // Fire on DOMContentLoaded OR immediately if already ready.
        if (document.readyState === "loading") {
            document.addEventListener("DOMContentLoaded", send, { once: true });
        } else {
            send();
        }
        // Retry once a bit later so the beacon still fires if the player
        // initialises after our first send (and gets a real videoId).
        setTimeout(send, 3500);
    }

    start();
    fabAck();
})();
