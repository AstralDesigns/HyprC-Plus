# HyprCandyDock Electron-to-Python Runtime Migration

## Implemented

The active inference path now uses the visible WebKitGTK application and the existing Python local runtime. Local, BYOK, and cloud chat requests use `/api/chat/start` plus `/api/chat/poll/{task_id}`; the frontend no longer requires an Electron renderer for normal inference.

The Python runtime now provides Hugging Face model discovery through `/api/models/search` and `/api/models/inspect`. Model Manager search uses those runtime endpoints rather than making direct browser requests.

Chat cancellation is now server-side. The runtime exposes `/api/chat/cancel/{task_id}`, cancels the detached asyncio task, and releases the in-flight llama-server request. The frontend calls this endpoint when a conversation is stopped or superseded.

The legacy Llama service adapter now talks to the Python runtime endpoints for model listing, search, inspection, status, pull, start, and stop. The launcher’s active Llama toggle no longer launches or dispatches to Electron.

Electron package scripts/dependencies and the Electron entrypoint files were removed:

- `agent-app/electron/`
- `start-electron-agent.sh`
- `launch-agent-keybind.sh`

## Validation

- `python3 -m py_compile Agents/local_runtime/runtime_server.py Agents/local_runtime/llama_manager.py`
- Runtime route registration check passed for model search, model inspect, chat start, chat poll, and chat cancel.
- `node --check app-launcher.js`
- `npm run build` passed successfully.

The build reports only the existing large-chunk warning for the Monaco-heavy bundle. The extracted archive’s legacy `run_tests.js` expects an installed `/home/king/.hyprcandy` deployment and could not run directly against this sandbox checkout; this is an environment/path assumption in that test harness, not a build failure.

## Compatibility note

A small set of defensive launcher branches still recognizes old `worker_*`/Electron-originated messages so stale clients fail safely or receive a response. Those branches do not start Electron, do not require Electron files, and are not used by the migrated runtime path.

## Follow-up fix: models and provider connection errors

The screenshots showed `Could not connect to 127.0.0.1: Connection refused` for every provider. Electron removal had accidentally removed the only call that started the Python runtime. The launcher now starts `Agents/local_runtime/start.sh` when the WebKit agent tab is initialized, and the bridge retries transient startup connection failures.

The model catalog continues to use the confirmed path `~/.local/share/hyprcandy/llama-models`. For compatibility with older installations, the runtime also scans the similarly named `~/.local/share/hyprcand/llama-models` and both corresponding `models` directories.

## Follow-up fix: discrete-GPU detection and llama offload

The CLI log showed Vulkan probing `/dev/dri/renderD129` failing and the launcher selecting its legacy-Ivy-Bridge safety branch. The launcher now avoids Gio read probes that can return `EINVAL` for usable DRM character devices, ranks accessible non-Intel adapters ahead of `boot_vga`, logs the complete render-node topology, and exports the selected `DRI_PRIME`/PCI metadata to child processes.

The Python llama runtime now starts `llama-server` with `--n-gpu-layers -1` by default, preserving full backend offload. It also logs the selected GPU metadata and inherited `DRI_PRIME` value. Override the layer count with `HYPRCANDY_LLAMA_GPU_LAYERS` if a particular backend cannot offload all layers.
