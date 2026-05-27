#!/usr/bin/env python3
"""
org.freedesktop.Notifications DBus service for Quickshell.
Claims the well-known name so swaync/dunst are not needed.
Emits JSON lines to stdout for QS to consume.

Ensure this starts before swaync or kill swaync first:
  exec-once = pkill -x swaync; sleep 0.2; qs -c ~/.config/quickshell/notifications
"""

import sys
import os
import re
import time
import json
import tempfile
import subprocess
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

NOTIF_IFACE   = "org.freedesktop.Notifications"
NOTIF_PATH    = "/org/freedesktop/Notifications"
DBUS_NAME     = "org.freedesktop.Notifications"

def emit(obj):
    print(json.dumps(obj), flush=True)

URGENCY_MAP = {0: "low", 1: "normal", 2: "critical"}

# ── Icon resolution ────────────────────────────────────────────────────────
# Resolution priority (mirrors how swaync works):
#   1. Absolute path in app_icon → use directly
#   2. image-data hint → decode raw ARGB pixels → save PNG to /tmp
#   3. image-path hint → resolve as file or icon name
#   4. app_icon name → GTK icon theme lookup (honours user theme)
#   5. app_icon name → manual XDG search (hicolor + common themes)
#   6. Screenshot thumbnail → if summary/body mentions a screenshot file
#   7. Favicon → if app is a browser and body contains a URL

def _resolve_icon_name(icon_name: str) -> str:
    """Resolve an icon name to an absolute path via GTK theme then XDG search."""
    if not icon_name:
        return ""
    if os.path.isabs(icon_name) and os.path.isfile(icon_name):
        return icon_name

    # GTK icon theme — most accurate, honours the user's current theme
    try:
        import gi
        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk
        theme = Gtk.IconTheme.get_default()
        # Try multiple sizes, prefer larger
        for sz in (64, 48, 128, 32, 256):
            info = theme.lookup_icon(icon_name, sz, 0)
            if info:
                path = info.get_filename()
                if path and os.path.isfile(path):
                    return path
    except Exception:
        pass

    # Manual XDG search — catches icons the GTK theme misses (e.g. flatpak apps)
    xdg_data = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")
    xdg_data += [os.path.expanduser("~/.local/share")]
    # Check user's configured theme from GTK settings if possible
    try:
        theme_names = []
        settings_file = os.path.expanduser("~/.config/gtk-3.0/settings.ini")
        if os.path.isfile(settings_file):
            with open(settings_file) as f:
                for line in f:
                    if "gtk-icon-theme-name" in line:
                        theme_names.append(line.split("=")[-1].strip())
        theme_names += ["hicolor", "Adwaita", "breeze", "Papirus", "gnome"]
    except Exception:
        theme_names = ["hicolor", "Adwaita", "breeze", "gnome"]

    sizes = ["scalable", "64x64", "48x48", "128x128", "32x32", "256x256", "22x22"]
    categories = ["apps", "status", "devices", "mimetypes", "actions", "places"]
    exts = [".svg", ".png", ".xpm"]

    for base in xdg_data:
        for theme in theme_names:
            for size in sizes:
                for cat in categories:
                    for ext in exts:
                        p = os.path.join(base, "icons", theme, size, cat, icon_name + ext)
                        if os.path.isfile(p):
                            return p
    # pixmaps fallback
    for base in xdg_data:
        for ext in (".png", ".svg", ".xpm"):
            p = os.path.join(base, "pixmaps", icon_name + ext)
            if os.path.isfile(p):
                return p
    return ""


