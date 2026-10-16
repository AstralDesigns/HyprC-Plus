# Turning the HyprCandy `agent-app` Chat Panel into a "Qoder Quest"-style Flow

**Scope:** feasibility + concrete implementation plan for reshaping
`~/.hyprcandy/GJS/hyprcandydock/agent-app` (React/WebKit UI) and
`~/.hyprcandy/GJS/hyprcandydock/Agents/local_runtime` (Python runtime) so the chat
panel behaves like **Qoder Quest**: a left "Quests" task list, Spec-driven planning,
visible agent reasoning, a live task checklist, testing-and-verification, steering
prompts, editable/revertable turns, and chat naming.

**Verdict up front: YES — this is very feasible, and most of the hard machinery already
exists.** Roughly **~70% of the primitives are already in the codebase** (todo/plan
tools, tool dispatch, inline diffs with accept/reject, multi-session storage with
auto-title, cancel, and a start→poll event protocol). The transform is mostly **UI/UX
reshaping plus four additive backend changes** (real reasoning capture, a verification
gate, mid-run steering, and per-turn snapshots for Revert). Nothing requires a rewrite
of the engine.

---

## 1. What "Qoder Quest" actually is (the model to mimic)

From Qoder's own docs (`docs.qoder.com/user-guide/quest/*`), Quest is **task delegation
to an autonomous coding agent**. Its flow, in their words:

> "The Agent completes development tasks end-to-end — autonomously clarifying
> requirements, planning solutions, executing code, and verifying results, without
> continuous manual intervention."

The observable UI/behaviour concepts we are cloning:

| Qoder Quest concept | What it means | Our closest existing asset |
|---|---|---|
| **Quest / New Quest** | A top-level task, created from a **left task list** | `sessions` array + `SessionsSidebar.tsx` (built, unmounted) |
| **Spec-driven mode** | Agent writes a structured **Spec** doc first; user approves direction before coding | `plan_update` + `_TodoList` + `task_complete` tools; `PlanData`/`PlanTask` types |
| **Prototype exploration** | Skip the Spec, code immediately | current default (no spec step) |
| **Agent reasoning** | Model's plan/thinking surfaced to the user | faux "Thinking…" phase pill only |
| **Task handling / progress** | Live checklist of steps | activity-timeline lines (`ListChecks` "Updating plan…") |
| **Autonomous validation** | Tests/builds run automatically; failures fixed iteratively before review | prompt-only "MANDATORY Verification", no gate |
| **Steer / natural-language iteration** | Add requirements mid/post-run ("make the button larger") | composer **disabled during run**; cancel-only |
| **Edit sent message** | Re-edit a past turn; workspace rolls back to before it | inline edit of last user msg only, no rollback |
| **Revert** | Restore workspace to pre-turn state; inspect in Diff View | per-file `PENDING_EDITS` snapshots (no per-turn grouping) |
| **Diff View / Summary Files** | Review all changed files together | `DiffWidget` + `PendingFilesBar` (already close) |
| **Agent vs Experts mode** | Single agent vs parallel multi-agent | single agent (`run_agentic_turn`) |
| **Local vs Worktree env** | Apply in place vs isolated git worktree | in-place `write_file` only |
| **Suggested replies / clarification** | Agent offers **tappable prompt chips** to clarify requirements or steer, instead of only free-text | none (free-text composer only) |

The **gap is behavioural/UI layering, not capability.** The agent can already plan, call
tools, edit files, run commands, and stream — it just isn't presented as a Quest.

---

## 2. Current architecture (grounded)

```
React/TS UI (WebKitGTK)                      Python "local runtime" (FastAPI)
  App.tsx  Header+Canvas+Sidebar+ChatPanel    127.0.0.1:17900  runtime_server.py
   ├─ ChatPanel.tsx   (session dropdown)       ├─ /api/chat/start   → chat_start()
   ├─ ChatStream.tsx  (block renderer)         ├─ /api/chat/poll    (typed events)
   ├─ Composer.tsx    (input/stop)             ├─ /api/chat/cancel  → task cancel
   ├─ engine/agent-engine.ts  runConversation  └─ agent_loop.py  run_agentic_turn()
   ├─ bridge.ts  postToHost / runtimeRequest        ├─ tools.py   TOOLS_SCHEMA/dispatch
   └─ store.ts   Message/Session + persistence       └─ byok_client / cloud_client (SSE)
        ▲                                                     ▲
        └── window.webkit.messageHandlers.agent ──► GJS host ─┘  (proxies HTTP)
```

