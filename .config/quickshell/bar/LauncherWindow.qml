import QtQuick
import QtQuick.Layouts
import QtCore
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtWebEngine
import QtQuick.Effects

// ═══════════════════════════════════════════════════════════════════════════
//  LauncherWindow.qml — qs port of GJS hyprcandydock/app-launcher.js.
//
//  Full-screen transparent overlay surface (ns hyprcandy-launcher, Overlay
//  layer, exclusive keyboard) with the launcher card anchored to the dock
//  edge — SmallLauncher dismiss pattern + GJS geometry contract:
//    margin = live dock thickness + Config.dockMargin + 3 (GAP_FROM_DOCK)
//    size   = Config.launcherFrame{Width,Height}(+Vert)
//  Tabs: launcher (Apps|Groups sub-tabs), clipboard, icons, web search,
//  agent.  Web/agent pages land with their own phases; the frame + apps +
//  groups + clipboard are this file's scope.
//
//  Context menus are in-card overlays (not popovers) — the surface already
//  owns keyboard focus, so no extra layer windows and no focus-stealing
//  grab chains (the GJS popover-grace hacks don't port).
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: launcherScope

    Variants {
        id: launcherVariants
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property var modelData
            screen: modelData

            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(win.screen)
            property bool monitorIsFocused: (Hyprland.focusedMonitor?.id === monitor?.id)

            visible: HCCLauncherState.visible && monitorIsFocused
            color: "transparent"

            WlrLayershell.namespace: "hyprcandy-launcher"
            WlrLayershell.layer: WlrLayer.Overlay
            // OnDemand (not Exclusive): QtWebEngine renders HTML select dropdowns as
            // separate transient popup surfaces that must grab keyboard focus to stay open.
            // Exclusive focus is held here, so the compositor denies the popup and it
            // dismisses instantly. OnDemand lets those popups take focus.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            anchors { top: true; bottom: true; left: true; right: true }

            // ── Geometry (GJS _setupLayerShell parity, same-process) ──────
            readonly property bool isVert: DockState.isVertical
            readonly property real dockThick: (Config.dockIconSize + 2 * Config.dockPadding)
                                              + 2 * Config.dockInnerPadding
            readonly property real edgeMargin: dockThick + Config.dockMargin + 3
            readonly property real cardW: isVert ? Config.launcherFrameWidthVert
                                                 : Config.launcherFrameWidth
            readonly property real cardH: isVert ? Config.launcherFrameHeightVert
                                                 : Config.launcherFrameHeight

            // ── Shared style shorthands ───────────────────────────────────
            readonly property color wColor2: Qt.color(Theme.wallustColors?.color2
                                                      ?? Theme.cSecondary)
            readonly property color wColor3: Qt.color(Theme.wallustColors?.color3
                                                      ?? Theme.cErr)
            readonly property real ip: Config.launcherInnerPadding

            // ── Tab + page state ──────────────────────────────────────────
            property string tab: HCCLauncherState.activeTab
            readonly property bool immersiveTab: tab === "websearch" || tab === "agent"
            property string subTab: "apps"          // launcher tab
            property string query: ""
            readonly property string q: query.toLowerCase().trim()

            property bool favCollapsed: true
            property bool selectMode: false
            property var selectedIds: []
            // "Add to:" popup state (selection mode) — adds the selected apps to
            // an existing group / Favorites instead of creating a new group.
            property bool _addToOpen: false
            property var _addToGroups: []
            property var expandedGroups: ({})
            readonly property bool _anyGroupExpanded:
                Object.values(expandedGroups).some(v => v === true)
            // Collapsed group tiles are uniform squares: a 2×2 preview-icon
            // cluster (groupPrevIcon each) plus the name row, inset from the
            // rounded border by even padding on all sides.
            readonly property int groupPrevIcon: 32      // ~1.33× the old 24px preview
            readonly property int groupCardSize: 116     // square collapsed group tile
            property int focusIdx: -1               // keyboard grid selection

            // Context-menu / dialog state
            property var _menuRows: []
            property var _menuRec: null
            property string _menuGroupCtx: ""
            property real _menuX: 0
            property real _menuY: 0
            property bool _menuOpen: false
            property string _wsSubKey: ""           // row key owning the ws panel
            property var _dlg: ({ open: false })    // group-name dialog

            // ── Icons tab state (glyphData.json) ────────────────────
            property string iconMode: "emoji"       // emoji | nerd
            property int emojiGroup: 0
            property int nerdCat: 0
            property bool glyphReady: false
            property var emojiAll: []
            property var emojiGroups: []
            property var nerdCats: []
            property string copiedChar: ""
            property string hoveredIconName: ""   // in-card hover readout

            // ── Web-Search tab state (SearXNG list mode) ───────────
            property var webResults: []
            property string webStatus: "idle"     // idle|loading|ready|offline|noresults
            property string webStatusTitle: ""
            property string webStatusBody: ""
            property string webLastQuery: ""
            property bool searxDockerAutoStarted: false
            property bool searxDockerStarting: false

            // ── Web-Search tab: persistent embedded SearXNG webview ──
            // The tab is always an in-page WebEngineView pointed at SearXNG (which
            // renders its own search UI), like a browser. webProfile is on-the-record
            // (default) so cookies + localStorage persist to disk and logins survive
            // across launches. webShowError drives the SearXNG-down overlay.
            property bool webShowError: false
            property bool webShowBookmarks: false
            property bool webShowCredentials: false
            // Search-box text for the bookmarks / credentials dropdowns (they
            // can outgrow the scroll height, so both are filterable).
            property string webBookmarkQuery: ""
            property string webCredentialQuery: ""
            // Origins (domains) that currently hold stored cookies, accumulated
            // from the profile's cookie store; feeds the clear-credentials menu.
            property var webCredOrigins: []
            // QtWebEngine will NOT mkdir -p a nested persistentStoragePath/cache
            // path: if the directory is absent when the (isFinal, creation-time)
            // profile initialises, on-the-record storage silently no-ops and
            // cookies/localStorage never reach disk -- which is exactly why site
            // logins were not surviving across launches. Create both roots up
            // front so the profile below actually persists to them.
            Process {
                id: webStorageInitProc
                command: ["mkdir", "-p",
                          Config.home + "/.local/share/hyprcandy/webengine",
                          Config.home + "/.local/share/hyprcandy/webengine/Default",
                          Config.home + "/.cache/hyprcandy/webengine"]
                Component.onCompleted: running = true
            }
            // Persistent (on-the-record) profile via WebEngineProfilePrototype.
            // Qt 6.9+ deprecated the inline `WebEngineProfile {}` element: it now
            // silently stays OFF-THE-RECORD (ignores storageName/cachePath, so the
            // Chromium cookie DB is never written) -- the exact "login dropped on
            // restart / empty credentials menu" symptom. The prototype's instance()
            // DOES persist, but calling it as a property BINDING during component
            // init SIGSEGVs this patched noctalia-qs build; resolving it ONCE in
            // win.Component.onCompleted (post-init) is crash-free (validated in an
            // isolated probe: otr=false, Cookies DB written + survives a restart).
            // profile is isFinal (creation-time only), so every WebEngineView is
            // created only AFTER win.webProfile is set (agentView via a gated
            // Loader, tab views via _ensureView). All views share this ONE profile
            // -- a second in-process WebEngineProfile aborts this build.
            WebEngineProfilePrototype {
                id: webProfileProto
                storageName: "hyprcandy-launcher"
                persistentStoragePath: Config.home + "/.local/share/hyprcandy/webengine"
                cachePath: Config.home + "/.cache/hyprcandy/webengine"
                httpCacheType: WebEngineProfile.DiskHttpCache
                persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
                // Bound the on-disk HTTP cache so it cannot grow without limit;
                // Qt prunes toward this ceiling automatically. 128 MiB is ample
                // for SearXNG + a handful of sites and keeps the cache small.
                httpCacheMaximumSize: 128 * 1024 * 1024
            }
            property WebEngineProfile webProfile: null

            // Build the single shared WebEngine profile on FIRST use, never
            // destroy it. instance() must run after component init (calling it
            // during init SIGSEGVs) and only once, so every entry point about to
            // create a WebEngineView calls this first. A launcher-only session
            // that never opens websearch/agent therefore never boots Chromium
            // -- no browser/GPU/network threads, no renderer -- the single
            // largest thread + memory saving available on this design.
            function _ensureWebProfile() {
                if (!win.webProfile)
                    win.webProfile = webProfileProto.instance()
                return win.webProfile
            }

            // Reclaim WebEngine memory the ways THIS Qt build exposes to QML.
            // There is no QML cookie/website-data wipe (those are C++-only) and
            // no JS GC, but a live RENDERER can be reaped safely by destroying
            // its WebEngineView -- the same create/destroy path the websearch
            // tab views already use on open/close without crashing. So the OFF
            // paths now free the big per-page heaps directly: web OFF destroys
            // the tab views, agent OFF deactivates agentViewLoader (view ->
            // destroyed). The shared browser core (zygote/utility/GPU) still
            // can't be torn down from QML once Chromium boots -- it only exists
            // because a tab used it, and the lazy profile keeps a never-used
            // session paying zero. Disk cache (re-downloadable, zero UX impact)
            // is the remaining safe lever:
            function _webClearCache() {
                if (win.webProfile)
                    win.webProfile.clearHttpCache()
            }

            // ── hcproxy lifecycle (opt-in MITM proxy, tied to websearch) ────
            // mitmdump + python-adblock idles at ~180MB, so it must NOT run
            // while the websearch tab is OFF. The agent tab is loopback-only and
            // never uses it. Only managed when the user opted in -- detected by
            // the --proxy-server flag baked into QTWEBENGINE_CHROMIUM_FLAGS by
            // `hcproxy enable`; otherwise every call is a no-op, so dotfile
            // users who never enabled the proxy are completely untouched.
            readonly property bool proxyOptIn:
                String(Quickshell.env("QTWEBENGINE_CHROMIUM_FLAGS") || "").indexOf("proxy-server") > -1
            property string _proxyWanted: ""   // "" unknown | "on" | "off" (last commanded)

            Process {
                id: hcproxyStartProc
                command: ["systemctl", "--user", "start", "hcproxy"]
            }
            Process {
                id: hcproxyStopProc
                command: ["systemctl", "--user", "stop", "hcproxy"]
            }
            // Bring the service up/down to match the websearch enabled state.
            // User-scoped systemctl (no sudo); idempotent and only fires on a
            // desired-state change. Cold start caveat: after an OFF->ON flip the
            // adblock engine takes a few seconds to build, so the very first
            // page load may need a reload.
            function _syncProxy(want) {
                if (!win.proxyOptIn) return
                const next = want ? "on" : "off"
                if (win._proxyWanted === next) return
                win._proxyWanted = next
                if (want) hcproxyStartProc.running = true
                else hcproxyStopProc.running = true
            }

            // activeView re-pins (tab switch/create/close) are not observable
            // through a normal binding on the pooled per-view signals, so
            // re-emit the shared chrome properties whenever the handle moves —
            // toolbar enabled-state, address text, progress, overlay, header.
            Connections {
                target: win.activeView
                function onLoadingChanged() { win.webRev++ }
                function onTitleChanged() { win.webRev++ }
                function onUrlChanged() { win.webRev++ }
                ignoreUnknownSignals: true
            }

            // ── Web-Search startup policy (SearXNG container ON/OFF) ──────
            // Mirrors the workspace (agent) toggle: a persisted ON/OFF policy
            // decides whether the SearXNG docker container is warmed when a
            // launcher session starts and whether the websearch tab shows its
            // live view. ON  → container runs from startup, the shared view is
            // live. OFF → stop the container, forget the open tabs and blank the
            // view (the WebView object itself is never destroyed — a fresh one
            // would be a second WebContentsAdapter and crash the shell).
            readonly property string webStatePath: Config.home
                + "/.local/share/hyprcandy/websearch-startup-state.json"
            property bool webEnabled: true
            property bool webAdBlockEnabled: true
            // Ad/tracker blocker source, loaded from scripts/webscripts/adblock.js
            // so the blocklist is user-editable without touching QML. Empty until
            // the FileView reads it; views made before then get no blocker until
            // re-injected on the next tab open or a shield toggle.
            property string webAdBlockScript: ""
            property string webSabrKillScript: ""
            property bool _webResolved: false
            // The launcher window is now kept loaded (hidden) so the shared
            // WebEngineView survives hide/show. Defer backend warm-up until the
            // window is first shown — otherwise shell startup would spin up the
            // SearXNG container / uvicorn runtime while the launcher is closed.
            property bool _everVisible: false

            // ── Collapsible web header (tab strip + nav toolbar) ─────────
            // The two chrome rows collapse to a thin rounded hotspot so sites get
            // maximum render space; hovering the hotspot (or double-clicking it)
            // expands them, and the chevron-up glyph folds them back explicitly.
            // (No auto-collapse: the native view swallows pointer-exit events.)
            property bool webHeaderHover: false
            property bool webHeaderPinned: false
            readonly property bool webHeaderShown: win.tab === "websearch" && win.webEnabled
                                                     && (win.webHeaderHover || win.webHeaderPinned)

            FileView {
                id: webStateFile
                path: win.webStatePath
                watchChanges: false
                onLoaded: {
                    win.webEnabled = win.readWebStartupState()
                    win.webAdBlockEnabled = win.readAdBlockState()
                    win._webResolved = true
                    // The async state read can land AFTER views were built (and
                    // after adBlockScriptFile.onLoaded re-injected with the
                    // default ON) -- re-apply so the persisted choice always
                    // wins, otherwise a shield-OFF silently keeps the script.
                    // The reload is MANDATORY: DocumentCreation scripts are
                    // snapshotted at page load, so a restored tab keeps the old
                    // injection until it re-navigates (proven: hcdebug beacons
                    // fired 30s into a session with adblock persisted OFF). The
                    // signature guard inside _applyUserScripts keeps this to at
                    // most ONE reload when the state genuinely differs.
                    for (var k in win._views) {
                        var v = win._views[k]
                        if (v && win._applyUserScripts(v)) v.reload()
                    }
                    // Only warm once the policy is resolved (2a): a persisted
                    // OFF must never be raced by a docker warm-up.
                    if (win.webEnabled && win.visible && win._webResolved) win.webEnsureUp()
                    // Persisted OFF: stop the login-autostarted hcproxy so its
                    // ~180MB is freed for the whole session until websearch is
                    // turned back on (no-op unless the proxy flag is present).
                    else if (!win.webEnabled) win._syncProxy(false)
                }
                Component.onCompleted: reload()
            }

            // Load the ad-block user script (read once at startup; watchChanges
            // false). A late load re-injects into any tabs already open.
            FileView {
                id: adBlockScriptFile
                path: Config.barDir + "/scripts/webscripts/adblock.js"
                watchChanges: false
                onLoaded: {
                    // NOTE: FileView.exists is undefined in this Quickshell build, so
                    // it must NOT gate the read -- text() is the content (empty when
                    // unreadable) and onLoaded only fires on a successful load.
                    win.webAdBlockScript = adBlockScriptFile.text() || ""
                    // Re-inject into any views built before this async load finished
                    // (restored tabs) and reload them -- setting the collection alone
                    // does not re-run DocumentCreation on an already-loaded page.
                    // (Signature guard: no reload when the view already runs this src.)
                    for (var k in win._views) {
                        var v = win._views[k]
                        if (v && win._applyUserScripts(v)) v.reload()
                    }
                }
                Component.onCompleted: reload()
            }

            // SABR kill-switch script (see scripts/webscripts/sabrkill.js):
            // ALWAYS on, independent of the ad-block shield -- it is the fix
            // for the ~12min YouTube deaths (SABR's in-band session-cache
            // deadline never reaches the player in QtWebEngine, so the 720s
            // renewal never fires).
            FileView {
                id: sabrKillScriptFile
                path: Config.barDir + "/scripts/webscripts/sabrkill.js"
                watchChanges: false
                onLoaded: {
                    win.webSabrKillScript = sabrKillScriptFile.text() || ""
                    for (var k in win._views) {
                        var v = win._views[k]
                        if (v && win._applyUserScripts(v)) v.reload()
                    }
                }
                Component.onCompleted: reload()
            }

            Process {
                id: webWriteProc
                property string _content: "{\"enabled\":true}\n"
                command: ["python3", "-c",
                          "import sys,os; d=os.path.dirname(sys.argv[1]); os.makedirs(d,exist_ok=True); "
                          + "open(sys.argv[1]+'.tmp','w').write(sys.argv[2]); "
                          + "os.replace(sys.argv[1]+'.tmp', sys.argv[1])",
                          win.webStatePath, webWriteProc._content]
            }

            function writeWebStartupState() {
                webWriteProc._content = JSON.stringify({ enabled: !!win.webEnabled, adblock: !!win.webAdBlockEnabled }) + "\n"
                webWriteProc.running = false
                webWriteProc.running = true
            }

            function readWebStartupState() {
                try {
                    const t = webStateFile.text()
                    if (!t) return true
                    const o = JSON.parse(t)
                    return (o && typeof o.enabled === "boolean") ? o.enabled : true
                } catch (e) { return true }
            }

            function readAdBlockState() {
                try {
                    const t = webStateFile.text()
                    if (!t) return true
                    const o = JSON.parse(t)
                    return (o && typeof o.adblock === "boolean") ? o.adblock : true
                } catch (e) { return true }
            }

            // The circular websearch toggle handler: flip + persist, then warm
            // (ON) or tear the container down and blank the shared view (OFF).
            function webToggleEnabled() {
                const next = !win.webEnabled
                win.webEnabled = next
                win.writeWebStartupState()
                if (next) {
                    if (win.tab !== "websearch") win.switchTab("websearch")
                    else win.webEnsureUp()
                } else {
                    // OFF: destroy every tab view (releasing renderers) and reset
                    // to a single home tab with a fresh id.
                    win._destroyAllViews()
                    win.webTabs = [{ url: win.searxBase, title: "", _id: win._nextTabId++ }]
                    win.activeWebTab = 0
                    win._setActiveView(null)
                    win._webTouch()
                    win.searxStopDocker()
                    win._webClearCache()
                    win._syncProxy(false)
                    win.webShowError = false
                    win.searxDown = false
                    win.webShowBookmarks = false
                    if (win.tab === "websearch") win.switchTab("launcher")
                }
            }

            // ── Agent tab: loopback-served React app, own session ──────────
            // Port of the GJS launcher's agent workspace: a small Python server
            // (bar/agent_loopback_server.py) serves agent-app/dist on a private
            // loopback origin (COOP/COEP headers for the WASM build), and the
            // app is hosted in a WebEngineView with its OWN profile so the agent
            // session stays isolated from the SearXNG web-search webview.
            readonly property int agentPort: 17842
            readonly property string agentUrl: "http://127.0.0.1:" + agentPort + "/index.html"
            // NOTE: this QtWebEngine fork aborts ("Zygote could not fork") once a
            // second WebEngineProfile is created in-process, so the agent tab reuses
            // win.webProfile below (storage is origin-scoped, so the agent session on
            // 127.0.0.1 stays separate from the SearXNG web-search cookies anyway).
            property bool agentReady: false
            property bool agentStarting: false
            property bool agentMissing: false

            // ── Per-tab persistent view pool (imperative, tab-id keyed) ────
            // Two live WebEngineViews coexist in this patched Qt 6.11 build
            // (validated: two views alive 45s+, no SIGTRAP) PROVIDED they share
            // the ONE win.webProfile -- a second in-process WebEngineProfile is
            // still the abort trigger. Each websearch tab owns exactly ONE
            // WebEngineView, created imperatively (tabViewProto -> webViewContainer)
            // and keyed by a stable tab id. A view loads its URL ONCE and is
            // NEVER re-navigated by model churn, so creating / closing /
            // reordering / switching tabs leaves every OTHER tab's page (and its
            // in-page state) completely untouched -- only the explicit reload
            // button or the address bar navigates a page. Only the active tab's
            // view is visible; the rest stay loaded. Closing a tab destroys just
            // that tab's view (releasing its renderer). agentView (the workspace)
            // is a separate persistent view on the same profile.
            property var webTabs: [{ url: searxBase, title: "", _id: 1 }]
            property int activeWebTab: 0
            property int webRev: 0
            // The view of the ACTIVE tab (null until it exists). Chrome rows
            // bind through this handle; re-emitted via webRev when it moves.
            property var activeView: null
            // Background truth about the SearXNG container (health checks set
            // it); deliberately NOT what paints the overlay anymore (2c).
            property bool searxDown: false
            // tabId -> WebEngineView, managed imperatively (a Repeater would
            // re-navigate reused delegates when the array shifts on removal).
            property var _views: ({})
            property int _nextTabId: 2
            // Tab whose view is in HTML5 fullscreen (-1 = none): its view stays
            // inside webViewContainer and the launcher chrome folds, so the
            // media fills only the tab's web-view area (other tabs and the
            // desktop stay reachable) rather than taking over the whole window.
            property int webFullscreenTabId: -1

            // Modern Chrome UA (QtWebEngine token stripped) injected as a
            // document-creation script into every web tab so sites that gate on
            // navigator.userAgent serve the desktop app. WhatsApp Web's "needs
            // Chrome 100+" wall trips on the "QtWebEngine" marker, not the
            // version -- this Chromium already reports Chrome/140, so we only
            // drop the toolkit token. httpUserAgent is isFinal/absent from the
            // prototype and the --user-agent flag is ignored by this build, so a
            // MainWorld DocumentCreation user script is the only working lever.
            readonly property string webUserAgent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
            readonly property string webUserScriptSource: "try{var B=[{brand:'Not_A Brand',version:'8'},{brand:'Chromium',version:'140'},{brand:'Google Chrome',version:'140'}];var U=\"" + webUserAgent + "\";var A=U.replace(/^Mozilla\\//,'');Object.defineProperty(navigator,'userAgent',{configurable:true,get:function(){return U;}});Object.defineProperty(navigator,'appVersion',{configurable:true,get:function(){return A;}});Object.defineProperty(navigator,'userAgentData',{configurable:true,get:function(){return {brands:B,mobile:false,platform:'Linux',getHighEntropyValues:function(){return Promise.resolve({brands:B,mobile:false,platform:'Linux',platformVersion:'6.5.0',architecture:'x86',bitness:'64',model:'',uaFullVersion:'140.0.0.0',fullVersionList:B});}};}});}catch(e){}"

            function _webTouch() { win.webTabs = win.webTabs.slice(); win.webRev++ }
            function _webTab() { return win.webTabs[win.activeWebTab] || win.webTabs[0] }
            function _webTabAt(i) { return win.webTabs[i] || null }
            function _activeTabObj() { return win.webTabs[win.activeWebTab] || null }
            function _tabById(id) {
                for (var i = 0; i < win.webTabs.length; i++)
                    if (win.webTabs[i]._id === id) return win.webTabs[i]
                return null
            }
            function _setActiveView(v) { win.activeView = v; win.webRev++ }
            function _urlBarText() {
                return (win.activeView && win.activeView.url)
                       ? win.activeView.url.toString() : win.searxBase
            }
            // Compact, browser-style display form of the address bar (scheme +
            // trailing slash stripped) shown only while the field is UNFOCUSED.
            // Focusing swaps back to the full URL (_urlBarText) so editing and
            // any selection/copy always operate on the complete URL.
            function _urlDisplayText() {
                const u = win._urlBarText()
                if (!u || u === "about:blank") return ""
                return u.replace(/^https?:\/\//, "").replace(/\/$/, "")
            }

            // Compose a view's user scripts: the Chrome-UA spoof always, plus the
            // ad/tracker blocker when enabled and its source is loaded. Both run at
            // DocumentCreation in the MainWorld so they beat the page's own scripts.
            function _applyUserScripts(v) {
                if (!v) return false
                // This patched build's non-standard userScripts.collection only
                // reliably injects a SINGLE entry: a second (11KB) source was silently
                // dropped -- the blocker never ran (no HCAB-RUN, doubleclick XHRs
                // reached CORS) while the first UA script did. So merge the UA spoof
                // and the ad/tracker blocker into ONE DocumentCreation source.
                // adblock.js is a self-contained IIFE, so concatenation is safe.
                var src = win.webUserScriptSource
                // SABR kill is always-on (merge first: adblock.js wraps fetch
                // after it, so both sanitizers chain on the same responses).
                if (win.webSabrKillScript && win.webSabrKillScript.length)
                    src += "\n;" + win.webSabrKillScript
                if (win.webAdBlockEnabled && win.webAdBlockScript && win.webAdBlockScript.length)
                    src += "\n;" + win.webAdBlockScript
                // Signature guard: the three startup FileViews (state, adblock,
                // sabrkill) each re-apply to restored views; without this check
                // every restored tab took 3-4 reloads in seconds, and YouTube
                // answered the pile-up with a playability ERROR on the restored
                // video ("Something went wrong", unlocalized $BEGIN_LINK
                // template) that survived manual reload but not a video change.
                // Only a REAL content change (persisted shield OFF, toggle) may
                // reload: DocumentCreation scripts are snapshotted at page load.
                if (v._hcAppliedSrc === src) return false
                v._hcAppliedSrc = src
                v.userScripts.collection = [{
                    name: "hyprcandy-inject", sourceCode: src,
                    injectionPoint: 2, worldId: 0, runsOnSubFrames: true
                }]
                return true
            }

            // Shield toggle: flip + persist, then re-inject into every live tab and
            // reload so the change takes effect immediately.
            function webToggleAdBlock() {
                win.webAdBlockEnabled = !win.webAdBlockEnabled
                win.writeWebStartupState()
                for (var k in win._views) {
                    var v = win._views[k]
                    if (v && win._applyUserScripts(v)) v.reload()
                }
                win.webRev++
            }

            // Create the tab's view once (loading its stored URL); never here.
            function _ensureView(tab) {
                if (!tab) return null
                // Never create a view before the shared profile is resolved (a view
                // built with a null profile would fall back to a SECOND in-process
                // profile and abort this build). onCompleted sets it first, so this
                // is just a defensive guard for the very earliest restore path.
                if (!win.webProfile) return null
                var id = tab._id
                var v = win._views[id]
                if (!v) {
                    if (!webViewContainer || !tabViewProto) return null
                    v = tabViewProto.createObject(webViewContainer, { tabId: id })
                    if (!v) return null
                    win._views[id] = v
                    v.url = (tab.url && tab.url.length) ? tab.url : win.searxBase
                }
                return v
            }
            function _destroyView(id) {
                var v = win._views[id]
                if (!v) return
                if (win.webFullscreenTabId === id) win.webFullscreenTabId = -1
                v.visible = false
                v.destroy()
                delete win._views[id]
            }
            function _destroyAllViews() {
                for (var k in win._views) { if (win._views[k]) win._views[k].destroy() }
                win._views = ({})
                win.webFullscreenTabId = -1
            }
            function _syncViewVisibility() {
                var t = win._activeTabObj()
                var activeId = t ? t._id : -1
                for (var i = 0; i < win.webTabs.length; i++) {
                    var v = win._views[win.webTabs[i]._id]
                    if (v) v.visible = (win.webTabs[i]._id === activeId
                                        && win.tab === "websearch")
                }
                var av = activeId >= 0 ? (win._views[activeId] || null) : null
                if (av !== win.activeView) win._setActiveView(av)
            }
            function _syncActiveView() { Qt.callLater(function () { win._syncViewVisibility() }) }

            // ── Per-view signal handlers (routed by the view's stable tabId) ──
            function _onViewLoad(id, loadRequest) {
                const dest = String(loadRequest.url ? loadRequest.url.toString() : "")
                const t = win._tabById(id)
                if (t && dest && dest !== "about:blank") t.url = dest
                if (win._activeTabObj() && win._activeTabObj()._id === id) {
                    const err = (loadRequest.errorString !== "" && loadRequest.error)
                    if (err && dest.indexOf(win.searxBase) === 0) win.webShowError = true
                    else if (dest.indexOf(win.searxBase) !== 0) win.webShowError = false
                }
                win.webRev++
            }
            function _onViewTitle(id, title) {
                const t = win._tabById(id); if (t) t.title = title; win.webRev++
            }
            function _onViewUrl(id, url) {
                const t = win._tabById(id); if (t && url) t.url = url.toString(); win.webRev++
            }
            // HTML5 fullscreen (Qt6 API: onFullScreenRequested, not the
            // non-existent featureRequested): when a page (e.g. a YouTube
            // player) requests it, accept but keep the view inside
            // webViewContainer -- its anchors.fill:parent already covers the
            // web-search area, and folding the chrome (webFullscreenTabId)
            // lets the media expand to fill just that area. This is the
            // deliberate "contained fullscreen" quirk: the video grows into
            // the tab's web view while the tab pills, the rest of the launcher
            // and the desktop behind it all remain interactive. No reparenting.
            function _onViewFullScreen(id, request) {
                const v = win._views[id]
                if (!v) { request.reject(); return }
                request.accept()
                win.webFullscreenTabId = request.toggleOn ? id : -1
                win.webRev++
            }

            // ── Media stall watchdog ─────────────────────────────────────────
            // When the launcher hides, the window unmaps and the WebEngine media
            // pipeline can hard-stall: the player still reports "playing" but
            // currentTime freezes and the renderer stops issuing ANY requests
            // (proxy logs go silent mid-buffer; relaunch shows a live UI stuck on
            // the spinner — only a manual reload recovered it). Chromium's
            // backgrounding flags reduce but do not eliminate this. So while the
            // websearch tab is on screen we poll the active view's <video>:
            // frozen-but-not-paused -> nudge play(), persisting freeze (>~20s) ->
            // one automatic reload. A user pause (paused=true) resets the watch.
            property real _wdLastT: -1
            property int  _wdTicks: 0
            property int  _wdOut: 0
            property int  _wdNoView: 0
            property real _wdReloadAt: 0
            property int  _wdReloads: 0
            property bool _wdGiveUp: false
            Process {
                id: ytStallLogProc
                property string _line: ""
                command: ["python3", "-c",
                          "import sys,os; p=os.path.expanduser("
                          + "'~/.local/share/hyprcandy/logs/yt-stall.log'); "
                          + "os.makedirs(os.path.dirname(p),exist_ok=True); "
                          + "open(p,'a').write(sys.argv[1]+chr(10))",
                          ytStallLogProc._line]
            }
            Timer {
                id: mediaStallWatchdog
                interval: 4000
                repeat: true
                // PARKED (running:false): this build never resolves the runJavaScript
                // promise (zero probe payloads in yt-stall.log across every run), so the
                // unanswered-probe ladder reloads HEALTHY pages seconds into playback --
                // the opposite of seamless. Recovery redesign must use the MPRIS channel
                // (playerctl position, browser-process side); prevention is the real fix.
                running: false
                // Lifecycle breadcrumbs for the (parked) watchdog; only fire if it
                // is ever un-parked via the MPRIS-channel redesign.
                function wdLog(tag) {
                    ytStallLogProc._line = JSON.stringify(
                        { at: Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss"),
                          wd: tag, tab: win.tab, vis: win.visible })
                    ytStallLogProc.running = false
                    ytStallLogProc.running = true
                }
                onTriggered: {
                    const t0 = win.webTabs[win.activeWebTab]
                    const v = win.activeView ?? (t0 ? win._views[t0._id] : null)
                    if (!v) {
                        win._wdLastT = -1; win._wdTicks = 0; win._wdOut = 0
                        win._wdNoView++
                        if (win._wdNoView === 5) mediaStallWatchdog.wdLog("no-activeView")
                        return
                    }
                    win._wdNoView = 0
                    if (win._wdGiveUp) return
                    if (v.loading || Date.now() - win._wdReloadAt < 60000) {
                        win._wdOut = 0; win._wdTicks = 0; win._wdLastT = -1
                        return
                    }
                    // Unanswered probe ladder: a hung renderer never resolves the
                    // runJavaScript promise (its main thread is stuck), so silence
                    // itself is the stall signal. 3 silent ticks (~12s) -> reload.
                    win._wdOut++
                    if (win._wdOut >= 3) {
                        win._wdOut = 0; win._wdTicks = 0; win._wdLastT = -1
                        if (win._wdReloads >= 3) {
                            win._wdGiveUp = true
                            mediaStallWatchdog.wdLog("giveup-unresponsive")
                            return
                        }
                        win._wdReloads++; win._wdReloadAt = Date.now()
                        ytStallLogProc._line = JSON.stringify(
                            { at: Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss"),
                              hang: "renderer-unresponsive",
                              url: String(v.url).slice(0, 120) })
                        ytStallLogProc.running = false
                        ytStallLogProc.running = true
                        v.reload()
                        return
                    }
                    v.runJavaScript("(function(){var e=document.querySelector('video');"
                        + "if(!e)return null;"
                        + "var pl=document.getElementById('movie_player');"
                        + "var b=0;try{for(var i=0;i<e.buffered.length;i++)"
                        + "if(e.buffered.end(i)>e.currentTime)b=e.buffered.end(i)-e.currentTime;"
                        + "}catch(x){}"
                        + "return JSON.stringify({p:!!e.paused,t:+e.currentTime||0,"
                        + "rs:e.readyState,ns:e.networkState,"
                        + "er:e.error?e.error.code:0,buf:+b.toFixed(1),"
                        + "ad:!!pl&&pl.classList.contains('ad-showing'),"
                        + "sp:!!document.querySelector('.ytp-spinner.is-visible')})})()")
                        .then(function (s) {
                            win._wdOut = 0; win._wdReloads = 0; win._wdGiveUp = false
                            if (!s) { win._wdLastT = -1; win._wdTicks = 0; return }
                            let o; try { o = JSON.parse(s) } catch (e) { return }
                            // Time moved (healthy play, seek, new video) -> re-baseline.
                            // User-paused AND buffer still ahead (>=1.5s) -> likewise.
                            // A quiet stall pauses with the buffer DRY, an ad-hang shows
                            // the spinner/ad class -- both must escalate, not reset.
                            if (Math.abs(o.t - win._wdLastT) > 0.2
                                || (o.p && !o.sp && !o.ad && o.buf >= 1.5)) {
                                win._wdLastT = o.t; win._wdTicks = 0; return
                            }
                            win._wdTicks++
                            if (win._wdTicks === 2)
                                v.runJavaScript("(function(){var e=document.querySelector('video');"
                                    + "if(e&&!e.paused){var pr=e.play();if(pr&&pr.catch)pr.catch(function(){})}})()")
                                    .catch(function () {})
                            // One diagnostic line per stall: buffer depth + readyState +
                            // networkState + error code tell dry-network stalls apart from
                            // decoder/MSE stalls. Devtools cannot attach; this can.
                            if (win._wdTicks === 3) {
                                ytStallLogProc._line = JSON.stringify(
                                    { at: Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss"),
                                      url: String(v.url).slice(0, 120), v: o })
                                ytStallLogProc.running = false
                                ytStallLogProc.running = true
                            }
                            if (win._wdTicks >= 6) {   // ~24s frozen (ad-hang or stall)
                                win._wdTicks = 0; win._wdLastT = -1
                                win._wdReloads++; win._wdReloadAt = Date.now()
                                v.reload()
                            }
                        })
                        .catch(function () {})
                }
            }

            function webNavigateActive(url) {
                const u = String(url ?? win.searxBase)
                const t = win._activeTabObj()
                if (t) t.url = u
                const v = t ? win._views[t._id] : win.activeView
                if (v) v.url = u
                else win.syncWebSurface()
            }

            // Persist the active tab's live url/title into the model (views
            // already report changes live via _onViewUrl/_onViewTitle; this is
            // just belt-and-braces before a switch/hide).
            function webSaveActive() {
                if (win.tab !== "websearch") return
                const t = win._activeTabObj()
                if (!t) return
                win._webTouch()
            }
            function webNewTab(url) {
                const tab = { url: (url && url.length) ? String(url) : win.searxBase,
                              title: "", _id: win._nextTabId++ }
                win.webTabs.push(tab)
                win.activeWebTab = win.webTabs.length - 1
                win._webTouch()
                win._ensureView(tab)
                win._syncViewVisibility()
                win.webSaveTabsState()
            }
            function webCloseTab(i) {
                // Destroy ONLY this tab's view; surviving tabs keep theirs.
                const t = win.webTabs[i]
                if (t) win._destroyView(t._id)
                if (win.webTabs.length <= 1) {
                    win.webTabs = [{ url: win.searxBase, title: "", _id: win._nextTabId++ }]
                    win.activeWebTab = 0
                } else {
                    win.webTabs.splice(i, 1)
                    if (i < win.activeWebTab) win.activeWebTab--
                    if (win.activeWebTab >= win.webTabs.length) win.activeWebTab = win.webTabs.length - 1
                }
                win._webTouch()
                win._ensureView(win._activeTabObj())
                win._syncViewVisibility()
                win.webSaveTabsState()
            }
            function webSwitchTab(i) {
                if (i === win.activeWebTab) return
                win.activeWebTab = i
                win._webTouch()
                win._ensureView(win._activeTabObj())
                win._syncViewVisibility()
                win.webSaveTabsState()
            }
            // Drag-to-reorder: move a tab slot; views are untouched (keyed by id).
            function webMoveTab(from, to) {
                if (from === to || from < 0 || to < 0) return
                if (from >= win.webTabs.length || to >= win.webTabs.length) return
                const moved = win.webTabs.splice(from, 1)[0]
                win.webTabs.splice(to, 0, moved)
                if (win.activeWebTab === from) win.activeWebTab = to
                else if (from < win.activeWebTab && to >= win.activeWebTab) win.activeWebTab--
                else if (from > win.activeWebTab && to <= win.activeWebTab) win.activeWebTab++
                win._webTouch()
                win._syncViewVisibility()
                win.webSaveTabsState()
            }
            // Ensure the active tab has a materialised view (defaulting a blank
            // tab to SearXNG home, 2b) and re-pin the chrome handle. Called on
            // tab switch / page show / restore. Never re-navigates a live view.
            function syncWebSurface() {
                const t = win._activeTabObj()
                if (!t) return
                if (!t.url || t.url === "about:blank") t.url = win.searxBase
                win._ensureView(t)
                win._syncViewVisibility()
            }

            // ── Web tab persistence across launcher hide/show ───────────
            // The launcher window is a transient Loader, so hiding it destroys the
            // view; the open-tab MODEL is persisted to disk and restored on the next
            // show so the tab strip survives dock hide/re-show and tab round-trips.
            readonly property string webTabsStatePath: Config.home
                + "/.local/share/hyprcandy/websearch-tabs-state.json"

            // Ephemeral radio queues (list=RD...) die with the session: restoring
            // watch?v=X&list=RDx&start_radio=1 makes YouTube answer a playability
            // ERROR ("Something went wrong", raw $BEGIN_LINK tokens) because the
            // auto-generated queue no longer exists server-side -- while the same
            // track from history (plain watch URL) loads fine. Strip the dead
            // queue params at restore; real playlists (PL/OL...) are kept.
            function _sanitizeRestoreUrl(u) {
                try {
                    if (!/(\?|&)list=RD/.test(u) && !/(\?|&)start_radio=/.test(u)) return u
                    var i = u.indexOf("?")
                    if (i < 0) return u
                    var base = u.slice(0, i)
                    var keep = u.slice(i + 1).split("&").filter(function (p) {
                        return !/^list=RD/.test(p) && !/^start_radio=/.test(p)
                    })
                    return base + (keep.length ? "?" + keep.join("&") : "")
                } catch (e) { return u }
            }

            FileView {
                id: webTabsFile
                path: win.webTabsStatePath
                watchChanges: false
                onLoaded: {
                    try {
                        const o = JSON.parse(webTabsFile.text())
                        if (o && Array.isArray(o.tabs) && o.tabs.length) {
                            win.webTabs = o.tabs.map(function (t) {
                                return { url: win._sanitizeRestoreUrl(String(t.url || win.searxBase)),
                                         title: String(t.title || ""), _id: win._nextTabId++ }
                            })
                            win.activeWebTab = Math.min(Math.max(0, o.active | 0), win.webTabs.length - 1)
                            win.webRev++
                        }
                    } catch (e) { /* corrupt/absent: keep the default single tab */ }
                }
                Component.onCompleted: reload()
            }

            Process {
                id: webTabsWriteProc
                property string _content: ""
                command: ["python3", "-c",
                          "import sys,os; os.makedirs(os.path.dirname(sys.argv[1]),exist_ok=True); open(sys.argv[1],'w').write(sys.argv[2])",
                          win.webTabsStatePath, webTabsWriteProc._content]
            }

            function webSaveTabsState() {
                webTabsWriteProc._content = JSON.stringify({
                    active: win.activeWebTab,
                    tabs: win.webTabs.map(function (t) { return { url: t.url, title: t.title } })
                }) + "\n"
                webTabsWriteProc.running = false
                webTabsWriteProc.running = true
            }

            // ── Clear-credentials menu data ──────────────────────────────
            // This Qt build exposes NO cookieStore/deleteAllCookies API to QML
            // (verified against QtWebEngine/plugins.qmltypes: only the
            // persistentCookiesPolicy enum + persistentStoragePath exist), so
            // the list of sites holding stored credentials is read straight from
            // the profile's on-disk Chromium cookie DB (column host_key), opened
            // read-only so it is safe while the browser process holds it open.
            readonly property string webProfileDir: Config.home
                + "/.local/share/hyprcandy/webengine"
            Process {
                id: webCredListProc
                property string _buf: ""
                command: ["python3", "-c",
                    "import sqlite3,glob,json,sys\n" +
                    "base=sys.argv[1]; out=[]; s=set()\n" +
                    "for db in glob.glob(base+'/**/Cookies',recursive=True)+glob.glob(base+'/**/cookies',recursive=True):\n" +
                    "  try:\n" +
                    "    c=sqlite3.connect('file:'+db+'?mode=ro',uri=True)\n" +
                    "    for row in c.execute('select distinct host_key from cookies order by host_key'):\n" +
                    "      h=row[0]\n" +
                    "      if h and h not in s: s.add(h); out.append(h)\n" +
                    "    c.close()\n" +
                    "  except Exception: pass\n" +
                    "print(json.dumps(out))",
                    win.webProfileDir]
                stdout: SplitParser {
                    onRead: function (line) { webCredListProc._buf += line + "\n" }
                }
                onExited: {
                    try { win.webCredOrigins = JSON.parse(webCredListProc._buf.trim()) }
                    catch (e) { win.webCredOrigins = [] }
                    webCredListProc._buf = ""
                    webCredListProc.running = false
                }
            }
            function webRefreshCredOrigins() {
                webCredListProc.running = false
                webCredListProc._buf = ""
                webCredListProc.running = true
            }
            // Clearing has no QML API either, so it is done with a DELETE on the
            // cookie DB (host_key-scoped or all). Chromium caches cookies in the
            // running profile, so removal takes full effect when the web tab /
            // profile is next recycled (websearch OFF-ON toggle or relaunch).
            Process {
                id: webCredClearProc
                property string _host: ""
                command: ["python3", "-c",
                    "import sqlite3,glob,sys\n" +
                    "base=sys.argv[1]; host=sys.argv[2]\n" +
                    "for db in glob.glob(base+'/**/Cookies',recursive=True)+glob.glob(base+'/**/cookies',recursive=True):\n" +
                    "  try:\n" +
                    "    c=sqlite3.connect(db)\n" +
                    "    if host: c.execute('delete from cookies where host_key=?',(host,))\n" +
                    "    else: c.execute('delete from cookies')\n" +
                    "    c.commit(); c.close()\n" +
                    "  except Exception: pass",
                    win.webProfileDir, webCredClearProc._host]
            }
            function webClearCredential(host) {
                webCredClearProc._host = host || ""
                webCredClearProc.running = false
                webCredClearProc.running = true
                if (win.webProfile) win.webProfile.clearHttpCache()
                Qt.callLater(win.webRefreshCredOrigins)
            }

            // Enforcement-page auto-recovery: clears YouTube's HttpOnly session
            // cookies from the on-disk Chromium profile DB, purges the HTTP cache,
            // then destroys and recreates the view so Chromium re-reads the cookie
            // store from disk (the in-memory jar ignores external DB writes).
            // Called from adblock.js via a console signal when the "Ad blockers
            // violate ToS" page is detected.
            property int _fabRecoveryPending: -1
            property var _fabRecoveryTimer: null
            function _clearYouTubeCookiesAndReload(tabId) {
                if (win._fabRecoveryPending >= 0) return // already in progress
                win._fabRecoveryPending = tabId
                webCredClearProc._host = ".youtube.com"
                webCredClearProc.running = false
                webCredClearProc.running = true
                if (win.webProfile) {
                    win.webProfile.clearHttpCache()
                    // Nuke the in-memory cookie jar by flipping the persistent
                    // policy off-then-on. Chromium drops its cookie cache when
                    // the policy switches to NoPersistentCookies, so the next
                    // view we build starts with a clean cookie context.
                    win.webProfile.persistentCookiesPolicy =
                        WebEngineProfile.NoPersistentCookies
                }
                // Destroy the affected view IMMEDIATELY so Chromium releases the
                // renderer + its cached cookie jar for this origin. Then wait a
                // short beat for the sqlite write to land and the policy toggle
                // to propagate, then recreate the view (which navigates to
                // `tab.url` again). Cache-bust with a timestamp param so
                // Chromium's disk cache can't serve the flagged enforcement HTML.
                win._destroyView(tabId)
                if (win._fabRecoveryTimer) win._fabRecoveryTimer.stop()
                win._fabRecoveryTimer = Qt.createQmlObject('
                    import QtQuick; import QtQml; Timer {}', win)
                win._fabRecoveryTimer.interval = 700
                win._fabRecoveryTimer.singleShot = true
                win._fabRecoveryTimer.triggered.connect(function () {
                    if (win.webProfile) {
                        win.webProfile.persistentCookiesPolicy =
                            WebEngineProfile.ForcePersistentCookies
                    }
                    var t = win._tabById(tabId)
                    if (t) {
                        // Strip any previous cache-buster, then append a fresh
                        // timestamp so the next navigation is guaranteed cold.
                        var u = String(t.url || "")
                        u = u.replace(/[?&]_hcR=\d+/g, "")
                        if (u && u.indexOf("youtube.com") > -1) {
                            u += (u.indexOf("?") > -1 ? "&" : "?") +
                                 "_hcR=" + Date.now()
                            t.url = u
                        }
                        var v = win._ensureView(t)
                        if (v) v.url = t.url
                        win._syncViewVisibility()
                    }
                    win._fabRecoveryPending = -1
                })
                win._fabRecoveryTimer.start()
            }

            Process {
                id: agentServerProc
                command: ["python3", Config.barDir + "/agent_loopback_server.py"]
            }

            Process {
                id: agentHealthProc
                property var _cb: null
                command: ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                          "--max-time", "3", win.agentUrl]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const ok = text.trim() === "200"
                        const cb = agentHealthProc._cb
                        agentHealthProc._cb = null
                        agentHealthProc.running = false
                        if (cb) cb(ok)
                    }
                }
            }

            Timer {
                id: agentHealthRetry
                interval: 700
                repeat: true
                property int attempts: 0
                onTriggered: win.checkAgentHealth(function(ok) {
                    if (ok) {
                        agentHealthRetry.stop()
                        win.agentStarting = false
                        win.agentMissing = false
                        win.agentReady = true
                    } else if (agentHealthRetry.attempts >= 20) {
                        agentHealthRetry.stop()
                        win.agentStarting = false
                        win.agentMissing = true
                    } else {
                        agentHealthRetry.attempts++
                    }
                })
            }

            function checkAgentHealth(cb) {
                agentHealthProc._cb = cb
                agentHealthProc.running = false
                agentHealthProc.running = true
            }

            function agentEnsureUp() {
                if (!win.wsEnabled) return
                win._ensureWebProfile()
                win.ensureRuntimeBackend()
                if (win.agentReady) return
                win.checkAgentHealth(function(ok) {
                    if (ok) { win.agentMissing = false; win.agentReady = true; return }
                    if (win.agentStarting) return
                    win.agentStarting = true
                    win.agentMissing = false
                    agentServerProc.running = false
                    agentServerProc.running = true
                    agentHealthRetry.attempts = 0
                    agentHealthRetry.restart()
                })
            }

            // ── Workspace startup policy + Python runtime (GJS parity) ────
            // Mirrors app-launcher.js: a persisted ON/OFF policy decides whether
            // the agent workspace (loopback server + uvicorn runtime) is warmed
            // when a launcher session starts. Default ON so a fresh install
            // autostarts the workspace; toggling OFF persists {"enabled":false}
            // and the next session boots dormant (view hidden, runtime not spawned).
            readonly property string wsStatePath: Config.home
                + "/.local/share/hyprcandy/workspace-startup-state.json"
            readonly property string wsStateDir: Config.home + "/.local/share/hyprcandy"
            readonly property string runtimeDir: Config.home
                + "/.hyprcandy/GJS/hyprcandydock/Agents/local_runtime"
            property bool wsEnabled: true
            property bool runtimeStarted: false
            property bool _wsResolved: false

            FileView {
                id: wsStateFile
                path: win.wsStatePath
                watchChanges: false
                onLoaded: {
                    win.wsEnabled = win.readWorkspaceStartupState()
                    win._wsResolved = true
                    // Same resolved-gate as the web policy (3a).
                    if (win.wsEnabled && win.visible && win._wsResolved) win.ensureRuntimeBackend()
                }
                Component.onCompleted: reload()
            }

            // writeWorkspaceStartupState parity: makedirs + write the JSON via
            // argv so there is no bash/JSON quoting hazard (same idiom as the
            // launcher.state / bar-state writers).
            Process {
                id: wsWriteProc
                command: ["python3", "-c",
                          "import sys,os; os.makedirs(os.path.dirname(sys.argv[1]),exist_ok=True); open(sys.argv[1],'w').write(sys.argv[2])",
                          win.wsStatePath, wsWriteProc._content]
                property string _content: "{\"enabled\":true}\n"
            }

            function writeWorkspaceStartupState(enabled) {
                wsWriteProc._content = JSON.stringify({ enabled: !!enabled }) + "\n"
                wsWriteProc.running = false
                wsWriteProc.running = true
            }

            function readWorkspaceStartupState() {
                try {
                    // NOTE: FileView.exists is undefined in this Quickshell build,
                    // so it must NOT gate the read (that silently forced wsEnabled
                    // always-ON and made the agent tab autostart despite a persisted
                    // OFF). text() is the content (empty when unreadable) and
                    // onLoaded only fires on a successful load -- same as the web
                    // state readers above.
                    const t = wsStateFile.text()
                    if (!t) return true
                    const o = JSON.parse(t)
                    return (o && typeof o.enabled === "boolean") ? o.enabled : true
                } catch (e) { return true }
            }

            // ── Python uvicorn runtime (_agentStartPythonRuntime parity) ──
            // start.sh makes its venv, kills stale instances and daemonizes
            // uvicorn on :17900. Health-check first so a warm runtime is not
            // restarted; llama-server is never started here (still an explicit
            // Model Manager action, exactly as GJS now behaves).
            Process {
                id: runtimeHealthProc
                property var _cb: null
                command: ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                          "--max-time", "2", "http://127.0.0.1:17900/health"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const ok = text.trim() === "200"
                        const cb = runtimeHealthProc._cb
                        runtimeHealthProc._cb = null
                        runtimeHealthProc.running = false
                        if (cb) cb(ok)
                    }
                }
            }

            Process {
                id: runtimeSpawnProc
                command: ["bash", win.runtimeDir + "/start.sh"]
            }

            function ensureRuntimeBackend() {
                if (win.runtimeStarted) return
                win.runtimeStarted = true
                runtimeHealthProc._cb = function(ok) {
                    if (ok) return
                    runtimeSpawnProc.running = false
                    runtimeSpawnProc.running = true
                }
                runtimeHealthProc.running = false
                runtimeHealthProc.running = true
            }

            // ON branch of the toggle: reveal the workspace, warm the runtime and
            // surface the agent tab (GJS _agentRevealWorkspace + _agentToggleWorkspace).
            function agentRevealWorkspace() {
                win.agentReady = false
                win.agentStarting = false
                win.agentMissing = false
                win.agentEnsureUp()
                win.ensureRuntimeBackend()
                win.switchTab("agent")
            }

            // The circular workspace toggle handler: flip + persist the policy, then
            // reveal (ON) or hide-and-return-to-launcher (OFF).
            function agentToggleWorkspace() {
                const next = !win.wsEnabled
                win.wsEnabled = next
                win.writeWorkspaceStartupState(next)
                if (next) {
                    win.agentRevealWorkspace()
                } else {
                    win.agentReady = false
                    win.agentStarting = false
                    win._webClearCache()
                    win.switchTab("launcher")
                }
            }

            // ── App model ─────────────────────────────────────────────────
            // records: { name, icon, cls, desktopId, exec, entry? }
            property var allApps: []
            property var steamApps: []
            property int _entriesEpoch: 0
            property var _pixmapIcons: ({})

            readonly property var filteredApps: {
                win._entriesEpoch; win.pinnedEpoch
                const qs = win.q
                const favs = GroupsState.favorites
                const out = []
                for (const a of win.allApps) {
                    if (qs !== "" && !String(a.name).toLowerCase().includes(qs)) continue
                    // Favorites live in their own section, so drop them from the
                    // main grid — except while searching (they must appear in the
                    // relevant results) or in selection mode (the grid is then the
                    // single place to pick from, so favorites stay selectable).
                    if (!qs && !win.selectMode && favs.includes(a.cls)) continue
                    out.push(a)
                }
                return out
            }
            readonly property var favoriteApps: {
                win._entriesEpoch
                const out = []
                for (const a of win.allApps)
                    if (GroupsState.favorites.includes(a.cls)) out.push(a)
                return out
            }

            function rebuildApps() {
                const out = [], seen = []
                const m = DesktopEntries.applications
                const vals = (m && m.values) ? m.values : []
                for (const e of vals) {
                    if (!e || !e.name || e.name === "") continue
                    const id = String(e.id || "")
                    if (id === "" || seen.includes(id)) continue
                    const exec = String(e.execString || "")
                    if (exec === "") continue
                    seen.push(id)
                    out.push({
                        "name": e.name, "icon": e.icon || "application-x-executable",
                        "cls": id.replace(/\.desktop$/, ""), "desktopId": id.replace(/\.desktop$/, ""),
                        "exec": exec, "entry": e,
                    })
                }
                for (const s of win.steamApps) {
                    if (seen.includes(s.desktopId + ".desktop")) continue
                    seen.push(s.desktopId + ".desktop")
                    out.push(s)
                }
                out.sort((a, b) => String(a.name).localeCompare(String(b.name)))
                win.allApps = out
                win._entriesEpoch++
            }

            // Steam game shortcuts live on ~/Desktop (GJS scan parity).
            Process {
                id: steamScan
                running: true
                command: ["python3", "-c",
                    "import os,glob,json,re\n" +
                    "out=[]\n" +
                    "d=os.path.expanduser('~/Desktop')\n" +
                    "for f in glob.glob(d+'/*.desktop'):\n" +
                    "    try: txt=open(f,encoding='utf-8',errors='ignore').read()\n" +
                    "    except: continue\n" +
                    "    if not re.search(r'^Type=Application$',txt,re.M): continue\n" +
                    "    m=re.search(r'^Exec=(.*)$',txt,re.M)\n" +
                    "    if not m or 'steam://rungameid' not in m.group(1): continue\n" +
                    "    did=os.path.basename(f)[:-8]\n" +
                    "    nm=re.search(r'^Name=(.*)$',txt,re.M); ic=re.search(r'^Icon=(.*)$',txt,re.M)\n" +
                    "    out.append({'name':nm.group(1) if nm else did,'icon':(ic.group(1) if ic else 'steam'),\n" +
                    "        'cls':did,'desktopId':did,'exec':m.group(1)})\n" +
                    "print(json.dumps(out))"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try { win.steamApps = JSON.parse(text) } catch (_) { win.steamApps = [] }
                        win.rebuildApps()
                    }
                }
            }

            // /usr/share/pixmaps fallback map (DockWindow parity).
            Process {
                id: pixmapScan
                running: true
                command: ["bash", "-c",
                    'for d in "$HOME/.local/share/pixmaps" /usr/share/pixmaps; do ' +
                    '[ -d "$d" ] || continue; ' +
                    'find "$d" -maxdepth 1 -type f \\( -iname "*.png" -o -iname "*.svg" ' +
                    '-o -iname "*.xpm" -o -iname "*.ico" \\); done']
                property var _lines: []
                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: function(l) { pixmapScan._lines.push(l.trim()) }
                }
                onExited: {
                    const map = {}
                    for (const l of _lines) {
                        const m = l.match(/\/([^/]+)\.(png|svg|xpm|ico)$/i)
                        if (m && !(m[1].toLowerCase() in map)) map[m[1].toLowerCase()] = l
                    }
                    _lines = []
                    win._pixmapIcons = map
                    running = false
                }
            }

            function iconSource(rec) {
                // check=true overload (dock parity): returns the resolved path only
                // when it maps to a real theme icon / existing file. The previous
                // fallback-string form handed broken absolute Icon= paths (HP Scan's
                // missing Humanity printer.svg) straight to the Image, which painted
                // Quickshell's own "no icon" placeholder while reporting Ready — so
                // our ghost never appeared. check=true collapses those to "".
                const p = Quickshell.iconPath(rec.icon, true)
                if (p && p !== "") return p
                const px = win._pixmapIcons[String(rec.cls).toLowerCase()]
                if (px) return px
                return ""   // unresolved → ghost glyph overlay (dock parity)
            }

            // ── Icons tab: lazy glyphData.json load + filter + copy ──────
            Process {
                id: glyphProc
                command: ["cat", Quickshell.env("HOME")
                                    + "/.config/quickshell/bar/glyphData.json"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const d = JSON.parse(text)
                            win.emojiAll = d.EMOJI_ALL
                            win.emojiGroups = d.EMOJI_GROUPS
                            win.nerdCats = d.NERD_CATS
                            win.glyphReady = true
                        } catch (_) { win.glyphReady = false }
                        glyphProc.running = false
                    }
                }
            }
            function ensureGlyphData() {
                if (!win.glyphReady && !glyphProc.running) glyphProc.running = true
            }

            // GJS _filterEmoji parity: query searches every group/category,
            // no query shows the active category only.
            readonly property var iconCells: {
                if (!win.glyphReady) return []
                const out = []
                if (win.iconMode === "nerd") {
                    if (win.q !== "") {
                        for (const cat of win.nerdCats) {
                            const cm = String(cat.name).toLowerCase().includes(win.q)
                                    || String(cat.prefix ?? "").includes(win.q)
                            for (const g of cat.glyphs) {
                                if (cm || String(g.s ?? g.n.toLowerCase()).includes(win.q))
                                    out.push(g)
                            }
                        }
                    } else {
                        const c = win.nerdCats[win.nerdCat]
                        if (c) out.push(...c.glyphs)
                    }
                } else {
                    for (const e of win.emojiAll) {
                        if (win.q !== "") {
                            if (String(e.n).toLowerCase().includes(win.q)) out.push(e)
                        } else if (e.g === win.emojiGroup) out.push(e)
                    }
                }
                return out
            }

            Process {
                id: copyProc
                property string _arg: ""
                command: ["wl-copy", "--", copyProc._arg]
            }
            Timer {
                id: copiedTimer
                interval: 1800
                repeat: false
                onTriggered: win.copiedChar = ""
            }
            function copyGlyph(c) {
                copyProc._arg = String(c)
                copyProc.running = false
                copyProc.running = true
                win.copiedChar = String(c)
                copiedTimer.restart()
            }

            // ── Web-Search tab: SearXNG JSON (curl) + docker lifecycle ────
            readonly property string searxBase: "http://127.0.0.1:8080"

            Timer {
                id: webDebounce
                interval: 400
                repeat: false
                onTriggered: win.webSearch(win.query)
            }

            // Search GET → parse result list.
            Process {
                id: searchProc
                property string _url: ""
                command: ["curl", "-s", "--max-time", "8", searchProc._url]
                stdout: StdioCollector {
                    onStreamFinished: {
                        searchProc.running = false
                        if (win.tab !== "websearch" || win.webLastQuery === "") return
                        let d = null
                        try { d = JSON.parse(text) } catch (_) { d = null }
                        if (d === null) {
                            win.webStatus = "offline"
                            win.webStatusTitle = "SearXNG offline"
                            win.webStatusBody = "Could not connect to SearXNG on 127.0.0.1:8080.\nPlease ensure SearXNG service is running."
                            return
                        }
                        const raw = (d.results ?? []).slice(0, 30)
                        const clean = []
                        for (const r of raw) {
                            clean.push({
                                title: win._searxClean(r.title),
                                url: String(r.url ?? ""),
                                content: win._searxClean(r.content),
                            })
                        }
                        win.webResults = clean
                        if (win.webResults.length === 0) {
                            win.webStatus = "noresults"
                            win.webStatusTitle = "No results"
                            win.webStatusBody = "Nothing found for \u201C" + win.webLastQuery + "\u201D"
                        } else {
                            win.webStatus = "ready"
                        }
                    }
                }
            }

            // Health ping (HTTP code only) → invokes _cb(ok).
            Process {
                id: healthProc
                property var _cb: null
                command: ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                          "--max-time", "4", win.searxBase + "/search?q=ping&format=json"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const ok = text.trim() === "200"
                        const cb = healthProc._cb
                        healthProc._cb = null
                        healthProc.running = false
                        if (cb) cb(ok)
                    }
                }
            }

            // docker start|stop via a port-local copy of the SearXNG control
            // script (bar/scripts/hyprcandy-docker.sh). Invoked DIRECTLY
            // (shebang + exec bit), NOT via a `bash` wrapper, so the script's
            // `sudo -n "$0" "$@"` self-elevation resolves $0 to this exact path
            // — which is the path the NOPASSWD rule in
            // /etc/sudoers.d/hyprcandy-background must allow. Running as root
            // lets ensure_storage_driver_ready() fix the CachyOS/BTRFS
            // overlay-on-overlay mount, without which `docker run` fails.
            Process {
                id: dockerProc
                property string _action: "start"
                command: [Config.barDir + "/scripts/hyprcandy-docker.sh",
                          dockerProc._action]
                onExited: {
                    if (dockerProc._action === "start") {
                        healthRetry.attempts = 0
                        healthRetry.restart()
                    }
                    dockerProc.running = false
                }
            }

            Timer {
                id: healthRetry
                interval: 800
                repeat: true
                property int attempts: 0
                onTriggered: {
                    win.checkSearxHealth(function(ok) {
                        if (ok) {
                            healthRetry.stop()
                            win.searxDockerStarting = false
                            win.searxDockerAutoStarted = true
                            win.searxDown = false
                            // SearXNG came up after a docker start: recover only an
                            // ACTIVE tab that actually errored on the searx origin.
                            const t = win._activeTabObj()
                            if (win.webShowError && win.tab === "websearch" && t
                                    && String(t.url || "").indexOf(win.searxBase) === 0) {
                                win.webNavigateActive(win.searxBase)
                            }
                            win.webShowError = false
                        } else if (healthRetry.attempts >= 25 || win.tab !== "websearch") {
                            healthRetry.stop()
                            win.searxDockerStarting = false
                            // Background truth only — never paints the overlay over
                            // a working page (2c); the view's own load error does.
                            win.searxDown = true
                        } else {
                            healthRetry.attempts++
                        }
                    })
                }
            }

            function checkSearxHealth(cb) {
                healthProc._cb = cb
                healthProc.running = false
                healthProc.running = true
            }

            function webSearch(q) {
                q = String(q ?? "").trim()
                if (q === "") { win.webResults = []; win.webStatus = "idle"; win.webStatusTitle = ""; win.webStatusBody = ""; return }
                win.webLastQuery = q
                win.webStatus = "loading"
                win.webStatusTitle = "Searching\u2026"
                win.webStatusBody = q
                searchProc._url = win.searxBase + "/search?q="
                                  + encodeURIComponent(q) + "&format=json"
                searchProc.running = false
                searchProc.running = true
            }

            function searxStartDocker() {
                win.webLastQuery = ""
                if (win.searxDockerStarting) return
                win.searxDockerStarting = true
                win.webStatus = "loading"
                win.webStatusTitle = "Starting SearXNG\u2026"
                win.webStatusBody = ""
                dockerProc._action = "start"
                dockerProc.running = false
                dockerProc.running = true
            }

            function searxStopDocker() {
                if (!win.searxDockerAutoStarted) return
                win.searxDockerAutoStarted = false
                dockerProc._action = "stop"
                dockerProc.running = false
                dockerProc.running = true
            }

            function webOpenExternal(url) {
                if (url) Quickshell.execDetached(["xdg-open", String(url)])
            }

            // Ensure the SearXNG service is up for the embedded webview: if it is
            // already healthy, clear any stale overlay (reloading the page if we had
            // errored out); otherwise kick off the docker start and let healthRetry
            // finish the boot and recover the view.
            function webEnsureUp() {
                win._ensureWebProfile()
                win._syncProxy(true)
                win.checkSearxHealth(function(ok) {
                    if (ok) {
                        win.searxDown = false
                        const t = win._activeTabObj()
                        if (win.webShowError && t
                                && String(t.url || "").indexOf(win.searxBase) === 0) {
                            win.webNavigateActive(win.searxBase)
                        }
                        win.webShowError = false
                        // Fresh session: make sure the active tab has a view and
                        // defaults to the SearXNG home, not about:blank (2b).
                        win.syncWebSurface()
                    } else {
                        win.searxStartDocker()
                    }
                })
            }

            // Toggle a search-result URL in the shared bookmarks store.
            function webToggleBookmark(url, title) {
                WebBookmarksState.toggle(String(url ?? ""), String(title ?? ""))
            }

            // Offline fallback: open the SearXNG web UI (not JSON) externally.
            function searxOpenQueryExternal() {
                const q = String(win.webLastQuery || win.query || "").trim()
                const url = q !== ""
                    ? win.searxBase + "/search?q=" + encodeURIComponent(q)
                    : win.searxBase
                win.webOpenExternal(url)
            }

            // Strip SearXNG result HTML (highlight <b>/<mark> tags) + decode
            // the handful of entities that show up in titles / snippets.
            function _searxClean(s) {
                s = String(s ?? "")
                s = s.replace(/<[^>]*>/g, "")
                s = s.replace(/&amp;/g, "&").replace(/&lt;/g, "<")
                      .replace(/&gt;/g, ">").replace(/&quot;/g, "\"")
                      .replace(/&#39;/g, "'").replace(/&nbsp;/g, " ")
                return s.replace(/\s+/g, " ").trim()
            }

            // ── Running windows (dock helpers, same contract) ─────────────
            readonly property int toplevelCount: Hyprland.toplevels ? Hyprland.toplevels.values.length : 0
            property int _classEpoch: 0

            function _normClass(c) { return String(c || "").toLowerCase() }
            function _toplevelClass(tl) {
                const o = (tl && tl.lastIpcObject) || {}
                return String(o.class || o.initialClass || "")
            }
            function _allToplevels() {
                const m = Hyprland.toplevels
                return (m && m.values) ? m.values : []
            }
            function clientsFor(appClass) {
                win._classEpoch
                const target = win._normClass(appClass)
                const out = []
                if (!target) return out
                for (const tl of win._allToplevels()) {
                    if (!tl) continue
                    const o = tl.lastIpcObject || {}
                    if (win._normClass(win._toplevelClass(tl)) === target
                        || win._normClass(o.initialClass) === target) out.push(tl)
                }
                return out
            }

            Timer {
                id: tlRefresh
                interval: 150
                repeat: false
                onTriggered: { Hyprland.refreshToplevels(); win._classEpoch++ }
            }
            Connections {
                target: Hyprland
                function onRawEvent(event) {
                    if (event && (event.name === "openwindow" || event.name === "movewindow"))
                        tlRefresh.restart()
                }
            }
            // DesktopEntries populate lazily after qs boot.
            Timer {
                interval: 300
                repeat: true
                running: win.allApps.length === 0 && DesktopEntries.applications.count === 0
                property int _attempts: 0
                onTriggered: {
                    _attempts++
                    if (DesktopEntries.applications.count > 0) { win.rebuildApps(); stop() }
                    else if (_attempts >= 40) stop()
                }
            }

            // ── Hyprland dispatch helpers (exact GJS daemon.js strings) ───
            function _hlDispatch(cmd) {
                Quickshell.execDetached(["hyprctl", "dispatch", cmd])
            }
            function _addr(a) {
                const s = String(a ?? "")
                if (s === "") return ""
                return s.startsWith("0x") ? s : "0x" + s
            }
            function _focusAddr(a) {
                win._hlDispatch("hl.dsp.focus({ window = 'address:" + win._addr(a) + "' })")
            }
            function _isMin(tl) {
                const w = tl && tl.workspace ? String(tl.workspace.name) : ""
                return w === "hidden" || w === "special:hidden"
            }
            property string _restorePendingAddr: ""
            Timer {
                id: restoreFocusTimer
                interval: 80
                repeat: false
                onTriggered: {
                    if (win._restorePendingAddr !== "")
                        win._hlDispatch("hl.dsp.focus({ window = 'address:" + win._restorePendingAddr + "' })")
                    win._restorePendingAddr = ""
                }
            }
            function _restoreAddr(a) {
                const addr = win._addr(a)
                win._hlDispatch("hl.dsp.window.move({ window = 'address:" + addr + "', workspace = 'e+0' })")
                win._restorePendingAddr = addr
                restoreFocusTimer.restart()
            }
            function _raiseToplevel(tl) {
                if (!tl || !tl.address) return
                if (win._isMin(tl)) win._restoreAddr(tl.address)
                else win._focusAddr(tl.address)
            }

            // ── Launching ─────────────────────────────────────────────────
            Process {
                id: launchProc
                property string _cmd: ""
                command: ["bash", "-c", launchProc._cmd]
                onExited: running = false
            }
            function cleanExec(rec) {
                return String(rec.exec || "").replace(/%[UuFfIiDdNnVvKk]/g, "").trim()
            }
            function launchApp(rec) {
                if (!rec) return
                if (rec.entry) { rec.entry.execute(); return }
                const line = win.cleanExec(rec)
                if (line === "") return
                launchProc._cmd = line + " &"
                launchProc.running = true
            }

            // ── dGPU list via switcheroo (DockWindow parity) ──────────────
            property var gpuList: []
            property bool gpuReady: false
            Process {
                id: gpuProc
                property string _buf: ""
                running: true
                command: ["bash", "-c",
                    "python3 -c \"\n" +
                    "import sys, json\n" +
                    "try:\n" +
                    "    import gi; gi.require_version('GLib','2.0'); from gi.repository import GLib, Gio\n" +
                    "    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)\n" +
                    "    r = bus.call_sync(" +
                    "'net.hadess.SwitcherooControl','/net/hadess/SwitcherooControl'," +
                    "'org.freedesktop.DBus.Properties','Get'," +
                    "GLib.Variant('(ss)',['net.hadess.SwitcherooControl','GPUs'])," +
                    "None,Gio.DBusCallFlags.NONE,-1,None)\n" +
                    "    gpus=[]\n" +
                    "    for g in r.unpack()[0]:\n" +
                    "        if g.get('Default',True): continue\n" +
                    "        ev=g.get('Environment',[]); env={}\n" +
                    "        for i in range(0,len(ev)-1,2): env[ev[i]]=ev[i+1]\n" +
                    "        gpus.append({'name':g.get('Name','dGPU'),'env':env})\n" +
                    "    print(json.dumps(gpus))\n" +
                    "except: print('[]')\n" +
                    "\" 2>/dev/null || echo '[]'"
                ]
                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: function(line) { gpuProc._buf += line }
                }
                onExited: {
                    try { win.gpuList = JSON.parse(_buf) } catch (_) { win.gpuList = [] }
                    win.gpuReady = true
                }
            }
            function abbrevGpu(name) {
                return String(name)
                    .replace(/^Advanced Micro Devices,?\s*Inc\.?\s*\[AMD\/ATI\]\s*/i, "")
                    .replace(/^NVIDIA\s+Corporation\s*/i, "")
                    .replace(/^Intel\s+Corporation\s*/i, "")
                    .slice(0, 32)
            }
            function launchOnGpu(exec, envObj) {
                let envStr = ""
                for (const [k, v] of Object.entries(envObj ?? {}))
                    envStr += k + "=" + v + " "
                launchProc._cmd = "env " + envStr + exec + " &"
                launchProc.running = true
            }

            // Workspace-targeted launch: focus ws, +50 ms exec_cmd rule (GJS).
            property string _wsPendingExec: ""
            property int _wsPendingWs: 0
            Timer {
                id: wsLaunchTimer
                interval: 50
                repeat: false
                onTriggered: {
                    if (win._wsPendingExec === "") return
                    win._hlDispatch("hl.dsp.exec_cmd('" + win._wsPendingExec +
                        "', { workspace = " + win._wsPendingWs + " })")
                    win._wsPendingExec = ""
                    win._wsPendingWs = 0
                }
            }
            function launchOnWs(rec, wsNum, envObj) {
                if (!rec) return
                let exec = win.cleanExec(rec)
                if (exec === "" && rec.entry && rec.entry.execString)
                    exec = String(rec.entry.execString).replace(/%[UuFfIiDdNnVvKk]/g, "").trim()
                if (exec === "") return
                if (envObj) {
                    let envStr = ""
                    for (const [k, v] of Object.entries(envObj))
                        envStr += k + "=" + v + " "
                    exec = envStr + exec
                }
                win._hlDispatch("hl.dsp.focus({ workspace = " + wsNum + " })")
                win._wsPendingExec = exec.replace(/'/g, "")
                win._wsPendingWs = wsNum
                wsLaunchTimer.restart()
            }

            // ── Pin checks (three-form parity) ────────────────────────────
            readonly property string pinnedEpoch: PinnedAppsState.pinnedOrderKey
            function isPinnedDock(rec) {
                win.pinnedEpoch
                const forms = [rec.desktopId, rec.cls].filter(x => x)
                for (const f of forms)
                    if (PinnedAppsState.isPinned(f)) return true
                return false
            }
            function togglePinDock(rec) {
                if (isPinnedDock(rec)) {
                    PinnedAppsState.unpin(rec.desktopId)
                    PinnedAppsState.unpin(rec.cls)
                } else {
                    PinnedAppsState.pin(rec.desktopId || rec.cls)
                }
            }
            function isPinnedDesk(rec) {
                const list = DesktopPinnedState.apps ?? []
                for (const a of list)
                    if (a.class === rec.desktopId || a.class === rec.cls) return true
                return false
            }
            function togglePinDesk(rec) {
                if (isPinnedDesk(rec)) {
                    DesktopPinnedState.removeApp(rec.cls)
                    if (rec.desktopId !== rec.cls) DesktopPinnedState.removeApp(rec.desktopId)
                } else {
                    DesktopPinnedState.addApp(rec.desktopId || rec.cls)
                }
            }

            // ── Context menu rows ─────────────────────────────────────────
            function _openAppMenu(rec, gx, gy, groupCtx) {
                win._menuRec = rec
                win._menuGroupCtx = groupCtx ?? ""
                win._addToOpen = false
                const rows = []
                const inst = win.clientsFor(rec.cls)
                if (inst.length > 0) {
                    if (inst.length > 1) rows.push({ kind: "hdr", text: "Running Windows" })
                    for (let i = 0; i < inst.length; i++) {
                        const t = String(inst[i].title ?? "")
                        rows.push({
                            kind: "item", key: "inst:" + i,
                            text: inst.length === 1 ? "Switch to Window"
                                 : (t.length > 34 ? t.slice(0, 34) + "\u2026" : (t === "" ? "Window" : t)),
                        })
                    }
                    rows.push({ kind: "sep" })
                }
                rows.push({ kind: "item", key: "newwin", text: "New Window", chev: "\u203A" })
                rows.push({ kind: "sep" })
                rows.push({ kind: "item", key: "pindock",
                            text: win.isPinnedDock(rec) ? "Unpin from Dock" : "Pin to Dock" })
                rows.push({ kind: "item", key: "pindesk",
                            text: win.isPinnedDesk(rec) ? "Unpin from Desktop" : "Pin to Desktop" })
                rows.push({ kind: "sep" })
                rows.push({ kind: "item", key: "fav",
                            text: GroupsState.isFavorite(rec.cls) ? "Remove from Favorites"
                                                                  : "Add to Favorites" })
                rows.push({ kind: "sep" })
                rows.push({ kind: "hdr", text: "Groups" })
                const inGroups = GroupsState.groupsForApp(rec.cls)
                if (win._menuGroupCtx !== "") {
                    rows.push({ kind: "item", key: "grm:" + win._menuGroupCtx,
                                text: "Remove from \u201C" + win._menuGroupCtx + "\u201D" })
                } else {
                    for (const g of Object.keys(GroupsState.groups)) {
                        if (inGroups.includes(g))
                            rows.push({ kind: "item", key: "grm:" + g, text: "Remove from \u201C" + g + "\u201D" })
                    }
                    for (const g of Object.keys(GroupsState.groups)) {
                        if (!inGroups.includes(g))
                            rows.push({ kind: "item", key: "gra:" + g, text: "Add to \u201C" + g + "\u201D" })
                    }
                    rows.push({ kind: "item", key: "gnew", text: "New Group\u2026" })
                }
                if (win.gpuReady && win.gpuList.length > 0) {
                    rows.push({ kind: "sep" })
                    rows.push({ kind: "hdr", text: "Launch on GPU" })
                    rows.push({ kind: "sep" })
                    for (let i = 0; i < win.gpuList.length; i++)
                        rows.push({ kind: "item", key: "gpu:" + i,
                                    text: win.abbrevGpu(win.gpuList[i].name), chev: "\u203A" })
                }
                win._menuRows = rows
                win._menuOpen = true
                win._wsSubKey = ""
                // Position: beside the tile, clamped inside the card.
                const mh = menuCol.implicitHeight + 12
                win._menuX = Math.max(6, Math.min(gx + 8, card.width - 250 - 6))
                win._menuY = Math.max(6, Math.min(gy - 20, card.height - mh - 6))
            }

            function _openGroupMenu(groupName, gx, gy) {
                win._menuRec = null
                win._menuGroupCtx = groupName
                win._menuRows = [
                    { kind: "hdr", text: groupName },
                    { kind: "sep" },
                    { kind: "item", key: "gren", text: "Rename Group\u2026" },
                    { kind: "sep" },
                    { kind: "item", key: "grdel", text: "Delete Group" },
                ]
                win._menuOpen = true
                win._wsSubKey = ""
                win._menuX = Math.max(6, Math.min(gx, card.width - 250 - 6))
                win._menuY = Math.max(6, Math.min(gy, card.height - 150))
            }

            function _hideMenu() {
                win._menuOpen = false
                win._wsSubKey = ""
                win._menuRec = null
                win._menuGroupCtx = ""
            }

            // ── "Add to:" popup (selection mode) ──────────────────
            // Builds the group list on open (avoids relying on GroupsState change
            // notifications) and adds every selected app to the picked target.
            // Favorites is handled specially (toggle-on only when absent).
            function toggleAddTo() {
                if (win._addToOpen) { win._addToOpen = false; return }
                win._addToGroups = Object.keys(GroupsState.groups)
                win._addToOpen = true
            }
            function addSelectedTo(isFav, group) {
                const ids = win.selectedIds.slice()
                if (isFav) {
                    for (const c of ids) if (!GroupsState.isFavorite(c)) GroupsState.toggleFavorite(c)
                } else {
                    for (const c of ids) GroupsState.addAppToGroup(group, c)
                }
                win._addToOpen = false
                win.selectedIds = []
                win.selectMode = false
            }

            function _menuActivate(row) {
                const rec = win._menuRec
                const key = row.key ?? ""
                if (key.startsWith("inst:")) {
                    const inst = rec ? win.clientsFor(rec.cls) : []
                    const i = parseInt(key.substring(5), 10)
                    if (inst[i]) win._raiseToplevel(inst[i])
                    win._hideMenu(); HCCLauncherState.close()
                } else if (key === "newwin") {
                    win.launchApp(rec)
                    win._hideMenu(); HCCLauncherState.close()
                } else if (key === "pindock") {
                    win.togglePinDock(rec); win._hideMenu()
                } else if (key === "pindesk") {
                    win.togglePinDesk(rec); win._hideMenu()
                } else if (key === "fav") {
                    GroupsState.toggleFavorite(rec.cls); win._hideMenu()
                } else if (key.startsWith("gra:")) {
                    GroupsState.addAppToGroup(key.substring(4), rec.cls); win._hideMenu()
                } else if (key.startsWith("grm:")) {
                    GroupsState.removeAppFromGroup(key.substring(4), rec.cls); win._hideMenu()
                } else if (key === "gnew") {
                    win._dlg = { open: true, mode: "newgroup", ids: [rec.cls],
                                 title: "New group for \u201C" + rec.name + "\u201D" }
                    win._hideMenu()
                } else if (key === "gren") {
                    win._dlg = { open: true, mode: "rename", group: win._menuGroupCtx,
                                 title: "Rename group \u201C" + win._menuGroupCtx + "\u201D",
                                 initial: win._menuGroupCtx }
                    win._hideMenu()
                } else if (key === "grdel") {
                    const g = win._menuGroupCtx
                    const exp = Object.assign({}, win.expandedGroups)
                    delete exp[g]
                    win.expandedGroups = exp
                    GroupsState.deleteGroup(g)
                    win._hideMenu()
                } else if (key.startsWith("gpu:")) {
                    const g = win.gpuList[parseInt(key.substring(4), 10)]
                    const line = rec ? win.cleanExec(rec) : ""
                    if (g && line !== "") win.launchOnGpu(line, g.env ?? {})
                    win._hideMenu(); HCCLauncherState.close()
                } else {
                    win._hideMenu()
                }
            }

            // WS sub-panel pick (row key owns it: "newwin" or "gpu:<i>").
            function _wsPick(wsNum) {
                const rec = win._menuRec
                const k = win._wsSubKey
                win._hideMenu()
                if (!rec) return
                if (k.startsWith("gpu:")) {
                    const g = win.gpuList[parseInt(k.substring(4), 10)]
                    win.launchOnWs(rec, wsNum, g?.env)
                } else {
                    win.launchOnWs(rec, wsNum, null)
                }
                HCCLauncherState.close()
            }

            // ── Tab switching / dismissal ─────────────────────────────────
            function switchTab(id) {
                if (win.tab === id) return
                if (win.tab === "websearch") win.webSaveActive()
                win.tab = id
                HCCLauncherState.setTab(id)
                win.query = ""
                searchInput.text = ""
                win.focusIdx = -1
                win._hideMenu()
                win._addToOpen = false
                if (id === "clipboard") ClipboardState.refresh()
                if (id === "emoji") win.ensureGlyphData()
                if (id === "websearch" && win.webEnabled) win.webEnsureUp()
                if (id === "agent") win.agentEnsureUp()
                win.syncWebSurface()
                Qt.callLater(function() {
                    if (win.tab === "websearch" || win.tab === "agent") { if (win.activeView) win.activeView.forceActiveFocus() }
                    else searchInput.forceActiveFocus()
                })
            }
            function cycleTab(dir) {
                const tabs = HCCLauncherState.tabs
                const i = tabs.indexOf(win.tab)
                win.switchTab(tabs[((i === -1 ? 0 : i) + dir + tabs.length) % tabs.length])
            }
            function dismiss() {
                if (win._addToOpen) { win._addToOpen = false; return }
                if (win._menuOpen) { win._hideMenu(); return }
                if (win._dlg.open) { win._dlg = { open: false }; return }
                HCCLauncherState.close()
            }
            onSelectModeChanged: if (!win.selectMode) win._addToOpen = false

            onTabChanged: {
                if (HCCLauncherState.activeTab !== win.tab) HCCLauncherState.setTab(win.tab)
            }
            // When the workspace finishes booting (async health success) while its
            // tab is showing, navigate the shared view onto the agent app.
            onAgentReadyChanged: if (win.tab === "agent") win.syncWebSurface()
            Connections {
                target: HCCLauncherState
                function onActiveTabChanged() {
                    if (win.tab !== HCCLauncherState.activeTab) win.tab = HCCLauncherState.activeTab
                }
            }
            onVisibleChanged: {
                if (visible) {
                    idleCacheTrim.stop()
                    // First show of the (now persistent) window: resolve the
                    // startup policies and warm any enabled backend. Deferred here
                    // rather than Component.onCompleted so a hidden-at-boot window
                    // never starts docker/uvicorn on shell launch.
                    if (!win._everVisible) {
                        win._everVisible = true
                        wsInitProbe.restart()
                        webInitProbe.restart()
                    }
                    // Keyboard focus is granted by WlrKeyboardFocus.OnDemand and
                    // searchInput.forceActiveFocus(); there is no layershell
                    // focusWindow() method (calling it threw a TypeError).
                    win.query = ""; searchInput.text = ""
                    win.focusIdx = -1
                    win._hideMenu()
                    win._dlg = { open: false }
                    win.selectMode = false; win.selectedIds = []; win._addToOpen = false
                    win.tab = HCCLauncherState.activeTab
                    if (win.tab === "clipboard") ClipboardState.refresh()
                    if (win.tab === "emoji") win.ensureGlyphData()
                    // Warm-up only once the persisted startup policies have been
                    // resolved, so a stored OFF is never raced (2a/3a).
                    if (win.tab === "websearch" && win.webEnabled && win._webResolved) win.webEnsureUp()
                    if (win.tab === "agent" && win._wsResolved) win.agentEnsureUp()
                    win.syncWebSurface()
                    Qt.callLater(function() {
                        if (win.tab === "websearch" || win.tab === "agent") { if (win.activeView) win.activeView.forceActiveFocus() }
                        else searchInput.forceActiveFocus()
                    })
                }
                // else: keep the SearXNG container warm (no teardown) so re-show
                // returns instantly and autostart can't wedge mid-toggle; persist the
                // open-tab model so the strip survives the transient-Loader teardown.
                else {
                    win.webSaveActive(); win.webSaveTabsState()
                    // Hidden = idle: start the cooldown after which the bounded HTTP
                    // disk cache is reclaimed (live pages keep in-memory state).
                    idleCacheTrim.restart()
                }
            }

            // Resolve the persisted workspace startup policy at session start and
            // warm the runtime if it is ON. FileView.onLoaded handles an existing
            // state file; this probe handles an absent one (default ON).
            Timer {
                id: wsInitProbe
                interval: 600
                repeat: false
                onTriggered: {
                    if (!win._wsResolved && !wsStateFile.exists) {
                        win._wsResolved = true
                        win.wsEnabled = true
                        win.ensureRuntimeBackend()
                    }
                }
            }
            // Resolve the persisted web-search startup policy at session start and
            // warm the SearXNG container if it is ON (the FileView.onLoaded path
            // handles an existing state file; this probe handles an absent one).
            Timer {
                id: webInitProbe
                interval: 650
                repeat: false
                onTriggered: {
                    if (!win._webResolved && !webStateFile.exists) {
                        win._webResolved = true
                        win.webEnabled = true
                        win.webEnsureUp()
                    }
                }
            }
            // Idle HTTP-cache reclamation: fires once per hide, only acting if the
            // window is still hidden when it elapses. clearHttpCache is async
            // (emits clearHttpCacheCompleted) and safe to call repeatedly.
            Timer {
                id: idleCacheTrim
                interval: 10 * 60 * 1000   // 10 min after the launcher is hidden
                repeat: false
                onTriggered: { if (!win.visible) win._webClearCache() }
            }

            // Boot is deferred to the first show (see onVisibleChanged) — the
            // window stays loaded across hide/show so web/agent pages keep running.
            Component.onCompleted: {
                // Deliberately does NOT create the WebEngine profile: it is built
                // lazily via _ensureWebProfile() the first time websearch or the
                // agent tab is actually used, so an idle launcher never boots
                // Chromium's browser/GPU/network threads or a renderer. (instance()
                // must also not run during component init -- it SIGSEGVs.)
            }

            // ── Backdrop: click outside the card dismisses ────────────────
            MouseArea {
                anchors.fill: parent
                onClicked: win.dismiss()
            }

            // ══════════════════════════════════════════════════════════════
            //  Card
            // ══════════════════════════════════════════════════════════════
            Rectangle {
                id: card
                width: win.cardW
                height: win.cardH
                x: win.isVert
                   ? (win.isVert && DockState.position === "left" ? win.edgeMargin
                       : win.width - win.edgeMargin - width)
                   : (win.width - width) / 2
                y: win.isVert ? (win.height - height) / 2
                   : (DockState.position === "top" ? win.edgeMargin
                       : win.height - win.edgeMargin - height)
                radius: Config.launcherBorderRadius
                color: Theme.blurBackground
                // GJS window shell: border-width ${bw}px + border-color @<borderColorVar>
                // — config.js holds borderColorVar: 'color6' (wallust), the same source
                // the bar/dock border uses → Config.barBorderColor (mode-aware resolve).
                border.width: Config.launcherBorderWidth
                border.color: Config.barBorderColor
                clip: true
                opacity: win.visible ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                readonly property int cols: Math.max(2, Math.floor(
                    (win.cardW - 52 - 24 + 2) / (Config.launcherFixedTileWidth + 2)))

                // ── Search row ────────────────────────────────────────────
                Item {
                    id: searchRow
                    x: win.ip; y: win.ip
                    width: parent.width - 2 * win.ip
                    height: 40
                    visible: !win.immersiveTab

                    readonly property real frac: Math.min(1, Math.max(0.2, Config.launcherSearchWidth))
                    readonly property real sfW: Math.max(120, Math.round(win.cardW * frac) - 2 * win.ip)

                    // Left slot — clipboard clear (GJS header slot parity)
                    Rectangle {
                        id: clipClearBtn
                        visible: win.tab === "clipboard"
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: clipClearText.implicitWidth + 24
                        height: 28
                        radius: 20
                        color: clipMa.containsMouse
                               ? Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.30)
                               : Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.14)
                        border.width: 1
                        border.color: Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.3)
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Text {
                            id: clipClearText
                            anchors.centerIn: parent
                            text: "\u{F00E2}  Clear history"
                            font.pixelSize: 11
                            color: Theme.cOnSurf   // header buttons: OnSurf text
                        }
                        MouseArea {
                            id: clipMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ClipboardState.clear()
                        }
                    }

                    // Left slot — icon-mode toggles (Emojis | Glyphs). Sits
                    // outside the list frame like the clipboard clear button.
                    Row {
                        visible: win.tab === "emoji"
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Repeater {
                            model: [{ k: "emoji", l: "Emojis" },
                                    { k: "nerd", l: "Glyphs" }]
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool active: win.iconMode === modelData.k
                                width: iconModeLbl.implicitWidth + 24
                                height: 28
                                radius: 20
                                color: active ? Qt.alpha(win.wColor3, 0.3)
                                       : modeMa.containsMouse
                                         ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                   Theme.cPrimary.b, 0.25)
                                         : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                   Theme.cPrimary.b, 0.15)
                                border.width: 1
                                border.color: active ? Qt.alpha(win.wColor3, 0.8)
                                          : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                    Theme.cPrimary.b, 0.3)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text {
                                    id: iconModeLbl
                                    anchors.centerIn: parent
                                    text: modelData.l
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Theme.cOnSurf   // header buttons: OnSurf text
                                }
                                MouseArea {
                                    id: modeMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (win.iconMode === modelData.k) return
                                        win.iconMode = modelData.k
                                        win.query = ""; searchInput.text = ""
                                    }
                                }
                            }
                        }
                    }

                    // Center — search field
                    Rectangle {
                        id: searchBox
                        x: (parent.width - width) / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.sfW
                        height: 38
                        // GJS .search-frame: pill radius + blur_background8 fill +
                        // 1px @primary 0.20 border (matugen/wallust via Theme).
                        radius: 99
                        color: Qt.rgba(Theme.cBackground.r, Theme.cBackground.g,
                                       Theme.cBackground.b, 0.65)
                        border.width: 1
                        // Same 1px @primary 0.20 as the list frame — shared
                        // subtle indented/concave look, no focus brightening.
                        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                              Theme.cPrimary.b, 0.2)

                        TextInput {
                            id: searchInput
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.cPrimary
                            cursorVisible: searchInput.activeFocus
                            font.pixelSize: 13
                            clip: true
                            onTextChanged: { win.query = text; win.focusIdx = -1; win._addToOpen = false }

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: win.placeholder()
                                color: Theme.cPrimary
                                opacity: 0.45
                                font: searchInput.font
                                visible: searchInput.text === ""   // GTK-style: stays while focused+empty
                            }

                            Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_Escape) {
                                    win.dismiss(); event.accepted = true
                                } else if (event.key === Qt.Key_Tab
                                           && (event.modifiers & Qt.ControlModifier)) {
                                    win.cycleTab(event.modifiers & Qt.ShiftModifier ? -1 : 1)
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    win.activateCurrent()
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Down) {
                                    win.moveFocus(1); event.accepted = true
                                } else if (event.key === Qt.Key_Up) {
                                    win.moveFocus(-1); event.accepted = true
                                } else if (event.key === Qt.Key_Right) {
                                    win.moveFocus(win.subTab === "apps" ? 1 : 0); event.accepted = true
                                } else if (event.key === Qt.Key_Left) {
                                    win.moveFocus(win.subTab === "apps" ? -1 : 0); event.accepted = true
                                }
                            }
                        }
                    }

                    // Right slot — (Select button moved into listFrame top-right)
                }

                // ── Inner list frame: [tab pill | pages] ──────────────────
                Rectangle {
                    id: listFrame
                    x: win.ip
                    y: win.immersiveTab ? win.ip
                       : searchRow.y + searchRow.height + Math.round(win.ip / 2)
                    width: parent.width - 2 * win.ip
                    height: parent.height - y - win.ip
                    radius: Config.launcherListRadius
                    // GJS .list-frame: same blur_background8 fill as the search
                    // field + 1px @primary 0.20 border.
                    color: Qt.rgba(Theme.cBackground.r, Theme.cBackground.g,
                                   Theme.cBackground.b, 0.65)
                    border.width: 1
                    border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                          Theme.cPrimary.b, 0.2)

                    // Vertical tab pill
                    Rectangle {
                        id: tabPill
                        width: 52
                        height: tabCol.implicitHeight + 12
                        radius: 30
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: win.immersiveTab
                            ? Math.round((searchRow.y + searchRow.height
                                          + Math.round(win.ip / 2) - win.ip) / 2)
                            : 0
                        color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                       Theme.cInversePrimary.b, 0.75)
                        border.width: 1
                        border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g,
                                              Theme.cScrim.b, 0.5)

                        Column {
                            id: tabCol
                            anchors.centerIn: parent
                            spacing: 6
                            Repeater {
                                model: [
                                    { id: "launcher",  glyph: "\u{F0D46}", tip: "Launcher" },
                                    { id: "clipboard", glyph: "\u{F0147}", tip: "Clipboard" },
                                    { id: "emoji",     glyph: "\u{EB54}", tip: "Icons" },
                                    { id: "websearch", glyph: "\u{F059F}", tip: "Web Search" },
                                    { id: "agent",     glyph: "\u{F06A9}", tip: "Agent" },
                                ]
                                delegate: Rectangle {
                                    id: tabBtn
                                    required property var modelData
                                    readonly property bool active: win.tab === modelData.id
                                    width: 36; height: 36
                                    radius: 18
                                    color: active ? Theme.cSurfaceTint
                                           : tabHover.hovered ? Theme.cOnSecondary
                                             : "transparent"
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    HoverHandler { id: tabHover }
                                    Text {
                                        anchors.centerIn: parent
                                        text: tabBtn.modelData.glyph
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 17
                                        color: tabBtn.active ? Theme.cOnSecondary
                                               : Theme.cSurfaceTint
                                    }
                                    TapHandler {
                                        onTapped: win.switchTab(tabBtn.modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    // ── Workspace ON/OFF circular toggle (tab-rail top) ──
                    // GJS's manual workspace start/stop button, ported: ON
                    // reveals the workspace + warms the Python runtime, OFF
                    // hides it and returns to the launcher tab. Sits above the
                    // tab pill (which is centred directly beneath it) with the
                    // workspace filling the area to the right, websearch-style.
                    Rectangle {
                        id: agentWsToggle
                        width: 40
                        height: 40
                        radius: 20
                        visible: win.tab === "agent"
                        anchors.horizontalCenter: tabPill.horizontalCenter
                        anchors.bottom: tabPill.top
                        anchors.bottomMargin: 10
                        color: win.wsEnabled
                               ? Theme.cPrimary
                               : Qt.rgba(Theme.cSurface.r, Theme.cSurface.g, Theme.cSurface.b, 0.10)
                        border.width: 1.5
                        border.color: win.wsEnabled
                                   ? Theme.cPrimary
                                   : Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.40)
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            anchors.centerIn: parent
                            // Nerd Font MDI eye pair: nf-md-eye (ON) / nf-md-eye_off (OFF).
                            text: win.wsEnabled ? "\u{F0208}" : "\u{F0209}"
                            font.family: Theme.fontFamily
                            font.pixelSize: 20
                            color: win.wsEnabled ? Theme.cOnPrimary : Theme.cOnSurf
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.agentToggleWorkspace()
                        }
                    }

                    // ── Web-search ON/OFF circular toggle (tab-rail top) ──
                    // Mirrors the workspace toggle: ON warms the SearXNG container
                    // (kept running from launcher startup) and reveals the live view;
                    // OFF stops the container, forgets the open tabs and blanks the
                    // shared view. Only one of this / the workspace toggle is visible
                    // at a time (websearch vs agent), so both anchor above the pill.
                    Rectangle {
                        id: webSearchToggle
                        width: 40
                        height: 40
                        radius: 20
                        visible: win.tab === "websearch"
                        anchors.horizontalCenter: tabPill.horizontalCenter
                        anchors.bottom: tabPill.top
                        anchors.bottomMargin: 10
                        color: win.webEnabled
                               ? Theme.cPrimary
                               : Qt.rgba(Theme.cSurface.r, Theme.cSurface.g, Theme.cSurface.b, 0.10)
                        border.width: 1.5
                        border.color: win.webEnabled
                                   ? Theme.cPrimary
                                   : Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.40)
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            anchors.centerIn: parent
                            // Nerd Font MDI eye pair: nf-md-eye (ON) / nf-md-eye_off (OFF).
                            text: win.webEnabled ? "\u{F0208}" : "\u{F0209}"
                            font.family: Theme.fontFamily
                            font.pixelSize: 20
                            color: win.webEnabled ? Theme.cOnPrimary : Theme.cOnSurf
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.webToggleEnabled()
                        }
                    }

                    // ── Launcher tab: inline header strip ────────────────
                    // Spans the full list-frame width (the tab pill is
                    // vertically centred, so it never collides): switcher
                    // far left, favorites pill centred, select/create right.
                    Row {
                        id: launcherSubRow
                        anchors.top: parent.top
                        anchors.topMargin: 6
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        height: visible ? 34 : 0
                        visible: win.tab === "launcher"
                        spacing: 8
                        CCSegmented {
                            id: appsGroupsSeg
                            anchors.verticalCenter: parent.verticalCenter
                            options: [{ key: "apps", label: "Apps" },
                                      { key: "groups", label: "Groups" }]
                            current: win.subTab
                            onPicked: key => { win.subTab = key; win.focusIdx = -1 }
                        }
                        // Left spacer — centres the favorites pill on the
                        // full frame width (true centre, not between-gaps).
                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            height: parent.height
                            visible: win.subTab === "apps"
                                     && win.favoriteApps.length > 0
                                     && !win.selectMode
                            width: Math.max(0, (launcherSubRow.width - favPill.width) / 2
                                            - appsGroupsSeg.width
                                            - 2 * launcherSubRow.spacing)
                        }
                        Rectangle {
                            id: favPill
                            anchors.verticalCenter: parent.verticalCenter
                            visible: win.subTab === "apps"
                                     && win.favoriteApps.length > 0
                                     && !win.selectMode
                            width: favHeaderRow.implicitWidth + 24
                            height: 26
                            radius: 99
                            color: favHeaderMa.containsMouse
                                   ? Qt.rgba(Theme.cSecondaryContainer.r,
                                             Theme.cSecondaryContainer.g,
                                             Theme.cSecondaryContainer.b, 0.45)
                                   : "transparent"
                            Behavior on color { ColorAnimation { duration: 110 } }
                            Row {
                                id: favHeaderRow
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "\u{F06D0}"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                    color: win.wColor2
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Favorites"
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: Theme.cPrimary
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: win.favCollapsed ? "\u{F0B2C}" : "\u{F0B26}"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                    color: Theme.cPrimary
                                }
                            }
                            MouseArea {
                                id: favHeaderMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.favCollapsed = !win.favCollapsed
                            }
                        }
                    }

                    // Top-right of the list frame — multi-select toggle that
                    // morphs into the create-group action (OnSecondary bg +
                    // Primary text) once apps are selected.
                    Rectangle {
                        id: selectBtn
                        visible: win.tab === "launcher" && win.subTab === "apps"
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.top: parent.top
                        anchors.topMargin: 8
                        z: 6
                        readonly property bool creating: win.selectMode && win.selectedIds.length > 0
                        width: selectBtnText.implicitWidth + 24
                        height: 28
                        radius: 14
                        color: win.selectMode ? Theme.cOnSecondary
                               : selMa.containsMouse
                                 ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                           Theme.cPrimary.b, 0.10)
                                 : "transparent"
                        border.width: 1
                        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                              Theme.cPrimary.b, 0.3)
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Text {
                            id: selectBtnText
                            anchors.centerIn: parent
                            text: selectBtn.creating
                                     ? "\u{F0028} Create (" + win.selectedIds.length + ")"
                                   : win.selectMode ? "\u{F0156} Cancel" : "\u{F012E} Select"
                            font.pixelSize: 11
                            font.bold: selectBtn.creating || win.selectMode
                            color: Theme.cPrimary
                        }
                        MouseArea {
                            id: selMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                win._addToOpen = false
                                if (selectBtn.creating) {
                                    win._dlg = {
                                        open: true, mode: "newgroup",
                                        ids: win.selectedIds.slice(),
                                        title: "New group (" + win.selectedIds.length + " apps)"
                                    }
                                } else if (win.selectMode) {
                                    win.selectMode = false
                                    win.selectedIds = []
                                } else {
                                    win.selectMode = true
                                }
                            }
                        }
                    }

                    // ── Selection-mode actions (left of the Select/Create pill) ──
                    // "Unselect all" clears the selection; "Add to:" opens a popup
                    // listing Favorites + every existing group so the selected apps
                    // can be added without creating a new group. Both show only in
                    // selection mode; the popup mirrors the right-click menu styling
                    // (OnSecondary bg, scrim border, Primary-tinted row hover).
                    Rectangle {
                        id: unselectBtn
                        visible: win.tab === "launcher" && win.subTab === "apps"
                                 && win.selectMode && win.selectedIds.length > 0
                        anchors.right: addToBtn.left
                        anchors.rightMargin: 6
                        anchors.top: parent.top
                        anchors.topMargin: 8
                        z: 6
                        width: unselectText.implicitWidth + 24
                        height: 28
                        radius: 14
                        color: unselectMa.containsMouse
                               ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.10)
                               : "transparent"
                        border.width: 1
                        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.3)
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Text {
                            id: unselectText
                            anchors.centerIn: parent
                            text: "Unselect all"
                            font.pixelSize: 11
                            font.bold: true
                            color: Theme.cPrimary
                        }
                        MouseArea {
                            id: unselectMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.selectedIds = []
                        }
                    }

                    Rectangle {
                        id: addToBtn
                        visible: win.tab === "launcher" && win.subTab === "apps" && win.selectMode
                        anchors.right: selectBtn.left
                        anchors.rightMargin: 6
                        anchors.top: parent.top
                        anchors.topMargin: 8
                        z: 6
                        opacity: win.selectedIds.length > 0 ? 1 : 0.45
                        width: addToText.implicitWidth + 24
                        height: 28
                        radius: 14
                        color: win._addToOpen ? Theme.cOnSecondary
                               : addToMa.containsMouse
                                 ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.10)
                                 : "transparent"
                        border.width: 1
                        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.3)
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Text {
                            id: addToText
                            anchors.centerIn: parent
                            text: "Add to:  \u{F0140}"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                            color: Theme.cPrimary
                        }
                        MouseArea {
                            id: addToMa
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: win.selectedIds.length > 0
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.toggleAddTo()
                        }
                    }

                    // Click-away scrim for the "Add to:" popup.
                    MouseArea {
                        id: addToScrim
                        anchors.fill: parent
                        visible: win._addToOpen
                        z: 39
                        onClicked: win._addToOpen = false
                    }

                    // ── "Add to:" popup — Favorites + existing groups ──────
                    Rectangle {
                        id: addToMenu
                        visible: win._addToOpen
                        z: 40
                        anchors.top: addToBtn.bottom
                        anchors.topMargin: 6
                        anchors.right: addToBtn.right
                        width: 220
                        height: Math.min(addToCol.implicitHeight + 12, listFrame.height - 16)
                        radius: 14
                        color: Theme.cOnSecondary
                        border.width: 1
                        border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.5)
                        clip: true

                        Flickable {
                            anchors.fill: parent
                            anchors.margins: 6
                            contentHeight: addToCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            Column {
                                id: addToCol
                                width: parent.width
                                spacing: 0

                                Item {
                                    width: parent.width; height: 22
                                    Text {
                                        anchors.left: parent.left; anchors.leftMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Add " + win.selectedIds.length + " app"
                                              + (win.selectedIds.length === 1 ? "" : "s") + " to"
                                        font.pixelSize: 10; font.bold: true
                                        color: Qt.alpha(Theme.cPrimary, 0.7)
                                    }
                                }

                                // Favorites target
                                Rectangle {
                                    width: addToCol.width; height: 30; radius: 8
                                    color: favRowMa.containsMouse
                                           ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.14)
                                           : "transparent"
                                    Behavior on color { ColorAnimation { duration: 110 } }
                                    Row {
                                        anchors.left: parent.left; anchors.leftMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{F06D0}"; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.cPrimary }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Favorites"; font.pixelSize: 12; color: Theme.cOnSurf }
                                    }
                                    MouseArea {
                                        id: favRowMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: win.addSelectedTo(true, "")
                                    }
                                }

                                Item {
                                    width: addToCol.width; height: 9
                                    visible: addToRepeater.count > 0
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width - 12; height: 1
                                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.18)
                                    }
                                }

                                Repeater {
                                    id: addToRepeater
                                    model: win._addToGroups
                                    delegate: Rectangle {
                                        required property string modelData
                                        width: addToCol.width; height: 30; radius: 8
                                        color: grpRowMa.containsMouse
                                               ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.14)
                                               : "transparent"
                                        Behavior on color { ColorAnimation { duration: 110 } }
                                        Text {
                                            anchors.left: parent.left; anchors.leftMargin: 8
                                            anchors.right: parent.right; anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData
                                            font.pixelSize: 12; color: Theme.cOnSurf
                                            elide: Text.ElideRight
                                        }
                                        MouseArea {
                                            id: grpRowMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: win.addSelectedTo(false, modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Page area
                    Item {
                        id: pageArea
                        anchors.left: tabPill.right
                        anchors.leftMargin: 4
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.top: launcherSubRow.bottom
                        anchors.bottom: parent.bottom
                        anchors.topMargin: 2
                        anchors.bottomMargin: 6

                        // ── Apps page ─────────────────────────────────────
                        Flickable {
                            id: appsFlick
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            visible: win.tab === "launcher" && win.subTab === "apps"
                            contentHeight: appsCol.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true
                            onVisibleChanged: if (visible) contentY = 0

                            Column {
                                id: appsCol
                                width: appsFlick.width
                                spacing: 2

                                // Favorites grid (collapsible via the header
                                // pill in launcherSubRow, collapsed default)
                                Column {
                                    width: parent.width
                                    // Hidden during a search (the filtered grid already
                                    // includes matching favorites, so this would only add
                                    // unfiltered clutter) and in selection mode (the grid
                                    // then lists every app — favorites included — so all are
                                    // selectable in one place).
                                    visible: win.favoriteApps.length > 0
                                             && win.q === "" && !win.selectMode
                                    Grid {
                                        visible: !win.favCollapsed
                                        columns: card.cols
                                        spacing: 2
                                        Repeater {
                                            model: win.favoriteApps
                                            AppTile {
                                                required property var modelData
                                                rec: modelData
                                                groupCtx: ""
                                            }
                                        }
                                    }
                                    Rectangle {
                                        visible: !win.favCollapsed && win.favoriteApps.length > 0
                                        width: parent.width
                                        height: 1
                                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                       Theme.cPrimary.b, 0.16)
                                    }
                                }

                                // Main app grid
                                Grid {
                                    id: appsGrid
                                    width: parent.width
                                    columns: card.cols
                                    spacing: 2
                                    Repeater {
                                        model: win.filteredApps
                                        AppTile {
                                            required property var modelData
                                            required property int index
                                            rec: modelData
                                            groupCtx: ""
                                            keyboardFocused: win.focusIdx === index
                                        }
                                    }
                                }
                            }
                        }

                        // ── Groups page ───────────────────────────────────
                        Flickable {
                            id: groupsFlick
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            visible: win.tab === "launcher" && win.subTab === "groups"
                            contentHeight: groupsGrid.implicitHeight + 8
                                           + (win._anyGroupExpanded ? 150 : 0)
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true

                            // Lightbox exit — a click on the empty backdrop
                            // collapses any expanded group.
                            MouseArea {
                                x: 0; y: groupsFlick.contentY
                                width: groupsFlick.width
                                height: groupsFlick.height
                                enabled: win._anyGroupExpanded
                                onClicked: win.expandedGroups = ({})
                            }

                            Grid {
                                id: groupsGrid
                                x: 2; y: 2
                                columns: Math.max(1, Math.floor(
                                    (pageArea.width + 8) / (win.groupCardSize + 8)))
                                spacing: 8
                                Repeater {
                                    model: win.groupCards
                                    delegate: GroupCard {
                                        required property var modelData
                                        cardName: modelData.name
                                        cardApps: modelData.apps
                                    }
                                }
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: win.groupCards.length === 0
                                text: win.q === "" ? "No groups yet — right-click an app to create one"
                                                   : "No matching groups"
                                font.pixelSize: 12
                                color: Theme.cOnSurf
                                opacity: 0.55
                            }
                        }

                        // ── Clipboard page ────────────────────────────────
                        ListView {
                            id: clipList
                            anchors.fill: parent
                            visible: win.tab === "clipboard"
                            clip: true
                            spacing: 2
                            boundsBehavior: Flickable.StopAtBounds
                            model: win.clipFiltered
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                width: clipList.width
                                height: clipRow.implicitHeight + 20
                                radius: 16
                                color: clipRowMa.containsMouse
                                       ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                 Theme.cPrimary.b, 0.08)
                                       : "transparent"
                                border.width: clipRowMa.containsMouse ? 1 : 0
                                border.color: Qt.rgba(win.wColor3.r, win.wColor3.g,
                                                      win.wColor3.b, 0.18)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text {
                                    id: clipRow
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    text: modelData.text
                                    font.pixelSize: 12
                                    color: Theme.cOnSurf
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                                MouseArea {
                                    id: clipRowMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        ClipboardState.restore(modelData.raw)
                                        HCCLauncherState.close()
                                    }
                                }
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: clipList.count === 0
                                text: ClipboardState.failed ? "cliphist not found"
                                      : ClipboardState.loading ? "Loading\u2026"
                                                               : "No clipboard history found"
                                font.pixelSize: 12
                                color: Theme.cOnSurf
                                opacity: 0.55
                            }
                        }

                        // ── Icons page (Emojis | Glyphs, glyphData.json) ──
                        Item {
                            anchors.fill: parent
                            visible: win.tab === "emoji"

                            Column {
                                id: iconPage
                                anchors.fill: parent
                                spacing: 6

                                // Category buttons — .emoji-cat-btn recipe
                                Row {
                                    spacing: 2
                                    Repeater {
                                        model: win.iconMode === "nerd"
                                               ? win.nerdCats : win.emojiGroups
                                        delegate: Rectangle {
                                            required property var modelData
                                            required property int index
                                            readonly property bool active: win.iconMode === "nerd"
                                                                          ? win.nerdCat === index
                                                                          : win.emojiGroup === index
                                            width: 40; height: 34
                                            radius: 6
                                            color: active ? Qt.rgba(Theme.cInversePrimary.r,
                                                                    Theme.cInversePrimary.g,
                                                                    Theme.cInversePrimary.b, 0.45)
                                                   : catMa.containsMouse
                                                     ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                               Theme.cPrimary.b, 0.08)
                                                     : "transparent"
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.glyph ?? ""
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 22
                                                color: Theme.cPrimary
                                            }
                                            MouseArea {
                                                id: catMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (win.iconMode === "nerd") win.nerdCat = index
                                                    else win.emojiGroup = index
                                                }
                                            }
                                        }
                                    }
                                }

                                Text {
                                    visible: !win.glyphReady
                                    text: "Loading glyph data\u2026"
                                    font.pixelSize: 12
                                    color: Theme.cOnSurf
                                    opacity: 0.55
                                }

                                // Cell grid (GJS FlowBox: 42px cells)
                                Flickable {
                                    width: parent.width
                                    height: iconPage.height - y
                                    visible: win.glyphReady
                                    contentHeight: iconGridCol.implicitHeight
                                    contentWidth: width
                                    boundsBehavior: Flickable.StopAtBounds
                                    clip: true
                                    Column {
                                        id: iconGridCol
                                        width: parent.width
                                        spacing: 4
                                        Grid {
                                            id: iconGrid
                                            columns: Math.max(6,
                                                       Math.floor(iconGrid.width / 46))
                                            spacing: 4
                                            width: parent.width
                                            Repeater {
                                                // Cap keeps QML responsive on broad
                                                // nerd searches (GJS FlowBox was no
                                                // faster at 10k buttons).
                                                model: win.iconCells.slice(0, 600)
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    width: 42; height: 42
                                                    radius: 8
                                                    color: cellMa.containsMouse
                                                           ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                                     Theme.cPrimary.b, 0.1)
                                                           : "transparent"
                                                    Behavior on color { ColorAnimation { duration: 100 } }
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: modelData.c ?? ""
                                                        font.family: win.iconMode === "nerd"
                                                                     ? Theme.fontFamily : ""
                                                        font.pixelSize: win.iconMode === "nerd" ? 30 : 22
                                                        color: Theme.cPrimary
                                                    }
                                                    MouseArea {
                                                        id: cellMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: win.copyGlyph(modelData.c)
                                                        onContainsMouseChanged: {
                                                            const nm = modelData.n ?? ""
                                                            if (containsMouse) win.hoveredIconName = nm
                                                            else if (win.hoveredIconName === nm) win.hoveredIconName = ""
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        Text {
                                            visible: win.iconCells.length > 600
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: (win.iconCells.length - 600)
                                                 + " more \u2014 refine the search"
                                            font.pixelSize: 11
                                            color: Theme.cOnSurf
                                            opacity: 0.55
                                        }
                                    }
                                }
                            }

                            // Hover readout — in-card (no Controls popup, which
                            // would not composite on the override surface): shows
                            // the name of the emoji / glyph under the cursor in the
                            // free top-right corner (the grid scrolls beneath it).
                            Text {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.rightMargin: 8
                                anchors.topMargin: 6
                                width: Math.min(implicitWidth, Math.round(parent.width / 2))
                                horizontalAlignment: Text.AlignRight
                                visible: win.hoveredIconName !== ""
                                text: win.hoveredIconName
                                font.pixelSize: 11
                                color: Theme.cOnSurf
                                opacity: 0.7
                                elide: Text.ElideLeft
                            }

                            // Copied feedback bar — .emoji-copied-bar recipe
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottomMargin: 4
                                visible: win.copiedChar !== ""
                                width: copiedLbl.implicitWidth + 28
                                height: copiedLbl.implicitHeight + 10
                                radius: 8
                                color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                               Theme.cInversePrimary.b, 0.85)
                                Text {
                                    id: copiedLbl
                                    anchors.centerIn: parent
                                    text: win.copiedChar + "  Copied"
                                    font.pixelSize: 12
                                    color: Theme.cPrimary
                                }
                            }
                        }
                        // ── Dormant web-search card (policy OFF) ───────────
                        // Shown on the websearch tab when the SearXNG container is
                        // OFF. Mirrors the GJS dormant workspace: no view is spun up
                        // (spawning a second one would be fatal), the toggle re-arms it.
                        Rectangle {
                            visible: win.tab === "websearch" && !win.webEnabled
                            x: tabPill.x + tabPill.width + win.ip - pageArea.x
                            y: win.ip - pageArea.y
                            width: listFrame.width - tabPill.x - tabPill.width - 2 * win.ip
                            height: listFrame.height - 2 * win.ip
                            radius: 12
                            color: Qt.rgba(Theme.cSurface.r, Theme.cSurface.g, Theme.cSurface.b, 0.2)
                            //border.width: 1
                            //border.color: Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.22)
                        }
                        // ── Web-Search tab: persistent embedded SearXNG webview ──
                        // No native list-mode. SearXNG (docker @ searxBase) renders its
                        // own UI + search field inside a WebEngineView, like a browser.
                        // The frame fills the list area to the top with uniform padding
                        // (header is hidden on this tab); a slim nav toolbar (back /
                        // forward / reload / home) + read-only address + bookmark sits
                        // above it. forceDarkMode gives every site Chromium auto-dark;
                        // the surface colour follows the qs theme. The view is a plain
                        // child (not a transient Loader) so minimise/re-show keeps it.
                        Item {
                            id: webSearchPage
                            anchors.fill: parent
                            // Per-tab view pool surface: hosts ONE WebEngineView per
                            // websearch tab (plus the separate persistent agentView for
                            // the workspace) — all sharing the single win.webProfile, so
                            // switching tabs/round-tripping never reloads a page. On the
                            // websearch tab only the active tab's view renders; a dormant
                            // websearch shows the enable card instead. Chrome overlays
                            // gate to websearch.
                            visible: win.tab === "agent" || (win.tab === "websearch" && win.webEnabled)
                            onVisibleChanged: if (visible) win.syncWebSurface()

                            // Small glyph toolbar button used by the nav row.
                            component WebNavBtn: Rectangle {
                                required property string glyph
                                required property color tint
                                required property var handler
                                property int glyphSize: 15
                                width: 34; height: 30; radius: 8
                                color: wnMa.containsMouse
                                       ? Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.70)
                                       : Qt.rgba(Theme.cSurface.r, Theme.cSurface.g, Theme.cSurface.b, 0.45)
                                border.width: 1
                                border.color: Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.22)
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.glyph
                                    font.family: Theme.fontFamily
                                    font.pixelSize: parent.glyphSize
                                    color: parent.tint
                                }
                                MouseArea {
                                    id: wnMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: parent.enabled
                                    cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: parent.handler()
                                }
                            }

                            Rectangle {
                                id: webFrame
                                // webSearchPage lives inside pageArea (already inset from
                                // listFrame), so use explicit geometry referencing listFrame /
                                // tabPill / pageArea to sit exactly win.ip inside the list frame.
                                x: tabPill.x + tabPill.width + win.ip - pageArea.x
                                y: win.ip - pageArea.y
                                width: listFrame.width - tabPill.x - tabPill.width - 2 * win.ip
                                height: listFrame.height - 2 * win.ip
                                clip: true
                                radius: 12
                                color: Qt.rgba(Theme.cSurface.r, Theme.cSurface.g, Theme.cSurface.b, 0.2)
                                border.width: 0
                                border.color: Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.22)

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 0
                                    spacing: 6

                                    // ── Collapsed-header REVEAL hotspot (websearch) ─────
                                    // When the chrome rows are folded this thin rounded
                                    // handle is all that shows; hover expands, double-click
                                    // pins open. Collapse is EXPLICIT only (chevron-up) —
                                    // the old auto-collapse-on-exit raced the native view's
                                    // event grabbing and folded the header unexpectedly.
                                    Rectangle {
                                        visible: win.tab === "websearch" && win.webEnabled
                                                 && !win.webHeaderShown
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 8
                                        Layout.rightMargin: 8
                                        Layout.topMargin: 6
                                        Layout.preferredHeight: 6
                                        radius: 3
                                        color: Qt.rgba(Theme.cSurface.r, Theme.cSurface.g, Theme.cSurface.b, 0.55)
                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onEntered: win.webHeaderHover = true
                                            onDoubleClicked: win.webHeaderPinned = !win.webHeaderPinned
                                        }
                                    }

                                    // ── Tab strip (websearch only) ───────────────
                                    // Real browser-style tabs — each tab owns a pooled
                                    // WebEngineView (below): clicking switches the visible
                                    // view; "+" opens SearXNG in a new tab; the trailing
                                    // glyph closes one (tearing its view down). The active
                                    // tab shows the live view title via win.activeView.
                                    RowLayout {
                                        visible: win.webHeaderShown && win.webFullscreenTabId < 0
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 8
                                        Layout.rightMargin: 8
                                        Layout.topMargin: 8
                                        spacing: 4
                                        Repeater {
                                            model: (win.webRev, win.webTabs)
                                            delegate: Rectangle {
                                                required property int index
                                                required property var modelData
                                                Layout.preferredWidth: Math.min(170, Math.max(92, tabLbl.implicitWidth + 42))
                                                Layout.preferredHeight: 28
                                                radius: 8
                                                color: index === win.activeWebTab
                                                       ? Qt.rgba(Theme.cSurface.r, Theme.cSurface.g, Theme.cSurface.b, 0.72)
                                                       : "transparent"
                                                border.width: 1
                                                border.color: Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.18)
                                                RowLayout {
                                                    // Above the switch MouseArea below so the
                                                    // per-tab close glyph stays clickable.
                                                    z: 2
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 4
                                                    spacing: 4
                                                    Text {
                                                        id: tabLbl
                                                        Layout.fillWidth: true
                                                        text: (win.webRev, index === win.activeWebTab && win.tab === "websearch" && win.activeView)
                                                              ? (win.activeView.title || (win.activeView.url ? win.activeView.url.toString() : "New Tab"))
                                                              : (modelData.title || modelData.url || "New Tab")
                                                        elide: Text.ElideRight
                                                        font.pixelSize: 11
                                                        color: index === win.activeWebTab ? Theme.cOnSurf : Qt.alpha(Theme.cOnSurf, 0.65)
                                                    }
                                                    Item {
                                                        Layout.preferredWidth: 18; Layout.preferredHeight: 18
                                                        visible: win.webTabs.length > 1
                                                        Text { anchors.centerIn: parent; text: "\u{F0156}"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Qt.alpha(Theme.cOnSurf, 0.6) }
                                                        MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.webCloseTab(index) }
                                                    }
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    // Click switches tab; press-and-drag horizontally
                                                    // past ~60% of a tab reorders it (webMoveTab).
                                                    property real _sx: 0
                                                    property int _di: -1
                                                    onPressed: function (m) { _sx = m.x; _di = index }
                                                    onPositionChanged: function (m) {
                                                        if (_di < 0) return
                                                        const dx = m.x - _sx
                                                        const w = parent.width || 1
                                                        if (dx > w * 0.6 && _di < win.webTabs.length - 1) {
                                                            win.webMoveTab(_di, _di + 1); _di++; _sx = m.x
                                                        } else if (dx < -w * 0.6 && _di > 0) {
                                                            win.webMoveTab(_di, _di - 1); _di--; _sx = m.x
                                                        }
                                                    }
                                                    onReleased: {
                                                        if (_di === index) win.webSwitchTab(index)
                                                        _di = -1
                                                    }
                                                }
                                            }
                                        }
                                        // New tab.
                                        Rectangle {
                                            Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 8
                                            color: "transparent"
                                            border.width: 1
                                            border.color: Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.18)
                                            Text { anchors.centerIn: parent; text: "\u{F0415}"; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.cOnSurf }
                                            MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.webNewTab("") }
                                        }
                                        Item { Layout.fillWidth: true }

                                        // ── Collapse-header toggle (chevron-up) ──────────
                                        // The single explicit way to fold the chrome: the
                                        // native WebEngineView swallows hover so auto-collapse
                                        // on pointer-exit never worked reliably anyway. Fold
                                        // here, re-expand via the reveal hotspot above.
                                        Rectangle {
                                            Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 8
                                            color: collapseMa.containsMouse
                                                   ? Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.70)
                                                   : "transparent"
                                            border.width: 1
                                            border.color: Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.18)
                                            Text { anchors.centerIn: parent; text: "\u{F0143}"; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.cOnSurf }
                                            MouseArea {
                                                id: collapseMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    win.webHeaderPinned = false
                                                    win.webHeaderHover = false
                                                }
                                            }
                                        }
                                    }

                                    // ── Nav toolbar ──────────────────────────────
                                    // Order: home · reload · back · address bar ·
                                    // forward · bookmark toggle · bookmarks library ·
                                    // clear-credentials. The old leading "back to
                                    // launcher" glyph is gone (the tab-pill already
                                    // carries the apps toggle). back/forward/home use
                                    // a larger glyph so they match the reload circle.
                                    RowLayout {
                                        visible: win.webHeaderShown && win.webFullscreenTabId < 0
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 10
                                        Layout.rightMargin: 10
                                        Layout.topMargin: 10
                                        Layout.bottomMargin: 2
                                        spacing: 6
                                        WebNavBtn { glyphSize: 19; glyph: "\u{2302}"; tint: Theme.cOnSurf; handler: function () { win.webNavigateActive(win.searxBase) } }
                                        WebNavBtn { glyph: "\u{F0453}"; tint: Theme.cOnSurf; handler: function () { if (win.activeView) win.activeView.reload() } }
                                        WebNavBtn {
                                            glyphSize: 19
                                            glyph: "\u{21B6}"; enabled: win.activeView ? win.activeView.canGoBack : false
                                            tint: (win.webRev, win.activeView && win.activeView.canGoBack) ? Theme.cOnSurf : Qt.alpha(Theme.cOnSurf, 0.35)
                                            handler: function () { if (win.activeView && win.activeView.canGoBack) win.activeView.goBack() }
                                        }

                                        // Editable address bar: shows the live URL, but
                                        // the user can type/paste a URL (or a search)
                                        // and press Enter / the go-arrow to navigate.
                                        Rectangle {
                                            Layout.fillWidth: true; Layout.preferredHeight: 30; radius: 8
                                            color: urlInput.activeFocus
                                                   ? Qt.rgba(Theme.cSurface.r, Theme.cSurface.g, Theme.cSurface.b, 0.82)
                                                   : Qt.rgba(Theme.cSurface.r, Theme.cSurface.g, Theme.cSurface.b, 0.55)
                                            border.width: 1
                                            border.color: urlInput.activeFocus ? Theme.cPrimary
                                                       : Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.20)
                                            RowLayout {
                                                anchors { fill: parent; leftMargin: 10; rightMargin: 6 }
                                                spacing: 4
                                                TextInput {
                                                    id: urlInput
                                                    Layout.fillWidth: true
                                                    Layout.alignment: Qt.AlignVCenter
                                                    color: Theme.cOnSurf
                                                    font.pixelSize: 11
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    clip: true
                                                    selectByMouse: true
                                                    persistentSelection: false
                                                    selectionColor: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.1)
                                                    function _sync() { urlInput.text = win._urlDisplayText() }
                                                    function _go() {
                                                        var raw = urlInput.text.trim()
                                                        urlInput.focus = false
                                                        if (!raw) { urlInput._sync(); return }
                                                        if (!/^[a-zA-Z][a-zA-Z0-9+.\-]*:\/\//.test(raw)) {
                                                            if (/^(localhost|\d{1,3}(\.\d{1,3}){3})(:\d+)?(\/.*)?$/.test(raw)
                                                                || /^[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}(:\d+)?(\/.*)?$/.test(raw))
                                                                raw = "https://" + raw
                                                            else
                                                                raw = win.searxBase + "?q=" + encodeURIComponent(raw)
                                                        }
                                                        win.webNavigateActive(raw)
                                                    }
                                                    Component.onCompleted: urlInput._sync()
                                                    onActiveFocusChanged: {
                                                        if (activeFocus) { urlInput.text = win._urlBarText(); urlInput.selectAll() }
                                                        else urlInput._sync()
                                                    }
                                                    onAccepted: urlInput._go()
                                                    Keys.onEscapePressed: { urlInput._sync(); urlInput.focus = false }
                                                    Connections {
                                                        target: win
                                                        function onWebRevChanged() { if (!urlInput.activeFocus) urlInput._sync() }
                                                    }
                                                }
                                                // Go arrow — only while editing the field.
                                                Item {
                                                    Layout.preferredWidth: 22; Layout.preferredHeight: 22
                                                    visible: urlInput.activeFocus
                                                    Text { anchors.centerIn: parent; text: "\u{EA9F}"; font.family: Theme.fontFamily; font.pixelSize: 15; color: Theme.cPrimary }
                                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: urlInput._go() }
                                                }
                                            }
                                        }

                                        WebNavBtn {
                                            glyphSize: 19
                                            glyph: "\u{21B7}"; enabled: win.activeView ? win.activeView.canGoForward : false
                                            tint: (win.webRev, win.activeView && win.activeView.canGoForward) ? Theme.cOnSurf : Qt.alpha(Theme.cOnSurf, 0.35)
                                            handler: function () { if (win.activeView && win.activeView.canGoForward) win.activeView.goForward() }
                                        }

                                        // Bookmark the page currently shown (checked when saved).
                                        WebNavBtn {
                                            glyph: (win.webRev, WebBookmarksState.isBookmarked(win.activeView ? win.activeView.url : "")) ? "\u{F00C1}" : "\u{F00C0}"
                                            tint: (win.webRev, WebBookmarksState.isBookmarked(win.activeView ? win.activeView.url : "")) ? Theme.cPrimary : Theme.cOnSurf
                                            handler: function () { if (win.activeView) win.webToggleBookmark(win.activeView.url, win.activeView.title) }
                                        }

                                        // Open the saved-bookmarks library.
                                        WebNavBtn {
                                            glyph: "\u{F00C3}"
                                            tint: win.webShowBookmarks ? Theme.cPrimary : Theme.cOnSurf
                                            handler: function () { win.webShowBookmarks = !win.webShowBookmarks; win.webShowCredentials = false }
                                        }

                                        // Open the saved-credentials (cookies) library.
                                        WebNavBtn {
                                            glyph: "\u{EDE4}"
                                            tint: win.webShowCredentials ? Theme.cPrimary : Theme.cOnSurf
                                            handler: function () {
                                                win.webShowCredentials = !win.webShowCredentials
                                                win.webShowBookmarks = false
                                                if (win.webShowCredentials) win.webRefreshCredOrigins()
                                            }
                                        }

                                        // Ad/tracker blocker toggle (shield-check ON /
                                        // shield-off dim). Re-injects the blocker into
                                        // every live tab and reloads them.
                                        WebNavBtn {
                                            glyph: win.webAdBlockEnabled ? "\u{F0565}" : "\u{F099E}"
                                            tint: win.webAdBlockEnabled ? Theme.cPrimary : Qt.alpha(Theme.cOnSurf, 0.4)
                                            handler: function () { win.webToggleAdBlock() }
                                        }

                                        // Open the current page in the system default
                                        // browser (nf-md-web) -- handy for sites that want
                                        // a real Chrome, WebAuthn, or downloads the
                                        // embedded view can't handle.
                                        WebNavBtn {
                                            glyph: "\u{F059F}"
                                            tint: Theme.cOnSurf
                                            handler: function () {
                                                var v = win.activeView
                                                if (v && v.url) Qt.openUrlExternally(v.url.toString())
                                            }
                                        }
                                    }

                                    // Thin progress bar while loading (active view).
                                    // Websearch tab only — the agent workspace lives in
                                    // its own tab and has no header / URL bar to fill.
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: (win.webRev, win.tab === "websearch" && win.webFullscreenTabId < 0 && win.activeView && win.activeView.loading) ? 3 : 0
                                        visible: (win.webRev, win.tab === "websearch" && win.webFullscreenTabId < 0 && !!(win.activeView && win.activeView.loading))
                                        radius: 2
                                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.18)
                                        Rectangle {
                                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                            width: parent.width * ((win.webRev, win.activeView ? win.activeView.loadProgress : 0) / 100)
                                            radius: 2
                                            color: Theme.cPrimary
                                        }
                                    }

                                    // ── The web view + SearXNG-down overlay ──────
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        // Rounded wrap (12px on all four corners, workspace
                                        // included): QtQuick clip is rectangular and ignores
                                        // radius, so the rounding comes from a layer mask.
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            maskEnabled: true
                                            maskSource: webMask
                                            maskThresholdMin: 0.5
                                            maskSpreadAtMin: 1.0
                                        }
                                        Item {
                                            id: webMask
                                            anchors.fill: parent
                                            opacity: 0
                                            layer.enabled: true
                                            // Single rounded rect masks all four corners (per-corner
                                            // group props are unsupported in this build).
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 12
                                                color: "white"
                                            }
                                        }

                                        // ── Per-tab view pool (imperative) ───────────────────
                                        // webViewContainer hosts one WebEngineView per
                                        // websearch tab, created on demand by _ensureView()
                                        // from tabViewProto and keyed by the tab's stable id.
                                        // A view loads its URL once and is never re-bound to
                                        // model data, so tab churn never reloads a page. Only
                                        // the active tab's view is visible; closing a tab
                                        // destroys just its view (releasing the renderer).
                                        Item {
                                            id: webViewContainer
                                            anchors.fill: parent
                                        }
                                        Component {
                                            id: tabViewProto
                                            WebEngineView {
                                                id: tabView
                                                property int tabId: -1
                                                // Signature of the merged user-script
                                                // source this view last EXECUTED; drives
                                                // _applyUserScripts' reload decision.
                                                property string _hcAppliedSrc: ""
                                                // Spoof a clean Chrome UA (always) and
                                                // inject the ad/tracker blocker (when
                                                // enabled) before any page script runs.
                                                Component.onCompleted: win._applyUserScripts(tabView)
                                                anchors.fill: parent
                                                visible: false
                                                focus: true
                                                profile: win.webProfile
                                                backgroundColor: "transparent"
                                                settings.javascriptEnabled: true
                                                settings.forceDarkMode: true
                                                // Qt6 exposes fullscreen on the
                                                // settings object; the request
                                                // signal + isFullScreen live on
                                                // the view itself.
                                                settings.fullScreenSupportEnabled: true
                                                onLoadingChanged: function (loadRequest) { win._onViewLoad(tabId, loadRequest) }
                                                onTitleChanged: win._onViewTitle(tabId, title)
                                                onUrlChanged: win._onViewUrl(tabId, url)
                                                onFullScreenRequested: function (request) { win._onViewFullScreen(tabId, request) }
                                                // Installing this handler stops QtWebEngine forwarding every page
                                                // console message to the log. Chromium + third-party pages emit a lot
                                                // of benign noise we cannot act on (unused link-preload, WebGPU
                                                // context, Permissions-Policy). Drop info/warning wholesale and the
                                                // recurring harmless errors, but surface any other real JS error.
                                                onJavaScriptConsoleMessage: function (level, message, lineNumber, sourceID) {
                                                    // Enforcement-page recovery signal from adblock.js:
                                                    // clear YouTube cookies from the persistent profile
                                                    // and reload (HttpOnly cookies are unreachable from JS).
                                                    if (message === "__HC_FAB_CLEAR__") {
                                                        win._clearYouTubeCookiesAndReload(tabId)
                                                        return
                                                    }
                                                    if (level < 2) return
                                                    if (message.indexOf("allow-scripts") > -1) return
                                                    if (message.indexOf("ResizeObserver loop") > -1) return
                                                    if (message.indexOf("storage bucket") > -1 || message.indexOf("persistent-storage") > -1) return
                                                    console.error("js: " + message + " (" + sourceID + ":" + lineNumber + ")")
                                                }
                                            }
                                        }

                                        // ── Agent workspace: dedicated persistent view ──
                                        // A SECOND live WebEngineView is safe on this patched
                                        // Qt 6.11 build (validated 45s+, no SIGTRAP) provided
                                        // it shares the single win.webProfile -- a second
                                        // PROFILE still aborts. Its url is bound ONLY to
                                        // agentReady (never re-navigated on tab switch), so the
                                        // React+Monaco app loads once and the workspace state
                                        // survives hide/show + tab round-trips without a reload.
                                        // Hidden (parent webSearchPage off the agent/websearch
                                        // tabs) the page stays loaded, just not rendered.
                                        Component {
                                            id: agentViewProto
                                            WebEngineView {
                                                id: agentView
                                                anchors.fill: parent
                                                visible: win.tab === "agent"
                                                focus: true
                                                profile: win.webProfile
                                                url: win.agentReady ? win.agentUrl : "about:blank"
                                                backgroundColor: "transparent"
                                                settings.javascriptEnabled: true
                                                onVisibleChanged: if (visible) forceActiveFocus()
                                            }
                                        }
                                        // Gated so the agent view is instantiated only
                                        // AFTER win.webProfile resolves (profile is
                                        // creation-time only -> keeps it sharing the one
                                        // persistent profile, never a null/2nd one) AND
                                        // only while the workspace is enabled. Turning the
                                        // agent OFF deactivates the Loader -> the view is
                                        // destroyed -> its RENDERER process is reclaimed
                                        // (~60MB) instead of lingering on about:blank.
                                        // Re-enabling recreates it fresh (url rebinds via
                                        // agentReady), which is fine because OFF was an
                                        // explicit user choice. Destroying a WebEngineView
                                        // (never the profile) is the same create/destroy
                                        // path the websearch tab views already use safely.
                                        Loader {
                                            id: agentViewLoader
                                            anchors.fill: parent
                                            active: win.webProfile !== null && win.wsEnabled
                                            sourceComponent: agentViewProto
                                        }

                                        // ── Agent live theme (3c) ──────────────────────────
                                        // matugen rewrites ~/.config/gtk-4.0/colors.css and
                                        // Theme re-applies; the agent page (an in-process
                                        // view) never notices. Re-fetch through the app's own
                                        // bridge (server 'theme' action → theme_update
                                        // dispatch) with NO reload. Debounced so a burst of
                                        // matugen writes coalesces into one push.
                                        Timer {
                                            id: agentThemePush
                                            interval: 400
                                            repeat: false
                                            onTriggered: {
                                                var av = agentViewLoader.item
                                                if (!win.agentReady || !av) return
                                                av.runJavaScript(
                                                    "window.webkit.messageHandlers.agent.postMessage("
                                                    + "JSON.stringify({action:'theme'}));")
                                            }
                                        }
                                        Connections {
                                            target: Theme
                                            function onRevisionChanged() { agentThemePush.restart() }
                                        }

                                        // ── Bookmarks dropdown (websearch header) ──────────
                                        // Hangs from the library glyph in the nav header: a
                                        // compact scrollable menu of saved sites. Clicking one
                                        // navigates the shared view's active tab; a trailing
                                        // glyph removes it; a scrim closes it on outside-click.
                                        MouseArea {
                                            anchors.fill: parent
                                            visible: win.webShowBookmarks && win.tab === "websearch"
                                            z: 199
                                            onClicked: win.webShowBookmarks = false
                                        }
                                        Rectangle {
                                            anchors { top: parent.top; right: parent.right; margins: 8 }
                                            width: Math.min(320, parent.width - 16)
                                            height: Math.min(380, parent.height - 16)
                                            radius: 10
                                            visible: win.webShowBookmarks && win.tab === "websearch"
                                            z: 200
                                            clip: true
                                            color: Qt.rgba(Theme.cSurface.r, Theme.cSurface.g, Theme.cSurface.b, 0.98)
                                            border.width: 1
                                            border.color: Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.25)
                                            ColumnLayout {
                                                anchors { fill: parent; margins: 12 }
                                                spacing: 8
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: "\u{F00C3}  Bookmarks" + (WebBookmarksState.bookmarks.length ? "  (" + WebBookmarksState.bookmarks.length + ")" : "")
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 15
                                                        font.bold: true
                                                        color: Theme.cOnSurf
                                                    }
                                                    Rectangle {
                                                        Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 8
                                                        color: bmCloseMa.containsMouse ? Qt.alpha(Theme.cOnSurf, 0.14) : "transparent"
                                                        Text { anchors.centerIn: parent; text: "\u{F0156}"; font.family: Theme.fontFamily; font.pixelSize: 15; color: Theme.cOnSurf }
                                                        MouseArea { id: bmCloseMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.webShowBookmarks = false }
                                                    }
                                                }
                                                // Search box (the list can outgrow the scroll).
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 30; radius: 8
                                                    color: Qt.rgba(Theme.cSurface.r, Theme.cSurface.g, Theme.cSurface.b, 0.55)
                                                    border.width: 1
                                                    border.color: Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.20)
                                                    RowLayout {
                                                        anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
                                                        spacing: 6
                                                        Text { text: "\u{F0349}"; font.family: Theme.fontFamily; font.pixelSize: 13; color: Qt.alpha(Theme.cOnSurf, 0.6) }
                                                        TextInput {
                                                            id: bmSearchInput
                                                            Layout.fillWidth: true
                                                            verticalAlignment: TextInput.AlignVCenter
                                                            color: Theme.cOnSurf; font.pixelSize: 12; clip: true
                                                            selectByMouse: true
                                                            text: win.webBookmarkQuery
                                                            onTextChanged: win.webBookmarkQuery = text
                                                            Keys.onEscapePressed: { win.webBookmarkQuery = ""; bmSearchInput.focus = false }
                                                        }
                                                    }
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    visible: WebBookmarksState.bookmarks.length === 0
                                                    text: "No bookmarks yet. Use the bookmark button while on a page to save it here."
                                                    wrapMode: Text.WordWrap
                                                    font.pixelSize: 12
                                                    color: Qt.alpha(Theme.cOnSurf, 0.7)
                                                }
                                                ListView {
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    clip: true
                                                    spacing: 6
                                                    model: WebBookmarksState.bookmarks.filter(function (b) {
                                                        var q = win.webBookmarkQuery.toLowerCase()
                                                        return !q || String(b.title || "").toLowerCase().indexOf(q) >= 0
                                                                   || String(b.url || "").toLowerCase().indexOf(q) >= 0
                                                    })
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        required property int index
                                                        width: ListView.view.width
                                                        height: 46
                                                        radius: 10
                                                        color: bmRowMa.containsMouse ? Qt.alpha(win.wColor3, 0.16) : Qt.rgba(Theme.cSurface.r, Theme.cSurface.g, Theme.cSurface.b, 0.55)
                                                        border.width: 1
                                                        border.color: Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.18)
                                                        RowLayout {
                                                            anchors { fill: parent; leftMargin: 12; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                                            spacing: 10
                                                            ColumnLayout {
                                                                Layout.fillWidth: true
                                                                spacing: 2
                                                                Text {
                                                                    Layout.fillWidth: true
                                                                    text: modelData.title || modelData.url
                                                                    elide: Text.ElideRight
                                                                    font.pixelSize: 13
                                                                    font.bold: true
                                                                    color: Theme.cOnSurf
                                                                }
                                                                Text {
                                                                    Layout.fillWidth: true
                                                                    text: modelData.url
                                                                    elide: Text.ElideRight
                                                                    font.pixelSize: 11
                                                                    color: Qt.alpha(Theme.cOnSurf, 0.6)
                                                                }
                                                            }
                                                            Rectangle {
                                                                Layout.preferredWidth: 26; Layout.preferredHeight: 26; radius: 7
                                                                color: bmDelMa.containsMouse ? Qt.alpha(Theme.cErr, 0.22) : "transparent"
                                                                Text { anchors.centerIn: parent; text: "\u{F09CC}"; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.cErr }
                                                                MouseArea {
                                                                    id: bmDelMa
                                                                    anchors.fill: parent
                                                                    hoverEnabled: true
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    onClicked: WebBookmarksState.remove(modelData.url)
                                                                }
                                                            }
                                                        }
                                                        MouseArea {
                                                            id: bmRowMa
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                win.webNavigateActive(modelData.url)
                                                                win.webShowBookmarks = false
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // ── Credentials dropdown (websearch header) ──────
                                        // Same scrim+card pattern as bookmarks: a
                                        // scrollable, filterable list of the sites that
                                        // currently hold stored cookies (read from the
                                        // profile's cookie DB). A leading "clear all" and
                                        // a per-row broom delete the stored credential.
                                        MouseArea {
                                            anchors.fill: parent
                                            visible: win.webShowCredentials && win.tab === "websearch"
                                            z: 199
                                            onClicked: win.webShowCredentials = false
                                        }
                                        Rectangle {
                                            anchors { top: parent.top; right: parent.right; margins: 8 }
                                            width: Math.min(320, parent.width - 16)
                                            height: Math.min(380, parent.height - 16)
                                            radius: 10
                                            visible: win.webShowCredentials && win.tab === "websearch"
                                            z: 200
                                            clip: true
                                            color: Qt.rgba(Theme.cSurface.r, Theme.cSurface.g, Theme.cSurface.b, 0.98)
                                            border.width: 1
                                            border.color: Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.25)
                                            ColumnLayout {
                                                anchors { fill: parent; margins: 12 }
                                                spacing: 8
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: "\u{EDE4}  Credentials" + (win.webCredOrigins.length ? "  (" + win.webCredOrigins.length + ")" : "")
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 15
                                                        font.bold: true
                                                        color: Theme.cOnSurf
                                                    }
                                                    Rectangle {
                                                        Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 8
                                                        color: credCloseMa.containsMouse ? Qt.alpha(Theme.cOnSurf, 0.14) : "transparent"
                                                        Text { anchors.centerIn: parent; text: "\u{F0156}"; font.family: Theme.fontFamily; font.pixelSize: 15; color: Theme.cOnSurf }
                                                        MouseArea { id: credCloseMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.webShowCredentials = false }
                                                    }
                                                }
                                                // Search box (the list can outgrow the scroll).
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 30; radius: 8
                                                    color: Qt.rgba(Theme.cSurface.r, Theme.cSurface.g, Theme.cSurface.b, 0.55)
                                                    border.width: 1
                                                    border.color: Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.20)
                                                    RowLayout {
                                                        anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
                                                        spacing: 6
                                                        Text { text: "\u{F0349}"; font.family: Theme.fontFamily; font.pixelSize: 13; color: Qt.alpha(Theme.cOnSurf, 0.6) }
                                                        TextInput {
                                                            id: credSearchInput
                                                            Layout.fillWidth: true
                                                            verticalAlignment: TextInput.AlignVCenter
                                                            color: Theme.cOnSurf; font.pixelSize: 12; clip: true
                                                            selectByMouse: true
                                                            text: win.webCredentialQuery
                                                            onTextChanged: win.webCredentialQuery = text
                                                            Keys.onEscapePressed: { win.webCredentialQuery = ""; credSearchInput.focus = false }
                                                        }
                                                    }
                                                }
                                                // Clear-all affordance (only when something is stored).
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 30; radius: 8
                                                    visible: win.webCredOrigins.length > 0
                                                    color: credClearAllMa.containsMouse ? Qt.alpha(Theme.cErr, 0.20) : Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.08)
                                                    border.width: 1
                                                    border.color: Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.35)
                                                    RowLayout {
                                                        anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
                                                        spacing: 8
                                                        Text { text: "\u{EDE4}"; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.cErr }
                                                        Text { Layout.fillWidth: true; text: "Clear all credentials"; font.pixelSize: 12; font.bold: true; color: Theme.cErr }
                                                    }
                                                    MouseArea { id: credClearAllMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.webClearCredential("") }
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    visible: win.webCredOrigins.length === 0
                                                    text: "No stored site credentials yet. Log into a site in the web view and it will appear here."
                                                    wrapMode: Text.WordWrap
                                                    font.pixelSize: 12
                                                    color: Qt.alpha(Theme.cOnSurf, 0.7)
                                                }
                                                ListView {
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    clip: true
                                                    spacing: 6
                                                    model: win.webCredOrigins.filter(function (h) {
                                                        var q = win.webCredentialQuery.toLowerCase()
                                                        return !q || String(h).toLowerCase().indexOf(q) >= 0
                                                    })
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        required property int index
                                                        width: ListView.view.width
                                                        height: 40
                                                        radius: 10
                                                        color: credRowMa.containsMouse ? Qt.alpha(win.wColor3, 0.16) : Qt.rgba(Theme.cSurface.r, Theme.cSurface.g, Theme.cSurface.b, 0.55)
                                                        border.width: 1
                                                        border.color: Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.18)
                                                        RowLayout {
                                                            anchors { fill: parent; leftMargin: 12; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                                            spacing: 10
                                                            Text {
                                                                Layout.fillWidth: true
                                                                text: modelData
                                                                elide: Text.ElideMiddle
                                                                font.pixelSize: 13
                                                                color: Theme.cOnSurf
                                                            }
                                                            Rectangle {
                                                                Layout.preferredWidth: 26; Layout.preferredHeight: 26; radius: 7
                                                                color: credDelMa.containsMouse ? Qt.alpha(Theme.cErr, 0.22) : "transparent"
                                                                Text { anchors.centerIn: parent; text: "\u{EDE4}"; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.cErr }
                                                                MouseArea {
                                                                    id: credDelMa
                                                                    anchors.fill: parent
                                                                    hoverEnabled: true
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    onClicked: win.webClearCredential(modelData)
                                                                }
                                                            }
                                                        }
                                                        MouseArea { id: credRowMa; anchors.fill: parent; hoverEnabled: true; z: -1 }
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 10
                                            visible: win.webShowError && win.tab === "websearch"
                                            color: Qt.rgba(Theme.cSurface.r, Theme.cSurface.g, Theme.cSurface.b, 0.97)
                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: 10
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: "\u{F13B8}"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 34
                                                    color: Theme.cErr
                                                }
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: "SearXNG is not reachable"
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                    color: Theme.cOnSurf
                                                }
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: "Start the local SearXNG service to search."
                                                    font.pixelSize: 11
                                                    color: Theme.cOnSurf
                                                    opacity: 0.7
                                                }
                                                Rectangle {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    width: webStartLbl.implicitWidth + 28
                                                    height: 32
                                                    radius: 16
                                                    color: webStartMa.containsMouse ? Theme.cOnSecondary : Theme.cSecondaryContainer
                                                    Text {
                                                        id: webStartLbl
                                                        anchors.centerIn: parent
                                                        text: "\u{F04F5}  Start SearXNG"
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 12
                                                        color: Theme.cPrimary
                                                    }
                                                    MouseArea {
                                                        id: webStartMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: win.webEnsureUp()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        // ── Workspace (agent) tab ───────────────────────────
                        // The agent renders in its OWN persistent view (agentView,
                        // inside the pool surface above) sharing the single
                        // win.webProfile — two live views are validated on this
                        // patched build. Its frame geometry + chrome are handled
                        // inside webSearchPage; the circular ON/OFF workspace
                        // toggle (agentWsToggle) and agentEnsureUp() drive the
                        // one-shot load of win.agentUrl once the loopback server
                        // answers.
                    }
                }

                // ══════════════════════════════════════════════════════════
                //  Context menu overlay (in-card, GJS popover anatomy)
                // ══════════════════════════════════════════════════════════
                Item {
                    id: menuOverlay
                    anchors.fill: parent
                    visible: win._menuOpen
                    z: 50

                    MouseArea {
                        anchors.fill: parent
                        onClicked: win._hideMenu()
                    }

                    Rectangle {
                        id: menuPanel
                        x: win._menuX
                        y: Math.min(win._menuY, Math.max(6, card.height - height - 6))
                        width: 250
                        height: menuCol.implicitHeight + 12
                        radius: 14
                        color: Theme.cOnSecondary
                        border.width: 1
                        border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g,
                                              Theme.cScrim.b, 0.5)
                        clip: true

                        Column {
                            id: menuCol
                            x: 6; y: 6
                            width: parent.width - 12
                            spacing: 0
                            Repeater {
                                model: win._menuRows
                                delegate: Item {
                                    required property var modelData
                                    required property int index
                                    width: menuCol.width
                                    height: modelData.kind === "sep" ? 9
                                          : modelData.kind === "hdr" ? 22 : 30
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: modelData.kind === "item" ? 1 : 0
                                        radius: 8
                                        visible: modelData.kind === "item"
                                        color: itemMa.containsMouse
                                               ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                         Theme.cPrimary.b, 0.14)
                                               : "transparent"
                                        Behavior on color { ColorAnimation { duration: 110 } }
                                    }
                                    Text {
                                        visible: modelData.kind === "hdr"
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.text ?? ""
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: Qt.alpha(Theme.cPrimary, 0.7)
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        anchors.verticalCenter: undefined
                                        anchors.top: parent.top
                                        anchors.topMargin: 4
                                        width: parent.width - 12
                                        height: 1
                                        visible: modelData.kind === "sep"
                                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                       Theme.cPrimary.b, 0.18)
                                    }
                                    Row {
                                        visible: modelData.kind === "item"
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 6
                                        Text {
                                            width: parent.width - chevText.implicitWidth - 6
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.text ?? ""
                                            font.pixelSize: 12
                                            color: Theme.cOnSurf
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            id: chevText
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: (modelData.chevron ?? "") !== ""
                                            text: modelData.chevron ?? ""
                                            font.pixelSize: 13
                                            color: Theme.cOnSurf
                                            opacity: 0.6
                                        }
                                    }
                                    MouseArea {
                                        id: itemMa
                                        anchors.fill: parent
                                        enabled: modelData.kind === "item"
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: {
                                            if (modelData.kind !== "item") return
                                            win._wsSubKey = ((modelData.chevron ?? "") !== "")
                                                              ? modelData.key : ""
                                        }
                                        onClicked: win._menuActivate(modelData)
                                    }
                                }
                            }
                        }
                    }

                    // "Open on Workspace" sub-panel (New Window / GPU rows)
                    Rectangle {
                        id: wsPanel
                        visible: win._menuOpen && win._wsSubKey !== ""
                        width: 160
                        height: wsCol.implicitHeight + 12
                        x: menuPanel.x + menuPanel.width + 6 + width > card.width
                           ? menuPanel.x - width - 6
                           : menuPanel.x + menuPanel.width + 6
                        y: Math.min(menuPanel.y, card.height - height - 6)
                        radius: 14
                        color: Theme.cOnSecondary
                        border.width: 1
                        border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g,
                                              Theme.cScrim.b, 0.5)

                        Column {
                            id: wsCol
                            x: 6; y: 6
                            width: parent.width - 12
                            Text {
                                width: parent.width
                                text: "Open on Workspace"
                                font.pixelSize: 10
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                color: Qt.alpha(Theme.cPrimary, 0.7)
                                topPadding: 2; bottomPadding: 4
                            }
                            Rectangle {
                                width: parent.width
                                height: 1
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                               Theme.cPrimary.b, 0.18)
                            }
                            Repeater {
                                model: 10
                                delegate: Rectangle {
                                    required property int index
                                    width: wsCol.width
                                    height: 28
                                    radius: 8
                                    color: wsMa.containsMouse
                                           ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                     Theme.cPrimary.b, 0.14)
                                           : "transparent"
                                    Behavior on color { ColorAnimation { duration: 110 } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: "\u2192  WS " + (index + 1)
                                        font.pixelSize: 12
                                        color: Theme.cOnSurf
                                    }
                                    MouseArea {
                                        id: wsMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: win._wsPick(index + 1)
                                    }
                                }
                            }
                        }
                    }
                }

                // ══════════════════════════════════════════════════════════
                //  Group-name dialog (in-card overlay — keeps exclusive
                //  keyboard focus, no second surface grab chain)
                // ══════════════════════════════════════════════════════════
                Item {
                    id: dlgOverlay
                    anchors.fill: parent
                    visible: win._dlg.open
                    z: 60

                    MouseArea { anchors.fill: parent }
                    Rectangle {
                        anchors.fill: parent
                        color: Qt.alpha(Theme.cScrim, 0.45)
                    }
                    Rectangle {
                        id: dlgBox
                        width: 340
                        height: dlgCol.implicitHeight + 40
                        anchors.centerIn: parent
                        radius: 16
                        color: Theme.cOnSecondary
                        border.width: 1
                        border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g,
                                              Theme.cScrim.b, 0.6)
                        Column {
                            id: dlgCol
                            x: 24; y: 20
                            width: parent.width - 48
                            spacing: 12
                            Text {
                                width: parent.width
                                text: win._dlg.title ?? ""
                                font.pixelSize: 12
                                font.bold: true
                                color: Theme.cOnSurf
                                wrapMode: Text.WordWrap
                            }
                            Rectangle {
                                width: parent.width
                                height: 36
                                radius: Config.launcherSearchRadius
                                color: Qt.rgba(Theme.cOnSurf.r, Theme.cOnSurf.g,
                                               Theme.cOnSurf.b, 0.08)
                                TextInput {
                                    id: dlgInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    verticalAlignment: TextInput.AlignVCenter
                                    clip: true
                                    color: Theme.cOnSurf
                                    font.pixelSize: 13
                                    Text {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        text: "Group name\u2026"
                                        font: dlgInput.font
                                        color: Theme.cOnSurf
                                        opacity: 0.45
                                        visible: dlgInput.text === ""
                                    }
                                    Keys.onPressed: function(event) {
                                        if (event.key === Qt.Key_Escape) {
                                            win._dlg = { open: false }; event.accepted = true
                                        } else if (event.key === Qt.Key_Return
                                                   || event.key === Qt.Key_Enter) {
                                            win._dlgConfirm(dlgInput.text); event.accepted = true
                                        }
                                    }
                                }
                            }
                            Row {
                                width: parent.width
                                spacing: 8
                                layoutDirection: Qt.RightToLeft
                                Repeater {
                                    model: [{ key: "ok", label: win._dlg.mode === "rename" ? "Rename" : "Create" },
                                            { key: "cancel", label: "Cancel" }]
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: dlgBtnText.implicitWidth + 26
                                        height: 30
                                        radius: 15
                                        color: dlgBtnMa.containsMouse
                                               ? Qt.rgba(Theme.cOnSurf.r, Theme.cOnSurf.g,
                                                         Theme.cOnSurf.b, 0.18)
                                               : Qt.rgba(Theme.cOnSurf.r, Theme.cOnSurf.g,
                                                         Theme.cOnSurf.b, 0.08)
                                        border.width: 1
                                        border.color: Qt.rgba(Theme.cOnSurf.r, Theme.cOnSurf.g,
                                                              Theme.cOnSurf.b, 0.35)
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Text {
                                            id: dlgBtnText
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            font.pixelSize: 12
                                            color: Theme.cOnSurf
                                        }
                                        MouseArea {
                                            id: dlgBtnMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (modelData.key === "ok")
                                                    win._dlgConfirm(dlgInput.text)
                                                else
                                                    win._dlg = { open: false }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        onVisibleChanged: if (visible) {
                            dlgInput.text = win._dlg.initial ?? ""
                            Qt.callLater(function() { dlgInput.forceActiveFocus() })
                        }
                    }
                }
            }

            // ── Page-level helpers ────────────────────────────────────────
            function placeholder() {
                switch (win.tab) {
                case "clipboard": return " Search clipboard\u2026"
                case "emoji":     return win.iconMode === "nerd"
                                      ? " Search glyph\u2026" : " Search emoji\u2026"
                case "websearch": return " Search the web\u2026"
                case "agent":     return " Ask the agent\u2026"
                default:          return " Search applications\u2026"
                }
            }

            readonly property var clipFiltered: {
                const out = []
                const qs = win.q
                for (const e of ClipboardState.entries) {
                    if (qs !== "" && !String(e.text).toLowerCase().includes(qs)) continue
                    out.push(e)
                }
                return out
            }

            readonly property var groupCards: {
                win._entriesEpoch
                const qs = win.q
                const out = []
                for (const name of Object.keys(GroupsState.groups)
                         .sort((a, b) => String(a).localeCompare(String(b)))) {
                    const members = GroupsState.groups[name] ?? []
                    const apps = win.allApps.filter(a => members.includes(a.cls))
                    if (apps.length === 0) continue
                    if (qs !== ""
                        && !apps.some(a => String(a.name).toLowerCase().includes(qs))) continue
                    out.push({ name: name, apps: apps })
                }
                return out
            }

            function moveFocus(delta) {
                if (win.tab !== "launcher" || win.subTab !== "apps") return
                const n = filteredApps.length
                if (n === 0) return
                let i = win.focusIdx
                if (i === -1) i = delta > 0 ? 0 : n - 1
                else i = Math.max(0, Math.min(n - 1, i + delta))
                win.focusIdx = i
            }

            function activateCurrent() {
                if (win.tab === "launcher" && win.subTab === "apps") {
                    const list = filteredApps
                    const rec = win.focusIdx >= 0 && win.focusIdx < list.length
                                ? list[win.focusIdx] : (list.length > 0 ? list[0] : null)
                    if (rec) { win.launchApp(rec); HCCLauncherState.close() }
                } else if (win.tab === "clipboard") {
                    const list = win.clipFiltered
                    if (list.length > 0) {
                        ClipboardState.restore(list[0].raw)
                        HCCLauncherState.close()
                    }
                }
            }

            function _dlgConfirm(name) {
                name = String(name ?? "").trim()
                const d = win._dlg
                win._dlg = { open: false }
                if (!name) return
                if (d.mode === "rename" && d.group) {
                    GroupsState.renameGroup(d.group, name)
                } else if (d.mode === "newgroup") {
                    GroupsState.addGroup(name, d.ids ?? [])
                    // New groups start collapsed (lightbox expands on click)
                    win.selectMode = false
                    win.selectedIds = []
                    win.subTab = "groups"
                }
            }

            // ══════════════════════════════════════════════════════════════
            //  Inline components
            // ══════════════════════════════════════════════════════════════

            component AppTile: Rectangle {
                id: tile
                required property var rec
                property string groupCtx: ""
                property bool keyboardFocused: false

                width: Config.launcherFixedTileWidth
                height: Config.launcherFixedTileHeight
                radius: 10
                color: tileMa.containsMouse || keyboardFocused
                       ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                 Theme.cPrimary.b, 0.09)
                       : "transparent"
                border.width: keyboardFocused ? 1 : 0
                border.color: Theme.cPrimary
                Behavior on color { ColorAnimation { duration: 110 } }

                // GJS DragSource parity removed — app tiles are click-only now.

                Column {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -3
                    spacing: 4
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Config.launcherIconSize
                        height: Config.launcherIconSize
                        Image {
                            id: tileIcon
                            anchors.fill: parent
                            source: tile.rec ? win.iconSource(tile.rec) : ""
                            sourceSize: Qt.size(Config.launcherIconSize, Config.launcherIconSize)
                            asynchronous: true   // decode off the GUI thread; the
                            cache: true          // pixmap cache warms before first open
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }
                        // Ghost fallback (U+F165D) for unresolved icons —
                        // same recipe as the dock buttons.
                        Text {
                            visible: tileIcon.status !== Image.Ready
                            anchors.centerIn: parent
                            text: "\u200a\u200a\u200a\u200a\u{F165D}\u200a\u200a\u200a\u200a"
                            color: Theme.cSurfaceTint
                            font.family: Theme.fontFamily
                            font.pixelSize: Math.round(Config.launcherIconSize * 1.0)
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: tile.width - 6
                        text: tile.rec ? tile.rec.name : ""
                        font.pixelSize: Config.launcherTextFontSize
                        color: tileMa.containsMouse || keyboardFocused
                               ? Theme.cSurfaceTint : Theme.cOnSurf
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // Running-instance dots (max 2, flush bottom-center)
                Row {
                    id: dotsRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 1
                    spacing: 2
                    visible: tile.rec !== null && dotsRow.dots > 0
                    property int dots: Math.min(
                        tile.rec ? win.clientsFor(tile.rec.cls).length : 0, 2)
                    Repeater {
                        model: dotsRow.dots
                        Rectangle {
                            width: 7; height: 7
                            radius: 3.5
                            color: win.wColor3
                        }
                    }
                }

                // Multi-select checkbox — shown in selection mode even while
                // searching, so filtered results carry the same empty/checked
                // indicator as the unfiltered grid.
                Rectangle {
                    visible: win.selectMode
                    width: 18; height: 18
                    radius: 9
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 3
                    color: tile.rec && win.selectedIds.includes(tile.rec.cls)
                           ? win.wColor3 : Qt.rgba(Theme.cScrim.r, Theme.cScrim.g,
                                                   Theme.cScrim.b, 0.35)
                    border.width: 1
                    border.color: Qt.alpha(Theme.cOnSurf, 0.5)
                    Text {
                        anchors.centerIn: parent
                        visible: tile.rec && win.selectedIds.includes(tile.rec.cls)
                        text: "\u2713"
                        font.pixelSize: 11
                        color: Theme.cOnSurf
                    }
                }

                MouseArea {
                    id: tileMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function(mouse) {
                        if (!tile.rec) return
                        if (mouse.button === Qt.RightButton) {
                            const pt = tile.mapToItem(card, mouse.x, mouse.y)
                            win._openAppMenu(tile.rec, pt.x, pt.y, tile.groupCtx)
                            return
                        }
                        if (win.selectMode) {
                            const cur = win.selectedIds.slice()
                            const i = cur.indexOf(tile.rec.cls)
                            if (i === -1) cur.push(tile.rec.cls)
                            else cur.splice(i, 1)
                            win.selectedIds = cur
                            return
                        }
                        win.launchApp(tile.rec)
                        HCCLauncherState.close()
                    }
                }
            }

            component GroupCard: Rectangle {
                id: gcard
                required property string cardName
                required property var cardApps
                readonly property bool expanded: win.expandedGroups[cardName] === true

                // Lightbox: the grid footprint always stays at the collapsed
                // size; the expanded body renders in the foreground expander
                // box, overlapping the collapsed neighbours behind it.
                width: win.groupCardSize
                height: win.groupCardSize
                z: expanded ? 20 : 0
                radius: 14
                color: expanded ? "transparent"
                       : Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                 Theme.cInversePrimary.b, 0.30)
                border.width: 1
                border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g,
                                      Theme.cScrim.b, 0.45)
                Behavior on color { ColorAnimation { duration: 160 } }

                // Lightbox is exclusive — expanding one group collapses the rest.
                function toggle() {
                    const exp = {}
                    if (!expanded) exp[cardName] = true
                    win.expandedGroups = exp
                }

                // Collapsed: 2×2 cluster preview + name
                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    visible: !gcard.expanded
                    Grid {
                        anchors.horizontalCenter: parent.horizontalCenter
                        columns: 2
                        spacing: 6
                        Repeater {
                            model: gcard.cardApps.slice(0, 4)
                            delegate: Item {
                                required property var modelData
                                width: win.groupPrevIcon; height: win.groupPrevIcon
                                Image {
                                    id: prevIcon
                                    anchors.fill: parent
                                    source: win.iconSource(modelData)
                                    sourceSize: Qt.size(win.groupPrevIcon, win.groupPrevIcon)
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                }
                                Text {
                                    visible: prevIcon.status !== Image.Ready
                                    anchors.centerIn: parent
                                    text: "\u{F165D}"
                                    color: Theme.cSurfaceTint
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 30
                                }
                            }
                        }
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 4
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u{F06D0}"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: win.wColor2
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            // Cap + elide long names so they stay inside the square
                            // tile; short names keep their natural (centered) width.
                            width: Math.min(implicitWidth, gcard.width - 44)
                            text: gcard.cardName
                            font.pixelSize: 11
                            font.bold: true
                            color: Theme.cPrimary
                            elide: Text.ElideRight
                        }
                    }
                }

                // Expanded: foreground lightbox box over the neighbours
                Rectangle {
                    id: expander
                    visible: gcard.expanded
                    x: 0; y: 0
                    // Stop at the last icon column — width follows the grid
                    // (max 4 columns), not the whole list frame.
                    width: Math.max(Config.launcherFixedTileWidth * 2 + 10,
                                    gbody.implicitWidth + 16)
                    height: gbody.implicitHeight + 34
                    radius: 14
                    color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                   Theme.cInversePrimary.b, 0.92)
                    border.width: 1
                    border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g,
                                          Theme.cScrim.b, 0.45)
                    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    Column {
                    id: gbody
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    spacing: 4
                    Row {
                        width: parent.width
                        spacing: 4
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u{F06D0}"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: win.wColor2
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: gcard.cardName
                            font.pixelSize: 11
                            font.bold: true
                            color: Theme.cPrimary
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u{F0B2C}"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.cPrimary
                        }
                    }
                    Grid {
                        columns: Math.max(2, Math.min(4, gcard.cardApps.length))
                        spacing: 2
                        Repeater {
                            model: gcard.cardApps
                            AppTile {
                                required property var modelData
                                rec: modelData
                                groupCtx: gcard.cardName
                            }
                        }
                    }
                    }

                    // Expanded header click collapses again
                    MouseArea {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 26
                        cursorShape: Qt.PointingHandCursor
                        onClicked: gcard.toggle()
                        onReleased: {} // no-op: keep drag release from launching
                    }
                    // Expanded card right-click → group menu (header strip)
                    MouseArea {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 26
                        acceptedButtons: Qt.RightButton
                        hoverEnabled: false
                        onClicked: function(mouse) {
                            const pt = gcard.mapToItem(card, mouse.x, mouse.y)
                            win._openGroupMenu(gcard.cardName, pt.x, pt.y)
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    enabled: !gcard.expanded
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton) {
                            const pt = gcard.mapToItem(card, mouse.x, mouse.y)
                            win._openGroupMenu(gcard.cardName, pt.x, pt.y)
                            return
                        }
                        gcard.toggle()
                    }
                }
            }
        }
    }
}
