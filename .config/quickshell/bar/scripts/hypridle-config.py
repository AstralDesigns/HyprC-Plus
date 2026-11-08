#!/usr/bin/env python3
"""
hypridle-config.py — Read and update hypridle.conf timeout listeners for HyprCandy.
"""

import os
import sys
import re
import subprocess
import argparse

CONF_PATH = os.path.expanduser("~/.config/hypr/hypridle.conf")

def parse_listener_blocks(lines):
    in_listener = False
    level = 0
    block_lines = []
    blocks = []

    for idx, line in enumerate(lines):
        stripped = line.strip()
        if not in_listener:
            if stripped.startswith("listener") and "{" in stripped and not stripped.startswith("#"):
                in_listener = True
                level = line.count("{") - line.count("}")
                block_lines = [idx]
        else:
            level += line.count("{") - line.count("}")
            block_lines.append(idx)
            if level <= 0:
                in_listener = False
                blocks.append(block_lines)

    return blocks

def identify_block(lines, block_indices):
    on_timeout = ""
    for i in block_indices:
        if "on-timeout" in lines[i]:
            on_timeout = lines[i]
            break
    if "brightnessctl" in on_timeout:
        return "dim"
    elif "lock-session" in on_timeout:
        return "lock"
    elif "dpms off" in on_timeout:
        return "off"
    elif "suspend" in on_timeout:
        return "suspend"
    return None

def cmd_get():
    if not os.path.isfile(CONF_PATH):
        print("ERROR\tConfig not found", file=sys.stderr)
        sys.exit(1)

    with open(CONF_PATH, "r", encoding="utf-8") as f:
        lines = f.readlines()

    blocks = parse_listener_blocks(lines)
    timeouts = {"dim": "", "lock": "", "off": "", "suspend": ""}

    for b in blocks:
        kind = identify_block(lines, b)
        if kind and kind in timeouts:
            for i in b:
                m = re.match(r"^\s*timeout\s*=\s*(\d+)", lines[i])
                if m:
                    timeouts[kind] = m.group(1)
                    break

    print(f"DIM\t{timeouts['dim']}")
    print(f"LOCK\t{timeouts['lock']}")
    print(f"OFF\t{timeouts['off']}")
    print(f"SUSPEND\t{timeouts['suspend']}")

def cmd_set(dim=None, lock=None, off=None, suspend=None):
    if not os.path.isfile(CONF_PATH):
        print("ERROR\tConfig not found", file=sys.stderr)
        sys.exit(1)

    with open(CONF_PATH, "r", encoding="utf-8") as f:
        lines = f.readlines()

    blocks = parse_listener_blocks(lines)
    updates = {}
    if dim is not None:
        updates["dim"] = int(dim)
    if lock is not None:
        updates["lock"] = int(lock)
    if off is not None:
        updates["off"] = int(off)
    if suspend is not None:
        updates["suspend"] = int(suspend)

    changed = False
    for b in blocks:
        kind = identify_block(lines, b)
        if kind and kind in updates:
            new_val = updates[kind]
            for i in b:
                if re.match(r"^\s*timeout\s*=\s*\d+", lines[i]):
                    old_line = lines[i]
                    lines[i] = re.sub(r"(^\s*timeout\s*=\s*)\d+", r"\g<1>" + str(new_val), lines[i])
                    if lines[i] != old_line:
                        changed = True

    if changed:
        with open(CONF_PATH, "w", encoding="utf-8") as f:
            f.writelines(lines)

    # Restart hypridle so updated timers take effect
    try:
        subprocess.run(["pkill", "-x", "hypridle"], check=False)
        subprocess.Popen(["hypridle"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    except Exception as e:
        print(f"WARN\tRestart failed: {e}", file=sys.stderr)

    print("OK")

def main():
    parser = argparse.ArgumentParser(description="Manage hypridle timeout listeners")
    subparsers = parser.add_subparsers(dest="action")

    subparsers.add_parser("get")

    set_p = subparsers.add_parser("set")
    set_p.add_argument("--dim", type=int, help="Screen dimming timeout in seconds")
    set_p.add_argument("--lock", type=int, help="Screen lock timeout in seconds")
    set_p.add_argument("--off", type=int, help="Screen off (DPMS) timeout in seconds")
    set_p.add_argument("--suspend", type=int, help="Suspension timeout in seconds")

    args = parser.parse_args()
    if args.action == "get":
        cmd_get()
    elif args.action == "set":
        cmd_set(dim=args.dim, lock=args.lock, off=args.off, suspend=args.suspend)
    else:
        cmd_get()

if __name__ == "__main__":
    main()

