#!/usr/bin/env python3
"""
tray-icon-resolve.py — icon resolver for SystemTray.qml, ActiveWindow.qml,
                        and DesktopPinnedState.qml

Resolution order:
  1. Absolute path / image:// URL → pass through
  2. ~/Desktop/<name>.desktop → extract Icon= field, then resolve that icon
  3. Gio.DesktopAppInfo lookup (class → icon name):
       a. Try <variant>.desktop ID combinations
       b. Scan all apps for matching StartupWMClass
  4. GTK icon theme lookup on resolved/original name
  5. Manual XDG search (hicolor, Papirus, user theme…)
  6. /usr/share/pixmaps fallback
"""
import sys, os, warnings
warnings.filterwarnings("ignore")
# Suppress GTK/GLib stderr noise
os.environ.setdefault("G_MESSAGES_DEBUG", "none")
os.environ.setdefault("GTK_DEBUG", "")
import logging; logging.disable(logging.CRITICAL)

HOME = os.path.expanduser("~")
DESKTOP_DIR = os.path.join(HOME, "Desktop")


def _desktop_variants(cls: str):
    """Yield .desktop ID candidates derived from a window class."""
    seen, variants = set(), []
    def add(v):
        if v and v not in seen:
            seen.add(v); variants.append(v)
    add(cls); add(cls.lower())
    parts = cls.split(".")
    if len(parts) > 1:
        add(parts[-1]); add(parts[-1].lower())
        add("-".join(parts[1:]))
    add(cls.lower().replace(" ", "-").replace("_", "-"))
    return variants


def _read_desktop_file(path: str) -> dict:
    """Parse a .desktop file; return a dict of [Desktop Entry] keys."""
    result = {}
    in_main = False
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if line == "[Desktop Entry]":
                    in_main = True
                elif line.startswith("["):
                    in_main = False
                elif in_main and "=" in line:
                    k, _, v = line.partition("=")
                    result[k.strip()] = v.strip()
    except OSError:
        pass
    return result


def _icon_from_desktop_dir(name: str) -> str:
    """
    Check ~/Desktop/<name>.desktop (exact and case-insensitive) for an Icon=
    field, then resolve that icon name to an absolute path.
    Steam game shortcuts land here as e.g. Caliber.desktop / Combat_Master.desktop.
    """
    if not os.path.isdir(DESKTOP_DIR):
        return ""
    # Build a case-insensitive map of stem → filename on first call pattern.
    # We rebuild it every call since the directory can change; it's small.
    candidates = []
    name_lower = name.lower()
    try:
        for fname in os.listdir(DESKTOP_DIR):
            if not fname.endswith(".desktop"):
                continue
            stem = fname[:-8]  # strip ".desktop"
            # Match by stem exactly, case-insensitively, or with underscores/spaces
            stem_norm = stem.lower().replace("_", " ").replace("-", " ")
            name_norm = name_lower.replace("_", " ").replace("-", " ")
            if stem.lower() == name_lower or stem_norm == name_norm:
                candidates.append(fname)
    except OSError:
        return ""

    for fname in candidates:
        fpath = os.path.join(DESKTOP_DIR, fname)
        entry = _read_desktop_file(fpath)
        if entry.get("Type") != "Application":
            continue
        icon = entry.get("Icon", "")
        if not icon:
            continue
        # If the Icon field is already an absolute path, use it directly
        if os.path.isabs(icon) and os.path.isfile(icon):
            return icon
        # Otherwise resolve the icon name through the normal lookup chain
        # (GTK theme + XDG manual search), skipping the Gio step to avoid
        # infinite recursion since we're already in a file-based resolution.
        p = _gtk_lookup(icon)
        if p:
            return p
        p = _xdg_lookup(icon)
        if p:
            return p
        # Last resort: return the icon name itself so QML can try Quickshell.iconPath
        return icon

    return ""


