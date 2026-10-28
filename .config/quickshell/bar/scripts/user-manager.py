#!/usr/bin/env python3
"""
user-manager.py — local account helper for the HyprCandy Control-Center User tab.

Elevation model: the CC runs this whole script through a narrow sudoers rule
(NOPASSWD on *this script path only*, mirroring hotspot-toggle.sh), so when the
CC invokes it we are already root and simply run useradd/userdel/chpasswd
directly. The raw binaries are deliberately NOT in sudoers, so an unrelated
process (e.g. a terminal) cannot create accounts without authenticating — if a
person runs this script as their own user, it re-invokes through interactive
`sudo` and prompts for their password there.

Credential handling:
  * HC_PASS     — the *new* user's password (add/setpass). Never argv; kept
                  across the sudo boundary via a scoped `env_keep` and piped to
                  chpasswd on stdin.

Subcommands
-----------
  list
      NDJSON, one human user (uid >= 1000, excluding nobody) per line:
        {"name","real","uid","type","icon","home","current","path"}
      Unprivileged (reads /etc/passwd + /etc/group).

  add <id> <full_name> <standard|admin>
      useradd (+ -G wheel when admin), then chpasswd if HC_PASS is set.

  setpass <id>
      chpasswd for <id> using HC_PASS.

  delete <id> <removehome:true|false>
      userdel [-r] <id>. Refuses to delete the invoking user.

Every mutation prints {"ok":true,...} or {"ok":false,"error":...} and exits 0/1.
"""

import json
import os
import pwd
import grp
import re
import subprocess
import sys

ADMIN_GROUPS = ("wheel", "sudo", "adm", "lpadmin")
SHELL = "/bin/bash"


def _err(msg):
    print(json.dumps({"ok": False, "error": str(msg).strip()}))
    sys.exit(1)


def _invoker():
    """The real human behind the call: SUDO_USER when run via the CC's sudo
    rule, else the plain USER (terminal use). getuid() is root under sudo, so
    it cannot be used to identify the current account."""
    return os.environ.get("SUDO_USER") or os.environ.get("USER") or ""


def _run(args, stdin_bytes=b"", timeout=120):
    """Run a privileged command.

    Primary path: the CC launches this whole script through a narrow `sudo -n`
    sudoers rule, so we are already root and run the command directly. Fallback:
    if a person runs the script from a terminal as their own (unprivileged)
    user, re-invoke through `sudo`, which prompts for their password there.
    """
    env = {**os.environ, "LC_ALL": "C"}
    cmd = args if os.geteuid() == 0 else ["sudo"] + args
    p = subprocess.run(
        cmd, input=stdin_bytes,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=timeout,
    )
    return (p.returncode,
            p.stdout.decode(errors="replace"),
            p.stderr.decode(errors="replace"))


def _admin_members():
    members = set()
    for gn in ADMIN_GROUPS:
        try:
            members.update(grp.getgrnam(gn).gr_mem)
        except KeyError:
            pass
    return members


def cmd_list():
    cur = os.getuid()
    admins = _admin_members()
    for p in pwd.getpwall():
        if p.pw_uid < 1000 or p.pw_uid == 65534:
            continue
        real = p.pw_gecos.split(",")[0] if p.pw_gecos else ""
        face = os.path.join(p.pw_dir, ".face")
        print(json.dumps({
            "name": p.pw_name,
            "real": real,
            "uid": p.pw_uid,
            "type": "admin" if p.pw_name in admins else "standard",
            "icon": face if os.path.isfile(face) else "",
            "home": p.pw_dir,
            "current": p.pw_uid == cur,
            "path": "",
        }))


def cmd_add(name, full, type_str):
    if not re.match(r"^[a-z_][a-z0-9_-]*$", name or ""):
        _err("Invalid username (lowercase letters, digits, _ - ; must start with a letter or _).")
    try:
        pwd.getpwnam(name)
        _err(f"User '{name}' already exists.")
    except KeyError:
        pass

    args = ["useradd", "-m", "-s", SHELL]
    if full:
        args += ["-c", full]
    if type_str == "admin":
        args += ["-G", "wheel"]
    args.append(name)
    rc, _, e = _run(args)
    if rc != 0:
        _err(e or "useradd failed.")

    newpw = os.environ.get("HC_PASS", "")
    if newpw:
        rc2, _, e2 = _run(["chpasswd"], stdin_bytes=(f"{name}:{newpw}\n").encode())
        if rc2 != 0:
            print(json.dumps({"ok": True, "created": name,
                              "password_set": False, "warning": e2.strip()}))
            return
    print(json.dumps({"ok": True, "created": name, "password_set": bool(newpw)}))


def cmd_setpass(name):
    newpw = os.environ.get("HC_PASS", "")
    if not newpw:
        _err("No new password supplied.")
    try:
        pwd.getpwnam(name)
    except KeyError:
        _err(f"User '{name}' not found.")
    rc, _, e = _run(["chpasswd"], stdin_bytes=(f"{name}:{newpw}\n").encode())
    if rc != 0:
        _err(e or "chpasswd failed.")
    print(json.dumps({"ok": True, "setpass": name}))


def cmd_delete(name, removehome_str):
    rmhome = str(removehome_str).lower() in ("1", "true", "yes")
    if name and name == _invoker():
        _err("Refusing to delete the current user.")
    try:
        pwd.getpwnam(name)
    except KeyError:
        _err(f"User '{name}' not found.")
    args = ["userdel"] + (["-r"] if rmhome else []) + [name]
    rc, _, e = _run(args)
    if rc != 0:
        _err(e or "userdel failed.")
    print(json.dumps({"ok": True, "deleted": name}))


def main():
    if len(sys.argv) < 2:
        _err("usage: user-manager.py <list|add|setpass|delete> ...")
    cmd = sys.argv[1]
    if cmd == "list":
        cmd_list()
    elif cmd == "add" and len(sys.argv) >= 5:
        cmd_add(sys.argv[2], sys.argv[3], sys.argv[4])
    elif cmd == "setpass" and len(sys.argv) >= 3:
        cmd_setpass(sys.argv[2])
    elif cmd == "delete" and len(sys.argv) >= 3:
        cmd_delete(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "false")
    else:
        _err(f"bad invocation: {' '.join(sys.argv[1:])}")


if __name__ == "__main__":
    main()
