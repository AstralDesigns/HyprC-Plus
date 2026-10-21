"""
agent_loop.py — Unified multi-step agentic loop for HyprCandy Agent

Handles the BYOK provider and managed-cloud (Vercel AI Gateway) backends
through a single `backend_fn` interface. There is no local backend: llama.cpp
and WebLLM were fully removed from the product (2026-10).

Emits poll-ready dicts:
  {"type": "token",        "data": "..."}
  {"type": "reasoning",    "data": {"text": "..."}}                 # real chain-of-thought
  {"type": "tool_start",   "data": {"id": "...", "name": "...", "arguments": {...}}}
  {"type": "tool_result",  "data": {"id": "...", "name": "...", "result": any}}
  {"type": "tool_error",   "data": {"id": "...", "name": "...", "error": "..."}}
  {"type": "steer_ack",    "data": {"text": "..."}}                 # injected user instruction accepted
  {"type": "suggestions",  "data": {"mode": "...", "question": str, "options": [...], "questions": [...]}}
  {"type": "spec",         "data": {"status": "drafting"|"ready", "markdown": str}}  # spec-driven plan
  {"type": "awaiting_approval", "data": {"question": str}}          # loop blocks until /approve
  {"type": "verification", "data": {"command": str, "status": "running"|"complete", "exitCode": int, "output": str, "passed": bool}}
  {"type": "heartbeat",    "data": {}}                              # keepalive while blocked
  {"type": "done",         "data": {"content": "final text"}}
  {"type": "error",        "data": {"message": "..."}}
"""

from __future__ import annotations

import asyncio
import json
import re
from pathlib import Path
from typing import Any, AsyncIterator, Callable, Optional

import httpx

from tools import TOOLS_SCHEMA, dispatch, list_memories

