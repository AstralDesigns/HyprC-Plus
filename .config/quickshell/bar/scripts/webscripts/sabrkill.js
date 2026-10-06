// sabrkill.js — YouTube stall RECOVERY watchdog (v10).
//
// Context: SABR cache-wall deaths in this QtWebEngine build were never
// fully preventable (every response-sanitizing lever — page hooks, MITM
// strips, the inline setter trap — is now attestation- or
// rollout-fatal; see memory/header of v8 revert). v9 = untouched
// responses + a frozen-playhead recovery. FIELD RESULT (2026-10-06):
// long videos play across the old wall points fine; what remains are
// STALL STATES, and v9's detector missed them because it only counted
// frozen time while the element was playing. Observed stalls that v9
// watched go by without acting:
//   * post-ad paused stall: ad auto-skips, content stays PAUSED at the
//     freeze point (adblock.js's play() nudge can lose the race),
//   * latched offline UI: SPA shows "You're offline" while the network
//     is demonstrably alive (proxy tape flowing).
// v10 detects any non-advancing playhead regardless of paused state,
// distinguishes USER pause (state 2, no error UI -> hands off), and
// escalates a ladder: play() -> loadVideoById resume (same video, same
// position; the manual re-click, mechanized) -> document reload /
// Retry-click for the offline latch. Pure state observation + public
// API; edits no request, no response.
(function () {
    "use strict";
    try {
        if (!/(^|\.)(youtube\.com|youtu\.be)$/.test(location.hostname)) return;

        var lastT = -1, frozen = 0, playTries = 0;
        var rec = {}, lastRec = 0, reloads = {}, lastReload = 0;

        setInterval(function () {
            try {
                if (!/^\/watch/.test(location.pathname)) return;
                var v = document.querySelector("video");
                if (!v || v.ended) { frozen = 0; return; }

                if (v.currentTime !== lastT) {         // progressing
                    frozen = 0; playTries = 0;
                    lastT = v.currentTime;
                    return;
                }
                frozen++;
                if (frozen < 6) return;                // ~12s stuck
                lastT = -1;                            // re-arm sampling

                var p = document.querySelector("#movie_player");
                if (!p) return;
                var txt = p.innerText || "";
                var offline = /offline|check your connection/i.test(txt);
                var errored = /something went wrong|an error occurred|playback is on another/i.test(txt);

                // --- offline latch: real network is fine; bounce the doc.
                if (offline) {
                    var now = Date.now();
                    var rid = (/[?&]v=([\w-]{11})/.exec(location.search) || [])[1] || "?";
                    if (now - lastReload > 60000 && (reloads[rid] || 0) < 3) {
                        lastReload = now; reloads[rid] = (reloads[rid] || 0) + 1;
                        var btns = p.querySelectorAll("button");
                        for (var i = 0; i < btns.length; i++)
                            if (/retry/i.test(btns[i].textContent || "")) {
                                btns[i].click(); return;
                            }
                        location.reload();
                    }
                    return;
                }

                // --- user pause (no error UI): respect it.
                var st = -9;
                try { st = p.getPlayerState ? p.getPlayerState() : -9; } catch (e) {}
                if (v.paused && st === 2 && !errored) return;

                // --- frozen media / error screen: ladder.
                if (!p.loadVideoById || !p.getPlayerResponse) return;
                var pr = p.getPlayerResponse();
                var id = pr && pr.videoDetails && pr.videoDetails.videoId;
                if (!id) return;
                var m = /[?&]v=([\w-]{11})/.exec(location.search);
                if (!m || m[1] !== id) return;         // mid-transition

                // gentle first: a plain play() fixes most ad-resume races
                if (v.paused && playTries < 3 && !errored) {
                    playTries++;
                    try { var q = v.play(); if (q && q.catch) q.catch(function () {}); } catch (e) {}
                    return;
                }

                var now2 = Date.now();
                if (now2 - lastRec < 30000) return;    // global settle
                if ((rec[id] || 0) >= 6) return;       // per-video brake
                rec[id] = (rec[id] || 0) + 1;
                lastRec = now2; playTries = 0; frozen = 0;
                p.loadVideoById({ videoId: id,
                                  startTimeSeconds: Math.max(0, v.currentTime - 0.5) });
            } catch (e) {}
        }, 2000);
    } catch (e) {}
})();
