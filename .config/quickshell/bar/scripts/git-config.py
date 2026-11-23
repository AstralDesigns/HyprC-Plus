#!/usr/bin/env python3
"""
git-config.py — Read and update ~/.gitconfig and GitHub CLI status for HyprCandy Control Center.
"""

import sys
import os
import subprocess
import argparse

CONFIG_PATH = os.path.expanduser("~/.gitconfig")

def get_git_val(key):
    try:
        res = subprocess.run(
            ["git", "config", "--global", key],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=True
        )
        return res.stdout.strip()
    except subprocess.CalledProcessError:
        return ""

def set_git_val(key, val):
    val = val.strip() if val else ""
    if val:
        subprocess.run(["git", "config", "--global", key, val], check=True)
    else:
        subprocess.run(["git", "config", "--global", "--unset-all", key], stderr=subprocess.DEVNULL)

def get_gh_user():
    try:
        res = subprocess.run(
            ["gh", "api", "user", "-q", ".login"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=True
        )
        return res.stdout.strip()
    except Exception:
        return ""

def cmd_get():
    name    = get_git_val("user.name")
    email   = get_git_val("user.email")
    branch  = get_git_val("init.defaultBranch")
    helper  = get_git_val("credential.helper")
    safedir = get_git_val("safe.directory")
    editor  = get_git_val("core.editor")
    gh_user = get_gh_user()

    raw = ""
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8", errors="replace") as f:
                raw = f.read()
        except Exception as e:
            raw = f"# Error reading {CONFIG_PATH}: {e}"

    print(f"NAME\t{name}")
    print(f"EMAIL\t{email}")
    print(f"BRANCH\t{branch}")
    print(f"HELPER\t{helper}")
    print(f"SAFEDIR\t{safedir}")
    print(f"EDITOR\t{editor}")
    print(f"GH_USER\t{gh_user}")
    print("RAW_START")
    print(raw, end="")

def cmd_set(args):
    if args.name is not None:
        set_git_val("user.name", args.name)
    if args.email is not None:
        set_git_val("user.email", args.email)
    if args.branch is not None:
        set_git_val("init.defaultBranch", args.branch)
    if args.helper is not None:
        set_git_val("credential.helper", args.helper)
    if args.safedir is not None:
        set_git_val("safe.directory", args.safedir)
    if args.editor is not None:
        set_git_val("core.editor", args.editor)
    print("OK")

def cmd_set_raw():
    content = sys.stdin.read()
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        f.write(content)
    print("OK")

def main():
    parser = argparse.ArgumentParser(description="Git / GitHub configuration helper")
    subparsers = parser.add_subparsers(dest="command")

    subparsers.add_parser("get", help="Read current git configuration")

    set_parser = subparsers.add_parser("set", help="Update git configuration")
    set_parser.add_argument("--name", type=str, default=None)
    set_parser.add_argument("--email", type=str, default=None)
    set_parser.add_argument("--branch", type=str, default=None)
    set_parser.add_argument("--helper", type=str, default=None)
    set_parser.add_argument("--safedir", type=str, default=None)
    set_parser.add_argument("--editor", type=str, default=None)

    subparsers.add_parser("set-raw", help="Write stdin to ~/.gitconfig")

    args = parser.parse_args()

    if args.command == "get":
        cmd_get()
    elif args.command == "set":
        cmd_set(args)
    elif args.command == "set-raw":
        cmd_set_raw()
    else:
        parser.print_help()
        sys.exit(1)

if __name__ == "__main__":
    main()