# ── System prompt ─────────────────────────────────────────────────────────────
SYSTEM_PROMPT = """You are the HyprCandy Agent — an intelligent, autonomous AI coding assistant embedded in the HyprCandy desktop environment on Hyprland Linux.

## Persona & Style
- Respond in clean, concise Markdown.
- For simple conversational questions or explanations, just answer directly — no task planning needed.
- For multi-step coding, file editing, or agentic tasks, use the todo list and tool calls to work step by step.
- Never invent file contents or project facts — always inspect with tools first.

## Tools Available
You have access to these tools (call them as JSON tool_calls):

| Tool              | Purpose |
|-------------------|---------|
| list_directory    | List files/subdirs in a path |
| read_file         | Read file content (use offset/limit for large files) |
| write_file        | Create or overwrite a file |
| exec_command      | Run a bash command (build, git, test, install, service reload) |
| web_search        | Search via the local SearXNG instance |
| fetch_url         | Fetch and read a URL's text content |
| capture_preview   | Take a Wayland screenshot with grim (use during verification before completion) |
| todo_add          | Add tasks to your internal todo list |
| todo_start        | Mark a todo task as in-progress |
| todo_done         | Mark a todo task as complete |
| todo_skip         | Skip a todo task with a reason |
| todo_list         | Show the current todo list |
| suggest_options   | Offer the user tappable clarifying / next-step options |
| list_memories     | List durable topic memories saved across past sessions |
| read_memory       | Read one memory's full markdown by topic |
| save_memory       | Create/overwrite a durable markdown memory for a topic |
| delete_memory     | Remove an obsolete memory by topic |
| task_complete     | Signal the ENTIRE task is fully done (required to end agentic loops) |

## Agentic Task Workflow (for multi-step tasks)
1. **Plan first**: Call `todo_add` with a list of concrete subtasks. Include a mandatory **Verification** step as the final subtask before completion.
2. **Work step by step**: For each subtask, call `todo_start`, do the work with tools, then call `todo_done`.
3. **Inspect before editing**: Always `read_file` before `write_file` on existing files.
4. **Mandatory Verification**: Never finish a task without actively verifying your changes! (See Verification Methodology below).
5. **Complete properly**: Only call `task_complete` once ALL subtasks are done and verified. Include a dedicated `### Verification` section in your summary.
6. **Capture durable learnings first**: Immediately before `task_complete` (at the end of the turn), reflect on the work and, whenever you judge it worthwhile — without the user having to ask — `save_memory` any durable fact and update/`delete_memory` anything now stale (see the Memory rule below).

## Verification Methodology (MANDATORY Before Calling task_complete)
Always verify your implementation based on the project type:

### 1. Web & Frontend Applications (React, Vite, Vue, HTML/CSS/JS)
- **Build / Typecheck**: Run `exec_command` with `npm run build` or `vite build` or `tsc --noEmit` to confirm zero compilation or type errors.
- **Visual Verification**: If visual UI changes were made (layouts, modals, buttons, themes, CSS):
  - Trigger or reload the relevant view.
  - Call `capture_preview` to capture a screenshot via grim and verify that the layout, colors, elements, and states render cleanly without visual defects.

### 2. Desktop Shell & System Components (GTK4, GJS, Hyprland, Waybar, Quickshell, QML, Lua, Bash)
- **Syntax Validation**: Run syntax checks (e.g. `bash -n <script>`, `python3 -m py_compile <file>`).
- **Service Reload**: Reload the daemon or service (e.g. `systemctl --user restart <service>` or `./toggle-app-launcher.sh`).
- **Visual Verification**: Call `capture_preview` with `grim` to confirm the surface, window, or popup renders properly and is anchored correctly.

### 3. Backend, APIs & Server Applications (Python, FastAPI, Node, Go, Rust)
- **Tests & Linting**: Run test suites (e.g. `pytest`, `cargo test`, `go test ./...`, `npm test`).
- **Health & Endpoint Check**: Smoke-test endpoints with `curl -s http://127.0.0.1:<port>/health` or verify process logs for clean startup.

### 4. Non-Visual Projects, Scripts & CLI Tools
- **Execution & Return Codes**: Verify by running the tool/script with test arguments or `--help` and ensuring exit code 0.

### 5. Final Summary Requirements
When calling `task_complete` and presenting your response, ALWAYS include a numbered or bulleted `### Verification` section detailing:
- What build/compilation commands were run.
- What services were reloaded or tested.
- What visual screenshot (`capture_preview`) or command output verified the work.

## Critical Rules
- **task_complete is the final signal** — call it ONLY when the entire task is fully done and verified, not as a progress update.
- **Memory** — you have durable, topic-scoped markdown memories that persist across sessions. At the start of a substantive task, glance at `list_memories` and `read_memory` any relevant topic before re-discovering facts. **Maintain memory proactively — never wait to be asked.** As you work, and especially right before you call `task_complete` at the end of the turn, briefly reflect on what you did and, whenever you judge it worthwhile, `save_memory` any durable fact (a stable project convention, an architecture / tech-stack fact, a reusable gotcha or decision, or a user preference) and `update` or `delete_memory` any that went stale. Use your own judgment about what deserves persisting — skip trivia and one-off details that won't help future sessions. Never store secrets (API keys, passwords, tokens) in memory.
- **suggest_options** — when you need the user to make a choice before you can proceed, call it with `mode: "clarify"` and 2-4 concrete options; the turn will pause for their pick. For several decisions at once, pass `questions` (1-4) — each question shows its options plus a free-text "Other" field and the turn pauses until the user submits. Use `mode: "next-step"` to offer optional follow-ups after an answer. Never fabricate choices you can't act on.
- **Normal answers don't need task_complete** — for conversational responses, just reply in Markdown and stop.
- **Don't repeat failing tools** — if a tool fails 3 times with the same args, report the limitation and stop.
- **exec_command safety** — avoid destructive commands (rm -rf, sudo dd, etc.) without clear user intent.
- **capture_preview** — use during the verification phase of UI/visual tasks to confirm layout and design quality.

## Inline Selection Edits
The user can attach an exact code selection as a structured block in their message:
<selection path="/abs/path/file.ext" lines="12-18">
…the selected text…
</selection>
When you see one, the user is asking you to change THAT region. `read_file` the given path for full surrounding context, edit only the selected lines (the block already shows their current content), then `write_file` the complete updated file so the user reviews the diff before it is applied. Follow the user's actual instruction that accompanies the block; if the requested change is unclear, ask rather than guess. Handle every `<selection>` block when several appear.

## Context
You are running on a Hyprland Wayland compositor. The user's project files are provided in context. Use list_directory and read_file to explore when needed."""

