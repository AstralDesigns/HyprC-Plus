"""
tools.py — Shared tool matrix for HyprCandy Agent

All tools are called identically regardless of whether the backend is
llama-server (local) or the Vercel AI Gateway (cloud).

Each tool is an async function returning a JSON-serialisable value.
Errors raise exceptions; the caller converts them to tool error results.
"""

from __future__ import annotations

import asyncio
import difflib
import json
import os
import re
import subprocess
import tempfile
import time
from datetime import datetime
from pathlib import Path
from typing import Optional
from urllib.parse import urlencode

import httpx

# ── Pending file edits (write_file stages here for accept/reject review) ────
# Files are written to disk immediately (so subsequent tool calls in the same
# turn see consistent state — a read_file right after a write_file must see
# the new content), but the pre-edit snapshot is kept here so the UI can
# offer a real "reject" (revert to snapshot) and "accept" (just forget the
# snapshot — the file is already correct on disk) without re-running the
# model. Keyed by absolute path; last write for a path wins.
PENDING_EDITS: dict[str, dict] = {}


def _diff_counts(old: str, new: str) -> tuple[int, int]:
    if old == new:
        return (0, 0)
    diff = difflib.unified_diff(old.splitlines(), new.splitlines(), lineterm="")
    additions = deletions = 0
    for line in diff:
        if line.startswith("+++") or line.startswith("---"):
            continue
        if line.startswith("+"):
            additions += 1
        elif line.startswith("-"):
            deletions += 1
    return (additions, deletions)


def accept_edit(path: str) -> bool:
    """File is already on disk with the new content — just forget the snapshot."""
    return PENDING_EDITS.pop(path, None) is not None


def reject_edit(path: str) -> bool:
    """Restore the pre-edit snapshot (or delete the file if it was newly created)."""
    record = PENDING_EDITS.pop(path, None)
    if record is None:
        return False
    p = Path(path)
    if record["is_new"]:
        try:
            p.unlink(missing_ok=True)
        except OSError:
            pass
    else:
        p.write_text(record["old_content"])
    return True


def accept_all_edits() -> int:
    count = len(PENDING_EDITS)
    PENDING_EDITS.clear()
    return count


def reject_all_edits() -> int:
    paths = list(PENDING_EDITS.keys())
    for path in paths:
        reject_edit(path)
    return len(paths)


def list_pending_edits() -> list[dict]:
    return [
        {
            "path": path,
            "is_new": record["is_new"],
            "additions": record["additions"],
            "deletions": record["deletions"],
            "old_content": record["old_content"],
            "new_content": record["new_content"],
            "timestamp": record["timestamp"],
        }
        for path, record in PENDING_EDITS.items()
    ]

# ── SearXNG config (same instance as the GJS launcher web-search tab) ─────────
SEARXNG_URL = os.environ.get("HYPRCANDY_SEARXNG_URL", "http://127.0.0.1:8888")

