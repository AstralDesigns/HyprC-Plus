"""
agent_loop.py — Unified multi-step agentic loop for HyprCandy Agent

Handles both local (llama-server) and cloud (Vercel AI Gateway) backends
through a single `backend_fn` interface.

Emits poll-ready dicts:
  {"type": "token",        "data": "..."}
  {"type": "tool_start",   "data": {"id": "...", "name": "...", "arguments": {...}}}
  {"type": "tool_result",  "data": {"id": "...", "name": "...", "result": any}}
  {"type": "tool_error",   "data": {"id": "...", "name": "...", "error": "..."}}
  {"type": "done",         "data": {"content": "final text"}}
  {"type": "error",        "data": {"message": "..."}}
"""

from __future__ import annotations

import asyncio
import json
import re
from typing import Any, AsyncIterator, Callable, Optional

import httpx

from tools import TOOLS_SCHEMA, dispatch

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
| task_complete     | Signal the ENTIRE task is fully done (required to end agentic loops) |

## Agentic Task Workflow (for multi-step tasks)
1. **Plan first**: Call `todo_add` with a list of concrete subtasks. Include a mandatory **Verification** step as the final subtask before completion.
2. **Work step by step**: For each subtask, call `todo_start`, do the work with tools, then call `todo_done`.
3. **Inspect before editing**: Always `read_file` before `write_file` on existing files.
4. **Mandatory Verification**: Never finish a task without actively verifying your changes! (See Verification Methodology below).
5. **Complete properly**: Only call `task_complete` once ALL subtasks are done and verified. Include a dedicated `### Verification` section in your summary.

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
- **Normal answers don't need task_complete** — for conversational responses, just reply in Markdown and stop.
- **Don't repeat failing tools** — if a tool fails 3 times with the same args, report the limitation and stop.
- **exec_command safety** — avoid destructive commands (rm -rf, sudo dd, etc.) without clear user intent.
- **capture_preview** — use during the verification phase of UI/visual tasks to confirm layout and design quality.

## Context
You are running on a Hyprland Wayland compositor. The user's project files are provided in context. Use list_directory and read_file to explore when needed."""

MAX_ITERATIONS = 20

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


# ── Local backend (llama-server) ──────────────────────────────────────────────
async def local_backend(messages: list[dict]) -> AsyncIterator[dict]:
    """Stream from llama-server /v1/chat/completions (OpenAI-compatible)."""
    from llama_manager import LLAMA_PORT

    payload = {
        "model": "local",
        "messages": messages,
        "tools": TOOLS_SCHEMA,
        "tool_choice": "auto",
        "parallel_tool_calls": False,
        "stream": True,
        "temperature": 0.2,
        "max_tokens": 4096,
    }

    tool_call_buffer: dict[str, dict] = {}

    async with httpx.AsyncClient(timeout=180.0) as client:
        async with client.stream(
            "POST",
            f"http://127.0.0.1:{LLAMA_PORT}/v1/chat/completions",
            json=payload,
            headers={"Content-Type": "application/json"},
        ) as resp:
            if not resp.is_success:
                body = await resp.aread()
                yield {"type": "error", "message": f"llama-server HTTP {resp.status_code}: {body[:300].decode()}"}
                return

            buffer = ""
            async for raw_chunk in resp.aiter_bytes(1024):
                buffer += raw_chunk.decode(errors="replace")
                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    line = line.strip()
                    if not line or not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    if data == "[DONE]":
                        break
                    try:
                        chunk = json.loads(data)
                    except json.JSONDecodeError:
                        continue

                    choice = (chunk.get("choices") or [{}])[0]
                    delta = choice.get("delta", {})

                    if delta.get("content"):
                        yield {"type": "token", "content": delta["content"]}

                    for tc_delta in delta.get("tool_calls") or []:
                        idx = str(tc_delta.get("index", 0))
                        if idx not in tool_call_buffer:
                            tool_call_buffer[idx] = {"id": "", "name": "", "arguments": ""}
                        buf = tool_call_buffer[idx]
                        buf["id"] = buf["id"] or tc_delta.get("id", f"call_{idx}")
                        fn = tc_delta.get("function", {})
                        buf["name"] += fn.get("name", "")
                        buf["arguments"] += fn.get("arguments", "")

                    if choice.get("finish_reason"):
                        break

    # Flush buffered tool calls
    if tool_call_buffer:
        yield {
            "type": "tool_calls",
            "calls": list(tool_call_buffer.values()),
        }

    yield {"type": "done"}


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
) -> AsyncIterator[dict]:
    """
    Run the multi-step agentic loop.
    Yields poll-ready dicts (see module docstring for types).
    """
    # Per-request todo list instance
    todo = _TodoList()

    # Build working message history
    working: list[dict] = [{"role": "system", "content": SYSTEM_PROMPT}]
    working.extend(history)

    first_user_content = user_message
    if project_context:
        first_user_content = f"{user_message}\n\n{project_context}"
    working.append({"role": "user", "content": first_user_content})

    full_response = ""
    task_done = False
    repeated_calls: dict[str, int] = {}

    for iteration in range(MAX_ITERATIONS):
        if task_done:
            break

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

        if not task_done and iteration < MAX_ITERATIONS - 1:
            # Provide todo status in continuation prompt so the model stays on track
            todo_status = todo.format() if todo.tasks else ""
            continue_msg = "Continue the task. Call task_complete only when it is fully done."
            if todo_status:
                continue_msg += f"\n\nCurrent todo list:\n{todo_status}"
            working.append({
                "role": "user",
                "content": continue_msg,
            })

    yield {"type": "done", "data": {"content": full_response}}