def _decode_image_data(hints: dict, nid: int) -> str:
    """Decode image-data or image_data hint (raw ARGB pixels) to a temp PNG.

    The hint is a struct: (width, height, rowstride, has_alpha, bpp, n_channels, data)
    Used by Spotify (album art), Firefox (site icon), and many Electron apps.
    """
    for key in ("image-data", "image_data"):
        if key not in hints:
            continue
        try:
            w, h, rs, has_alpha, bpp, channels, data = hints[key]
            w, h, rs = int(w), int(h), int(rs)
            mode = "RGBA" if has_alpha else "RGB"
            from PIL import Image as _Img
            img = _Img.frombytes(mode, (w, h), bytes(data), "raw", mode, rs)
            path = f"/tmp/qs_notif_img_{nid}.png"
            img.save(path)
            return path
        except Exception:
            pass
    return ""


def _screenshot_thumbnail(summary: str, body: str, nid: int) -> str:
    """If the notification is a screenshot (from grimblast/grim/flameshot etc.)
    try to find the saved file and return its path as the thumbnail.

    grimblast saves to ~/Pictures/Screenshots/ and emits the path in the body.
    grim+slurp doesn't notify by default but custom scripts often embed the path.
    flameshot emits "screenshot saved to <path>" in the body.
    """
    # Look for an image file path in summary or body
    for text in (body, summary):
        if not text:
            continue
        # Match /path/to/file.png or ~/path/to/file.png
        matches = re.findall(r"(?:~|/)[^\s\"'<>]+\.(?:png|jpg|jpeg|webp)", text)
        for m in matches:
            expanded = os.path.expanduser(m)
            if os.path.isfile(expanded):
                return expanded
    # Common screenshot dirs as fallback — pick most recent file
    screenshot_dirs = [
        os.path.expanduser("~/Pictures/Screenshots"),
        os.path.expanduser("~/Pictures"),
        os.path.expanduser("~/Screenshots"),
    ]
    for d in screenshot_dirs:
        if not os.path.isdir(d):
            continue
        try:
            files = sorted(
                [os.path.join(d, f) for f in os.listdir(d)
                 if f.lower().endswith((".png", ".jpg", ".jpeg"))],
                key=os.path.getmtime, reverse=True
            )
            if files:
                # Only use if modified within the last 10 seconds
                if os.path.getmtime(files[0]) > (time.time() - 10):
                    return files[0]
        except Exception:
            pass
    return ""


def _is_screenshot_notif(app_name: str, summary: str, body: str) -> bool:
    """Detect screenshot notifications from common tools."""
    text = " ".join([app_name, summary, body]).lower()
    keywords = ("screenshot", "grimblast", "grim", "flameshot",
                 "spectacle", "captured", "snipped", "screen capture")
    return any(k in text for k in keywords)


def _resolve_all(app_name: str, app_icon: str, hints: dict, summary: str, body: str, nid: int) -> str:
    """Full icon resolution pipeline."""

    # 1. image-data hint (inline pixels — album art, site icons from browsers)
    path = _decode_image_data(hints, nid)
    if path:
        return path

    # 2. Absolute path in app_icon — covers notify-send -i /path/to/screenshot.png
    if app_icon:
        ic = app_icon
        if ic.startswith("file://"):
            ic = ic[7:]
        if os.path.isabs(ic) and os.path.isfile(ic):
            return ic

    # 3. image-path hint (file path or icon name)
    img_path_hint = str(hints.get("image-path", hints.get("image_path", "")))
    if img_path_hint:
        if img_path_hint.startswith("file://"):
            img_path_hint = img_path_hint[7:]
        if os.path.isabs(img_path_hint) and os.path.isfile(img_path_hint):
            return img_path_hint
        resolved = _resolve_icon_name(img_path_hint)
        if resolved:
            return resolved

    # 4. Screenshot thumbnail — check before generic icon so we show the actual image
    if _is_screenshot_notif(app_name, summary, body):
        thumb = _screenshot_thumbnail(summary, body, nid)
        if thumb:
            return thumb

    # 5. app_icon name → GTK theme + XDG search
    if app_icon:
        resolved = _resolve_icon_name(app_icon)
        if resolved:
            return resolved

    # 6. app_name as fallback icon name (many apps set app_name = icon name)
    if app_name:
        resolved = _resolve_icon_name(app_name.lower().replace(" ", "-"))
        if resolved:
            return resolved
        # Try without hyphens too
        resolved = _resolve_icon_name(app_name.lower().replace(" ", ""))
        if resolved:
            return resolved

    return ""


