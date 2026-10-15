#!/usr/bin/env python3
# searxng_prefs.py — read/write a curated set of SearXNG settings.yml keys.
#
# The QML preferences panel owns the descriptor list (single source of truth);
# this script only resolves dot-paths (and plugin `active` flags) against the
# live settings.yml. Keys are described by either a dotted `path` (nested dict)
# or a `plugin` name (which maps to plugins.<name>.active).
#
#   searxng_prefs.py get  <settings.yml> <specJson>
#       specJson = [ {"id":.., "path":.. | "plugin":.., "default":..}, ... ]
#       -> prints { id: currentValue, ... } as JSON
#
#   searxng_prefs.py set  <settings.yml> <specJson>
#       specJson = [ {"id":.., "path":.. | "plugin":.., "value":.., "default":..}, ... ]
#       -> applies each value (creating intermediate maps), writes atomically
#
# `default` is used both for the get fallback and to coerce the stored type
# (bool/int) so e.g. safe_search stays an int, not a string.
import sys, json, os
import yaml


def _resolve(data, desc):
    if "plugin" in desc:
        return (data.get("plugins") or {}).get(desc["plugin"], {}) \
            .get("active", desc.get("default"))
    cur = data
    for part in desc["path"].split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return desc.get("default")
    return cur


def _coerce(value, default):
    if isinstance(default, bool):
        return bool(value)
    if isinstance(default, int) and not isinstance(default, bool):
        try:
            return int(value)
        except (TypeError, ValueError):
            return value
    return value


def _apply(data, desc):
    value = _coerce(desc.get("value"), desc.get("default"))
    if "plugin" in desc:
        plugins = data.setdefault("plugins", {})
        plug = plugins.setdefault(desc["plugin"], {})
        plug["active"] = value
        return
    parts = desc["path"].split(".")
    cur = data
    for p in parts[:-1]:
        nxt = cur.get(p)
        if not isinstance(nxt, dict):
            nxt = {}
            cur[p] = nxt
        cur = nxt
    cur[parts[-1]] = value


def main():
    if len(sys.argv) < 4:
        print(json.dumps({"ok": False, "error": "usage"}))
        return 1
    mode, settings_path = sys.argv[1], sys.argv[2]
    spec = json.loads(sys.argv[3])

    data = {}
    if os.path.exists(settings_path):
        with open(settings_path, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}

    if mode == "get":
        print(json.dumps({d["id"]: _resolve(data, d) for d in spec}))
        return 0

    if mode == "set":
        for d in spec:
            _apply(data, d)
        tmp = settings_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            yaml.safe_dump(data, f, sort_keys=False,
                           default_flow_style=False, allow_unicode=True)
        os.replace(tmp, settings_path)
        print(json.dumps({"ok": True}))
        return 0

    print(json.dumps({"ok": False, "error": "bad mode"}))
    return 1


if __name__ == "__main__":
    sys.exit(main())
