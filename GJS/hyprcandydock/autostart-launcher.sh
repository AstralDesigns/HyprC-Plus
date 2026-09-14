#!/usr/bin/env bash
# TEMPORARY — standalone HyprCandy app-launcher diagnostic starter.
#
# This intentionally does not start the dock. It runs only app-launcher.js so
# its GTK/GJS/WebKit/Electron output can be inspected independently of the
# dock's autostart log.
#
# Example:
#   setsid ~/.hyprcandy/GJS/hyprcandydock/autostart-launcher.sh \
#     </dev/null >/tmp/hyprcandy-app-launcher.log 2>&1 &
#
# Stop it with:
#   pkill -f 'gjs.*app-launcher\\.js'

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCHER="$SCRIPT_DIR/app-launcher.js"
LOG_FILE="${HYPRCANDY_LAUNCHER_LOG:-/tmp/hyprcandy-launcher-wrapper.log}"

# Make the wrapper's own diagnostics visible even when the caller redirects
# stdout/stderr. The app-launcher process inherits this file descriptor.
mkdir -p "$(dirname "$LOG_FILE")"
exec >>"$LOG_FILE" 2>&1

printf '\n[%s] starting standalone app-launcher\n' "$(date --iso-8601=seconds)"
printf '[launcher-wrapper] script_dir=%s\n' "$SCRIPT_DIR"
printf '[launcher-wrapper] launcher=%s\n' "$LAUNCHER"
printf '[launcher-wrapper] WAYLAND_DISPLAY=%s\n' "${WAYLAND_DISPLAY:-<unset>}"
printf '[launcher-wrapper] XDG_RUNTIME_DIR=%s\n' "${XDG_RUNTIME_DIR:-<unset>}"

if [[ ! -f "$LAUNCHER" ]]; then
    printf '[launcher-wrapper] ERROR: launcher not found: %s\n' "$LAUNCHER"
    exit 1
fi

if pgrep -f 'gjs.*app-launcher\.js' >/dev/null 2>&1; then
    printf '[launcher-wrapper] ERROR: an app-launcher instance is already running\n'
    printf '[launcher-wrapper] stop it first with: pkill -f '\''gjs.*app-launcher\\.js'\''\n'
    exit 2
fi

# The launcher uses GTK4 layer-shell for its Wayland surface. Match the
# production startup scripts without touching the user's global environment.
if [[ -f /usr/lib/libgtk4-layer-shell.so ]]; then
    export LD_PRELOAD="/usr/lib/libgtk4-layer-shell.so${LD_PRELOAD:+:$LD_PRELOAD}"
elif [[ -f /usr/lib64/libgtk4-layer-shell.so ]]; then
    export LD_PRELOAD="/usr/lib64/libgtk4-layer-shell.so${LD_PRELOAD:+:$LD_PRELOAD}"
else
    printf '[launcher-wrapper] WARNING: libgtk4-layer-shell.so was not found\n'
fi

# Preserve normal Wayland selection while making GJS/GLib diagnostics explicit.
# Use the quietest default so the app launcher only emits warnings/errors.
export GDK_BACKEND="${GDK_BACKEND:-wayland}"
export G_MESSAGES_DEBUG="${G_MESSAGES_DEBUG:-none}"
# IMPORTANT: do NOT export GJS_DEBUG_OUTPUT unconditionally. GJS treats "the
# var is set at all" as "log every debug topic" unless GJS_DEBUG_TOPICS also
# narrows it down — so setting GJS_DEBUG_OUTPUT here unconditionally was
# silently turning on GJS's full internal trace firehose (every "JS G NS:",
# "JS G OBJ:", "JS IMPORT:", "JS MAINLOOP:" line — thousands of lines per
# run) on EVERY use of this script, which is the opposite of "quietest
# default". G_MESSAGES_DEBUG=none above only silences GLib's own
# g_message()/g_debug() calls; it has no effect on this separate GJS
# tracing system. Only opt into it explicitly when actually debugging GJS
# internals: HYPRCANDY_GJS_TRACE=1 ./autostart-launcher.sh ...
if [[ "${HYPRCANDY_GJS_TRACE:-0}" == "1" ]]; then
    export GJS_DEBUG_OUTPUT="${GJS_DEBUG_OUTPUT:-stderr}"
    export GJS_DEBUG_TOPICS="${GJS_DEBUG_TOPICS:-JS ERROR;JS LOG}"
fi

cd "$SCRIPT_DIR" || exit 1
printf '[launcher-wrapper] exec: gjs %s %s\n' "$LAUNCHER" "$*"
exec gjs "$LAUNCHER" "$@"