- **Transport:** JSON-RPC-ish `bridge.postToHost(action, payload)` ↔
  `window.__hyprcandy_agent_dispatch` (`bridge.ts:110`, `:32`). Runtime HTTP is proxied
  through `runtimeRequest()` (`bridge.ts:336`).
- **Turn orchestration (3 layers):**
  - UI: `AgentEngine.runConversation()` — `engine/agent-engine.ts:115` (start + poll loop `:302`–`:449`).
  - Server: `chat_start()` — `runtime_server.py:175`.
  - Engine: **`run_agentic_turn()`** — `agent_loop.py:270` (`for iteration in range(MAX_ITERATIONS)`, `MAX_ITERATIONS = 20`, `:99`/`:296`).
- **Data model (`store.ts`):** `Message` `:81`–`:93`; `MessageBlock` union
  (`text|activity|command|diff`) `:75`–`:79`; `Session` `:101`–`:108`; `PlanData`/`PlanTask`
  `:56`–`:66`. Persistence = localStorage `hyprcandy_agent_state_v2` (`:269`) + a durable
  host mirror to `~/.local/share/hyprcandy/agent-state.json` via `bridge.storePersist`
  (`bridge.ts:320`).
- **Tools (`tools.py:496`–`:505`):** `list_directory, read_file, write_file, exec_command,
  web_search, fetch_url, capture_preview, task_complete` + planning tools
  `todo_add/start/done/skip/list`, `plan_update` (`tools.py:231`–`:307`).
- **Backends:** **cloud only** — real **BYOK** aggregators (`openrouter` default, `groq`;
  legacy `aimlapi/google/anthropic/openai/xai` hidden) + managed **cloud** gateway.
  **All local inference is fully removed (2026-10):** llama.cpp/llama-server retired first
  (dead `llama-cpp.service.ts` + `/api/server/*` callers gone), then the WebLLM "Local" tab
  was deleted when it was verified that Qt WebEngine architecturally cannot expose a WebGPU
  adapter (§8.2). Runtime `/api/models/*` + `/api/server/*` remain only as inert `disabled`
  stubs for old clients.

### The existing `poll` event protocol
`/api/chat/poll/{task_id}?since=N` replays typed events: `token`, `tool_start`,
`tool_result`, `tool_error`, `done`, `error` (`agent_loop.py:7`–`:13`, consumed
`agent-engine.ts:290`–`:449`). **This is the single most important asset for the
transform** — steering, verification, and reasoning events are all additive event types on
this bus, not a new architecture.

---

## 3. Feature-by-feature: what exists, what's missing, effort

Legend — **Effort:** S ≈ hours, M ≈ 1–2 days, L ≈ multi-day.

### 3.1 Left "Quests" markdown sidebar + jumping between chats — **Effort: S** ✅ **DONE (as dropdown, Option A)**
- **Today:** `store.sessions` + create/switch/rename/delete actions exist
  (`store.ts:665`–`:715`), and a complete `SessionsSidebar.tsx` (new / switch / delete /
  relative-time / preview line) is **written but never imported**. Sessions switch today
  through the `ChatPanel` header dropdown (`ChatPanel.tsx:115`–`:194`).
- **Implemented (revised direction):** a persistent left rail was tried and **rejected**
  in favor of folding the Quest manager into the existing **`ChatPanel` header dropdown**
  — the panel is already extensive and is where the rest of the plan will keep improving
  integration. The dropdown now reads "Quests": *New Quest*, newest-updated-first list,
  click-to-switch, double-click/pencil inline rename, per-quest delete; Cmd/Ctrl+N and the
  `agent_new_chat` host event call `storeActions.createSession()` (`App.tsx`).
  `SessionsSidebar.tsx` stays in-tree **unmounted** as a ready-made component should a
  rail ever be wanted; its `.quests-rail` CSS was removed.
- **Result:** near-instant "jump to a specific chat" without spending horizontal space
  in the canvas; P1+ quest chrome (status dots, pinned plan) lands in the same dropdown.

### 3.2 Chat naming — **Effort: S** ✅ **DONE**
- **Today:** auto-title from the first completed turn exists —
  `deriveSessionTitle()` (`agent-engine.ts:43`–`:56`, invoked `:408`–`:416`); manual rename
  wins over auto. `Session.title` / `titleSource` are in the type (`store.ts:101`–`:108`).
- **Implemented:** **inline rename** on the Quests dropdown rows (double-click title or the
  pencil → editable, Enter/blur commits via `renameSession` which sets `titleSource='user'`,
  so `autoNameSession` never overwrites a manual name). Optional (not done): a cheap LLM
  "name this quest" call after the first turn. No backend change was required.