def _gio_icon_name(cls: str) -> str:
    """Return an icon name (or absolute path) from DesktopAppInfo, or ''."""
    try:
        import gi
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio

        def _extract(info):
            if not info:
                return ""
            gicon = info.get_icon()
            if not gicon:
                return ""
            names = getattr(gicon, "get_names", lambda: None)()
            if names:
                return names[0]
            fobj = getattr(gicon, "get_file", lambda: None)()
            if fobj:
                p = getattr(fobj, "get_path", lambda: None)()
                if p and os.path.isfile(p):
                    return p
            return ""

        # Fast path: .desktop ID variants
        for v in _desktop_variants(cls):
            try:
                result = _extract(Gio.DesktopAppInfo.new(v + ".desktop"))
                if result:
                    return result
            except Exception:
                pass

        # Slow path: scan all apps for StartupWMClass match
        norm = cls.lower().replace("-", "").replace("_", "").replace(" ", "")
        for info in Gio.AppInfo.get_all():
            try:
                wm = getattr(info, "get_startup_wm_class", lambda: None)()
                if wm and (wm.lower() == cls.lower() or
                           wm.lower().replace("-","").replace("_","") == norm):
                    result = _extract(info)
                    if result:
                        return result
            except Exception:
                pass
    except Exception:
        pass
    return ""


def _gtk_lookup(name: str) -> str:
    """Look up an icon name in the GTK icon theme; return file path or ''."""
    try:
        import gi
        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk
        theme = Gtk.IconTheme.get_default()
        for sz in (32, 24, 48, 16, 64, 128, 256):
            info = theme.lookup_icon(name, sz, 0)
            if info:
                p = info.get_filename()
                if p and os.path.isfile(p):
                    return p
    except Exception:
        pass
    return ""


def _xdg_lookup(name: str) -> str:
    """Manual XDG icon search as fallback."""
    xdg_data = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")
    xdg_data += [os.path.expanduser("~/.local/share")]
    theme_names: list = []
    try:
        settings = os.path.expanduser("~/.config/gtk-3.0/settings.ini")
        if os.path.isfile(settings):
            with open(settings) as f:
                for line in f:
                    if "gtk-icon-theme-name" in line:
                        theme_names.append(line.split("=", 1)[-1].strip())
    except Exception:
        pass
    theme_names += ["hicolor", "Papirus", "Adwaita", "breeze", "gnome"]
    sizes = ["scalable", "32x32", "24x24", "48x48", "16x16", "64x64", "128x128", "256x256"]
    cats  = ["apps", "status", "devices", "mimetypes", "actions", "places"]
    exts  = [".svg", ".png", ".xpm"]
    for base in xdg_data:
        for theme in theme_names:
            for size in sizes:
                for cat in cats:
                    for ext in exts:
                        p = os.path.join(base, "icons", theme, size, cat, name + ext)
                        if os.path.isfile(p):
                            return p
    for base in xdg_data:
        for ext in (".png", ".svg", ".xpm"):
            p = os.path.join(base, "pixmaps", name + ext)
            if os.path.isfile(p):
                return p
    return ""


def resolve(name: str) -> str:
    if not name:
        return ""
    if name.startswith("image://") or name.startswith("file://"):
        return name
    if os.path.isabs(name) and os.path.isfile(name):
        return name

    # Step 1: ~/Desktop/<name>.desktop — catches Steam game shortcuts and any
    # other .desktop files that live outside XDG application directories.
    p = _icon_from_desktop_dir(name)
    if p and (os.path.isabs(p) or not p.startswith("/")):
        # If it's an absolute path, we're done; if it's a theme name, fall through
        if os.path.isabs(p) and os.path.isfile(p):
            return p
        # It's a theme name returned by _icon_from_desktop_dir — resolve it below
        name = p  # swap in the resolved icon name (e.g. "steam")

    # Step 2: gio DesktopAppInfo → icon name or path
    gio = _gio_icon_name(name)
    if gio and os.path.isabs(gio) and os.path.isfile(gio):
        return gio  # absolute path from gio
    lookup = gio if gio else name  # theme name to resolve

    # Step 3: GTK theme lookup
    p = _gtk_lookup(lookup)
    if p:
        return p
    # Also try original name if we had a gio rename
    if gio and lookup != name:
        p = _gtk_lookup(name)
        if p:
            return p

    # Step 4: manual XDG search
    p = _xdg_lookup(lookup)
    if p:
        return p
    if gio and lookup != name:
        p = _xdg_lookup(name)
        if p:
            return p

    return ""


if __name__ == "__main__":
    # argv[1] = single class/name (ActiveWindow); stdin = one per line (SystemTray)
    if len(sys.argv) > 1:
        print(resolve(sys.argv[1]), flush=True)
    else:
        for line in sys.stdin:
            n = line.strip()
            print(resolve(n), flush=True)