# ── MPRIS media notification ───────────────────────────────────────────────
# Polls playerctl every 3 seconds. When a new track starts playing emits a
# synthetic notify event with a circular thumbnail generated by ImageMagick
# (same pipeline as candylock). Reuses notification ID 0xMEDIA (reserved).

MEDIA_NOTIF_ID = 0xDEAD   # fixed synthetic ID so updates replace themselves
_last_media_key = ""      # "artist|title" of last emitted notification
_art_tmp_raw = "/tmp/qs_media_notif_raw.png"


def _fetch_art_circle(art_url: str) -> str:
    """Download/copy art and convert to 96px circle PNG via ImageMagick.

    The output path is derived from a short hash of art_url so each unique
    album/track art maps to a distinct file.  Qt's image cache keys on the
    file:// URL, so a new path forces a fresh texture load — no stale art.
    Returns path on success, empty string on failure.
    """
    if not art_url:
        return ""
    import hashlib
    art_hash  = hashlib.md5(art_url.encode()).hexdigest()[:10]
    # Include timestamp in filename for robust cache-busting
    dest_path = f"/tmp/qs_media_art_{art_hash}_{int(time.time())}.png"

    src_path = art_url
    if art_url.startswith("file://"):
        src_path = art_url[7:]
    elif art_url.startswith("http"):
        try:
            import urllib.request
            urllib.request.urlretrieve(art_url, _art_tmp_raw)
            src_path = _art_tmp_raw
        except Exception:
            return ""
    if not os.path.isfile(src_path):
        return ""
    try:
        result = subprocess.run(
            ["magick", src_path,
             "-resize", "96x96^", "-gravity", "center", "-extent", "96x96",
             "(", "+clone", "-alpha", "extract",
             "-fill", "black", "-colorize", "100",
             "-fill", "white", "-draw", "circle 48,48 48,0", ")",
             "-compose", "CopyOpacity", "-composite",
             "-strip", dest_path],
            timeout=8, capture_output=True
        )
        if result.returncode == 0 and os.path.isfile(dest_path):
            return dest_path
    except Exception:
        pass
    return ""



# ── Desktop-entry database ─────────────────────────────────────────────────
# Built once on first use and cached.  Stores every .desktop file's key fields
# so we can do O(1) lookups instead of re-scanning on every notification.
#
# Each entry: { "id": str, "name": str, "wmc": str, "bin": str, "exec": str }
#   id   — basename without .desktop (e.g. "brave-browser")
#   name — Name= value (e.g. "Brave")
#   wmc  — StartupWMClass= lowercased (e.g. "brave-browser", "zen")
#   bin  — first word of Exec= stripped to basename, lowercased (e.g. "brave-browser")
#   exec — full Exec= line (for launch)

_DESKTOP_DIRS = [
    "/usr/share/applications",
    "/usr/local/share/applications",
    os.path.expanduser("~/.local/share/applications"),
    "/var/lib/flatpak/exports/share/applications",
    os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
]
_desktop_db: "list[dict] | None" = None