### 3.3 Visible agent reasoning (real chain-of-thought) — **Effort: M** — ✅ **P1 DONE**
- **Today:** **faux only.** A "Thinking…" phase pill is derived from tool state
  (`ChatStream.tsx:44`–`:71`, gradient line `ChatPanel.tsx:213`). Real reasoning tokens are
  dropped: OpenAI-compat reads only `delta.content` (`byok_client.py:581`); Anthropic handles
  only `text_delta`/`input_json_delta`, **not `thinking_delta`** (`byok_client.py:696`–`:701`);
  Google emits only `part.text` even though `thinkingBudget` is set (`byok_client.py:434`,
  `:490`).
- **To do:**
  1. **Python:** in `byok_client.py`, capture reasoning per provider —
     Anthropic `content_block_delta` where `delta.type === "thinking_delta"`; OpenAI
     o-series `delta.reasoning_summary_text`/`reasoning_content`; Google
     `part.thought`. Emit a new event type **`reasoning`** on the poll bus.
  2. **Protocol:** add a `reasoning` MessageBlock subtype to the store union
     (`store.ts:75`–`:79`) — e.g. `{ type:'reasoning'; text:string }`.
  3. **UI:** in `ChatStream.tsx`, render reasoning as a **collapsible, dimmed "Thinking"
     section** above the answer (reuse the ambient-timeline collapse pattern at
     `ChatStream.tsx:136`–`:176`). Keep it visually distinct from narration.
- **Caveat:** reasoning availability is **model-dependent**. Providers/models that don't
  return reasoning fall back to the current derived pill — degrade gracefully, never fabricate.

### 3.4 Spec-driven mode (plan-before-code) — **Effort: M** — ✅ **P2 DONE**
- **Today:** the *material* for a Spec exists — internal `_TodoList`
  (`agent_loop.py:102`–`:152`), `plan_update`/`task_complete` tools
  (`tools.py:231`–`:307`), `PlanData`/`PlanTask` types (`store.ts:56`–`:66`) — but the plan
  is only shown as activity log lines (`ChatStream.tsx:54`–`:56`, `:90`–`:94`). There is no
  "generate a document, pause for approval, then execute" gate.