MAX_ITERATIONS = 20
MAX_FIX_ROUNDS = 3

# ── Spec-driven mode: instruction that constrains the first phase to planning ─
SPEC_DRAFT_INSTRUCTION = """SPEC-DRIVEN MODE IS ON. Do NOT call any tools, edit any file,\
 or run any command in this phase. Produce ONLY a concrete implementation plan in Markdown:

- A 1-2 sentence **Overview** of the approach.
- A numbered **Steps** checklist of the specific changes you will make.
- A **Files** list of what you expect to touch (use the provided project tree only).
- A **Verification** note describing how you'll prove it works (build/test commands,\
 screenshot, etc.).

Keep it tight and actionable. The user will Approve or ask for revisions before you execute."""


def _detect_verify_command(project_path: Optional[str]) -> Optional[str]:
    """Best-effort discovery of a project's build/test command for the
    verification gate. An explicit `verify_command` in `.hyprcandy-agent.json`
    at the project root always wins; otherwise infer from common manifests.
    Returns None when there's nothing sensible to run (→ the gate is skipped,
    which is correct for non-code/conversational turns)."""
    if not project_path:
        return None
    root = Path(project_path).expanduser()
    try:
        if not root.is_dir():
            return None
    except OSError:
        return None
    cfg = root / ".hyprcandy-agent.json"
    if cfg.is_file():
        try:
            data = json.loads(cfg.read_text())
            cmd = data.get("verify_command")
            if isinstance(cmd, str) and cmd.strip():
                return cmd.strip()
        except Exception:
            pass
    if (root / "package.json").is_file():
        try:
            pkg = json.loads((root / "package.json").read_text())
            scripts = pkg.get("scripts", {}) or {}
            for key in ("build", "typecheck", "test"):
                if key in scripts:
                    return f"npm run {key}"
        except Exception:
            pass
    if (root / "pyproject.toml").is_file() or (root / "pytest.ini").is_file() or (root / "setup.py").is_file():
        if (root / "tests").is_dir() or (root / "test").is_dir():
            return "pytest -q"
    if (root / "Cargo.toml").is_file():
        return "cargo build"
    if (root / "go.mod").is_file():
        return "go build ./..."
    if (root / "Makefile").is_file():
        return "make"
    return None


async def _run_verify(command: str, cwd: Optional[str], timeout: int = 300) -> dict:
    """Run the verification command WITHOUT blocking the event loop, so client
    polls keep flowing during a long build. stdout+stderr are merged."""
    try:
        proc = await asyncio.create_subprocess_shell(
            command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            cwd=str(Path(cwd).expanduser()) if cwd else None,
        )
    except Exception as exc:
        return {"exitCode": -1, "output": f"failed to start command: {exc}"}
    try:
        out, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        try:
            proc.kill()
        except Exception:
            pass
        return {"exitCode": -1, "output": f"verification timed out after {timeout}s"}
    text = (out or b"").decode("utf-8", "replace")
    return {"exitCode": proc.returncode, "output": text[-4000:]}

# ── In-memory per-request todo list ──────────────────────────────────────────
class _TodoList:
    def __init__(self):
        self.tasks: list[dict] = []
        self.next_id = 1

    def add(self, tasks: list[str]) -> list[int]:
        ids = []
        for t in tasks:
            tid = self.next_id
            self.next_id += 1
            self.tasks.append({"id": tid, "task": t, "status": "pending"})
            ids.append(tid)
        return ids

    def start(self, task_id: int) -> bool:
        for t in self.tasks:
            if t["id"] == task_id:
                t["status"] = "in_progress"
                return True
        return False

    def done(self, task_id: int) -> bool:
        for t in self.tasks:
            if t["id"] == task_id:
                t["status"] = "done"
                return True
        return False

    def skip(self, task_id: int, reason: str = "") -> bool:
        for t in self.tasks:
            if t["id"] == task_id:
                t["status"] = "skipped"
                if reason:
                    t["skip_reason"] = reason
                return True
        return False

    def format(self) -> str:
        if not self.tasks:
            return "Todo list is empty."
        lines = []
        for t in self.tasks:
            mark = {"done": "✓", "in_progress": "▶", "skipped": "○", "pending": "☐"}.get(t["status"], "☐")
            skip_note = f" (skipped: {t.get('skip_reason', '')})" if t["status"] == "skipped" else ""
            lines.append(f"  {mark} [{t['id']}] {t['task']}{skip_note}")
        done = sum(1 for t in self.tasks if t["status"] == "done")
        total = len(self.tasks)
        return f"Todo ({done}/{total} done):\n" + "\n".join(lines)

    def has_pending(self) -> bool:
        return any(t["status"] in ("pending", "in_progress") for t in self.tasks)