def _get_desktop_db() -> "list[dict]":
    global _desktop_db
    if _desktop_db is not None:
        return _desktop_db
    import glob as _glob
    db = []
    for d in _DESKTOP_DIRS:
        for df in _glob.glob(os.path.join(d, "*.desktop")):
            try:
                eid = os.path.basename(df).replace(".desktop", "")
                name = wmc = bin_ = exec_ = ""
                with open(df, encoding="utf-8", errors="ignore") as f:
                    in_main = True
                    for line in f:
                        line = line.strip()
                        if line.startswith("[") and line != "[Desktop Entry]":
                            in_main = False
                        if not in_main:
                            continue
                        if line.startswith("Name=") and not name:
                            name = line[5:].strip()
                        elif line.startswith("StartupWMClass="):
                            wmc = line[15:].strip().lower()
                        elif line.startswith("Exec=") and not exec_:
                            exec_ = line[5:].strip()
                            bin_ = exec_.split()[0].split("/")[-1].lower()
                            # Strip %U/%F/etc field codes from bin
                            bin_ = bin_.split("%")[0].rstrip("-").strip()
                db.append({"id": eid, "name": name, "wmc": wmc,
                           "bin": bin_, "exec": exec_})
            except Exception:
                continue
    _desktop_db = db
    return db


def _resolve_app_entry(key: str) -> "tuple[str, str]":
    """Given any of: desktop-entry hint, app_name, app_icon — return
    (desktop_entry_id, display_name).

    Resolution order (most → least authoritative):
      1. Exact id match (case-insensitive)
      2. StartupWMClass match   ← catches zen (wmc=zen, bin=firefox)
      3. id prefix/suffix match (e.g. "org.gnome.Foo" → "foo")
      4. Exec binary match      ← after WMClass so firefox binary doesn't eat zen
      5. Name match with qualifier stripping ("Spotify (Launcher)" → "spotify")

    Returns ("", "") when nothing matches.
    """
    if not key:
        return ("", "")
    k = key.lower().strip()
    # Strip common suffixes that appear in desktop-entry hints
    k_base = k.replace("-browser", "").replace("-desktop", "").replace("-stable", "")
    db = _get_desktop_db()

    # Pass 1 — exact id
    for e in db:
        if e["id"].lower() == k or e["id"].lower() == k + "-browser":
            return (e["id"], e["name"])

    # Pass 2 — StartupWMClass (before binary so zen wins over firefox)
    for e in db:
        if e["wmc"] and (e["wmc"] == k or e["wmc"] == k_base):
            return (e["id"], e["name"])

    # Pass 3 — id ends/starts with key (handles reverse-dns ids)
    for e in db:
        eid = e["id"].lower()
        if eid.endswith("-" + k) or eid.endswith("." + k) or eid.startswith(k + "-"):
            return (e["id"], e["name"])

    # Pass 4 — binary match (Exec= basename)
    for e in db:
        if e["bin"] and (e["bin"] == k or e["bin"] == k_base
                         or e["bin"].startswith(k + "-")
                         or e["bin"].endswith("-" + k)):
            return (e["id"], e["name"])

    # Pass 5 — Name match, stripping parenthetical qualifiers
    import re as _re
    k_stripped = _re.sub(r'\s*\(.*?\)\s*', '', k).strip()
    best_id = best_name = ""
    best_rank = 99
    for e in db:
        en = e["name"].lower()
        en_stripped = _re.sub(r'\s*\(.*?\)\s*', '', en).strip()
        rank = 99
        if en == k:
            rank = 0
        elif en_stripped == k_stripped:
            rank = 1
        if rank < best_rank:
            best_rank, best_id, best_name = rank, e["id"], e["name"]
        if best_rank == 0:
            break
    if best_id:
        return (best_id, best_name)

    return ("", "")


def _resolve_player_desktop_entry(player_name: str) -> "tuple[str, str]":
    """Given a playerctl playerName (e.g. 'brave', 'spotify', 'vlc'), return
    (desktop_entry_id, display_name) by querying MPRIS then the shared db."""
    if not player_name:
        return ("", "")
    pn_low = player_name.lower()

    # 1. MPRIS DesktopEntry property — authoritative
    try:
        import dbus as _dbus
        _bus = _dbus.SessionBus()
        _obj = _bus.get_object(f"org.mpris.MediaPlayer2.{player_name}", "/org/mpris/MediaPlayer2")
        _p   = _dbus.Interface(_obj, "org.freedesktop.DBus.Properties")
        de   = str(_p.Get("org.mpris.MediaPlayer2", "DesktopEntry"))
        iden = str(_p.Get("org.mpris.MediaPlayer2", "Identity"))
        if de:
            return (de, iden or player_name)
    except Exception:
        pass

    # 2. Shared desktop-entry db (StartupWMClass → binary → name)
    eid, name = _resolve_app_entry(player_name)
    if eid:
        return (eid, name or player_name)

    return (pn_low, player_name)


