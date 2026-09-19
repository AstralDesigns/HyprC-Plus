#!/usr/bin/env python3
"""Replace the crash-prone _setupAdBlocker with a hardened, robust version."""

NEW_SETUP_ADBLOCKER = '''    // ── WebKit: Native Ad & Tracker Blocker setup (hardened version) ─────
    _setupAdBlocker(ucm, cacheDir) {
        try {
            if (!ucm || typeof ucm.add_filter !== 'function') {
                console.warn('[launcher] _setupAdBlocker: invalid ucm, skipping');
                return false;
            }
            if (!cacheDir || typeof cacheDir !== 'string') {
                console.warn('[launcher] _setupAdBlocker: invalid cacheDir, skipping filter store');
            }

            let storePath = null;
            if (cacheDir) {
                try {
                    storePath = GLib.build_filenamev([cacheDir, 'filters']);
                    GLib.mkdir_with_parents(storePath, 0o755);
                    if (!GLib.file_test(storePath, GLib.FileTest.IS_DIR)) {
                        storePath = null;
                    }
                } catch (_e) {
                    storePath = null;
                }
            }

            const adDomains = [
                "*.doubleclick.net", "*.googlesyndication.com", "*.googleadservices.com",
                "*.googleads.g.doubleclick.net", "*.adservice.google.com", "*.google-analytics.com",
                "*.googletagmanager.com", "*.googletagservices.com",
                "*.adnxs.com", "*.taboola.com", "*.outbrain.com", "*.scorecardresearch.com",
                "*.criteo.com", "*.advertising.com", "*.popads.net", "*.adroll.com",
                "*.pubmatic.com", "*.rubiconproject.com", "*.amazon-adsystem.com",
                "*.moatads.com", "*.buysellads.com", "*.casalemedia.com", "*.openx.net",
                "*.bidswitch.net", "*.quantserve.com", "*.lijit.com", "*.trafficjunky.net",
                "*.adsystem.com", "*.adsrvr.org", "*.sharethrough.com", "*.sovrn.com",
                "*.facebook.net", "*.connect.facebook.net", "*.pixel.facebook.com",
                "*.ads-twitter.com", "*.ads.pinterest.com", "*.snap.licdn.com"
            ];

            const safeResourceTypes = [
                "image", "script", "style", "font", "media", "raw",
                "subdocument", "popup", "xhr", "fetch"
            ];

            const simpleBlockRule = {
                "trigger": { "url-filter": ".*", "if-domain": adDomains },
                "action": { "type": "block" }
            };

            const resourceBlockRule = {
                "trigger": {
                    "url-filter": ".*",
                    "resource-type": safeResourceTypes,
                    "if-domain": adDomains
                },
                "action": { "type": "block" }
            };

            const cosmeticSelector = [
                ".adsbygoogle", ".ad-container", ".ad-banner", ".advertisement",
                "[id^=\\"google_ads_iframe\\"]", ".taboola-placeholder",
                ".outbrain_widget", ".criteo-ad", ".ad-slot", ".sponsored-post",
                ".ytp-ad-overlay-container", ".ytp-ad-message-container",
                ".ytp-ad-preview-container", "ytd-ad-slot-renderer",
                "ytd-in-feed-ad-layout-renderer", "ytd-banner-promo-renderer",
                "ytd-statement-banner-renderer", "ytd-action-companion-ad-renderer",
                "#player-ads"
            ].join(", ");

            const cosmeticRule = {
                "trigger": { "url-filter": ".*" },
                "action": { "type": "css-display-none", "selector": cosmeticSelector }
            };

            const filterRules = [simpleBlockRule, resourceBlockRule, cosmeticRule];

            let filterStore = null;
            if (storePath) {
                try {
                    filterStore = new WebKit.UserContentFilterStore({ path: storePath });
                } catch (e) {
                    console.warn('[launcher] Adblock UserContentFilterStore unavailable:', e.message);
                    filterStore = null;
                }
            }

            if (filterStore) {
                try {
                    const ruleJson = JSON.stringify(filterRules);
                    const ruleBytes = new GLib.Bytes(new TextEncoder().encode(ruleJson));
                    const ucmRef = new WeakRef ? new WeakRef(ucm) : null;
                    filterStore.save("adblock-v2", ruleBytes, null, (s, res) => {
                        try {
                            if (!s || !res) return;
                            let filter = null;
                            try {
                                filter = s.save_finish(res);
                            } catch (saveErr) {
                                console.warn('[launcher] Adblock filter save_finish failed:', saveErr.message);
                                filter = null;
                            }
                            if (!filter) return;
                            const targetUcm = ucmRef ? ucmRef.deref() : ucm;
                            if (targetUcm && typeof targetUcm.add_filter === 'function') {
                                try {
                                    targetUcm.add_filter(filter);
                                } catch (addErr) {
                                    console.warn('[launcher] Adblock add_filter failed:', addErr.message);
                                }
                            }
                        } catch (outerErr) {
                            console.warn('[launcher] Adblock filter callback error:', outerErr.message);
                        }
                    });
                } catch (e) {
                    console.warn('[launcher] Adblock filterStore.save error:', e.message);
                }
            }

            try {
                const cosmeticCSS = [
                    ".adsbygoogle, .ad-container, .ad-banner, .advertisement,",
                    "[id^=\\"google_ads_iframe\\"], .taboola-placeholder, .outbrain_widget,",
                    ".criteo-ad, .ad-slot, .sponsored-post, .ytp-ad-overlay-container,",
                    ".ytp-ad-message-container, .ytp-ad-preview-container,",
                    "ytd-ad-slot-renderer, ytd-in-feed-ad-layout-renderer,",
                    "ytd-banner-promo-renderer, ytd-statement-banner-renderer,",
                    "ytd-action-companion-ad-renderer, #player-ads {",
                    "  display: none !important;",
                    "  visibility: hidden !important;",
                    "  height: 0 !important;",
                    "  max-height: 0 !important;",
                    "  opacity: 0 !important;",
                    "  pointer-events: none !important;",
                    "}"
                ].join("\\n");
                const styleSheet = new WebKit.UserStyleSheet(
                    cosmeticCSS,
                    WebKit.UserContentInjectedFrames.ALL_FRAMES,
                    WebKit.UserStyleLevel.USER,
                    null, null
                );
                try { ucm.add_style_sheet(styleSheet); } catch (e) {
                    console.warn('[launcher] Adblock add_style_sheet failed:', e.message);
                }
            } catch (e) {
                console.warn('[launcher] Adblock UserStyleSheet create failed:', e.message);
            }

            try {
                const ytAdScript = `(function() {
                    'use strict';
                    try {
                        var _lastRun = 0;
                        function _safeRemove(el) {
                            try { if (el && el.parentNode) el.parentNode.removeChild(el); } catch(_) {}
                        }
                        function _safeClick(btn) {
                            try { if (btn && typeof btn.click === 'function') btn.click(); } catch(_) {}
                        }
                        function cleanYouTubeAds() {
                            try {
                                var hn = (window.location && window.location.hostname) ? window.location.hostname : '';
                                if (hn.indexOf('youtube.com') === -1 && hn.indexOf('youtu.be') === -1) return;
                                var now = Date.now();
                                if (now - _lastRun < 250) return;
                                _lastRun = now;
                                var v = document.querySelector('video');
                                var ad = document.querySelector('.ad-showing, .ad-interrupting, .ytp-ad-player-overlay');
                                if (ad && v && !isNaN(v.duration) && isFinite(v.duration)) {
                                    try { v.muted = true; } catch(_) {}
                                    try { if (v.playbackRate < 16) v.playbackRate = 16; } catch(_) {}
                                    try { if (v.duration > 0) v.currentTime = v.duration; } catch(_) {}
                                }
                                var skips = [
                                    '.ytp-ad-skip-button', '.ytp-ad-skip-button-modern',
                                    '.ytp-skip-ad-button', '.ytp-ad-skip-button-slot',
                                    'button.ytp-ad-skip-button-modern', '.ytp-ad-overlay-close-button'
                                ];
                                for (var i = 0; i < skips.length; i++) {
                                    var b = document.querySelector(skips[i]);
                                    if (b) _safeClick(b);
                                }
                                var sel = [
                                    '.ytp-ad-overlay-container', '.ytp-ad-message-container',
                                    'ytd-ad-slot-renderer', 'ytd-banner-promo-renderer',
                                    'ytd-in-feed-ad-layout-renderer', 'ytd-statement-banner-renderer',
                                    '#player-ads'
                                ].join(',');
                                var nodes = document.querySelectorAll(sel);
                                for (var j = 0; j < nodes.length; j++) _safeRemove(nodes[j]);
                            } catch (_) {}
                        }
                        var _observerInstalled = false;
                        function _installObserver() {
                            if (_observerInstalled) return;
                            try {
                                var tgt = document.body || document.documentElement;
                                if (!tgt) { setTimeout(_installObserver, 200); return; }
                                if (typeof MutationObserver !== 'undefined') {
                                    var obs = new MutationObserver(function() { cleanYouTubeAds(); });
                                    obs.observe(tgt, { childList: true, subtree: true });
                                    _observerInstalled = true;
                                } else {
                                    setInterval(cleanYouTubeAds, 1500);
                                    _observerInstalled = true;
                                }
                                cleanYouTubeAds();
                            } catch (_) {
                                setTimeout(_installObserver, 500);
                            }
                        }
                        if (document.readyState === 'loading') {
                            document.addEventListener('DOMContentLoaded', _installObserver);
                        } else {
                            _installObserver();
                        }
                    } catch (_) {}
                })();`;
                const ytUserScript = new WebKit.UserScript(
                    ytAdScript,
                    WebKit.UserContentInjectedFrames.ALL_FRAMES,
                    WebKit.UserScriptInjectionTime.START,
                    null, null
                );
                try { ucm.add_script(ytUserScript); } catch (e) {
                    console.warn('[launcher] Adblock YouTube script add failed:', e.message);
                }
            } catch (e) {
                console.warn('[launcher] Adblock YouTube script create failed:', e.message);
            }

            try {
                const codecScript = `(function() {
                    'use strict';
                    try {
                        function _isBlocked(t) {
                            if (!t || typeof t !== 'string') return false;
                            var l = t.toLowerCase();
                            return (l.indexOf('vp8') !== -1 || l.indexOf('vp9') !== -1 ||
                                    l.indexOf('vp09') !== -1 || l.indexOf('av01') !== -1 ||
                                    l.indexOf('av1') !== -1 || l.indexOf('webm') !== -1);
                        }
                        try {
                            if (window.MediaSource && typeof window.MediaSource.isTypeSupported === 'function') {
                                var _orig = window.MediaSource.isTypeSupported.bind(window.MediaSource);
                                window.MediaSource.isTypeSupported = function(t) {
                                    try { if (_isBlocked(t)) return false; } catch(_) {}
                                    return _orig(t);
                                };
                            }
                        } catch (_) {}
                        try {
                            var hp = window.HTMLMediaElement && window.HTMLMediaElement.prototype;
                            if (hp && typeof hp.canPlayType === 'function') {
                                var _orig2 = hp.canPlayType;
                                hp.canPlayType = function(t) {
                                    try { if (_isBlocked(t)) return ''; } catch(_) {}
                                    return _orig2.call(this, t);
                                };
                            }
                        } catch (_) {}
                    } catch (_) {}
                })();`;
                const codecUserScript = new WebKit.UserScript(
                    codecScript,
                    WebKit.UserContentInjectedFrames.ALL_FRAMES,
                    WebKit.UserScriptInjectionTime.START,
                    null, null
                );
                try { ucm.add_script(codecUserScript); } catch (e) {
                    console.warn('[launcher] Adblock codec script add failed:', e.message);
                }
            } catch (e) {
                console.warn('[launcher] Adblock codec script create failed:', e.message);
            }

            return true;
        } catch (e) {
            console.warn('[launcher] _setupAdBlocker top-level error:', e.message);
            return false;
        }
    }

    _attachWebViewCrashHandlers(webView, label) {
        if (!webView) return;
        try {
            if (typeof webView.connect === 'function') {
                try {
                    webView.connect('web-process-crashed', (wv) => {
                        console.warn('[launcher] WebProcess crashed:', label || 'unknown');
                        try { wv.stop_loading(); } catch (_) {}
                        return true;
                    });
                } catch (_) {}
                try {
                    webView.connect('web-process-terminated', (wv, reason) => {
                        console.warn('[launcher] WebProcess terminated:', label || 'unknown', 'reason:', reason);
                        return true;
                    });
                } catch (_) {}
            }
        } catch (e) {
            console.warn('[launcher] attach crash handlers failed:', e.message);
        }
    }
'''

with open('app-launcher.js', 'r') as f:
    lines = f.readlines()

# Find _setupAdBlocker (17319-17532 1-indexed => 17318-17531 0-indexed)
start = None
end = None
depth = 0
in_method = False
for i, line in enumerate(lines):
    if '_setupAdBlocker(ucm, cacheDir)' in line and not in_method:
        start = i
        in_method = True
        depth += line.count('{') - line.count('}')
        continue
    if in_method:
        depth += line.count('{') - line.count('}')
        if depth == 0:
            end = i
            break

print(f'Replacing lines {start+1}-{end+1}...')
new_lines = lines[:start] + [NEW_SETUP_ADBLOCKER.rstrip() + '\n'] + lines[end+1:]

with open('app-launcher.js', 'w') as f:
    f.writelines(new_lines)

print(f'Done. File now has {len(new_lines)} lines.')
