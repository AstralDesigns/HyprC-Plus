Good news: I dug into `Agents/local_runtime/` (which I only skimmed before), and Manus's plan is directionally right but underestimates how far along this already is — and misses one real gap. Here's the full picture.

## Manus is right, and it's further along than it thinks

`Agents/local_runtime/llama_manager.py` + `runtime_server.py` **already are** the native host Manus says needs to be built:

- `llama_manager.py` already does binary discovery, `list_models()`, `download_model()`, `import_model()`, `start_server()` / `stop_server()` / `server_status()` / `health_check()` / `delete_model()` / `clear_all_models()` — spawning the exact same `llama-server` binary on port **17843**, with proper `SIGTERM`→5s→`SIGKILL` shutdown.
- `runtime_server.py` already exposes all of it over HTTP: `/api/models`, `/api/models/pull/start`+`/pull/status`, `/api/models/import`, `/api/models/delete`, `/api/models/clear`, `/api/server/start`, `/api/server/stop`, `/api/server/status`.
- `agent_loop.py` + `tools.py` already run the **entire tool-calling agent loop server-side** (`list_directory`, `read_file`, `write_file`, `exec_command`, `web_search`, `fetch_url`, `capture_preview`, todo tools) against the local filesystem — this is a more complete implementation than the client-side `AGENT_TOOLS` loop in `agent-engine.ts`'s Electron branch.
- This is wired into `/api/chat/start` + `/api/chat/poll/{task_id}`, which routes to `local` (llama-server), `byok`, or `cloud` from one unified endpoint.

So Manus's step 1–3 ("move LlamaServerManager into GJS/Python, route llamaRequest() there") is basically **done on the backend**. What's actually left is almost entirely a **frontend consolidation**: stop calling the Electron IPC path (`window.__llamaServer`, `llamaRequest`, `llamaCppService`, `runLlamaConversation`) and route everything through `bridge.runtimeRequest(...)` to the Python server instead — which the `!isElectronMode() && (runtimeMode === 'local' || ...)` branch in `agent-engine.ts` (lines ~587-767) already does for chat. That branch is your real target architecture; it just needs to become the *only* path instead of one of three.

## This migration fixes the other two bugs for free

Once you delete the Electron branch and `llamaCppService`/`webllm.service.ts`:

- The leftover **WebLLM/Wllama-in-Chromium fallback** (my earlier finding #2) disappears entirely — there's no Chromium renderer left for it to run in.
- The **unbounded stream hang** (my earlier finding #1 — `llamaCppService.chat()`'s `reader.read()` with no timeout) disappears too, because the surviving path is the Python polling loop, which already has the `POLL_TIMEOUT_MS = 5 * 60 * 1000` watchdog and reports "Agent timed out" instead of hanging.

So this isn't just an architecture cleanup — it's the actual fix for the instability you've been chasing.

## One real gap Manus's plan doesn't mention: no cancellation server-side

I checked `runtime_server.py` and `agent_loop.py` for a cancel/abort endpoint — there isn't one. `/api/chat/start` spawns a detached `asyncio.create_task(_run())`; the client's `abortController.abort()` today only stops the *client* from polling (`isCurrentConversation()` goes false and it resolves locally) — the Python task keeps running to completion regardless, still occupying `llama-server`, which only serves `--parallel 1` request at a time.

Right now this is hidden because the Electron/native path handles real cancellation via a genuine `fetch` `AbortSignal`. Once that path is gone and this Python polling path is the *only* way to talk to local models, hitting Stop or sending a follow-up message while a turn is in flight will silently queue behind the abandoned generation instead of cancelling it — which will look exactly like a hang. **This needs a `/api/chat/cancel/{task_id}` (or similar) that actually stops `run_agentic_turn` and, ideally, hits llama-server's own cancellation if it exposes one**, before you commit to this as the sole backend.

## Other gaps to close before deleting Electron

1. **Model search/inspect for the Model Manager UI**: `llama-server-manager.cjs`'s `searchModels()`/`inspectModel()` are just plain HTTPS calls to the public HF API (`huggingface.co/api/models?search=...`, `.../api/models/{repo}?full=true`) — no Electron capability needed. These don't exist in `llama_manager.py` yet; porting them is ~20 lines plus two `runtime_server.py` endpoints.
2. **Download progress plumbing**: today, pull progress flows Electron → GJS stdout → WebKit inject as `llama_progress`/`agent_llama_progress`. The Python side already has `/api/models/pull/start` + `/pull/status/{task_id}` polling — you'll want the Model Manager UI to poll that the same way chat does, rather than expecting a pushed event.
3. **Context-building parity**: the Python "local" chat branch in `agent-engine.ts` (~line 611) builds a much thinner `project_context` string than `runLlamaConversation()` does (no `contextMode` levels, no project-tree truncation tiers, no context-image awareness). If you delete the richer client-side path, port its context assembly into the branch you're keeping, or you'll quietly regress answer quality for local models.
4. **Llama activation ios toggle and legacy header ON/OFF logic**: currently gates Electron dispatch via `_agentLlamaEnabled`/`_sendOrQueueElectronDispatch` in `app-launcher.js`. That whole gate goes away — the toggle should just call `/api/server/start` / `/api/server/stop` on the Python runtime directly (both already exist).

## Confirmed removal list (matches Manus's step 6, verified against actual code)

- `agent-app/electron/` (all of it, including `llama-server-manager.cjs`, `main.cjs`, `preload.cjs`)
- `start-electron-agent.sh`, `launch-agent-keybind.sh` (the untracked standalone entry point I found last time — also needs to go or be repointed)
- Electron deps/scripts in `agent-app/package.json`
- `_startAgentElectronProc`, `_ensureElectronWorker`, `_sendOrQueueElectronDispatch`, `_agentOnElectronLine`, `_agentOnElectronDead`, and the `llama_request`/`worker_*` relay branches in `app-launcher.js`
- `webllm.service.ts`, `browserllm.service.ts`, `webllm-helpers.ts`, the `wllama` dependency, and every `isElectronMode()` branch + the Electron-mode WebLLM path in `agent-engine.ts` and `main.tsx`
- `llama-cpp.service.ts` and `runLlamaConversation()` — replaced by the existing Python polling branch

Want me to actually start on this — add the cancel endpoint and search/inspect to the Python runtime first (since those are the missing pieces), then strip the Electron paths and repoint the Model Manager UI, and hand you back the updated tree?