def _poll_mpris(notif_service):
    """Background thread: poll playerctl every 3 s, emit Playing notification on track change."""
    global _last_media_key
    _player_cache: dict = {}
    while True:
        time.sleep(3)
        try:
            result = subprocess.run(
                ["playerctl", "-a", "metadata", "--format",
                 "{{status}}\t{{playerName}}\t{{mpris:artUrl}}\t{{xesam:title}}\t{{xesam:artist}}\t{{xesam:album}}"],
                capture_output=True, text=True, timeout=3
            )
            if result.returncode != 0:
                _last_media_key = ""
                continue
            # Take the first Playing line
            playing_line = ""
            for line in result.stdout.strip().splitlines():
                if line.startswith("Playing\t"):
                    playing_line = line
                    break
            if not playing_line:
                _last_media_key = ""
                continue
            parts = playing_line.split("\t")
            if len(parts) < 5:
                continue
            player_name = parts[1].strip()
            art_url     = parts[2].strip()
            title       = parts[3].strip() or "Unknown Title"
            artist      = parts[4].strip()
            album       = parts[5].strip() if len(parts) > 5 else ""
            media_key   = player_name + "|" + artist + "|" + title
            if media_key == _last_media_key:
                continue
            _last_media_key = media_key
            if player_name not in _player_cache:
                _player_cache[player_name] = _resolve_player_desktop_entry(player_name)
            desktop_entry, display_name = _player_cache[player_name]
            icon_path = _fetch_art_circle(art_url)
            body_parts = []
            if artist: body_parts.append(artist)
            if album:  body_parts.append(album)
            body = " · ".join(body_parts)
            emit({
                "type":          "notify",
                "id":            MEDIA_NOTIF_ID,
                "app_name":      display_name or player_name,
                "desktop_entry": desktop_entry,
                "icon":          desktop_entry or player_name,
                "icon_path":     icon_path,
                "summary":       title,
                "body":          body,
                "urgency":       "low",
                "category":      "media.playing",
                "actions":       [],
                "timeout":       6000
            })
        except Exception:
            pass


