#!/usr/bin/env bash
# ── ssh-config.sh ────────────────────────────────────────────────────────────
# Manage Host entries in ~/.ssh/config for the ControlCenter SSH sub-tab.
# Line-based and conservative: it only ever rewrites the Host block it is asked
# to touch and preserves every other line (comments, global options, Match
# blocks). The file is created with 0600 and the directory with 0700, which is
# what sshd/ssh insist on.
#
#   ssh-config.sh list
#   ssh-config.sh add    <name> <hostname> <user> <port> <identity>
#   ssh-config.sh edit   <oldname> <name> <hostname> <user> <port> <identity>
#   ssh-config.sh remove <name>
#
# `list` prints a JSON array on stdout:
#   [{name,aliases,hostname,user,port,identity}, ...]
# Mutations print a single status line ("ok …" / "err …"); the caller re-lists.
set -u
exec python3 - "$@" <<'PY'
import sys, os, re, json, stat

HOME = os.path.expanduser("~")
CFG = os.path.join(HOME, ".ssh", "config")

HOST_RE  = re.compile(r'^[ \t]*Host[ \t]+\S', re.I)
MATCH_RE = re.compile(r'^[ \t]*Match\b', re.I)
OPT_RE   = re.compile(r'^(\w+)[ \t]*=?[ \t]+(.*)$')

argv = sys.argv[1:]
verb = argv[0] if argv else "list"


def read_lines():
    try:
        with open(CFG, encoding="utf-8", errors="replace") as f:
            return f.read().split("\n")
    except FileNotFoundError:
        return []
    except Exception:
        return []


def host_blocks(lines):
    """Return [(start, end)] for each Host block (end is exclusive, stops at the
    next Host/Match header or EOF)."""
    res, n, i = [], len(lines), 0
    while i < n:
        if HOST_RE.match(lines[i]):
            j = i + 1
            while j < n and not (HOST_RE.match(lines[j]) or MATCH_RE.match(lines[j])):
                j += 1
            res.append((i, j))
            i = j
        else:
            i += 1
    return res


def parse_block(lines, s, e):
    aliases = lines[s].strip().split()[1:]
    opts = {}
    for l in lines[s + 1:e]:
        st = l.strip()
        if not st or st.startswith("#"):
            continue
        m = OPT_RE.match(st)
        if m:
            opts[m.group(1).lower()] = m.group(2).strip().strip('"')
    return {
        "name": aliases[0] if aliases else "",
        "aliases": aliases,
        "hostname": opts.get("hostname", ""),
        "user": opts.get("user", ""),
        "port": opts.get("port", ""),
        "identity": opts.get("identityfile", ""),
    }


def find_block(lines, name):
    for s, e in host_blocks(lines):
        if name in lines[s].strip().split()[1:]:
            return (s, e)
    return None


def block_lines(name, hostname, user, port, identity):
    out = ["Host " + name]
    if hostname: out.append("    HostName " + hostname)
    if user:     out.append("    User " + user)
    if port:     out.append("    Port " + port)
    if identity: out.append("    IdentityFile " + identity)
    return out


def ensure_dir():
    d = os.path.dirname(CFG)
    if not os.path.isdir(d):
        os.makedirs(d, 0o700, exist_ok=True)
    if not os.path.exists(CFG):
        open(CFG, "w").close()
        os.chmod(CFG, 0o600)


def write_lines(lines):
    ensure_dir()
    tmp = CFG + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    os.chmod(tmp, 0o600)
    os.replace(tmp, CFG)


def clean(x):
    x = (x or "").strip()
    return "" if x in ("—", "-") else x


def do_list():
    lines = read_lines()
    out = [parse_block(lines, s, e) for s, e in host_blocks(lines)]
    out.sort(key=lambda r: r["name"].lower())
    sys.stdout.write(json.dumps(out))


def do_add(a):
    name, hostname, user, port, identity = (clean(a[i]) for i in range(0, 5))
    if not name:
        return sys.stdout.write("err name required\n")
    lines = read_lines()
    if find_block(lines, name):
        return sys.stdout.write("err host '%s' already exists\n" % name)
    # Normalise: drop a trailing blank line so the new block rides at the end.
    while lines and lines[-1].strip() == "":
        lines.pop()
    if lines:
        lines.append("")
    lines += block_lines(name, hostname, user, port, identity)
    write_lines(lines)
    sys.stdout.write("ok added\n")


def do_edit(a):
    old, name, hostname, user, port, identity = (clean(a[i]) for i in range(0, 6))
    if not old:
        return sys.stdout.write("err no host to edit\n")
    lines = read_lines()
    blk = find_block(lines, old)
    if not blk:
        return sys.stdout.write("err host '%s' not found\n" % old)
    s, e = blk
    newblk = block_lines(name, hostname, user, port, identity)
    # Keep the block's trailing blank separator (if it had one) so neighbouring
    # Host blocks don't run together after an edit.
    k = e
    while k > s and lines[k - 1].strip() == "":
        k -= 1
    if k < e:
        newblk.append("")
    lines[s:e] = newblk
    write_lines(lines)
    sys.stdout.write("ok edited\n")


def do_remove(a):
    name = clean(a[0]) if a else ""
    if not name:
        return sys.stdout.write("err no host to remove\n")
    lines = read_lines()
    blk = find_block(lines, name)
    if not blk:
        return sys.stdout.write("err host '%s' not found\n" % name)
    s, e = blk
    # Take the blank line that visually precedes the block too, if present.
    if s > 0 and lines[s - 1].strip() == "":
        s -= 1
    del lines[s:e]
    write_lines(lines)
    sys.stdout.write("ok removed\n")


if verb == "list":
    do_list()
else:
    args = argv[1:]
    args += [""] * (6 - len(args))      # pad so index access never throws
    try:
        if verb == "add":        do_add(args[:5])
        elif verb == "edit":     do_edit(args[:6])
        elif verb == "remove":   do_remove(args[:1])
        else:                    sys.stdout.write("err unknown verb\n")
    except Exception as ex:
        sys.stdout.write("err %s\n" % ex)
PY
