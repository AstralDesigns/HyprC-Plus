#!/usr/bin/env python3
"""
tray-icon-resolve.py — icon resolver for SystemTray.qml and ActiveWindow.qml

Resolution order:
  1. Absolute path / image:// URL → pass through
  2. Gio.DesktopAppInfo lookup (class → icon name):
       a. Try <variant>.desktop ID combinations
       b. Scan all apps for matching StartupWMClass
  3. GTK icon theme lookup on resolved/original name
  4. Manual XDG search (hicolor, Papirus, user theme…)
  5. /usr/share/pixmaps fallback
"""
import sys, os, warnings
warnings.filterwarnings("ignore")
# Suppress GTK/GLib stderr noise
os.environ.setdefault("G_MESSAGES_DEBUG", "none")
os.environ.setdefault("GTK_DEBUG", "")
import logging; logging.disable(logging.CRITICAL)


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

    # Step 1: gio DesktopAppInfo → icon name or path
    gio = _gio_icon_name(name)
    if gio and os.path.isabs(gio) and os.path.isfile(gio):
        return gio  # absolute path from gio
    lookup = gio if gio else name  # theme name to resolve

    # Step 2: GTK theme lookup
    p = _gtk_lookup(lookup)
    if p:
        return p
    # Also try original name if we had a gio rename
    if gio and lookup != name:
        p = _gtk_lookup(name)
        if p:
            return p

    # Step 3: manual XDG search
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
