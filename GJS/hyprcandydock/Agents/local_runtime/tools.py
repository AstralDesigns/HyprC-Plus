"""
tools.py — Shared tool matrix for HyprCandy Agent

All tools are called identically regardless of which cloud backend is
active (a BYOK provider or the Vercel AI Gateway).

Each tool is an async function returning a JSON-serialisable value.
Errors raise exceptions; the caller converts them to tool error results.
"""

from __future__ import annotations

import asyncio
import contextvars
import difflib
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
from datetime import datetime
from pathlib import Path
from typing import Optional
from urllib.parse import urlencode

import httpx

try:
    from ddgs import DDGS
except ImportError:
    DDGS = None  # type: ignore

try:
    from curl_cffi.requests import AsyncSession
except ImportError:
    AsyncSession = None  # type: ignore

try:
    import trafilatura
except ImportError:
    trafilatura = None  # type: ignore

# ── Pending file edits (write_file stages here for accept/reject review) ────
# Files are written to disk immediately (so subsequent tool calls in the same
# turn see consistent state — a read_file right after a write_file must see
# the new content), but the pre-edit snapshot is kept here so the UI can
# offer a real "reject" (revert to snapshot) and "accept" (just forget the
# snapshot — the file is already correct on disk) without re-running the
# model. Keyed by absolute path; last write for a path wins.
PENDING_EDITS: dict[str, dict] = {}


# ── Per-turn snapshot ledger ("Revert this turn", plan §3.7) ─────────────────
# Every agentic turn is tagged with a client-supplied turn id, exposed to the
# tools through the CURRENT_TURN_ID context var (set by runtime_server before
# the loop runs, so it stays isolated per concurrent asyncio task). The FIRST
# time a turn touches a path we record its pre-turn content; a later revert
# restores every file the turn changed and deletes the ones it created, in one
# action — independent of the accept/reject review above. Plain dicts preserve
# insertion order (3.7+); the ledger is capped to the most recent turns.
CURRENT_TURN_ID: contextvars.ContextVar[Optional[str]] = contextvars.ContextVar(
    "hyprcandy_current_turn_id", default=None
)
TURN_EDITS: dict[str, dict[str, dict]] = {}
_MAX_TURNS_KEPT = 60


def _register_turn_edit(path: str, old_content: str, is_new: bool, new_content: str) -> None:
    turn_id = CURRENT_TURN_ID.get()
    if not turn_id:
        return
    ledger = TURN_EDITS.get(turn_id)
    if ledger is None:
        ledger = TURN_EDITS[turn_id] = {}
        # Bound memory: drop the oldest turns once past the cap.
        while len(TURN_EDITS) > _MAX_TURNS_KEPT:
            TURN_EDITS.pop(next(iter(TURN_EDITS)), None)
    entry = ledger.get(path)
    if entry is None:
        # First touch this turn → this is the true pre-turn state to restore.
        ledger[path] = {"old_content": old_content, "is_new": is_new, "new_content": new_content}
    else:
        # A later write in the same turn keeps the original pre-turn snapshot
        # and only advances the latest content (for reporting).
        entry["new_content"] = new_content


def revert_turn(turn_id: str) -> dict:
    """Restore every file this turn touched to its pre-turn state (deleting the
    files the turn created). Returns {ok, reverted:[paths], count}."""
    ledger = TURN_EDITS.pop(turn_id, None)
    if not ledger:
        return {"ok": False, "reverted": [], "count": 0}
    reverted: list[str] = []
    for path, rec in ledger.items():
        p = Path(path)
        try:
            if rec["is_new"]:
                p.unlink(missing_ok=True)
            else:
                p.write_text(rec["old_content"])
            reverted.append(path)
        except OSError:
            pass
        # The on-disk file no longer matches any staged diff — drop its review
        # snapshot so a later accept/reject can't re-apply stale content.
        PENDING_EDITS.pop(path, None)
    return {"ok": True, "reverted": reverted, "count": len(reverted)}