class NotificationService(dbus.service.Object):
    def __init__(self, bus):
        self.bus = bus
        self._id_counter = 1
        super().__init__(bus, NOTIF_PATH)

    @dbus.service.method(NOTIF_IFACE,
                         in_signature="susssasa{sv}i",
                         out_signature="u")
    def Notify(self, app_name, replaces_id, app_icon,
               summary, body, actions, hints, expire_timeout):
        nid = int(replaces_id) if replaces_id else self._id_counter
        if not replaces_id:
            self._id_counter += 1

        urgency = URGENCY_MAP.get(int(hints.get("urgency", 1)), "normal")
        category = str(hints.get("category", ""))

        # Full icon resolution pipeline
        icon_path = _resolve_all(str(app_name), str(app_icon), hints, str(summary), str(body), nid)

        action_list = []
        it = iter(actions)
        for key in it:
            label = next(it, "")
            action_list.append({"key": str(key), "label": str(label)})

        # desktop-entry hint is the authoritative app id.
        # Chromium browsers (Brave, Zen, Chrome, Vivaldi…) always set it
        # on website notifications, e.g. "brave-browser", "zen-browser".
        desktop_entry_hint = str(hints.get("desktop-entry", hints.get("desktop_entry", "")))

        # Resolve to a verified desktop entry id + display name.
        # Use the hint as the primary key; fall back to app_icon then app_name.
        # _resolve_app_entry handles StartupWMClass so zen → zen-browser (not firefox),
        # and name-stripped matching so "spotify" → "Spotify (Launcher)".
        # Resolve app identity from desktop-entry hint then app_name only.
        # app_icon is intentionally excluded: Firefox-based browsers (Zen, Librewolf)
        # set app_icon = "org.mozilla.firefox" which would match firefox.desktop
        # before app_name = "Zen Browser" gets a chance to match zen.desktop.
        resolved_id = resolved_name = ""
        for _key in filter(None, [desktop_entry_hint, str(app_name)]):
            resolved_id, resolved_name = _resolve_app_entry(_key)
            if resolved_id:
                break
        # Prefer the hint value as the emitted desktop_entry when we couldn't
        # resolve it — QML's _findEntry may still succeed via DesktopEntries.byId.
        desktop_entry = resolved_id or desktop_entry_hint

        # Chromium web-push: source URL lives in several hint keys.
        source_url = ""
        for _hk in ("x-chromium-notification-url", "x-notification-url", "source-url"):
            _v = hints.get(_hk, "")
            if _v:
                source_url = str(_v)
                break
        if not source_url and body:
            _href = re.search(r'href=["\']?(https?://[^"\'\\s<>]+)', str(body))
            if _href:
                source_url = _href.group(1)
            else:
                _bare = re.search(r'https?://[^\s"\'<>]+', str(body))
                if _bare:
                    source_url = _bare.group(0)
        if not source_url:
            # Check summary and first line of body as bare domain candidates.
            # Chromium web-push sets body = "domain.com\nMessage text".
            _domain_candidates = [str(summary).strip()]
            if body:
                _domain_candidates.append(str(body).split("\n")[0].strip())
            _dom_re = re.compile(
                r'^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
            )
            for _dc in _domain_candidates:
                if _dom_re.match(_dc):
                    source_url = "https://" + _dc
                    break

        emit({
            "type":             "notify",
            "id":               nid,
            "app_name":         resolved_name or str(app_name),
            "desktop_entry":    desktop_entry,
            "icon":             str(app_icon),
            "icon_path":        icon_path,
            "summary":          str(summary),
            "body":             str(body),
            "urgency":          urgency,
            "category":         category,
            "actions":          action_list,
            "timeout":          int(expire_timeout),
            "source_url":       source_url
        })
        return dbus.UInt32(nid)

    @dbus.service.method(NOTIF_IFACE, in_signature="u", out_signature="")
    def CloseNotification(self, nid):
        emit({"type": "close", "id": int(nid)})
        self.NotificationClosed(dbus.UInt32(nid), dbus.UInt32(3))

    @dbus.service.method(NOTIF_IFACE, in_signature="", out_signature="ssss")
    def GetServerInformation(self):
        return ("quickshell-notif", "quickshell", "1.0", "1.2")

    @dbus.service.method(NOTIF_IFACE, in_signature="", out_signature="as")
    def GetCapabilities(self):
        return ["body", "body-markup", "actions", "persistence", "icon-static"]

    @dbus.service.signal(NOTIF_IFACE, signature="uu")
    def NotificationClosed(self, nid, reason):
        pass

    @dbus.service.signal(NOTIF_IFACE, signature="us")
    def ActionInvoked(self, nid, action_key):
        pass


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    session_bus = dbus.SessionBus()

    try:
        name = dbus.service.BusName(DBUS_NAME, session_bus,
                                     allow_replacement=True,
                                     replace_existing=True,
                                     do_not_queue=True)
    except dbus.exceptions.NameExistsException:
        emit({"type": "error", "msg": "Could not claim org.freedesktop.Notifications"})
        sys.exit(1)

    svc = NotificationService(session_bus)

    # Start MPRIS media polling in background thread
    import threading as _threading
    _t = _threading.Thread(target=_poll_mpris, args=(svc,), daemon=True)
    _t.start()

    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    main()