# Tool definitions in OpenAI function-calling schema (shared with React UI)
TOOLS_SCHEMA = [
    {
        "type": "function",
        "function": {
            "name": "list_directory",
            "description": "List files and subdirectories inside a given directory.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Directory path to list."}
                },
                "required": ["path"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Read the text content of a file. Use offset/limit for large files.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Absolute or relative file path."},
                    "offset": {"type": "integer", "description": "1-based line number to start from (optional)."},
                    "limit": {"type": "integer", "description": "Max lines to read from offset (optional)."},
                },
                "required": ["path"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "write_file",
            "description": "Create or overwrite a file with new content.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Path to write to."},
                    "content": {"type": "string", "description": "Full text content."},
                },
                "required": ["path", "content"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "exec_command",
            "description": "Execute a bash shell command. Use cautiously for builds, git, tests.",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {"type": "string", "description": "Bash command to run."},
                    "cwd": {"type": "string", "description": "Working directory (optional)."},
                },
                "required": ["command"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "web_search",
            "description": "Search the web via the local SearXNG instance. Returns structured results.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Search query."}
                },
                "required": ["query"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "fetch_url",
            "description": "Fetch a URL and return its readable text content.",
            "parameters": {
                "type": "object",
                "properties": {
                    "url": {"type": "string", "description": "Absolute URL (http/https)."}
                },
                "required": ["url"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "capture_preview",
            "description": (
                "Capture a screenshot of the current Wayland display using grim. "
                "Call this towards the end of a task to visually verify progress. "
                "Optionally specify a region as 'x,y,width,height'."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "region": {
                        "type": "string",
                        "description": "Optional region: 'x,y,width,height'. Leave empty for full screen.",
                    }
                },
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "task_complete",
            "description": "Signal that the ENTIRE requested task is fully complete. Call this only once all subtasks are done — never as a progress update.",
            "parameters": {
                "type": "object",
                "properties": {
                    "summary": {"type": "string", "description": "Concise completion summary of what was accomplished."},
                    "remaining": {"type": "string", "description": "Optional: any remaining limitations or follow-up items."},
                },
                "required": ["summary"],
            },
        },
    },
    # ── Todo list tools (internal task tracking — Tinker-style) ───────────────
    {
        "type": "function",
        "function": {
            "name": "todo_add",
            "description": "Add one or more tasks to your internal todo list for tracking multi-step work. Call this early in a complex task to plan your steps.",
            "parameters": {
                "type": "object",
                "properties": {
                    "tasks": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "List of task descriptions to add.",
                    },
                    "task": {
                        "type": "string",
                        "description": "Single task to add (use 'tasks' for multiple).",
                    },
                },
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "todo_start",
            "description": "Mark a todo task as in-progress (call when starting work on it).",
            "parameters": {
                "type": "object",
                "properties": {
                    "task_id": {"type": "integer", "description": "ID of the task to mark as in-progress."},
                },
                "required": ["task_id"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "todo_done",
            "description": "Mark a todo task as complete.",
            "parameters": {
                "type": "object",
                "properties": {
                    "task_id": {"type": "integer", "description": "ID of the task to mark as done."},
                },
                "required": ["task_id"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "todo_skip",
            "description": "Skip a todo task with an optional reason.",
            "parameters": {
                "type": "object",
                "properties": {
                    "task_id": {"type": "integer", "description": "ID of the task to skip."},
                    "reason": {"type": "string", "description": "Why this task is being skipped."},
                },
                "required": ["task_id"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "todo_list",
            "description": "Show the current todo list status.",
            "parameters": {
                "type": "object",
                "properties": {},
                "required": [],
            },
        },
    },
]


# ── Tool implementations ──────────────────────────────────────────────────────

def _resolve_path(path: str) -> Path:
    """Resolve a path, falling back to HyprCandy workspace if slightly misplaced."""
    p = Path(path).expanduser()
    if p.exists():
        return p

    workspace_root = Path(os.environ.get("HYPRCANDY_WORKSPACE", Path(__file__).resolve().parents[2]))

    # 1. Relative to workspace
    cand = workspace_root / path.lstrip("/")
    if cand.exists():
        return cand

    # 2. If model passed /home/user/.hyprcandy/xxx, check ~/.hyprcandy/GJS/hyprcandydock/xxx
    parts = path.strip("/").split("/")
    if ".hyprcandy" in parts:
        idx = parts.index(".hyprcandy")
        sub = "/".join(parts[idx + 1:])
        cand2 = workspace_root / sub
        if cand2.exists():
            return cand2

    return p


async def list_directory(path: str = ".") -> list[dict]:
    p = _resolve_path(path)
    if not p.exists():
        raise FileNotFoundError(f"Path does not exist: {path}")
    items = []
    for entry in sorted(p.iterdir(), key=lambda e: (not e.is_dir(), e.name.lower())):
        try:
            stat = entry.stat()
            items.append({
                "name": entry.name,
                "path": str(entry),
                "isDir": entry.is_dir(),
                "size": stat.st_size if not entry.is_dir() else 0,
            })
        except PermissionError:
            pass
    return items


async def read_file(path: str, offset: Optional[int] = None, limit: Optional[int] = None) -> str:
    p = _resolve_path(path)
    if not p.exists():
        raise FileNotFoundError(f"File not found: {path}")
    text = p.read_text(errors="replace")
    if offset is not None or limit is not None:
        lines = text.splitlines(keepends=True)
        start = max(0, (offset or 1) - 1)
        end = start + (limit or len(lines))
        text = "".join(lines[start:end])
    # Cap at ~50k chars to keep context manageable
    if len(text) > 50_000:
        text = text[:50_000] + f"\n\n[... truncated at 50,000 chars, total {len(p.read_bytes())} bytes ...]"
    return text


async def write_file(path: str, content: str) -> dict:
    p = _resolve_path(path)
    is_new = not p.exists()
    old_content = "" if is_new else p.read_text(errors="replace")
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content)

    additions, deletions = _diff_counts(old_content, content)
    record = {
        "path": str(p),
        "old_content": old_content,
        "new_content": content,
        "is_new": is_new,
        "additions": additions,
        "deletions": deletions,
        "timestamp": time.time(),
    }
    PENDING_EDITS[str(p)] = record

    return {
        "success": True,
        "path": str(p),
        "bytes": len(content.encode()),
        "old_content": old_content,
        "new_content": content,
        "is_new": is_new,
        "additions": additions,
        "deletions": deletions,
    }


async def exec_command(command: str, cwd: Optional[str] = None) -> dict:
    work_dir = Path(cwd).expanduser() if cwd else Path.home()
    try:
        result = subprocess.run(
            ["/bin/bash", "-c", command],
            capture_output=True,
            text=True,
            cwd=str(work_dir),
            timeout=60,
        )
        return {
            "exitCode": result.returncode,
            "stdout": result.stdout[:20_000],
            "stderr": result.stderr[:5_000],
        }
    except subprocess.TimeoutExpired:
        return {"exitCode": -1, "stdout": "", "stderr": "Command timed out after 60 seconds"}


async def web_search(query: str) -> list[dict]:
    params = urlencode({"q": query, "format": "json", "categories": "general"})
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(f"{SEARXNG_URL}/search?{params}")
            resp.raise_for_status()
            data = resp.json()
            results = data.get("results", [])[:8]
            return [
                {
                    "title": r.get("title", ""),
                    "url": r.get("url", ""),
                    "content": r.get("content", r.get("snippet", "")),
                }
                for r in results
            ]
    except Exception as e:
        raise RuntimeError(f"SearXNG search failed: {e}")


async def fetch_url(url: str) -> dict:
    async with httpx.AsyncClient(
        timeout=20.0,
        headers={"User-Agent": "HyprCandy-Agent/1.0"},
        follow_redirects=True,
    ) as client:
        resp = await client.get(url)
        resp.raise_for_status()
        content_type = resp.headers.get("content-type", "")
        if "html" in content_type:
            text = _strip_html(resp.text)
        else:
            text = resp.text
        return {"url": url, "text": text[:30_000]}


def _strip_html(html: str) -> str:
    """Minimal HTML→text stripping."""
    text = re.sub(r"<script[^>]*>.*?</script>", "", html, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r"<style[^>]*>.*?</style>", "", text, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"&nbsp;", " ", text)
    text = re.sub(r"&amp;", "&", text)
    text = re.sub(r"&lt;", "<", text)
    text = re.sub(r"&gt;", ">", text)
    text = re.sub(r"\s{3,}", "\n\n", text)
    return text.strip()[:30_000]


async def capture_preview(region: Optional[str] = None) -> dict:
    ts = int(time.time())
    out_path = f"/tmp/hyprcandy_preview_{ts}.png"
    cmd = ["grim"]
    if region and region.strip():
        cmd += ["-g", region.strip()]
    cmd.append(out_path)
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    if result.returncode != 0:
        raise RuntimeError(f"grim failed: {result.stderr}")
    return {
        "path": out_path,
        "filename": f"hyprcandy_preview_{ts}.png",
        "verified": True,
        "status": "success",
        "message": f"Wayland screenshot captured to {out_path}. Visual layout and UI elements are captured for verification.",
    }


async def task_complete(summary: str, remaining: str = "") -> dict:
    return {"summary": summary, "remaining": remaining, "completed": True}


# ── Dispatcher ─────────────────────────────────────────────────────────────────
TOOL_FUNCTIONS = {
    "list_directory": list_directory,
    "read_file": read_file,
    "write_file": write_file,
    "exec_command": exec_command,
    "web_search": web_search,
    "fetch_url": fetch_url,
    "capture_preview": capture_preview,
    "task_complete": task_complete,
}

TOOL_ALIASES = {
    "read_directory": "list_directory",
    "list_dir": "list_directory",
    "dir_list": "list_directory",
    "list_files": "list_directory",
    "ls": "list_directory",
    "view_file": "read_file",
    "cat": "read_file",
    "open_file": "read_file",
    "edit_file": "write_file",
    "save_file": "write_file",
    "create_file": "write_file",
    "run_command": "exec_command",
    "bash": "exec_command",
    "sh": "exec_command",
    "shell": "exec_command",
}


async def dispatch(name: str, arguments: dict) -> any:
    """Call a tool by name with parsed arguments, resolving aliases and arg variations."""
    canonical_name = TOOL_ALIASES.get(name, name)
    fn = TOOL_FUNCTIONS.get(canonical_name)
    if not fn:
        raise ValueError(f"Unknown tool: {name}")

    args = dict(arguments or {})

    # Normalize argument key variations for universal provider model compatibility
    if canonical_name == "list_directory":
        if "path" not in args:
            args["path"] = args.get("directory") or args.get("dir_path") or args.get("dir") or args.get("folder") or "."
    elif canonical_name in ("read_file", "write_file"):
        if "path" not in args:
            args["path"] = args.get("file_path") or args.get("filepath") or args.get("file") or args.get("target_file") or ""
        if canonical_name == "write_file" and "content" not in args:
            args["content"] = args.get("code") or args.get("text") or args.get("body") or args.get("data") or ""
    elif canonical_name == "exec_command":
        if "command" not in args:
            args["command"] = args.get("cmd") or args.get("script") or args.get("shell_command") or ""
    elif canonical_name == "web_search":
        if "query" not in args:
            args["query"] = args.get("q") or args.get("search_query") or args.get("text") or ""
    elif canonical_name == "fetch_url":
        if "url" not in args:
            args["url"] = args.get("uri") or args.get("link") or ""

    return await fn(**args)