# ── Backend function type ─────────────────────────────────────────────────────
# backend_fn(messages: list[dict]) -> AsyncIterator[dict]
# Each yielded dict must have one of:
#   {"type": "token", "content": str}
#   {"type": "tool_calls", "calls": [{"id": str, "name": str, "arguments": str}]}
#   {"type": "done"}
#   {"type": "error", "message": str}



# ── Inline tool-call parser (fallback for models that output <tool_call> XML) ─
_TOOL_CALL_RE = re.compile(
    r"<tool_call>\s*(\{.*?\})\s*</tool_call>", re.DOTALL | re.IGNORECASE
)


def _parse_inline_calls(text: str) -> list[dict]:
    calls = []
    for m in _TOOL_CALL_RE.finditer(text):
        try:
            obj = json.loads(m.group(1))
            name = obj.get("name") or obj.get("function", {}).get("name", "")
            args = obj.get("arguments") or obj.get("args") or {}
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except Exception:
                    args = {}
            if name:
                calls.append({"id": f"inline_{len(calls)}", "name": name, "arguments": json.dumps(args)})
        except Exception:
            pass
    return calls


def _strip_tool_call_text(text: str) -> str:
    """Remove <tool_call>...</tool_call> blocks from visible text."""
    return _TOOL_CALL_RE.sub("", text).strip()


