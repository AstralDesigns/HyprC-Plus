#!/usr/bin/env bash
# ── appimage-action.sh ───────────────────────────────────────────────────────
# Per-AppImage actions for the launcher AppImages tab. All operations are
# user-level (no pkexec / root). Paths are taken from argv so spaces and shell
# metacharacters never need quoting by the caller.
#
#   appimage-action.sh launch     <path>
#   appimage-action.sh chmod-on   <path>
#   appimage-action.sh chmod-off  <path>
#   appimage-action.sh integrate  <path> <name> [version]
#   appimage-action.sh unintegrate <path>
#   appimage-action.sh move       <path>
#
# Prints a one-line result to stdout ("ok ..." / "err ..."). `move` also prints
# the destination path on stdout so the caller can rescan.
set -u
exec python3 - "$@" <<'PY'
import sys, os, re, json, stat, shutil, subprocess

HOME = os.path.expanduser("~")
APPS = os.path.join(HOME, ".local", "share", "applications")
HOME_APP = os.path.join(HOME, ".Applications")

verb = sys.argv[1] if len(sys.argv) > 1 else ""
path = sys.argv[2] if len(sys.argv) > 2 else ""
name = sys.argv[3] if len(sys.argv) > 3 else ""
ver  = sys.argv[4] if len(sys.argv) > 4 else ""


def out(msg):
    sys.stdout.write(str(msg) + "\n")
    sys.stdout.flush()


def desktop_dirs():
    return [APPS, os.path.join(HOME, ".applications")]


# Exec value -> the program token, honouring a leading double-quoted path.
def _exec_target(val):
    val = (val or "").strip()
    if val.startswith('"'):
        e = val.find('"', 1)
        return val[1:e] if e > 0 else val[1:]
    return val.split(" ")[0]


# Find every per-user .desktop whose Exec points at this exact file.
def linked_desktops(real_path):
    hits = []
    for d in desktop_dirs():
        if not os.path.isdir(d):
            continue
        for fn in os.listdir(d):
            if not fn.endswith(".desktop"):
                continue
            fp = os.path.join(d, fn)
            try:
                txt = open(fp, encoding="utf-8", errors="replace").read()
            except Exception:
                continue
            for line in txt.splitlines():
                if line.startswith("Exec="):
                    tok = _exec_target(line[5:])
                    if tok and os.path.realpath(tok) == real_path:
                        hits.append(fp)
                        break
    return hits


def slug(s):
    s = re.sub(r"[^a-z0-9]+", "-", (s or "").lower()).strip("-")
    return s or "appimage"


def do_launch(p):
    if not os.path.isfile(p):
        return out("err not found")
    if not os.access(p, os.X_OK):
        try:
            os.chmod(p, os.stat(p).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        except Exception as e:
            return out("err chmod: %s" % e)
    try:
        subprocess.Popen([p], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                         start_new_session=True)
        out("ok launched")
    except Exception as e:
        out("err launch: %s" % e)


def do_chmod(p, on):
    try:
        m = os.stat(p).st_mode
        xbits = stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH
        os.chmod(p, (m | xbits) if on else (m & ~xbits))
        out("ok chmod")
    except Exception as e:
        out("err chmod: %s" % e)


def do_integrate(p, nm, vr):
    disp = nm or os.path.basename(p)
    icon = slug(disp)  # themed guess; generic fallback resolved by the icon theme
    body = (
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Version=1.0\n"
        "Name=%s\n"
        "Comment=AppImage %s\n"
        "Exec=\"%s\" %%u\n"
        "Icon=%s\n"
        "Terminal=false\n"
        "Categories=Application;\n"
        "StartupWMClass=%s\n"
        "X-AppImage-Version=%s\n" % (disp, disp, p, icon, slug(disp), vr or "")
    )
    try:
        os.makedirs(APPS, exist_ok=True)
        base = "appimage-%s" % slug(disp)
        fp = os.path.join(APPS, base + ".desktop")
        n = 1
        while os.path.exists(fp):
            try:
                if os.path.realpath(_exec_of(fp)) == os.path.realpath(p):
                    break
            except Exception:
                pass
            fp = os.path.join(APPS, "%s-%d.desktop" % (base, n)); n += 1
        with open(fp, "w", encoding="utf-8") as f:
            f.write(body)
        os.chmod(fp, 0o644)
        subprocess.run(["update-desktop-database", APPS],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        out("ok integrated")
    except Exception as e:
        out("err integrate: %s" % e)


def _exec_of(fp):
    for line in open(fp, encoding="utf-8", errors="replace"):
        if line.startswith("Exec="):
            return _exec_target(line[5:])
    return ""


def do_unintegrate(p):
    rp = os.path.realpath(p)
    removed = 0
    for fp in linked_desktops(rp):
        try:
            os.remove(fp); removed += 1
        except Exception:
            pass
    if removed:
        subprocess.run(["update-desktop-database", APPS],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    out("ok unintegrated %d" % removed)


def do_move(p):
    if not os.path.isfile(p):
        return out("err not found")
    try:
        os.makedirs(HOME_APP, exist_ok=True)
        dest = os.path.join(HOME_APP, os.path.basename(p))
        n = 1
        stem, ext = os.path.splitext(os.path.basename(p))
        while os.path.exists(dest):
            if os.path.realpath(dest) == os.path.realpath(p):
                break
            dest = os.path.join(HOME_APP, "%s-%d%s" % (stem, n, ext)); n += 1
        shutil.move(p, dest)
        out("ok moved")
        out("path " + dest)
    except Exception as e:
        out("err move: %s" % e)


if verb == "launch":       do_launch(path)
elif verb == "chmod-on":   do_chmod(path, True)
elif verb == "chmod-off":  do_chmod(path, False)
elif verb == "integrate":  do_integrate(path, name, ver)
elif verb == "unintegrate":do_unintegrate(path)
elif verb == "move":       do_move(path)
else:                      out("err unknown verb")
PY
