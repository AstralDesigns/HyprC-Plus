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
    dest_path = f"/tmp/qs_media_art_{art_hash}.png"

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
             "-alpha", "off", "-compose", "CopyOpacity", "-composite",
             "-strip", dest_path],
            timeout=8, capture_output=True
        )
        if result.returncode == 0 and os.path.isfile(dest_path):
            return dest_path
    except Exception:
        pass
    return ""


def _poll_mpris(notif_service):
    """Background thread: poll playerctl every 3 s, emit Playing notification on track change."""
    global _last_media_key
    while True:
        time.sleep(3)
        try:
            result = subprocess.run(
                ["playerctl", "-a", "metadata", "--format",
                 "{{status}}\t{{mpris:artUrl}}\t{{xesam:title}}\t{{xesam:artist}}\t{{xesam:album}}"],
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
                # Nothing playing — reset so next play triggers notification
                _last_media_key = ""
                continue
            parts = playing_line.split("\t")
            if len(parts) < 4:
                continue
            art_url = parts[1].strip()
            title   = parts[2].strip() or "Unknown Title"
            artist  = parts[3].strip()
            album   = parts[4].strip() if len(parts) > 4 else ""
            media_key = artist + "|" + title
            if media_key == _last_media_key:
                continue
            _last_media_key = media_key
            # Build circular thumbnail
            icon_path = _fetch_art_circle(art_url)
            body_parts = []
            if artist: body_parts.append(artist)
            if album:  body_parts.append(album)
            body = " · ".join(body_parts)
            emit({
                "type":      "notify",
                "id":        MEDIA_NOTIF_ID,
                "app_name":  "Now Playing",
                "icon":      "audio-x-generic",
                "icon_path": icon_path,
                "summary":   title,
                "body":      body,
                "urgency":   "low",
                "category":  "media.playing",
                "actions":   [],
                "timeout":   6000
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

        emit({
            "type":      "notify",
            "id":        nid,
            "app_name":  str(app_name),
            "icon":      str(app_icon),
            "icon_path": icon_path,
            "summary":   str(summary),
            "body":      str(body),
            "urgency":   urgency,
            "category":  category,
            "actions":   action_list,
            "timeout":   int(expire_timeout)
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
