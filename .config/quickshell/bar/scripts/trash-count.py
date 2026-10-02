#!/usr/bin/env python3
"""Print the trash item count — exact GJS dock-main.js parity.

GJS queries the "trash::item-count" GIO attribute on trash:///, which
aggregates every trash directory (local + mounted volumes). Ported 1:1 via
PyGObject. Prints an integer; 0 on any failure so the dock never crashes on
a transient gvfs hiccup.
"""
import sys


def main() -> int:
    try:
        import gi
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio

        TRASH_URI = "trash:" + "/" * 3
        f = Gio.File.new_for_uri(TRASH_URI)
        info = f.query_info(
            "trash::item-count",
            Gio.FileQueryInfoFlags.NONE,
            None,
        )
        # trash::item-count is an int32 attribute; reading it as a string is
        # type-agnostic and stable across GLib binding versions.
        count = int(info.get_attribute_as_string("trash::item-count") or 0)
        print(max(0, count))
    except Exception:
        print(0)
    return 0


if __name__ == "__main__":
    sys.exit(main())
