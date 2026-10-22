pragma Singleton

import QtQuick
import Quickshell

// ═══════════════════════════════════════════════════════════════════════════
//  TuiLaunch.qml — launcher for Terminal=true desktop entries.
//
//  Quickshell parses the flag (DesktopEntry.runInTerminal) but execute()
//  never honours it: the qs binary contains no terminal-spawn path at all.
//  TUI apps (btop/htop/nvtop/...) launched through entry.execute() therefore
//  start detached with no tty and die instantly -- which looks exactly like
//  "the app does not launch". Every launch surface (launcher grid, desktop
//  icons, dock, small launcher) must route entries through launchEntry() so
//  the terminal wrapper happens uniformly.
//
//  Terminal resolution order: $TERMINAL (HyprCandy's shell setup exports
//  TERMINAL=kitty), then the first installed common terminal. The chosen
//  terminal's exec-arg runs `bash -c <Exec line>`, keeping multi-token Exec
//  strings and shell metacharacters working like the old bash fallback.
//
//  Workspace-targeted launches ("Open on WS") go through hyprland's
//  exec_cmd dispatch instead of execDetached. That dispatch string is
//  embedded inside a Lua single-quoted literal ('...'), which forbids
//  literal newlines and single quotes, so wsCommand() emits a SELF-CONTAINED
//  one-line sh resolver (same terminal-choice logic as launch(), but
//  ';'/'&&'-joined and using only double quotes). It resolves the terminal
//  at dispatch time -- no async probe, no startup race.
// ═══════════════════════════════════════════════════════════════════════════

QtObject {
    id: root

    // Shared terminal-selection resolver statements, delimiter-joined by the
    // callers. launch() uses newlines (argv script); wsCommand() uses '; '
    // (single-line Lua literal). Kept as one source of truth so the two
    // paths can never drift apart on the candidate list or the sep rules.
    function _resolverLines() {
        return [
            "t=${TERMINAL:-kitty}; t=${t%% *}",
            "for c in \"$t\" kitty foot alacritty ghostty wezterm konsole xterm; do" +
                " command -v \"$c\" >/dev/null 2>&1 && { t=\"$c\"; break; }; done",
            "command -v \"$t\" >/dev/null 2>&1 || exit 1",
            "case \"${t##*/}\" in foot|*gnome-terminal|*mate-terminal) sep=-- ;; *) sep=-e ;; esac",
        ]
    }

    // Spawn execLine inside a resolved terminal window. Returns true when a
    // spawn was attempted.
    function launch(execLine) {
        const line = String(execLine ?? "").replace(/%[UuFfIiDdNnVvKk]/g, "").trim()
        if (line === "") return false
        // argv form: the entry line arrives as the inner bash's $0, so no
        // quoting of user content into the script text is ever needed.
        Quickshell.execDetached(["bash", "-c",
            _resolverLines().join("\n") + "\n" +
            "exec \"$t\" \"$sep\" bash -c \"$0\"",
            line])
        return true
    }

    // Entry-aware wrapper: honours runInTerminal, otherwise behaves exactly
    // like entry.execute(). execOverride (when non-empty) is the Exec line
    // the caller already has from its record. Returns true when handled.
    function launchEntry(entry, execOverride) {
        if (!entry) return false
        if (entry.runInTerminal === true || entry.terminal === true) {
            const o = String(execOverride ?? "")
            const line = o !== "" ? o
                : String(entry.command ?? entry.execString ?? "")
            if (line.trim() !== "" && launch(line)) return true
        }
        try { entry.execute(); return true } catch (_) { return false }
    }

    // One-line self-resolving command for hyprland exec_cmd dispatch
    // ("Open on Workspace" paths). Returns "" when the line is unusable.
    // The result is embedded in a Lua single-quoted literal downstream, so
    // it contains NO single quotes; exec content gets " and \ escaped.
    // envPrefix ("VAR=val " pairs, e.g. a dGPU's env) is injected INSIDE
    // the inner bash -c so the assignments export to the TUI process --
    // prefixing the compound resolver line instead would leave them as
    // non-exported shell locals and silently drop the GPU selection.
    function wsCommand(execLine, envPrefix) {
        const line = String(execLine ?? "").replace(/%[UuFfIiDdNnVvKk]/g, "").trim()
        if (line === "") return ""
        const inner = String(envPrefix ?? "") + line
        const safe = inner.replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/'/g, "")
        return _resolverLines().join("; ") +
            "; exec \"$t\" \"$sep\" bash -c \"" + safe + "\""
    }

    // Terminal=true probe for callers that only hold a record's desktopId /
    // class strings (the WS-dispatch menus). Resolution mirrors the byId
    // variants the launch surfaces use; first hit decides.
    function entryNeedsTerminal(desktopId, cls) {
        const cands = []
        if (desktopId) {
            cands.push(String(desktopId))
            cands.push(String(desktopId).replace(/\.desktop$/, ""))
        }
        if (cls) {
            const c = String(cls)
            cands.push(c, c.toLowerCase(), c.split(".").pop(), c.split(".").pop().toLowerCase())
        }
        for (const v of cands) {
            if (!v) continue
            const e = DesktopEntries.byId(v)
            if (e) return e.runInTerminal === true || e.terminal === true
        }
        return false
    }
}