# ── Main agentic loop ─────────────────────────────────────────────────────────
async def run_agentic_turn(
    user_message: str,
    history: list[dict],
    backend_fn: Callable[[list[dict]], AsyncIterator[dict]],
    project_context: Optional[str] = None,
    steer_source: Optional[Callable[[], list[str]]] = None,
    spec_enabled: bool = False,
    project_path: Optional[str] = None,
    approve_source: Optional[Callable[[], Optional[str]]] = None,
) -> AsyncIterator[dict]:
    """
    Run the multi-step agentic loop.
    Yields poll-ready dicts (see module docstring for types).

    `steer_source`, if provided, is called at every iteration boundary and must
    return (and clear) any instructions the user injected mid-run via the
    /api/chat/steer route; each is appended to the conversation as a user turn
    and acknowledged with a `steer_ack` event.

    When `spec_enabled` (and `approve_source` is provided), a first phase drafts
    a Markdown plan, emits `spec` + `awaiting_approval`, and BLOCKS until the user
    approves (execute the plan), revises (re-draft with the feedback folded in via
    `steer_source`), or cancels. `project_path` enables the post-completion
    verification gate; `approve_source` returns 'approve'|'revise'|'cancel' or None.
    """
    # Per-request todo list instance
    todo = _TodoList()

    # Build working message history
    working: list[dict] = [{"role": "system", "content": SYSTEM_PROMPT}]
    working.extend(history)

    first_user_content = user_message
    if project_context:
        first_user_content = f"{user_message}\n\n{project_context}"

    # Best-effort durable-memory index so the agent knows what long-term context
    # already exists; full bodies are loaded on demand via read_memory.
    try:
        _mem = await list_memories()
        _topics = ", ".join(
            m.get("topic") for m in (_mem.get("memories") or []) if m.get("topic")
        )
    except Exception:
        _topics = ""
    if _topics:
        first_user_content += (
            f"\n\n[Your durable memories cover: {_topics}. Use read_memory(topic) to "
            "load one, save_memory(topic, content) to record durable facts, and "
            "delete_memory(topic) to drop obsolete ones.]"
        )
    working.append({"role": "user", "content": first_user_content})

    full_response = ""
    task_done = False
    repeated_calls: dict[str, int] = {}

    # ── Spec-driven pre-phase: draft a plan, then block for approval ──
    spec_enabled = spec_enabled and approve_source is not None
    if spec_enabled:
        yield {"type": "spec", "data": {"status": "drafting", "markdown": ""}}
        while True:
            spec_text = ""
            spec_err = None
            spec_messages = working + [{"role": "user", "content": SPEC_DRAFT_INSTRUCTION}]
            async for event in backend_fn(spec_messages):
                if event["type"] == "token":
                    spec_text += event["content"]
                elif event["type"] == "reasoning":
                    yield {"type": "reasoning", "data": {"text": event["content"]}}
                elif event["type"] == "error":
                    spec_err = event["message"]
            if spec_err:
                yield {"type": "error", "data": {"message": spec_err}}
                return
            spec_text = _strip_tool_call_text(spec_text) or "_(the model returned no plan)_"
            yield {"type": "spec", "data": {"status": "ready", "markdown": spec_text}}
            yield {"type": "awaiting_approval", "data": {"question": "Approve this plan, or ask for revisions?"}}

            # Block until the user decides. Emit a heartbeat every few seconds so
            # the client's idle timeout doesn't fire while we're paused.
            decision = None
            waited = 0.0
            while decision is None:
                await asyncio.sleep(0.5)
                waited += 0.5
                if waited >= 5.0:
                    yield {"type": "heartbeat", "data": {}}
                    waited = 0.0
                try:
                    decision = approve_source() if approve_source else None
                except Exception:
                    decision = None

            if decision == "approve":
                # Seed the approved plan into the conversation, then execute it.
                working.append({"role": "assistant", "content": spec_text})
                working.append({
                    "role": "user",
                    "content": (
                        "Plan approved. Now execute it step by step using your tools. "
                        "Follow the checklist, do the verification, and call task_complete "
                        "only when fully done. Do not re-ask for approval."
                    ),
                })
                break
            if decision == "cancel":
                yield {"type": "done", "data": {"content": "Plan cancelled — nothing was executed."}}
                return
            # decision == 'revise': fold the revision notes (via the steering queue)
            # into the conversation and re-draft above.
            notes: list[str] = []
            if steer_source is not None:
                try:
                    notes = steer_source() or []
                except Exception:
                    notes = []
            if notes:
                for n in notes:
                    working.append({"role": "user", "content": f"[Plan revision request] {n}"})
                    yield {"type": "steer_ack", "data": {"text": n}}
            else:
                working.append({"role": "user", "content": "[Plan revision request] Please refine the plan."})
            yield {"type": "spec", "data": {"status": "drafting", "markdown": ""}}

    # ── Verification gate state (runs after the model claims completion) ──
    verify_cmd = _detect_verify_command(project_path)
    verified_ok = False
    fix_round = 0

    iteration = 0
    budget = MAX_ITERATIONS
    while iteration < budget:
        if task_done:
            break

        # Drain any steering instructions the user injected since the last boundary
        if steer_source is not None:
            try:
                steers = steer_source() or []
            except Exception:
                steers = []
            for s in steers:
                working.append({"role": "user", "content": f"[User steering] {s}"})
                yield {"type": "steer_ack", "data": {"text": s}}
                budget += 1

        # ── LLM call ─────────────────────────────────────────────────────────
        assistant_text = ""
        pending_calls: list[dict] = []

        async for event in backend_fn(working):
            if event["type"] == "token":
                token = event["content"]
                assistant_text += token
                # Suppress tool_call XML from visible stream
                open_idx = assistant_text.find("<tool_call>")
                visible = assistant_text[:open_idx].rstrip() if open_idx >= 0 else assistant_text
                if visible != full_response:
                    full_response = visible
                    yield {"type": "token", "data": token}

            elif event["type"] == "tool_calls":
                pending_calls = event["calls"]

            elif event["type"] == "reasoning":
                yield {"type": "reasoning", "data": {"text": event["content"]}}

            elif event["type"] == "error":
                yield {"type": "error", "data": {"message": event["message"]}}
                return

        # Also check for inline <tool_call> XML in text
        inline_calls = _parse_inline_calls(assistant_text)
        all_calls = pending_calls + inline_calls

        # Deduplicate
        seen = set()
        unique_calls = []
        for c in all_calls:
            sig = f"{c['name']}:{c['arguments']}"
            if sig not in seen:
                seen.add(sig)
                unique_calls.append(c)

        # Commit assistant turn to history
        if unique_calls:
            working.append({
                "role": "assistant",
                "content": _strip_tool_call_text(assistant_text) or None,
                "tool_calls": [
                    {
                        "id": c["id"],
                        "type": "function",
                        "function": {"name": c["name"], "arguments": c["arguments"]},
                    }
                    for c in unique_calls
                ],
            })
        else:
            working.append({"role": "assistant", "content": assistant_text})

        if not unique_calls:
            # No tool calls — final conversational answer
            full_response = _strip_tool_call_text(assistant_text)
            break

        # ── Execute tools ─────────────────────────────────────────────────────
        tool_messages: list[dict] = []

        for call in unique_calls:
            name = call["name"]
            try:
                args_raw = call.get("arguments", "{}")
                args = json.loads(args_raw) if isinstance(args_raw, str) else args_raw
            except json.JSONDecodeError:
                args = {}

            # Repeat-call guard
            sig = f"{name}:{json.dumps(args, sort_keys=True)}"
            repeat_count = repeated_calls.get(sig, 0) + 1
            repeated_calls[sig] = repeat_count
            if repeat_count > 3:
                err_content = f"Tool '{name}' was called {repeat_count} times with the same args and failed to make progress. Try a different approach or call task_complete with the limitation."
                yield {"type": "tool_error", "data": {"id": call["id"], "name": name, "error": err_content}}
                tool_messages.append({
                    "role": "tool",
                    "tool_call_id": call["id"],
                    "content": err_content,
                })
                if repeat_count >= 5:
                    task_done = True
                    full_response = f"Stopped: '{name}' was called repeatedly with the same arguments. Please verify the path/permissions and retry."
                continue

            # Handle todo list tools internally (not dispatched to tools.py)
            if name == "todo_add":
                tasks_list = args.get("tasks") or ([args["task"]] if "task" in args else [])
                ids = todo.add(tasks_list)
                result = {"added": ids, "list": todo.format()}
                yield {"type": "tool_start", "data": {"id": call["id"], "name": name, "arguments": args}}
                yield {"type": "tool_result", "data": {"id": call["id"], "name": name, "result": result}}
                tool_messages.append({
                    "role": "tool",
                    "tool_call_id": call["id"],
                    "content": json.dumps(result),
                })
                continue

            elif name == "todo_start":
                ok = todo.start(int(args.get("task_id", 0)))
                result = {"ok": ok, "list": todo.format()}
                yield {"type": "tool_start", "data": {"id": call["id"], "name": name, "arguments": args}}
                yield {"type": "tool_result", "data": {"id": call["id"], "name": name, "result": result}}
                tool_messages.append({
                    "role": "tool",
                    "tool_call_id": call["id"],
                    "content": json.dumps(result),
                })
                continue

            elif name == "todo_done":
                ok = todo.done(int(args.get("task_id", 0)))
                result = {"ok": ok, "list": todo.format()}
                yield {"type": "tool_start", "data": {"id": call["id"], "name": name, "arguments": args}}
                yield {"type": "tool_result", "data": {"id": call["id"], "name": name, "result": result}}
                tool_messages.append({
                    "role": "tool",
                    "tool_call_id": call["id"],
                    "content": json.dumps(result),
                })
                continue

            elif name == "todo_skip":
                ok = todo.skip(int(args.get("task_id", 0)), args.get("reason", ""))
                result = {"ok": ok, "list": todo.format()}
                yield {"type": "tool_start", "data": {"id": call["id"], "name": name, "arguments": args}}
                yield {"type": "tool_result", "data": {"id": call["id"], "name": name, "result": result}}
                tool_messages.append({
                    "role": "tool",
                    "tool_call_id": call["id"],
                    "content": json.dumps(result),
                })
                continue

            elif name == "todo_list":
                result = {"list": todo.format()}
                yield {"type": "tool_start", "data": {"id": call["id"], "name": name, "arguments": args}}
                yield {"type": "tool_result", "data": {"id": call["id"], "name": name, "result": result}}
                tool_messages.append({
                    "role": "tool",
                    "tool_call_id": call["id"],
                    "content": json.dumps(result),
                })
                continue

            elif name == "suggest_options":
                mode = args.get("mode", "next-step")
                options = args.get("options") or []
                questions = args.get("questions") or []
                question = args.get("question", "")
                result = {"ok": True, "mode": mode, "options": options, "questions": questions}
                yield {"type": "tool_start", "data": {"id": call["id"], "name": name, "arguments": args}}
                yield {"type": "suggestions", "data": {"mode": mode, "question": question, "options": options, "questions": questions}}
                yield {"type": "tool_result", "data": {"id": call["id"], "name": name, "result": result}}
                tool_messages.append({
                    "role": "tool",
                    "tool_call_id": call["id"],
                    "content": json.dumps(result),
                })
                # A multi-question form is always a pause; a single-row clarify
                # pauses too. next-step chips stay advisory (turn continues).
                if mode == "clarify" or questions:
                    task_done = True
                    full_response = question or "Answer the questions above to continue."
                continue

            # All other tools dispatched to tools.py
            yield {"type": "tool_start", "data": {"id": call["id"], "name": name, "arguments": args}}

            try:
                result = await dispatch(name, args)
                result_str = json.dumps(result, ensure_ascii=False) if not isinstance(result, str) else result
                yield {"type": "tool_result", "data": {"id": call["id"], "name": name, "result": result}}
                tool_messages.append({
                    "role": "tool",
                    "tool_call_id": call["id"],
                    "content": result_str[:12_000],
                })
                if name == "task_complete":
                    task_done = True
                    full_response = args.get("summary", "Task completed.")
            except Exception as exc:
                err_msg = str(exc)
                yield {"type": "tool_error", "data": {"id": call["id"], "name": name, "error": err_msg}}
                tool_messages.append({
                    "role": "tool",
                    "tool_call_id": call["id"],
                    "content": f"Tool error: {err_msg}",
                })

        working.extend(tool_messages)

        # ── Verification gate: once the model claims completion, actually run the
        #    project's build/test and feed failures back for an iterative fix. ──
        if task_done and verify_cmd and not verified_ok:
            yield {"type": "verification", "data": {"command": verify_cmd, "status": "running", "exitCode": None, "output": "", "passed": None}}
            vres = await _run_verify(verify_cmd, project_path)
            exit_code = vres.get("exitCode", -1)
            output = vres.get("output", "")
            passed = (exit_code == 0)
            yield {"type": "verification", "data": {"command": verify_cmd, "status": "complete", "exitCode": exit_code, "output": output, "passed": passed}}
            if passed:
                verified_ok = True
            elif fix_round < MAX_FIX_ROUNDS:
                fix_round += 1
                task_done = False
                budget += 1
                working.append({
                    "role": "user",
                    "content": (
                        f"Verification FAILED — `{verify_cmd}` exited {exit_code}.\n"
                        f"--- output (tail) ---\n{output}\n"
                        f"Fix the remaining issues, re-verify locally if you can, then call "
                        f"task_complete again. (fix attempt {fix_round}/{MAX_FIX_ROUNDS})"
                    ),
                })
                iteration += 1
                continue
            else:
                full_response = (full_response or "") + (
                    f"\n\n⚠️ Verification still failing after {MAX_FIX_ROUNDS} fix attempts — "
                    f"stopping for your review (`{verify_cmd}` exited {exit_code})."
                )

        if not task_done and iteration < budget - 1:
            # Provide todo status in continuation prompt so the model stays on track
            todo_status = todo.format() if todo.tasks else ""
            continue_msg = "Continue the task. Call task_complete only when it is fully done."
            if todo_status:
                continue_msg += f"\n\nCurrent todo list:\n{todo_status}"
            working.append({
                "role": "user",
                "content": continue_msg,
            })

        iteration += 1

    yield {"type": "done", "data": {"content": full_response}}
