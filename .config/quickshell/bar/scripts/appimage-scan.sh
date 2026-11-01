#!/usr/bin/env bash
# ── appimage-scan.sh ─────────────────────────────────────────────────────────
# Read-only AppImage discovery for the launcher AppImages tab.
# Emits a single JSON array on stdout:
#   [{name,version,path,size,exe,integrated,icon}, ...]
#
#   appimage-scan.sh            -> scan the common drop-folders + $PATH
#
# Detection is by extension (.AppImage / .appimage, case-insensitive) with an
# `file`-magic fallback so oddly-named builds are still caught. Scans are
# shallow (depth 1) so it stays fast; results are de-duped by realpath and
# never require privilege. Name/version are derived from the filename, which
# for AppImages follows the usual "Name-Version-arch" convention.
# The heavy lifting (path checks + JSON escaping) is done in python3.
set -u
exec python3 - "$@" <<'PY'
import sys, os, json, re, shutil, subprocess

HOME = os.path.expanduser("~")

# Where users habitually drop AppImages, plus every $PATH entry. Missing dirs
# are simply skipped. ~/.Applications is the tab's own organised home.
def scan_dirs():
    seen, dirs = set(), []
    cand = [
        os.path.join(HOME, "Applications"),
        os.path.join(HOME, ".Applications"),
        os.path.join(HOME, ".local", "bin"),
        os.path.join(HOME, "Downloads"),
        os.path.join(HOME, "Documents"),
        os.path.join(HOME, ".appimagekit"),
        "/opt",
        "/opt/apps",
        "/usr/local/bin",
    ]
    for p in (os.environ.get("PATH", "") or "").split(os.pathsep):
        if p:
            cand.append(p)
    for d in cand:
        try:
            rp = os.path.realpath(d)
        except Exception:
            continue
        if rp in seen or not os.path.isdir(rp):
            continue
        seen.add(rp)
        dirs.append(d)
    return dirs


def is_appimage(path):
    name = os.path.basename(path).lower()
    if name.endswith(".appimage"):
        return True
    # Extension-less build: only pay the `file` cost for small ELF candidates
    # (cheap guard — skip huge dirs like /usr/bin noise by extension first).
    return False


# Filename -> (display name, version). Strips the extension then peels a
# trailing version token like "-1.2.3", "-1.2.3-beta", "-x86_64".
_VER = re.compile(r"[-._ ]?(\d[\w.+-]*)[-._ ]?(?:x86_64|i[36]86|aarch64|arm\w*|ppc64le|s390x)?$", re.I)
_ARCH_ONLY = re.compile(r"^(?:x86_64|i[36]86|aarch64|arm\w*|ppc64le|s390x)$", re.I)

def derive(path):
    stem = os.path.basename(path)
    if stem.lower().endswith(".appimage"):
        stem = stem[: -len(".appimage")]
    name, ver = stem, ""
    m = _VER.search(stem)
    if m and m.group(1):
        tail = stem[m.start():].strip(" -._")
        if not _ARCH_ONLY.match(tail) and re.search(r"\d", m.group(1)):
            ver = m.group(1)
            name = stem[: m.start()].strip(" -._") or stem
    name = name.replace("_", " ").strip() or stem
    return name, ver


# Integrated = a per-user .desktop points its Exec at this exact file. Return
# the themed Icon name from that entry so the row can show it.
def app_dirs():
    return [os.path.join(HOME, ".local", "share", "applications"),
            os.path.join(HOME, ".applications")]

# Exec value -> the program token, honouring a leading double-quoted path
# ("/my app x86_64.AppImage" %u). Stray closing quotes must not leak in.
def _exec_target(val):
    val = (val or "").strip()
    if val.startswith('"'):
        e = val.find('"', 1)
        return val[1:e] if e > 0 else val[1:]
    return val.split(" ")[0]


def integration_for(real_path):
    # Each .desktop is judged on its own: only return an icon from the file whose
    # Exec actually points at this AppImage. Leaking state across files used to
    # surface whatever icon happened to be scanned last in the folder.
    for d in app_dirs():
        if not os.path.isdir(d):
            continue
        try:
            entries = os.listdir(d)
        except Exception:
            continue
        for fn in entries:
            if not fn.endswith(".desktop"):
                continue
            try:
                txt = open(os.path.join(d, fn), encoding="utf-8",
                           errors="replace").read()
            except Exception:
                continue
            icon = ""
            matched = False
            for line in txt.splitlines():
                if line.startswith("Exec="):
                    tok = _exec_target(line[5:])
                    if tok and os.path.realpath(tok) == real_path:
                        matched = True
                elif line.startswith("Icon="):
                    icon = line[5:].strip()
            if matched:
                return True, icon
    return False, ""


def main():
    recs, seen = [], set()
    for d in scan_dirs():
        try:
            names = os.listdir(d)
        except Exception:
            continue
        for fn in names:
            p = os.path.join(d, fn)
            try:
                if not os.path.isfile(p):
                    continue
                rp = os.path.realpath(p)
                if rp in seen or not is_appimage(p):
                    continue
                seen.add(rp)
                name, ver = derive(p)
                try:
                    size = os.path.getsize(p)
                except Exception:
                    size = 0
                exe = os.access(p, os.X_OK)
                integrated, icon = integration_for(rp)
                recs.append({"name": name, "version": ver, "path": p,
                             "size": size, "exe": bool(exe),
                             "integrated": bool(integrated), "icon": icon})
            except Exception:
                continue
    recs.sort(key=lambda r: r["name"].lower())
    sys.stdout.write(json.dumps(recs))


main()
PY