def get_turn_edits(turn_id: str) -> list[dict]:
    ledger = TURN_EDITS.get(turn_id) or {}
    out = []
    for path, rec in ledger.items():
        additions, deletions = _diff_counts(rec["old_content"], rec["new_content"])
        out.append({"path": path, "is_new": rec["is_new"], "additions": additions, "deletions": deletions})
    return out


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

# ── Web search & extraction config ─────────────────────────────────────────
SEARXNG_URL = os.environ.get("HYPRCANDY_SEARXNG_URL", "http://127.0.0.1:8080")

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
            "description": "Execute a bash shell command. Use cautiously for builds, git, tests. Set sandbox=true to run inside a bubblewrap jail (whole filesystem read-only except the working directory, /tmp and ~/.cache; network kept) for risky or untrusted commands; leave it off when the command needs system-wide write access (package installs, sudo, system services).",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {"type": "string", "description": "Bash command to run."},
                    "cwd": {"type": "string", "description": "Working directory (optional)."},
                    "sandbox": {"type": "boolean", "description": "Run in a bubblewrap sandbox: read-only root, only cwd / /tmp / ~/.cache writable. Optional, default false."},
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
                    "suggestions": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Optional: 1 to 4 brief next step suggestions the user might want to run next.",
                    },
                    "screenshots": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "path": {"type": "string", "description": "Absolute path to a screenshot image (e.g. from capture_preview or grim)."},
                                "caption": {"type": "string", "description": "Optional concise caption for the verification image."}
                            },
                            "required": ["path"]
                        },
                        "description": "Optional verification screenshot(s) to attach to the summary (e.g. captured via capture_preview or grim).",
                    },
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
    # ── Interactive clarification / next-step chips (handled in agent_loop) ───
    {
        "type": "function",
        "function": {
            "name": "suggest_options",
            "description": (
                "Offer the user tappable follow-up or clarifying options instead of a wall "
                "of prose. Use when you need a decision to proceed (mode 'clarify') or to "
                "suggest convenient next steps after an answer (mode 'next-step'). Each "
                "option carries a short label and the exact prompt text it will send. For a "
                "richer Q&A, pass 'questions' (1-4) instead of a single 'options' row: each "
                "question renders its choices as buttons plus a trailing free-text field for "
                "the user's own answer, and the turn pauses until they submit."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "mode": {
                        "type": "string",
                        "enum": ["clarify", "next-step"],
                        "description": "clarify = pause and hand control back so the user picks; next-step = advisory chips shown alongside your answer.",
                    },
                    "question": {"type": "string", "description": "Short prompt shown above the chips (optional)."},
                    "options": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "label": {"type": "string", "description": "Concise chip text (1-5 words)."},
                                "promptText": {"type": "string", "description": "The message sent to the agent when the chip is tapped."},
                                "sendAs": {
                                    "type": "string",
                                    "enum": ["send", "steer"],
                                    "description": "steer = inject into the running turn; send = start a new turn. Defaults to send.",
                                },
                            },
                            "required": ["label", "promptText"],
                        },
                    },
                    "questions": {
                        "type": "array",
                        "description": "Optional multi-question clarification form (1-4 questions). Preferred over a single 'options' row when several decisions are needed at once. Each question always gets a free-text 'Other' answer field as its last choice unless allowCustom is false.",
                        "items": {
                            "type": "object",
                            "properties": {
                                "question": {"type": "string", "description": "The question text shown above this question's choices."},
                                "options": {
                                    "type": "array",
                                    "items": {
                                        "type": "object",
                                        "properties": {
                                            "label": {"type": "string", "description": "Choice text (1-5 words)."},
                                            "promptText": {"type": "string", "description": "Answer text sent for this choice; defaults to the label."},
                                        },
                                        "required": ["label"],
                                    },
                                },
                                "allowCustom": {"type": "boolean", "description": "Show a free-text field as the last choice. Defaults to true."},
                            },
                            "required": ["question", "options"],
                        },
                    },
                },
                "required": [],
            },
        },
    },
    # ── Durable topic memory (markdown files under the HyprCandy cache) ──────
    {
        "type": "function",
        "function": {
            "name": "list_memories",
            "description": "List the durable topic memories you (and past sessions) have saved. Call this to see what long-term context exists before deciding to read or update one.",
            "parameters": {"type": "object", "properties": {}, "required": []},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "read_memory",
            "description": "Read the full markdown content of a saved memory by its topic.",
            "parameters": {
                "type": "object",
                "properties": {"topic": {"type": "string", "description": "The memory topic/name (as listed by list_memories)."}},
                "required": ["topic"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "save_memory",
            "description": (
                "Create or overwrite a durable markdown memory for a topic — facts, "
                "user preferences, or project conventions worth remembering across "
                "sessions. One note per topic; calling it again with the same topic "
                "replaces the previous content, so keep each memory current."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "topic": {"type": "string", "description": "Short subject line, e.g. 'HyprCandy launcher architecture'."},
                    "content": {"type": "string", "description": "Markdown body of the memory."},
                },
                "required": ["topic", "content"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "delete_memory",
            "description": "Delete an obsolete memory by topic.",
            "parameters": {
                "type": "object",
                "properties": {"topic": {"type": "string", "description": "The memory topic to remove."}},
                "required": ["topic"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "web_preview_open",
            "description": "Open (or refresh) a live web-app/website preview pane in the user's canvas. Use whenever you start or change a web project's dev server or static site so the user sees it. The pane is also your live test surface: web_preview_eval/snapshot/console/screenshot drive the very same page.",
            "parameters": {
                "type": "object",
                "properties": {
                    "url": {"type": "string", "description": "http(s) URL of the dev server or site, e.g. http://127.0.0.1:5173/"},
                    "title": {"type": "string", "description": "Optional tab title for the preview pane."},
                },
                "required": ["url"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "web_preview_eval",
            "description": "Evaluate JavaScript inside the live web preview page (the same iframe the user sees) and return the result. Use for live testing: click elements, fill inputs, read DOM state, assert rendered output. Requires the preview pane to be open.",
            "parameters": {
                "type": "object",
                "properties": {
                    "js": {"type": "string", "description": "JavaScript expression or IIFE; its value is returned (promises awaited)."},
                    "url": {"type": "string", "description": "Optional preview URL override; defaults to the last web_preview_open URL."},
                },
                "required": ["js"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "web_preview_snapshot",
            "description": "See the live web preview without pixels: page title, URL, visible text and up to 80 interactive elements (links/buttons/inputs with ids, text, hrefs). Use to verify what rendered and to pick selectors for web_preview_eval.",
            "parameters": {
                "type": "object",
                "properties": {
                    "url": {"type": "string", "description": "Optional preview URL override."},
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "web_preview_console",
            "description": "Read buffered console output and uncaught errors from the live web preview page (log/warn/error entries since attach). Use to check for runtime errors after interacting.",
            "parameters": {
                "type": "object",
                "properties": {
                    "clear": {"type": "boolean", "description": "Empty the buffer after reading (default false)."},
                    "url": {"type": "string", "description": "Optional preview URL override."},
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "web_preview_screenshot",
            "description": "Capture a PNG screenshot of the live web preview page (exactly what the user sees) and return the saved file path.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Optional output PNG path; defaults to /tmp/hyprcandy_web_<ts>.png."},
                    "url": {"type": "string", "description": "Optional preview URL override."},
                },
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
    _register_turn_edit(str(p), old_content, is_new, content)

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


async def exec_command(command: str, cwd: Optional[str] = None, sandbox: bool = False) -> dict:
    work_dir = Path(cwd).expanduser() if cwd else Path.home()

    # Pre-scan files that might be targeted by the command to capture pre-edit content
    raw_candidates = set()
    # 1. Quoted string literals that contain slashes or extensions
    for q in re.findall(r'[\'"]([^\'"\n\r]+)[\'"]', command):
        q = q.strip()
        if '/' in q or ('.' in q and not q.startswith('.')):
            raw_candidates.add(q)

    # 2. String concatenation prefixes like 'dir/' + var
    for pre in re.findall(r'[\'"]([^\'"\n\r]*/(?:[^\'"\n\r]*/)*)[\'"]\s*\+\s*[a-zA-Z0-9_]+', command):
        raw_candidates.add(pre.strip())

    # 3. Path-like unquoted tokens
    pattern = r'(?:[\s"\'(=,\[\]]|^)((?:~?/|/|[a-zA-Z0-9_\-.]+/)[a-zA-Z0-9_\-./]+\.[a-zA-Z0-9_\-]+)'
    for m in re.finditer(pattern, command):
        cand = m.group(1).strip("\"'[](),")
        raw_candidates.add(cand)

    candidates = set()
    for cand in raw_candidates:
        if cand.startswith(('http://', 'https://', 'ftp://')):
            continue
        p = Path(cand).expanduser()
        if not p.is_absolute():
            p = (work_dir / p).resolve()
        if p.is_file():
            candidates.add(p)
        elif p.is_dir():
            try:
                for root_dir, _, files in os.walk(p):
                    for f in files:
                        candidates.add(Path(root_dir) / f)
            except Exception:
                pass
        else:
            candidates.add(p)

    pre_snapshots = {}
    for p in candidates:
        if p.is_file():
            try:
                pre_snapshots[p] = (p.read_text(errors="replace"), p.stat().st_mtime)
            except Exception:
                pass
        else:
            pre_snapshots[p] = (None, None)

    try:
        # Optional bubblewrap sandbox (agent opts in per command): read-only
        # root with only the working directory, /tmp and the user cache dir
        # writable; network is kept so builds/downloads still work. Falls back
        # to a direct run (with a note) when bwrap is missing or cannot start.
        sandboxed = False
        sandbox_note = ""
        argv = ["/bin/bash", "-c", command]
        if sandbox:
            bwrap = shutil.which("bwrap")
            if bwrap:
                home = Path.home()
                argv = [
                    bwrap,
                    "--ro-bind", "/", "/",
                    "--bind", str(work_dir), str(work_dir),
                    "--bind", "/tmp", "/tmp",
                ]
                if (home / ".cache").is_dir():
                    argv += ["--bind", str(home / ".cache"), str(home / ".cache")]
                argv += [
                    "--dev", "/dev",
                    "--proc", "/proc",
                    "--tmpfs", "/run",
                    "--die-with-parent",
                    "--", "/bin/bash", "-c", command,
                ]
                sandboxed = True
            else:
                sandbox_note = "[sandbox unavailable: bwrap (bubblewrap) not installed; ran unsandboxed]\n"

        result = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            cwd=str(work_dir),
            timeout=60,
        )

        # bwrap itself failed to start (e.g. unprivileged user namespaces
        # disabled) — retry once unsandboxed so the task still progresses.
        if sandboxed and result.returncode != 0 and "bwrap:" in (result.stderr or ""):
            result = subprocess.run(
                ["/bin/bash", "-c", command],
                capture_output=True,
                text=True,
                cwd=str(work_dir),
                timeout=60,
            )
            sandboxed = False
            sandbox_note = "[sandbox failed to start; ran unsandboxed]\n"

        # Post-run discovery: scan stdout/stderr AND the command string itself for
        # file paths not captured in the pre-scan (e.g. python -c writing files via
        # variables). Also resolve relative open() paths against cwd.
        output_text = (result.stdout or '') + (result.stderr or '') + '\n' + command
        post_path_pattern = r'(?:^|[\s\'"(=,\[])(/(?:[^\s\'")\],]+/)*[^\s\'")\],]+\.[a-zA-Z0-9_-]{1,8})'
        for pm in re.finditer(post_path_pattern, output_text, re.MULTILINE):
            cand_str = pm.group(1).strip("\"'(),")
            if cand_str.startswith(('http://', 'https://')):
                continue
            cand_p = Path(cand_str)
            if cand_p not in pre_snapshots and cand_p.is_file():
                try:
                    mtime = cand_p.stat().st_mtime
                    if mtime >= (time.time() - 15):  # written in last 15s
                        pre_snapshots[cand_p] = (None, None)  # treat as new
                except Exception:
                    pass
        # Also scan for open() calls with relative paths written in cwd
        # (catches `python -c "open('rel/file.py','w').write(...)"` patterns)
        rel_open_pattern = r'(?:open|with open)\s*\(\s*[\'"]([^\'"]+\.[a-zA-Z0-9_-]{1,8})[\'"]'
        for rm in re.finditer(rel_open_pattern, command):
            rel_str = rm.group(1)
            cand_p = (work_dir / rel_str).resolve()
            if cand_p not in pre_snapshots and cand_p.is_file():
                try:
                    mtime = cand_p.stat().st_mtime
                    if mtime >= (time.time() - 15):
                        pre_snapshots[cand_p] = (None, None)
                except Exception:
                    pass


        # ── cwd mtime sweep ────────────────────────────────────────────────────
        # Catch files written via bare filenames (tee file.py, echo > conf,
        # heredocs like `cat > config.yml << EOF`) that the regex pre-scan can't
        # see because they have no path separator.  We do a shallow scan of
        # work_dir (not recursive — keeps it cheap) and add any file whose mtime
        # changed in the last 30 s and that isn't already tracked.
        cmd_end_time = time.time()
        try:
            for entry in work_dir.iterdir():
                if not entry.is_file() or entry in pre_snapshots:
                    continue
                try:
                    if entry.stat().st_mtime >= (cmd_end_time - 30):
                        pre_snapshots[entry] = (None, None)
                except Exception:
                    pass
        except Exception:
            pass

        # Post-scan modified files
        modified_files = []
        for p, (old_text, old_mtime) in pre_snapshots.items():
            try:
                if p.is_file():
                    mtime = p.stat().st_mtime
                    if old_mtime is None or mtime != old_mtime:
                        new_text = p.read_text(errors="replace")
                        if old_text is None or new_text != old_text:
                            is_new = (old_text is None)
                            old_c = old_text or ""
                            add, rem = _diff_counts(old_c, new_text)
                            _register_turn_edit(str(p), old_c, is_new, new_text)
                            rec = {
                                "path": str(p),
                                "old_content": old_c,
                                "new_content": new_text,
                                "is_new": is_new,
                                "additions": add,
                                "deletions": rem,
                            }
                            PENDING_EDITS[str(p)] = rec
                            rec['timestamp'] = time.time()
                            modified_files.append(rec)
            except Exception:
                pass

        # Cap content fields to keep the JSON payload (and working memory) bounded.
        # The agent-loop already caps tool_message content at 12k chars, but we also
        # need to prevent the in-process objects from ballooning when many files are
        # modified (each with full old+new text). UI diff blocks get content from the
        # live event yield (tool_result), not the working-memory copy, so the truncation
        # only affects what the LLM sees in its next turn's context.
        FILE_CONTENT_CAP = 4_000  # chars kept per old/new content in modified_files
        capped_modified = []
        for mf in modified_files:
            capped_modified.append({
                **mf,
                "old_content": (mf["old_content"] or "")[:FILE_CONTENT_CAP],
                "new_content": (mf["new_content"] or "")[:FILE_CONTENT_CAP],
            })
        res_payload = {
            "exitCode": result.returncode,
            "stdout": result.stdout[:8_000],
            "stderr": (sandbox_note + (result.stderr or ""))[:2_000],
            "sandboxed": sandboxed,
        }
        if capped_modified:
            res_payload["modified_files"] = capped_modified
        return res_payload
    except subprocess.TimeoutExpired:
        return {"exitCode": -1, "stdout": "", "stderr": "Command timed out after 60 seconds"}


async def web_search(query: str, max_results: int = 8) -> list[dict]:
    """
    Search the web with a multi-tier fallback pipeline:
    Tier 1: ddgs (DuckDuckGo Search) with native TLS fingerprinting (zero-config, local IP).
    Tier 2: Local SearXNG instance (http://127.0.0.1:8080) if ddgs is unavailable or fails.
    """
    cleaned_query = (query or "").strip()
    if not cleaned_query:
        return []

    # Tier 1: ddgs
    if DDGS is not None:
        try:
            def _sync_ddgs():
                d = DDGS()
                return list(d.text(cleaned_query, max_results=max_results))
            results = await asyncio.to_thread(_sync_ddgs)
            if results:
                formatted = []
                for r in results:
                    title = r.get("title") or ""
                    url = r.get("href") or r.get("url") or ""
                    snippet = r.get("body") or r.get("snippet") or ""
                    if title or url:
                        formatted.append({"title": title, "url": url, "content": snippet})
                if formatted:
                    return formatted
        except Exception:
            pass

    # Tier 2: SearXNG fallback
    try:
        params = urlencode({"q": cleaned_query, "format": "json", "categories": "general"})
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(f"{SEARXNG_URL}/search?{params}")
            if resp.is_success:
                data = resp.json()
                results = data.get("results", [])[:max_results]
                if results:
                    return [
                        {
                            "title": r.get("title", ""),
                            "url": r.get("url", ""),
                            "content": r.get("content", r.get("snippet", "")),
                        }
                        for r in results
                    ]
    except Exception:
        pass

    return []


async def fetch_url(url: str, max_chars: int = 24000) -> dict:
    """
    Fetch a URL and extract clean Markdown/text content with multi-tiered anti-bot resilience:
    Tier 1: curl_cffi AsyncSession with Chrome browser TLS/JA3 impersonation + trafilatura markdown extraction.
    Tier 2: Jina Reader (https://r.jina.ai/) headless reader for Cloudflare/WAF or JS-heavy SPAs.
    Tier 3: Standard httpx + regex HTML-stripping fallback.
    """
    target_url = (url or "").strip()
    if not target_url:
        return {"url": "", "text": "Error: empty URL provided."}

    # Tier 1: curl_cffi + trafilatura
    if AsyncSession is not None and trafilatura is not None:
        try:
            headers = {
                "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36",
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                "Accept-Language": "en-US,en;q=0.9",
            }
            async with AsyncSession(impersonate="chrome", timeout=12) as session:
                resp = await session.get(target_url, headers=headers)
                if resp.status_code == 200:
                    extracted = trafilatura.extract(
                        resp.text,
                        output_format="markdown",
                        include_links=True,
                        include_formatting=True,
                    )
                    if extracted and len(extracted.strip()) > 100:
                        clean_md = extracted.strip()[:max_chars]
                        return {"url": target_url, "text": clean_md}
        except Exception:
            pass

    # Tier 2: Jina Reader fallback (r.jina.ai)
    if AsyncSession is not None:
        try:
            jina_url = f"https://r.jina.ai/{target_url}"
            async with AsyncSession(timeout=15) as session:
                jina_resp = await session.get(jina_url)
                if jina_resp.status_code == 200 and jina_resp.text:
                    clean_md = jina_resp.text.strip()[:max_chars]
                    if len(clean_md) > 100:
                        return {"url": target_url, "text": clean_md}
        except Exception:
            pass

    # Tier 3: Standard httpx fallback with HTML stripping
    try:
        async with httpx.AsyncClient(
            timeout=15.0,
            headers={"User-Agent": "HyprCandy-Agent/1.0"},
            follow_redirects=True,
        ) as client:
            resp = await client.get(target_url)
            if resp.is_success:
                content_type = resp.headers.get("content-type", "")
                if "html" in content_type:
                    text = _strip_html(resp.text)
                else:
                    text = resp.text
                return {"url": target_url, "text": text[:max_chars]}
    except Exception as e:
        return {"url": target_url, "text": f"Failed to retrieve content from {target_url}: {e}"}

    return {"url": target_url, "text": f"Access restricted or empty content at {target_url}."}


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


async def task_complete(summary: str, remaining: str = "", suggestions: Optional[list] = None, screenshots: Optional[list] = None) -> dict:
    return {"summary": summary, "remaining": remaining, "suggestions": suggestions or [], "screenshots": screenshots or [], "completed": True}


# ── Agent memory (durable topic notes) ───────────────────────────────────────
# Lightweight long-term memory: the agent persists topic-scoped notes as
# markdown files under ~/.config/hyprcandy/cache/agent-memories so facts and
# preferences survive across sessions. One file per topic (slug-named) with a
# small front-matter header; the Memories panel lists/edits the same files.
MEMORY_DIR = Path(os.environ.get(
    "HYPRCANDY_MEMORY_DIR",
    str(Path.home() / ".config" / "hyprcandy" / "cache" / "agent-memories"),
))


def _memory_slug(topic: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", (topic or "").lower()).strip("-")
    return slug[:80] or "untitled"


def _memory_path(topic: str) -> Path:
    return MEMORY_DIR / f"{_memory_slug(topic)}.md"


def _parse_memory(text: str) -> dict:
    topic = ""
    updated = ""
    body = text
    if text.startswith("---"):
        parts = text.split("---", 2)
        if len(parts) >= 3:
            header, body = parts[1], parts[2].lstrip("\n")
            for line in header.splitlines():
                if line.startswith("topic:"):
                    topic = line[len("topic:"):].strip()
                elif line.startswith("updated:"):
                    updated = line[len("updated:"):].strip()
    return {"topic": topic, "updated": updated, "body": body}


async def list_memories() -> dict:
    if not MEMORY_DIR.is_dir():
        return {"memories": [], "dir": str(MEMORY_DIR)}
    items = []
    for f in sorted(MEMORY_DIR.glob("*.md")):
        try:
            text = f.read_text(errors="replace")
        except OSError:
            continue
        meta = _parse_memory(text)
        items.append({
            "topic": meta["topic"] or f.stem,
            "path": str(f),
            "updated": meta["updated"],
            "bytes": f.stat().st_size,
            "preview": " ".join(meta["body"].split())[:160],
        })
    return {"memories": items, "dir": str(MEMORY_DIR)}


async def read_memory(topic: str) -> dict:
    p = _memory_path(topic)
    if not p.is_file():
        raise FileNotFoundError(f"No memory named '{topic}'")
    meta = _parse_memory(p.read_text(errors="replace"))
    return {"topic": meta["topic"] or topic, "path": str(p), "content": meta["body"], "updated": meta["updated"]}


async def save_memory(topic: str, content: str) -> dict:
    MEMORY_DIR.mkdir(parents=True, exist_ok=True)
    p = _memory_path(topic)
    existed = p.is_file()
    ts = datetime.now().isoformat(timespec="seconds")
    p.write_text(f"---\ntopic: {topic}\nupdated: {ts}\n---\n\n{(content or '').strip()}\n")
    return {"ok": True, "path": str(p), "topic": topic, "created": not existed, "updated": ts}


async def delete_memory(topic: str) -> dict:
    p = _memory_path(topic)
    if not p.is_file():
        return {"ok": False, "path": str(p), "message": "no such memory"}
    p.unlink(missing_ok=True)
    return {"ok": True, "path": str(p), "topic": topic}


# ── Live web preview (canvas pane + CDP) ─────────────────────────────────────
# The React app polls /api/web_preview/state and opens/refreshes the pane when
# requestId advances; the agent then drives that same page over CDP.
WEB_PREVIEW_STATE = {"url": "", "title": "", "requestId": 0, "ts": 0.0}


def _preview_url(url: str = "") -> str:
    target = (url or WEB_PREVIEW_STATE["url"] or "").strip()
    if not target:
        raise ValueError("no web preview open — call web_preview_open first")
    return target


async def web_preview_open(url: str, title: str = "") -> dict:
    url = (url or "").strip()
    if not re.match(r"^https?://", url):
        raise ValueError("web_preview_open needs an http(s) URL")
    WEB_PREVIEW_STATE.update(url=url, title=title or url, ts=time.time())
    WEB_PREVIEW_STATE["requestId"] += 1
    return {
        "ok": True,
        "url": url,
        "requestId": WEB_PREVIEW_STATE["requestId"],
        "note": "The user's canvas opens/refreshes the preview pane within ~2s; "
                "web_preview_eval/snapshot/console/screenshot now drive that page.",
    }


async def web_preview_eval(js: str, url: str = "") -> dict:
    import cdp_client
    target = _preview_url(url)
    try:
        return await asyncio.to_thread(cdp_client.evaluate, target, js)
    except cdp_client.CDPUnavailable as e:
        return {"ok": False, "error": str(e)}


async def web_preview_snapshot(url: str = "") -> dict:
    import cdp_client
    target = _preview_url(url)
    try:
        return await asyncio.to_thread(cdp_client.snapshot, target)
    except cdp_client.CDPUnavailable as e:
        return {"ok": False, "error": str(e)}


async def web_preview_console(clear: bool = False, url: str = "") -> dict:
    import cdp_client
    target = _preview_url(url)
    try:
        entries = await asyncio.to_thread(cdp_client.console_entries, target, bool(clear))
        return {"ok": True, "entries": entries}
    except cdp_client.CDPUnavailable as e:
        return {"ok": False, "error": str(e)}


async def web_preview_screenshot(path: str = "", url: str = "") -> dict:
    import cdp_client
    target = _preview_url(url)
    out = path or f"/tmp/hyprcandy_web_{int(time.time())}.png"
    try:
        saved = await asyncio.to_thread(cdp_client.screenshot, target, out)
        return {"ok": True, "path": saved}
    except cdp_client.CDPUnavailable as e:
        return {"ok": False, "error": str(e)}


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
    "list_memories": list_memories,
    "read_memory": read_memory,
    "save_memory": save_memory,
    "write_memory": save_memory,
    "update_memory": save_memory,
    "delete_memory": delete_memory,
    "web_preview_open": web_preview_open,
    "web_preview_eval": web_preview_eval,
    "web_preview_snapshot": web_preview_snapshot,
    "web_preview_console": web_preview_console,
    "web_preview_screenshot": web_preview_screenshot,
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
        if "sandbox" not in args and "sandboxed" in args:
            args["sandbox"] = args.pop("sandboxed")
        if isinstance(args.get("sandbox"), str):
            args["sandbox"] = args["sandbox"].strip().lower() in ("true", "1", "yes", "on")
    elif canonical_name == "web_search":
        if "query" not in args:
            args["query"] = args.get("q") or args.get("search_query") or args.get("text") or ""
    elif canonical_name == "fetch_url":
        if "url" not in args:
            args["url"] = args.get("uri") or args.get("link") or ""
    elif canonical_name in ("web_preview_open", "web_preview_eval", "web_preview_snapshot",
                            "web_preview_console", "web_preview_screenshot"):
        if "url" not in args:
            args["url"] = args.get("uri") or args.get("link") or ""
        for k in ("uri", "link"):
            args.pop(k, None)
        if canonical_name == "web_preview_eval" and "js" not in args:
            args["js"] = args.get("expression") or args.get("code") or args.get("script") or ""
        for k in ("expression", "code", "script"):
            args.pop(k, None)
        if isinstance(args.get("clear"), str):
            args["clear"] = args["clear"].strip().lower() in ("true", "1", "yes", "on")
    elif canonical_name in ("read_memory", "save_memory", "delete_memory"):
        if "topic" not in args:
            args["topic"] = args.get("name") or args.get("title") or args.get("subject") or ""
        if canonical_name == "save_memory" and "content" not in args:
            args["content"] = args.get("text") or args.get("body") or args.get("notes") or ""

    # Memory tools take no/limited args; guard against a missing topic.
    if canonical_name in ("read_memory", "delete_memory") and not args.get("topic"):
        raise ValueError("memory tools require a 'topic'")
    if canonical_name == "save_memory" and not args.get("topic"):
        raise ValueError("save_memory requires a 'topic'")

    return await fn(**args)
