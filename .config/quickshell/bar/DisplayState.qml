pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  DisplayState — nwg-displays-style monitor management for the Control Center.
//
//  Reads live output state from `hyprctl monitors -j`, keeps an editable
//  "draft" working copy, and applies it by regenerating
//  ~/.config/hypr/monitors.lua (the hl.monitor{} DSL that hyprland.lua already
//  dofile()s) followed by `hyprctl reload`. DPMS is runtime-only and routed
//  through the dpms dispatcher.
// ═══════════════════════════════════════════════════════════════════════════

Singleton {
    id: ds

    readonly property string home: Quickshell.env("HOME")
    readonly property string luaPath: home + "/.config/hypr/monitors.lua"

    // ── Live + working state ───────────────────────────────────────────────
    property var   monitors: []        // raw hyprctl monitors -j (last read)
    property var   draft:    []        // editable per-monitor configs
    property int   selected: 0
    property bool  dirty:    false
    property string _baseline: ""   // JSON snapshot of the last committed draft
    property bool  loaded:   false
    property string statusText: ""

    readonly property real snapThreshold: 12   // logical px snap distance

    // ── Read live monitor state ────────────────────────────────────────────
    Process {
        id: readProc
        command: ["hyprctl", "monitors", "-j"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var arr = JSON.parse(this.text)
                    if (!Array.isArray(arr)) throw new Error("not-array")
                    ds.monitors = arr
                    ds._buildDraft(arr)
                    ds.loaded = true
                    ds.statusText = "Loaded " + arr.length + " display" + (arr.length === 1 ? "" : "s")
                } catch (e) {
                    ds.statusText = "Failed to read displays"
                }
            }
        }
    }

    function refresh() { if (!readProc.running) readProc.running = true }

    // ── Helpers: normalise hyprctl fields into our draft shape ──────────────
    function _modeStr(m) {
        return m.width + "x" + m.height + "@" + Number(m.refreshRate).toFixed(2)
    }
    function _availableModes(m) {
        var out = []
        var am = m.availableModes || []
        for (var i = 0; i < am.length; i++)
            out.push(String(am[i]).replace(/Hz\s*$/, ""))
        return out
    }
    function _bitdepth(m) {
        return /101010/.test(m.currentFormat || "") ? 10 : 8
    }

    function _buildDraft(arr) {
        var keepSel = ds.selected
        var d = []
        for (var i = 0; i < arr.length; i++) {
            var m = arr[i]
            var modes = _availableModes(m)
            var cur = _modeStr(m)
            var mode = "preferred"
            for (var k = 0; k < modes.length; k++)
                if (modes[k] === cur) mode = modes[k]
            var mirror = (m.mirrorOf && m.mirrorOf !== "none") ? m.mirrorOf : ""
            d.push({
                name:    m.name,
                desc:    m.description || ((m.make || "") + " " + (m.model || "")).trim(),
                modes:   modes,
                mode:    mode,
                x:       m.x | 0,
                y:       m.y | 0,
                w:       m.width | 0,
                h:       m.height | 0,
                pw:      m.physicalWidth | 0,
                ph:      m.physicalHeight | 0,
                scale:   Number(m.scale) || 1,
                transform: m.transform | 0,
                mirror:  mirror,
                bitdepth: _bitdepth(m),
                cm:      m.colorManagementPreset || "srgb",
                vrr:     m.vrr ? 1 : 0,
                sdrbrightness: Number(m.sdrBrightness) || 1,
                sdrsaturation: Number(m.sdrSaturation) || 1,
                disabled: !!m.disabled,
                dpms:    !!m.dpmsStatus,
                focused: !!m.focused
            })
        }
        ds.draft = d
        ds.selected = (keepSel < d.length) ? keepSel : 0
        ds._baseline = JSON.stringify(ds._trimDisplays())
        ds.dirty = false
    }

    // ── Draft mutation ─────────────────────────────────────────────────────
    // Each mutation replaces the touched entry with a NEW object. `draft` is a
    // JS array of plain objects; QML only re-emits the `sel` binding when the
    // object reference changes, so an in-place edit would leave every form
    // control (bit-depth / color / sliders / pills) visually stale even though
    // the value was stored. (The canvas is unaffected: its Repeater binds to the
    // `draft` array itself, which is always reassigned.)
    function _cloneEntry(o) {
        var e = {}
        for (var k in o) e[k] = o[k]
        return e
    }

    // dirty reflects whether the working draft differs from the last committed
    // baseline, so editing a value and setting it back clears the pending state.
    function _syncDirty() {
        ds.dirty = (JSON.stringify(ds._trimDisplays()) !== ds._baseline)
    }

    function setField(idx, key, val) {
        var d = ds.draft.slice()
        if (!d[idx]) return
        var e = ds._cloneEntry(d[idx])
        e[key] = val
        d[idx] = e
        ds.draft = d
        ds._syncDirty()
    }

    function setPosition(idx, x, y) {
        var d = ds.draft.slice()
        if (!d[idx]) return
        var e = ds._cloneEntry(d[idx])
        e.x = Math.round(x)
        e.y = Math.round(y)
        d[idx] = e
        ds.draft = d
        ds._syncDirty()
    }

    // Snap the dragged monitor's edges to neighbours, then commit.
    function snapAndCommit(idx) {
        var d = ds.draft
        if (!d[idx]) return
        var me = d[idx]
        var nx = me.x, ny = me.y
        var t = ds.snapThreshold
        for (var i = 0; i < d.length; i++) {
            if (i === idx) continue
            var o = d[i]
            // X axis: align lefts, rights, and butt edges together
            if (Math.abs(o.x - nx) <= t)               nx = o.x
            if (Math.abs((o.x + o.w) - (nx + me.w)) <= t) nx = (o.x + o.w) - me.w
            if (Math.abs((o.x + o.w) - nx) <= t)       nx = o.x + o.w
            if (Math.abs(o.x - (nx + me.w)) <= t)      nx = o.x - me.w
            // Y axis
            if (Math.abs(o.y - ny) <= t)               ny = o.y
            if (Math.abs((o.y + o.h) - (ny + me.h)) <= t) ny = (o.y + o.h) - me.h
            if (Math.abs((o.y + o.h) - ny) <= t)       ny = o.y + o.h
            if (Math.abs(o.y - (ny + me.h)) <= t)      ny = o.y - me.h
        }
        setPosition(idx, nx, ny)
    }

    // ── Generate monitors.lua (hl.monitor{} DSL; trailing commas are valid) ─
    function _q(s) {
        // strip anything that could break the double-quoted lua string
        var t = String(s === undefined ? "" : s)
        t = t.split('"').join("")
        t = t.split("\\").join("")
        t = t.split("\n").join(" ")
        t = t.split("\r").join(" ")
        return t
    }

    function generateLua() {
        var L = []
        L.push("-- Generated by HyprCandy Control Center (Display tab).")
        L.push("-- Re-generate from the Display panel rather than editing by hand.")
        L.push("")
        var d = ds.draft
        for (var i = 0; i < d.length; i++) {
            var m = d[i]
            L.push("hl.monitor({")
            L.push('    output = "' + _q(m.name) + '",')
            if (m.disabled) {
                L.push("    disabled = true,")
                L.push("})")
                L.push("")
                continue
            }
            L.push('    mode = "' + _q(m.mode) + '",')
            if (m.mirror && m.mirror.length) {
                L.push('    mirror = "' + _q(m.mirror) + '",')
            } else {
                L.push('    position = "' + (m.x | 0) + "x" + (m.y | 0) + '",')
            }
            L.push("    scale = " + (Number(m.scale) || 1) + ",")
            if ((m.transform | 0) !== 0) L.push("    transform = " + (m.transform | 0) + ",")
            L.push("    bitdepth = " + (m.bitdepth | 0) + ",")
            if (m.cm && m.cm.length) L.push('    cm = "' + _q(m.cm) + '",')
            if ((m.vrr | 0) !== 0) L.push("    vrr = " + (m.vrr | 0) + ",")
            if (Number(m.sdrbrightness) !== 1) L.push("    sdrbrightness = " + Number(m.sdrbrightness) + ",")
            if (Number(m.sdrsaturation) !== 1) L.push("    sdrsaturation = " + Number(m.sdrsaturation) + ",")
            L.push("})")
            L.push("")
        }
        return L.join("\n")
    }

    // ── Apply: write monitors.lua (quoted heredoc = literal body) + reload ──
    Process {
        id: applyProc
        running: false
        onExited: {
            ds.statusText = "Applied — hyprctl reload (rc " + exitCode + ")"
            ds.refresh()
            // Profile-bound wallpapers: let the outputs settle, then push them.
            if (ds.bindWallpapers && Object.keys(ds.pendingWallpapers || {}).length > 0)
                ds.applyWallpapers(ds.pendingWallpapers)
        }
    }

    function apply() {
        var lua = generateLua()
        // Quickshell drops embedded newlines in the `bash -c` SCRIPT argument, so
        // a heredoc writes nothing (bash still exits 0). Pass the generated lua as
        // a separate argv element ($1) — data args preserve newlines verbatim.
        applyProc.command = ["/bin/bash", "-c",
            "printf '%s' \"$1\" > '" + luaPath + "' && hyprctl reload 2>/dev/null || true",
            "_", lua]
        applyProc.running = true
    }

    // Discard edits and reload the working draft from live state.
    function reset() {
        ds._buildDraft(ds.monitors)
        ds.statusText = "Reverted to current layout"
    }

    // ── DPMS (runtime only, via dispatcher) ────────────────────────────────
    function setDpms(idx, on) {
        var m = ds.draft[idx]
        if (!m) return
        setField(idx, "dpms", on)
        Quickshell.execDetached(["hyprctl", "dispatch", on ? "dpmson" : "dpmsoff", m.name])
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Profiles (nwg-displays style) + profile-bound wallpapers
    //
    //  A profile is a JSON snapshot of the working draft plus a per-output
    //  wallpaper map. Layout: ~/.config/hypr/display-profiles/<name>.json and
    //  an .active marker. Loading populates the draft (marked dirty); the user
    //  reviews then hits Apply, which also re-applies the bound wallpapers via
    //  awww (our wallpaper daemon), mirroring nwg-displays' swww flow.
    // ═══════════════════════════════════════════════════════════════════════
    readonly property string profileDir: home + "/.config/hypr/display-profiles"
    readonly property string activeFile: profileDir + "/.active"
    readonly property string wallStore:  home + "/.config/wallpaper/monitors.json"

    property var    profileNames:     []
    property string activeProfile:    ""
    property bool   bindWallpapers:   true
    property var    pendingWallpapers: ({})   // { output: path } from last loaded profile

    function _safeName(n) {
        var t = String(n === undefined ? "" : n)
        t = t.split("/").join("_")
        t = t.split("\\").join("_")
        t = t.split("\n").join("")
        t = t.split("\r").join("")
        t = t.split("'").join("")
        return t
    }

    // Trim the live draft down to persistable fields (drop modes/w/h — re-derived).
    function _trimDisplays() {
        var out = []
        for (var i = 0; i < ds.draft.length; i++) {
            var m = ds.draft[i]
            out.push({
                name: m.name, mode: m.mode, x: m.x, y: m.y,
                scale: m.scale, transform: m.transform, mirror: m.mirror,
                bitdepth: m.bitdepth, cm: m.cm, vrr: m.vrr,
                sdrbrightness: m.sdrbrightness, sdrsaturation: m.sdrsaturation,
                disabled: m.disabled, dpms: m.dpms
            })
        }
        return out
    }

    // ── list profiles + read active marker ─────────────────────────────────
    Process {
        id: listProc
        running: false
        command: ["/bin/bash", "-c",
            "mkdir -p '" + ds.profileDir + "'; " +
            "for f in '" + ds.profileDir + "'/*.json; do [ -e \"$f\" ] && basename \"$f\" .json; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                var names = this.text.split("\n").filter(function (s) { return s.trim() !== "" })
                names.sort()
                ds.profileNames = names
            }
        }
    }
    Process {
        id: activeReadProc
        running: false
        command: ["cat", ds.activeFile]
        stdout: StdioCollector { onStreamFinished: ds.activeProfile = this.text.trim() }
    }
    function refreshProfiles() {
        if (!listProc.running) listProc.running = true
        if (!activeReadProc.running) activeReadProc.running = true
    }

    Process {
        id: activeWriteProc
        running: false
    }
    function _writeActive(name) {
        var n = ds._safeName(name)
        activeWriteProc.command = ["/bin/bash", "-c",
            "mkdir -p '" + ds.profileDir + "' && printf '%s' '" + n + "' > '" + ds.activeFile + "'"]
        activeWriteProc.running = true
    }

    // ── save (capture current per-output wallpapers, then write profile) ────
    Process {
        id: wallReadProc
        running: false
        property string forName: ""
        command: ["cat", ""]
        stdout: StdioCollector {
            onStreamFinished: {
                var mons = {}
                try { mons = JSON.parse(this.text) } catch (e) { mons = {} }
                ds._writeProfile(wallReadProc.forName, mons)
            }
        }
    }
    function saveProfile(name) {
        name = (name || "").trim()
        if (!name) { ds.statusText = "Enter a profile name to save"; return }
        wallReadProc.forName = name
        wallReadProc.command = ["cat", ds.wallStore]
        wallReadProc.running = true
    }
    function saveCurrent() { if (ds.activeProfile) saveProfile(ds.activeProfile) }

    function _writeProfile(name, mons) {
        var walls = {}
        for (var i = 0; i < ds.draft.length; i++) {
            var nm = ds.draft[i].name
            if (mons && mons[nm])      walls[nm] = mons[nm]
            else if (mons && mons["all"]) walls[nm] = mons["all"]
        }
        var data = { displays: ds._trimDisplays(), wallpapers: walls }
        var json = JSON.stringify(data)
        var path = ds.profileDir + "/" + ds._safeName(name) + ".json"
        // json passed as $1 (separate argv) — avoids the heredoc/newline issue.
        writeProc.command = ["/bin/bash", "-c",
            "mkdir -p '" + ds.profileDir + "' && printf '%s' \"$1\" > '" + path + "'",
            "_", json]
        writeProc.running = true
        ds.activeProfile = name
        ds.pendingWallpapers = walls
        ds._writeActive(name)
        ds.refreshProfiles()
        ds.statusText = "Saved profile: " + name
    }
    Process { id: writeProc; running: false }

    // ── load (populate draft from a profile; user then Applies) ─────────────
    Process {
        id: loadProc
        running: false
        property string want: ""
        command: ["cat", ""]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text)
                    ds._applyProfileData(data)
                    ds.activeProfile = loadProc.want
                    ds._writeActive(loadProc.want)
                    ds.statusText = "Loaded profile: " + loadProc.want + "  (hit Apply)"
                } catch (e) {
                    ds.statusText = "Failed to load profile"
                }
            }
        }
    }
    function loadProfile(name) {
        if (!name) return
        loadProc.want = name
        loadProc.command = ["cat", ds.profileDir + "/" + ds._safeName(name) + ".json"]
        loadProc.running = true
    }

    // Merge profile values onto the LIVE draft (only for currently-connected
    // outputs, so we keep live modes/w/h). Mirrors nwg's "match by name" load.
    function _applyProfileData(data) {
        var d = ds.draft.slice()
        var byName = {}
        for (var i = 0; i < d.length; i++) byName[d[i].name] = i
        var prof = data.displays || []
        for (var j = 0; j < prof.length; j++) {
            var p = prof[j]
            var idx = byName[p.name]
            if (idx === undefined) continue
            var e = ds._cloneEntry(d[idx])
            if (p.mode !== undefined)        e.mode = p.mode
            if (p.x !== undefined)           e.x = p.x | 0
            if (p.y !== undefined)           e.y = p.y | 0
            if (p.scale !== undefined)       e.scale = Number(p.scale)
            if (p.transform !== undefined)   e.transform = p.transform | 0
            if (p.mirror !== undefined)      e.mirror = p.mirror
            if (p.bitdepth !== undefined)    e.bitdepth = p.bitdepth | 0
            if (p.cm !== undefined)          e.cm = p.cm
            if (p.vrr !== undefined)         e.vrr = p.vrr | 0
            if (p.sdrbrightness !== undefined) e.sdrbrightness = Number(p.sdrbrightness)
            if (p.sdrsaturation !== undefined) e.sdrsaturation = Number(p.sdrsaturation)
            if (p.disabled !== undefined)    e.disabled = !!p.disabled
            if (p.dpms !== undefined)        e.dpms = !!p.dpms
            d[idx] = e
        }
        ds.draft = d
        ds.pendingWallpapers = data.wallpapers || {}
        ds._syncDirty()
    }

    // ── delete ─────────────────────────────────────────────────────────────
    Process { id: delProc; running: false }
    function deleteProfile(name) {
        if (!name) return
        var p = ds.profileDir + "/" + ds._safeName(name) + ".json"
        delProc.command = ["/bin/bash", "-c", "rm -f '" + p + "'"]
        delProc.running = true
        if (ds.activeProfile === name) { ds.activeProfile = ""; ds._writeActive("") }
        ds.refreshProfiles()
        ds.statusText = "Deleted profile: " + name
    }

    // ── wallpaper application (awww, per output) after layout settles ──────
    Process { id: wpProc; running: false }
    function applyWallpapers(map) {
        if (!map) return
        var cmds = []
        for (var out in map) {
            var path = map[out]
            if (!path) continue
            var p = String(path).split("'").join("")
            var o = String(out).split("'").join("")
            cmds.push("[ -f '" + p + "' ] && awww img --outputs '" + o + "' '" + p + "' 2>/dev/null || true")
        }
        if (cmds.length === 0) return
        // sleep first: give the just-reloaded outputs time to settle before painting
        wpProc.command = ["/bin/bash", "-c", "sleep 1.2; " + cmds.join("; ")]
        wpProc.running = true
    }
}