- **To do:**
  1. Add a **`spec_enabled` flag** to the `/api/chat/start` payload (UI "Spec-driven"
     toggle, mirroring Qoder's New Quest panel). In `run_agentic_turn`, when enabled, force
     a **first phase** that emits the plan as a structured `spec` object and returns a new
     **`awaiting_approval`** event instead of executing.
  2. Render the Spec as a **markdown card** (the app already renders markdown via
     `react-markdown`, `ChatStream.tsx:464`–`:484`) with **Approve / Revise** buttons.
     "Revise" = steer with natural language (see 3.6).
  3. On Approve, resume execution (`task_complete` already marks end-of-turn).
- **Reuses:** existing markdown renderer + plan types + todo tools. This is the one feature
  that needs a genuine new control state (`awaiting_approval`) in the loop.

### 3.5 Live task checklist (task handling) — **Effort: S–M**
- **Today:** todo/plan tools update internal state; the UI shows them as "Updating plan…"
  activity lines. `PlanData`/`PlanTask` are already typed for a checklist but unused as one.
- **To do:** promote plan state to a **dedicated checklist panel** (right of the stream or a
  collapsible card at the top of the chat). Map `todo_add/start/done/skip/list` events to
  `PlanTask` status transitions and render checkboxes. Pure UI + a `plan` MessageBlock/live
  slice; the event data already flows.

### 3.6 Steering prompts (guide an in-progress run) — **Effort: M** — ✅ **P1 DONE**
- **Today:** **partial.** Stop/cancel works — `AgentEngine.cancel()`
  (`agent-engine.ts:102`–`:113`) → `/api/chat/cancel/{task_id}` (`runtime_server.py:268`–`:286`);
  Stop button + Esc (`Composer.tsx:82`–`:97`, `:200`–`:208`). But the **composer textarea is
  disabled during a run** (`Composer.tsx:184`), so the only "steer" is: Stop → edit a prior
  message → resend (`ChatStream.tsx:334`–`:359`). No way to inject a new instruction into a
  running loop (Qoder's "make the button larger" mid/post-run iteration).
- **To do:**
  1. **UI:** keep the composer **enabled** while `agentRunning` (remove the `disabled` at
     `Composer.tsx:184`); on send during a run, POST a new `/api/chat/steer/{task_id}`
     with the text instead of starting a fresh turn.
  2. **Server:** `runtime_server.py` accepts the steer and appends it to a per-task
     **`pending_instructions`** deque (the task registry already exists there).
  3. **Engine:** in `run_agentic_turn`'s iteration loop (`agent_loop.py:296`), **drain the
     deque at each iteration boundary** and append the text as a user message to the running
     context, emitting a `steer_ack` event. Steering between LLM/tool boundaries is exactly
     how the loop already re-reads its message list each iteration, so it's a small hook.
- **Safety:** steer text is queued, never preempts mid-token; respects `MAX_ITERATIONS`
  (extend the budget when the user steers, as Qoder's "unlimited iterations" implies).

### 3.7 Edit-sent-message + Revert (rollback) — **Effort: L** — ✅ **P3 DONE**
- **Today:** per-**file** snapshots exist — `write_file` stores a pre-edit snapshot in
  `PENDING_EDITS` (`tools.py:373`–`:401`); accept=forget / reject=restore
  (`tools.py:53`–`:85`, `/api/files/*` `runtime_server.py:404`–`:430`). User messages are
  already inline-editable (`ChatStream.tsx:334`–`:359`, `store.ts:759`–`:772`). **There is no
  per-turn grouping and no file-state rollback on resend.**
- **To do:**
  1. Group `PENDING_EDITS` into a **per-turn snapshot set** keyed by `(sessionId, turnId)`
     so "Revert this turn" restores every file that turn touched (and deletes files it
     created) in one action. Add a **Revert** button in the chat stream (next to the existing
     per-diff accept/reject).
  2. **Edit & resend:** on resubmit of an edited earlier message, roll the workspace back to
     the snapshot **before that turn**, truncate stored messages after it, then run again
     (mirrors Qoder: "workspace files will safely roll back to the state prior to that
     conversation turn").
  3. **Diff View:** the existing `DiffWidget` (Monaco `DiffEditor`, side-by-side,
     `DiffWidget.tsx:86`–`:119`) already serves this; aggregate all of a turn's diffs into a
     "Summary Files" tab (reuse `PendingFilesBar.tsx` grouping).
- **Note:** true git-Worktree isolation (Qoder's recommended "Worktree environment") is a
  **separate, later** enhancement; the snapshot approach above gives Revert semantics
  without git and fits the current in-place `write_file` model.

### 3.8 Testing & verification gate — **Effort: M** — ✅ **P2 DONE**
- **Today:** **prompt-only.** The system prompt mandates a verification methodology ("run
  `npm build`, `pytest`, `capture_preview`", `agent_loop.py:62`–`:95`), and `exec_command`
  (`tools.py:404`–`:420`) *can* run tests — but there is **no programmatic pass/fail gate**;
  it relies entirely on the model choosing to. The only control-loop guard is the
  repeat-call detector (`agent_loop.py:368`–`:383`).
- **To do:**
  1. Add a **`verify` phase** after the model signals `task_complete`: if the project has a
     configured build/test command (detect `package.json`/`pyproject`/Makefile, or read an
     optional `.hyprcandy-agent.json`), run it via the existing `exec_command` path and
     capture the exit code.
  2. Emit a new **`verification`** event (command, exit code, stdout tail). **Gate "done" on
     exit code 0**; on failure, feed the error back into the loop for an **iterative fix**
     turn (bounded by a small `MAX_FIX_ROUNDS`) — exactly Qoder's "failures are fixed
     iteratively, and only then do I review diffs."
  3. **UI:** a **Verification card** (green pass / red fail with the log) rendered from the
     event (reuse `CommandWidget.tsx` output rendering).

### 3.9 Suggested replies / clarification chips — **Effort: S–M** — ✅ **P1 DONE**
- **Why:** Qoder Quest clarifies requirements and offers next-step prompts as **tappable
  options** rather than forcing the user to type every follow-up. This is the same
  interaction pattern used by the `AskUserQuestion`-style option chips (single-select or
  multi-select, each option carrying a short label + the prompt text it sends). It is the
  natural companion to steering (3.6) and the Spec approve/revise gate (3.4).
- **Today:** **absent.** The composer is free-text only (`Composer.tsx`), and any
  clarification the model wants comes back as plain prose the user must re-type. There is no
  channel for the agent to return structured options, and no chip UI anywhere in the app.
- **To do:**
  1. **Engine/tool:** add a `suggest_options` tool (or a `request_clarification` variant)
     the model can call to return a short list of `{ label, promptText, sendAs? }` options
     plus an optional "other / free text" fallback. Register it in `TOOLS_SCHEMA`
     (`tools.py:496`–`:505`) alongside the existing planning tools.
  2. **Protocol:** emit a new **`suggestions`** event on the poll bus carrying the option
     list and a `mode` (`clarify` = pause for a choice before continuing; `next-step` =
     advisory chips shown after the turn). Add a `suggestions` `MessageBlock` subtype to the
     store union (`store.ts:75`–`:79`) so the chips persist in the transcript.
  3. **UI:** render a horizontal **chip row** just above the composer; tapping a chip fills
     the composer with `promptText` and, per `sendAs`, either auto-sends as a **steer**
     (3.6 `/api/chat/steer`) during a run or starts the next turn. Keep a free-text box
     beside the chips so the user is never forced into the provided options.
  4. **Reuses:** the composer send path + the steer route from 3.6; no new transport needed.
- **Quest parity:** this is what makes "autonomously clarifying requirements" *interactive*
  rather than a wall of text, and doubles as the post-turn "suggested next steps" strip.

---

## 4. Protocol additions (all additive on the existing poll bus)

| New event (`agent_loop`→UI) | Purpose | Consumed in |
|---|---|---|
| `reasoning` | real chain-of-thought text | `ChatStream` collapsible |
| `spec` + `awaiting_approval` | Spec-driven pause | `ChatStream` approve/revise card |
| `plan_update` (typed) | checklist transitions | Task-list panel |
| `steer_ack` | confirm an injected instruction | composer + stream |
| `verification` | build/test result gate | Verification card |
| `turn_snapshot` | enables Revert | stream Revert button |
| `suggestions` | tappable clarify / next-step chips (with `mode`) | chip row above composer |

New inbound routes (mirror `/api/chat/{start,poll,cancel}`):
`POST /api/chat/steer/{task_id}`, `POST /api/chat/approve/{task_id}`, and
`POST /api/files/revert_turn` (grouped rollback). All live in `runtime_server.py`'s
existing task registry.

---

## 5. Recommended phasing

- **P0 — Quest shell (≈1 day):** ✅ Quest manager in the ChatPanel header dropdown (3.1,
  Option A — no left rail), inline rename + auto-title surfacing (3.2), plan promoted to a
  live checklist (3.5). Plus §8 (provider cut; local inference later removed entirely).
  *Pure UI, no backend risk. Immediately "feels like Quest".*
- **P1 — Real reasoning + steering (≈2–3 days):** ✅ **DONE.** Provider reasoning capture
  (`byok_client.py` OpenAI-compat `delta.reasoning*` / Anthropic `thinking_delta` w/ `thinking`
  enabled / Google `part.thought`; `cloud_client.py` parity) → `reasoning` events →
  collapsible dimmed "Thinking" section in `ChatStream` (`reasoning` MessageBlock) (3.3);
  composer **enabled during run** + `POST /api/chat/steer/{task_id}` → per-task
  `pending_instructions` deque drained at every loop boundary in `run_agentic_turn` (for→while
  so each steer extends the iteration budget), optimistic `steer` MessageBlock + `steer_ack`
  (3.6); `suggest_options` tool → `suggestions` event → `suggestions` MessageBlock + a
  tappable chip row above the composer wired to the steer/send path, `clarify` mode ends the
  turn to hand control back (3.9). Backend `py_compile` + frontend `tsc --noEmit` + `vite build`
  all green. Reasoning is display-only (never fed back to model context) and degrades to the
  existing derived pill when a provider returns none — no fabrication.
- **P2 — Spec-driven + verification (≈3–4 days):** ✅ **DONE.** Spec gate (3.4): a Composer
  "Spec-driven" toggle sets `specMode` (persisted) → `spec_enabled`/`project_path` on the
  `/api/chat/start` payload → in `run_agentic_turn` a first phase drafts a plan
  (`SPEC_DRAFT_INSTRUCTION`, accumulated without emitting `token` events) → `spec`
  MessageBlock (`drafting`→`ready`, filled in place) rendered as a markdown **SpecCard** with
  **Approve / Revise / Cancel** → a genuine new **`awaiting_approval`** control state that
  **blocks in the generator** (non-blocking `while decision is None` yielding a `heartbeat`
  every ~5s so the client's new **idle-based** poll timeout doesn't fire) → `POST
  /api/chat/approve/{task_id}` writes to the per-task `approval` registry, read via
  `approve_source()`. Approve seeds `working` (assistant spec + user "execute now") and breaks
  into the normal loop; Revise folds notes through the existing steer queue and re-drafts;
  Cancel ends the turn. Verification gate (3.8): only after `task_complete`, when
  `_detect_verify_command()` resolves a command (`.hyprcandy-agent.json` `verify_command`
  override, else `package.json`/`pyproject`/`Cargo`/`go`/`Makefile`), `_run_verify()` runs it
  via **`asyncio.create_subprocess_shell`** (non-blocking, so polls keep flowing) → `verification`
  event → **VerificationCard** (running / pass / fail + collapsible log). **Pass gates "done"
  on exit 0**; a failure under `MAX_FIX_ROUNDS` (3) resets `task_done`, extends the budget, and
  feeds the error back for an **iterative-fix** turn; conversational no-tool answers skip the
  gate. Backend `py_compile` + frontend `tsc --noEmit` + `vite build` all green.
- **P3 — Revert / turn snapshots (≈4–5 days):** ✅ **DONE.** Per-turn snapshot grouping +
  Revert + edit & resend rollback (3.7). A `contextvars.ContextVar CURRENT_TURN_ID` is set
  inside each chat task's `_run()` coroutine (concurrency-safe), so `write_file` tags its
  pre-edit snapshot into `TURN_EDITS[turn_id][path]` (first-touch wins, FIFO-capped at 60
  turns) alongside the legacy `PENDING_EDITS`. The client generates a `turnId` per turn
  (`agent-engine.ts nextTurnId()`), sends it as `turn_id` in the `/api/chat/start` payload,
  and stores it on the assistant `Message`. `POST /api/turns/revert {turn_id}` restores every
  touched file (deletes files the turn created) and pops matching `PENDING_EDITS`. A **Revert
  turn** button appears in the agent-turn meta row whenever the turn wrote diffs
  (`ChatStream.tsx`), and edit-&-resend calls `revertTurnsAfter()` (newest-first) before
  truncating. **Durable memory (Qoder-style):** four agent tools
  (`list_memories`/`read_memory`/`save_memory`/`delete_memory`) persist one slug-named
  `.md` per topic under `~/.config/hyprcandy/cache/agent-memories` (front-matter
  `topic`/`updated`); a compact topic index is injected into the first user content, and a
  **MemoryPanel** (Header BookOpen button → `memoryPanelOpen`) lists/opens (via the Markdown
  pane for human editing)/deletes memories through `GET /api/memories` + `POST
  /api/memories/delete`. Backend `py_compile` + frontend `tsc --noEmit` + `vite build` all
  green. Also fixed: inline `code` in the task-complete summary now wraps (`overflow-wrap:
  anywhere`) instead of overflowing the card border at narrow chat-panel widths.
- **P4 (optional):** git-worktree isolation for a true "Worktree environment".

---

## 6. Feasibility risks & open questions

1. **Reasoning is provider-dependent.** Not every BYOK model returns CoT; the UI must treat
   the current pill as the honest fallback and never synthesize "thinking" text. Anthropic
   needs `thinking_delta` + a `thinkingBudget`/`thinking` param (the Google budget is already
   set but unused).
2. **Poll → true streaming.** Runtime→UI is 150 ms polling
   (`agent-engine.ts:290`–`:449`), while Python→model is SSE. That's fine for events, but
   for a smoother Quest feel consider swapping the poll hop for an SSE/WebSocket over the
   GJS proxy (larger change; defer unless latency feels wrong).
3. **Local models are fully removed** (2026-10): no llama.cpp, no WebLLM — see §8.2
   findings (Qt WebEngine cannot expose WebGPU regardless of flags/hardware). Quest-style
   reasoning + autonomous multi-step will land best on strong cloud/BYOK models, which is
   now the only route. Do **not** re-wire a local backend unless the host or upstream Qt
   changes.
4. **Revert correctness** is the riskiest feature — it needs reliable per-turn file
   grouping and careful handling of files created/deleted/moved. Snapshots already exist;
   the work is keying them by turn and the resend-truncation path.
5. **Verification commands** must be **opt-in/auto-detected with an escape hatch** (a user
   override or "skip verification"), otherwise the gate can wedge on projects with unusual
   toolchains.
6. **Experts (multi-agent) mode** and **Worktree isolation** are additive and should stay
   out of P0–P3 scope.

---

## 7. Key file:line index (entry points to touch)

- UI root/layout: `agent-app/src/App.tsx` (left rail tried then removed — quest chrome
  lives in ChatPanel; Ctrl/Cmd+N handler here)
- Quest list (unmounted, kept for reuse): `agent-app/src/components/SessionsSidebar.tsx`
- Quest manager dropdown (live): `ChatPanel.tsx` header (`dropdown-*` / `session-*` classes)
- Message/session/plan types: `agent-app/src/store.ts` — `Message :81`–`:93`,
  `MessageBlock :75`–`:79`, `Session :101`–`:108`, `PlanData/PlanTask :56`–`:66`
- Turn orchestrator + poll loop: `engine/agent-engine.ts:115`, `:290`–`:449`;
  auto-title `:43`–`:56`
- Renderer (add reasoning/spec/verification/checklist blocks): `components/ChatStream.tsx:44`–`:71`,
  `:136`–`:176`, `:464`–`:537`
- Composer (enable during run for steering): `components/Composer.tsx:184`, `:82`–`:97`
- Diff + pending files (→ Summary Files / Revert): `components/DiffWidget.tsx:86`–`:119`,
  `components/PendingFilesBar.tsx`
- Server routes + task registry: `Agents/local_runtime/runtime_server.py:175`–`:286`, `:404`–`:430`
- Engine loop + todo + verification prompt: `agent_loop.py:270` (`:296`, `:99`), `:102`–`:152`,
  `:62`–`:95`, `:164`–`:236`
- Tools + dispatch + edit snapshots: `tools.py:231`–`:307`, `:373`–`:420`, `:496`–`:554`,
  `:53`–`:85`
- Provider streaming (add reasoning deltas): `byok_client.py:581`, `:696`–`:701`, `:434`–`:490`,
  `:718`–`:776`
- Bridge/protocol: `bridge.ts:32`–`:108`, `:110`–`:148`, `runtimeRequest :336`
- Provider catalog + default selection: `ModelManager.tsx:108`–`:232` (`BYOK_PROVIDERS`),
  `HIDE_PROVIDERS :21`, `getVisibleProviders :234`, default-pick `:353`–`:362`
- ~~WebLLM service (live, engine-backed): `engine/webllm.service.ts` (`probeHardware`,
  `listEngineModels`, `ensureEngine`, `generate`), `engine/webllm-helpers.ts`
  (`WEBLLM_MODELS`, `probeWebGPU`); UI: `ModelManager.tsx` `LocalWebLLMTab`~~ —
  **ALL DELETED 2026-10** (local inference removed; see §8.2)
- ~~Native local backend: `engine/llama-cpp.service.ts`~~ — **DELETED 2026-10** (dead code;
  llama.cpp is not part of this product)

---

## 8. Provider streamlining + local-inference retirement

This is an **independent track** from the Quest-flow reshaping above (P0–P4). Two changes:
cut the cloud provider list down to the two aggregators (OpenRouter + Groq), and — after
the WebGPU findings below — **remove local inference entirely**. The product is now cloud
BYOK + managed gateway only, and remaining effort goes to the chat interface / flow /
widget work (P1+).

### 8.1 Streamline cloud providers → OpenRouter (new default) + Groq only — **Effort: S** ✅ **DONE**
- **Today:** `BYOK_PROVIDERS` (`ModelManager.tsx:108`–`:232`) ships **seven** providers —
  `aimlapi`, `openrouter`, `groq`, `google`, `anthropic`, `openai`, `xai` — each rendered as
  a pill in the "Select Cloud Provider" tab bar via `visibleProviders.map`
  (`:855`–`:911`). The default selection logic (`:353`–`:362`) hard-picks **`aimlapi`**.
- **Target:** keep **only OpenRouter and Groq**; drop AI/ML API, Google Gemini, Anthropic,
  OpenAI, and xAI (Grok) — **and their buttons**. **OpenRouter becomes the new default**
  (its `defaultModel: 'openrouter/free'` already exists at `:139`).
- **To do (two viable paths):**
  1. **Fast toggle (recommended first):** add the five ids to `HIDE_PROVIDERS`
     (`ModelManager.tsx:21`) — `['aimlapi','google','anthropic','openai','xai']`. The
     existing `getVisibleProviders()` filter (`:234`) removes their pills with zero layout
     change; reversible in one line.
  2. **Clean bundle (later):** delete the five provider objects from `BYOK_PROVIDERS` and
     their icon components (`AIMLAPIIcon`, `GoogleGeminiIcon`, `AnthropicIcon`, `OpenAIIcon`,
     `XAIIcon` `:38`–`:104`) to shed dead SVG/code from the build.
- **Default flip:** in both paths, change the `:353`–`:362` selector to resolve to
  **`openrouter`** (replace the `aiml` lookup and the `|| 'aimlapi'` fallbacks with
  `openrouter`), and update the surrounding comment that still names AI/ML API as the
  no-key default.
- **Backend parity (optional):** `runtime_server.py`'s BYOK registry and `byok_client.py`
  still accept the removed providers — harmless, but can be pruned to `openrouter`/`groq`
  to keep the surface honest. No route changes required for the UI cut.

### 8.2 Local models (WebLLM) — **REMOVED ENTIRELY (2026-10)** ❌
- **Decision:** the WebLLM integration and the "Local" tab are deleted; the product keeps
  only the two cloud aggregators (OpenRouter default + Groq) and the managed gateway.
  All future effort goes to chat interface / flow / widget work (P1+), not local inference.
- **Why (verified FINDINGS on this host: Qt WebEngine 6.11.2 / Chromium, Ivy Bridge +
  OLAND hybrid; standalone PyQt probe + `--enable-logging` gpu_init traces):**
  - The renderer had `--enable-unsafe-webgpu` and `navigator.gpu` exists, but every
    `requestAdapter()` candidate resolves to `null` — Chromium logs
    `Failed to create WebGPU Context Provider`.
  - **Root cause is architectural:** Qt WebEngine hardcodes Chromium's `--in-process-gpu`
    (string lives in `libQt6WebEngineCore.so`), while Dawn-backed WebGPU needs a real
    out-of-process GPU service. Enabling Chromium's Vulkan backend
    (`--enable-features=Vulkan --use-vulkan=native`) makes Vulkan itself work but the
    WebGPU service still fails to bind — same conclusion independently reached by the
    SlicerLive project on Qt 6.10. Upstream Qt does not integrate WebGPU (absent from
    every WebEngine features list / changelog through 6.12).
  - **Consequence:** inside the launcher's QtWebEngine window WebGPU is unavailable on
    every user's machine, regardless of hardware or flags — the earlier
    "Qt gates WebGPU behind --enable-unsafe-webgpu" framing was wrong. The identical UI
    in a true Chromium runtime (`npm run dev` in a browser) DOES get an adapter, which is
    why the tab "worked" in dev but can never work in the shipped host.
- **Removal inventory (this pass):**
  - Frontend: `engine/webllm.service.ts` + `engine/webllm-helpers.ts` deleted;
    `@mlc-ai/web-llm` uninstalled; the Local tab + Cloud/Local segmented switch are gone
    from `ModelManager.tsx` (the modal always renders `CloudTab`); `inferenceMode` narrowed
    to `'byok' | 'cloud'` (persisted `'local'` states migrate to `'byok'`); dead
    `modelManagerTab` store field, `CustomWebLLMModel`, `getCustomWebLLMModels()` and the
    Header `'local'` label branch removed; `--enable-unsafe-webgpu` dropped from
    `bar/shell.qml` (with a comment documenting why it must not come back).
  - Runtime: `local_backend()` deleted from `agent_loop.py`; `llama_manager.py` +
    `llama_cpp_bridge.py` deleted; docstrings in `tools.py`/`cloud_client.py`/`byok_client.py`
    no longer cite a local backend. `/api/models/*` + `/api/server/*` stay as inert
    `disabled` no-op stubs for old clients.
  - Earlier passes: `engine/llama-cpp.service.ts`, `llama:*` npm scripts +
    `scripts/llama-*.cjs` deleted; `build-llama-server.sh` deleted. `hc-agent-build.sh`
    KEPT — it is the generic post-update build wrapper called by `UpdatesPopup.qml`
    (builds the frontend + venv; contains nothing llama-specific).
- **Re-verify tool kept:** `agent-app/scripts/webgpu_probe.py` — run
  `python3 scripts/webgpu_probe.py [flags]` to re-check adapter availability against any
  future Qt build. Should upstream Qt ever ship real WebGPU, the archived implementation
  (git history of this file + the deleted services) describes the full recipe: lazy
  `import('@mlc-ai/web-llm')` behind a service interface, honest `requestAdapter()`
  pre-flight, weight-blob Cache-API checks, auto-listing from `prebuiltAppConfig`.

---

**Bottom line:** treat this as *reshaping + four additive backend hooks*, not a rewrite.
Start with P0 (the Quest dropdown + checklist) for an immediate Quest-like feel, then layer
reasoning/steering (P1), spec/verification (P2), and Revert (P3). The **§8 provider cut
(OpenRouter + Groq)** is done; **local inference (llama.cpp and WebLLM alike) is fully
removed** — the QtWebEngine host architecturally cannot surface a WebGPU adapter, so the
product is cloud-only by design (§8.2).
