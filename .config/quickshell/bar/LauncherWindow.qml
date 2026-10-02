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
            property var expandedGroups: ({})
            readonly property bool _anyGroupExpanded:
                Object.values(expandedGroups).some(v => v === true)
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
            property WebEngineProfile webProfile: WebEngineProfile {
                storageName: "hyprcandy-launcher"   // persistent on-disk profile
            }

            // ── Agent tab: loopback-served React app, own session ──────────
            // Port of the GJS launcher's agent workspace: a small Python server
            // (bar/agent_loopback_server.py) serves agent-app/dist on a private
            // loopback origin (COOP/COEP headers for the WASM build), and the
            // app is hosted in a WebEngineView with its OWN profile so the agent
            // session stays isolated from the SearXNG web-search webview.
            readonly property int agentPort: 17842
            readonly property string agentUrl: "http://127.0.0.1:" + agentPort + "/index.html"
            property WebEngineProfile agentProfile: WebEngineProfile {
                storageName: "hyprcandy-agent"   // separate on-disk session
            }
            property bool agentReady: false
            property bool agentStarting: false
            property bool agentMissing: false

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
                    if (win.wsEnabled) win.ensureRuntimeBackend()
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
                    if (!wsStateFile.exists) return true
                    const o = JSON.parse(wsStateFile.text())
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
                    if (!qs && favs.includes(a.cls)) continue   // shown in Favorites
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
                            // SearXNG came up after a docker start: re-cover the
                            // overlay and (re)load the in-page webview.
                            if (win.webShowError) webView.url = win.searxBase
                            win.webShowError = false
                        } else if (healthRetry.attempts >= 25 || win.tab !== "websearch") {
                            healthRetry.stop()
                            win.searxDockerStarting = false
                            win.webShowError = true
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
                win.checkSearxHealth(function(ok) {
                    if (ok) {
                        if (win.webShowError) webView.url = win.searxBase
                        win.webShowError = false
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
                win.tab = id
                HCCLauncherState.setTab(id)
                win.query = ""
                searchInput.text = ""
                win.focusIdx = -1
                win._hideMenu()
                if (id === "clipboard") ClipboardState.refresh()
                if (id === "emoji") win.ensureGlyphData()
                if (id === "websearch") win.webEnsureUp()
                if (id === "agent") win.agentEnsureUp()
                Qt.callLater(function() {
                    if (win.tab === "websearch") { if (webView) webView.forceActiveFocus() }
                    else searchInput.forceActiveFocus()
                })
            }
            function cycleTab(dir) {
                const tabs = HCCLauncherState.tabs
                const i = tabs.indexOf(win.tab)
                win.switchTab(tabs[((i === -1 ? 0 : i) + dir + tabs.length) % tabs.length])
            }
            function dismiss() {
                if (win._menuOpen) { win._hideMenu(); return }
                if (win._dlg.open) { win._dlg = { open: false }; return }
                HCCLauncherState.close()
            }

            onTabChanged: {
                if (HCCLauncherState.activeTab !== win.tab) HCCLauncherState.setTab(win.tab)
            }
            Connections {
                target: HCCLauncherState
                function onActiveTabChanged() {
                    if (win.tab !== HCCLauncherState.activeTab) win.tab = HCCLauncherState.activeTab
                }
            }
            onVisibleChanged: {
                if (visible) {
                    // Keyboard focus is granted by WlrKeyboardFocus.OnDemand and
                    // searchInput.forceActiveFocus(); there is no layershell
                    // focusWindow() method (calling it threw a TypeError).
                    win.query = ""; searchInput.text = ""
                    win.focusIdx = -1
                    win._hideMenu()
                    win._dlg = { open: false }
                    win.selectMode = false; win.selectedIds = []
                    win.tab = HCCLauncherState.activeTab
                    if (win.tab === "clipboard") ClipboardState.refresh()
                    if (win.tab === "emoji") win.ensureGlyphData()
                    if (win.tab === "websearch") win.webEnsureUp()
                    if (win.tab === "agent") win.agentEnsureUp()
                    Qt.callLater(function() {
                        if (win.tab === "websearch") { if (webView) webView.forceActiveFocus() }
                        else searchInput.forceActiveFocus()
                    })
                }
                // else: keep the SearXNG container warm (no teardown) so re-show
                // returns instantly and autostart can't wedge mid-toggle.
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
            Component.onCompleted: wsInitProbe.restart()

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
                            onTextChanged: { win.query = text; win.focusIdx = -1 }

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
                            width: Math.max(0, (launcherSubRow.width - favPill.width) / 2
                                            - appsGroupsSeg.width
                                            - 2 * launcherSubRow.spacing)
                        }
                        Rectangle {
                            id: favPill
                            anchors.verticalCenter: parent.verticalCenter
                            visible: win.subTab === "apps"
                                     && win.favoriteApps.length > 0
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
                                    visible: win.favoriteApps.length > 0
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
                                    (pageArea.width + 8) / (Config.launcherFixedTileWidth * 2 + 14)))
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
                            visible: win.tab === "websearch"
                            onVisibleChanged: if (visible) win.webEnsureUp()

                            // Small glyph toolbar button used by the nav row.
                            component WebNavBtn: Rectangle {
                                required property string glyph
                                required property color tint
                                required property var handler
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
                                    font.pixelSize: 15
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
                                radius: 14
                                color: Qt.rgba(Theme.cSurface.r, Theme.cSurface.g, Theme.cSurface.b, 0.2)
                                border.width: 0
                                border.color: Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.22)

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 0
                                    spacing: 6

                                    // ── Nav toolbar ──────────────────────────────
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 10
                                        Layout.rightMargin: 10
                                        Layout.topMargin: 10
                                        Layout.bottomMargin: 2
                                        spacing: 6
                                        // Leave websearch → back to the launcher tab.
                                        WebNavBtn { glyph: "\u{2190}"; tint: Theme.cPrimary; handler: function () { win.switchTab("launcher") } }
                                        WebNavBtn {
                                            glyph: "\u{21B6}"; enabled: webView.canGoBack
                                            tint: webView.canGoBack ? Theme.cOnSurf : Qt.alpha(Theme.cOnSurf, 0.35)
                                            handler: function () { if (webView.canGoBack) webView.goBack() }
                                        }
                                        WebNavBtn {
                                            glyph: "\u{21B7}"; enabled: webView.canGoForward
                                            tint: webView.canGoForward ? Theme.cOnSurf : Qt.alpha(Theme.cOnSurf, 0.35)
                                            handler: function () { if (webView.canGoForward) webView.goForward() }
                                        }
                                        WebNavBtn { glyph: "\u{27F3}"; tint: Theme.cOnSurf; handler: function () { webView.reload() } }
                                        WebNavBtn { glyph: "\u{2302}"; tint: Theme.cOnSurf; handler: function () { webView.url = win.searxBase } }

                                        // Address display (read-only current URL).
                                        Rectangle {
                                            Layout.fillWidth: true; Layout.preferredHeight: 30; radius: 8
                                            color: Qt.rgba(Theme.cSurface.r, Theme.cSurface.g, Theme.cSurface.b, 0.55)
                                            border.width: 1
                                            border.color: Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.20)
                                            Text {
                                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                                                text: webView.url ? webView.url.toString() : win.searxBase
                                                font.pixelSize: 11
                                                color: Qt.rgba(Theme.cOnSurf.r, Theme.cOnSurf.g, Theme.cOnSurf.b, 0.75)
                                                elide: Text.ElideMiddle
                                            }
                                        }

                                        // Bookmark the page currently shown.
                                        WebNavBtn {
                                            glyph: WebBookmarksState.isBookmarked(webView.url) ? "\u{F00C2}" : "\u{F00C0}"
                                            tint: WebBookmarksState.isBookmarked(webView.url) ? Theme.cPrimary : Theme.cOnSurf
                                            handler: function () { win.webToggleBookmark(webView.url, webView.title) }
                                        }

                                        // Open the saved-bookmarks library.
                                        WebNavBtn {
                                            glyph: "\u{F00C3}"
                                            tint: win.webShowBookmarks ? Theme.cPrimary : Theme.cOnSurf
                                            handler: function () { win.webShowBookmarks = !win.webShowBookmarks }
                                        }
                                    }

                                    // Thin progress bar while loading.
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: webView.loading ? 3 : 0
                                        visible: webView.loading
                                        radius: 2
                                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.18)
                                        Rectangle {
                                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                            width: parent.width * (webView.loadProgress / 100)
                                            radius: 2
                                            color: Theme.cPrimary
                                        }
                                    }

                                    // ── The web view + SearXNG-down overlay ──────
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        // QtQuick clip is rectangular and ignores radius, so mask
                                        // the web content to round the panel bottom corners.
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
                                            // Round all corners, then repaint the top band opaque so only
                                            // the bottom two corners stay rounded (Qt Quick Rectangle here
                                            // rejects per-corner group props, so use plain radius only).
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 14
                                                color: "white"
                                            }
                                            Rectangle {
                                                x: 0
                                                y: 0
                                                width: parent.width
                                                height: 14
                                                color: "white"
                                            }
                                        }

                                        WebEngineView {
                                            id: webView
                                            anchors.fill: parent
                                            focus: true
                                            profile: win.webProfile
                                            url: win.searxBase
                                            backgroundColor: Theme.cSurface
                                            settings.javascriptEnabled: true
                                            settings.forceDarkMode: true
                                            onLoadingChanged: function (loadRequest) {
                                                win.webShowError = !!loadRequest.error
                                            }
                                            Component.onCompleted: forceActiveFocus()
                                        }

                                        // ── Bookmarks library overlay ──────────────────────
                                        // Lists saved sites; clicking one navigates the webview
                                        // (and hides the panel). A trailing glyph removes it.
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 10
                                            visible: win.webShowBookmarks
                                            z: 200
                                            color: Qt.rgba(Theme.cSurface.r, Theme.cSurface.g, Theme.cSurface.b, 0.97)
                                            border.width: 1
                                            border.color: Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.25)
                                            ColumnLayout {
                                                anchors { fill: parent; margins: 14 }
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
                                                    model: WebBookmarksState.bookmarks
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
                                                                Text { anchors.centerIn: parent; text: "\u{F1B8B}"; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.cErr }
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
                                                                webView.url = modelData.url
                                                                win.webShowBookmarks = false
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 10
                                            visible: win.webShowError
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
                        Item {
                            id: agentPage
                            anchors.fill: parent
                            visible: win.tab === "agent"
                            clip: true

                            // The loopback server + WebEngine session are only brought up when
                            // the workspace startup policy is ON (agentEnsureUp returns early
                            // otherwise), matching GJS: a dormant workspace keeps the view blank
                            // until the circular toggle turns it on.
                            onVisibleChanged: if (visible) win.agentEnsureUp()
                            Component.onCompleted: if (visible) win.agentEnsureUp()

                            // Workspace wrapped DIRECTLY at radius 12 — no separate loading
                            // card, no 'starting workspace' overlay. Content is masked so all
                            // four corners clip to the frame (QtQuick clip is rectangular,
                            // hence the MultiEffect + agentMask source).
                            Rectangle {
                                id: agentFrame
                                x: tabPill.x + tabPill.width + win.ip - pageArea.x
                                y: win.ip - pageArea.y
                                width: listFrame.width - tabPill.x - tabPill.width - 2 * win.ip
                                height: listFrame.height - 2 * win.ip
                                clip: true
                                radius: 12
                                color: "transparent"
                                border.width: 0
                                border.color: Qt.rgba(win.wColor3.r, win.wColor3.g, win.wColor3.b, 0.22)

                                Item {
                                    anchors.fill: parent
                                    anchors.margins: 0
                                    clip: true
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        maskEnabled: true
                                        maskSource: agentMask
                                        maskThresholdMin: 0.5
                                        maskSpreadAtMin: 1.0
                                    }

                                    Item {
                                        id: agentMask
                                        anchors.fill: parent
                                        opacity: 0
                                        layer.enabled: true
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 12
                                            color: "white"
                                        }
                                    }

                                    // Always-alive direct WebEngineView. A view created lazily
                                    // inside a layer.enabled item cannot composite into the layer
                                    // texture and paints black, so it is hosted directly (like
                                    // the working websearch tab) and navigates only once the
                                    // loopback server answers.
                                    WebEngineView {
                                        anchors.fill: parent
                                        profile: win.agentProfile
                                        url: win.agentReady ? win.agentUrl : "about:blank"
                                        visible: win.agentReady
                                        backgroundColor: Qt.rgba(Theme.cSurface.r, Theme.cSurface.g, Theme.cSurface.b, 0.25)
                                        settings.javascriptEnabled: true
                                    }
                                }
                            }
                        }
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

                // Multi-select checkbox
                Rectangle {
                    visible: win.selectMode && !win.q
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
                        if (win.selectMode && !win.q) {
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
                width: Config.launcherFixedTileWidth * 2 + 10
                height: 76
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
                        spacing: 4
                        Repeater {
                            model: gcard.cardApps.slice(0, 4)
                            delegate: Item {
                                required property var modelData
                                width: 24; height: 24
                                Image {
                                    id: prevIcon
                                    anchors.fill: parent
                                    source: win.iconSource(modelData)
                                    sourceSize: Qt.size(24, 24)
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
                            text: gcard.cardName
                            font.pixelSize: 11
                            font.bold: true
                            color: Theme.cPrimary
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
