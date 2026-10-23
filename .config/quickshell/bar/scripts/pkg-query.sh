#!/usr/bin/env bash
# ── pkg-query.sh ─────────────────────────────────────────────────────────────
# Read-only package listing / search for the launcher Packages tab.
# Emits a single JSON array on stdout:
#   [{name,version,source,description,repo,installed,icon}, ...]
#   source: "native" | "aur" | "flatpak"
#
#   pkg-query.sh installed        -> explicit native pkgs + installed flatpak apps
#   pkg-query.sh search <query>   -> merged native + AUR + Flathub matches
#
# Backends are auto-detected and silently skipped when their binary is absent,
# so the tab degrades to whatever the OS actually has. Never requires privilege.
# The heavy lifting (tool-output parsing + JSON escaping) is done in python3.
set -u
exec python3 - "$@" <<'PY'
import sys, json, shutil, re, subprocess

mode  = sys.argv[1] if len(sys.argv) > 1 else "installed"
query = sys.argv[2] if len(sys.argv) > 2 else ""

HAVE_PACMAN  = shutil.which("pacman") is not None
AUR_HELPER   = "paru" if shutil.which("paru") else ("yay" if shutil.which("yay") else None)
HAVE_FLATPAK = shutil.which("flatpak") is not None
PER_SOURCE = 150      # search: cap each backend so none is starved by another
INSTALLED_LIMIT = 6000  # installed view: effectively all (ListView virtualises)


def run(cmd, timeout=25):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.stdout or ""
    except Exception:
        return ""


# ── installed sets (used both for the `installed` view and to tag searches) ──
def native_installed():
    recs, names = [], set()
    if not HAVE_PACMAN:
        return recs, names
    # pacman -Qe -> "name version  description"
    for line in run(["pacman", "-Qe"]).splitlines():
        m = re.match(r"^(\S+)\s+(\S+)\s*(.*)$", line)
        if not m:
            continue
        name, ver, desc = m.group(1), m.group(2), m.group(3).strip()
        names.add(name)
        recs.append({"name": name, "version": ver, "source": "native",
                     "description": desc, "repo": "", "installed": True, "icon": ""})
    return recs, names


def flatpak_installed():
    recs, ids = [], set()
    if not HAVE_FLATPAK:
        return recs, ids
    out = run(["flatpak", "list", "--app",
               "--columns=name,application,version,description"])
    for line in out.splitlines():
        cols = line.split("\t")
        if len(cols) < 2:
            continue
        name, appid = cols[0].strip(), cols[1].strip()
        ver = cols[2].strip() if len(cols) > 2 else ""
        desc = cols[3].strip() if len(cols) > 3 else ""
        if not appid:
            continue
        ids.add(appid)
        recs.append({"name": name or appid, "version": ver, "source": "flatpak",
                     "description": desc, "repo": "flathub", "installed": True,
                     "icon": appid})
    return recs, ids


# ── search parser ────────────────────────────────────────────────────────────
# paru/yay -Ss searches the sync repos AND the AUR in one pass, so a single
# helper call replaces the old pacman -Ss + paru -Ss pair (and drops the
# duplicate native hits). Falls back to pacman -Ss (native only) with no helper.
# Each "repo/name version [extra]" line is tagged native, except the "aur/"
# prefix; the description rides on the following indented line.
def search_pkgs(q, inst_names):
    nat, aur = [], []
    if not q:
        return nat, aur
    if AUR_HELPER:
        tool = AUR_HELPER
    elif HAVE_PACMAN:
        tool = "pacman"
    else:
        return nat, aur
    cur = None
    for line in run([tool, "-Ss", q]).splitlines():
        m = re.match(r"^(\S+)/(\S+)\s+(\S+)\s*(.*)$", line)
        if m:
            if cur:
                (aur if cur["source"] == "aur" else nat).append(cur)
            repo, name, ver, rest = m.groups()
            cur = {"name": name, "version": ver,
                   "source": "aur" if repo == "aur" else "native",
                   "description": "", "repo": repo,
                   "installed": ("installed" in rest) or (name in inst_names),
                   "icon": ""}
        elif cur is not None and line.strip():
            cur["description"] = (cur["description"] + " " + line.strip()).strip()
    if cur:
        (aur if cur["source"] == "aur" else nat).append(cur)
    return nat, aur


def search_flatpak(q, fp_ids):
    recs = []
    if not HAVE_FLATPAK or not q:
        return recs
    out = run(["flatpak", "search", "--columns=name,application,description,version", q])
    for line in out.splitlines():
        cols = line.split("\t")
        if len(cols) < 2:
            continue
        name, appid = cols[0].strip(), cols[1].strip()
        desc = cols[2].strip() if len(cols) > 2 else ""
        ver = cols[3].strip() if len(cols) > 3 else ""
        if not appid or appid.lower() == "application":  # skip header row
            continue
        recs.append({"name": name or appid, "version": ver, "source": "flatpak",
                     "description": desc, "repo": "flathub",
                     "installed": appid in fp_ids, "icon": appid})
    return recs


def main():
    n_inst, n_names = native_installed()
    f_inst, f_ids = flatpak_installed()

    if mode == "installed":
        # pacman -Qe already lists installed AUR packages (same local DB).
        out = (n_inst + f_inst)[:INSTALLED_LIMIT]
    else:
        nat, aur = search_pkgs(query, n_names)
        nat = nat[:PER_SOURCE]
        aur = aur[:PER_SOURCE]
        fp = search_flatpak(query, f_ids)[:PER_SOURCE]
        rank = {"native": 0, "aur": 1, "flatpak": 2}
        merged, seen = [], set()
        for r in sorted(nat + aur + fp,
                        key=lambda r: (not r["installed"],
                                       rank.get(r["source"], 9),
                                       r["name"].lower())):
            key = (r["source"], r["name"])
            if key in seen:
                continue
            seen.add(key)
            merged.append(r)
        out = merged

    sys.stdout.write(json.dumps(out))


main()
PY
