#!/usr/bin/env bash
# HyprCandy Launcher — Electron Agent Renderer Entrypoint
# Wraps finding the electron binary + running the main.js file.
# Usage: ./start-electron-agent.sh [<http-url-to-load>]
# URL defaults to the GJS loopback server running on http://127.0.0.1:17842/index.html
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$HERE/agent-app"
ELECTRON_MAIN="$APP_DIR/electron/main.cjs"
ELECTRON_BIN="$APP_DIR/node_modules/electron/dist/electron"
NODE_BIN="$(command -v node || command -v nodejs || true)"

export HYPRCANDY_AGENT_URL="${1:-http://127.0.0.1:17842/index.html}"
# Signal to the Electron process that it is an embedded inference co-process.
# It will run the full React/WebLLM engine inside a hidden Chromium renderer;
# the GJS launcher hosts the visible UI in its own WebKitGTK widget.
export HYPRCANDY_ELECTRON_EMBEDDED=1
# Native provider. Set HYPRCANDY_INFERENCE_PROVIDER=wllama only for legacy
# rollback; llama-server is the default sidecar built by agent-app/build.sh.
export HYPRCANDY_INFERENCE_PROVIDER="${HYPRCANDY_INFERENCE_PROVIDER:-llama.cpp}"
export HYPRCANDY_LLAMA_MODEL="${HYPRCANDY_LLAMA_MODEL:-Qwen2.5-Coder-1.5B-Instruct}"

# llama-server uses native CPU/GPU backends; SwiftShader remains available for
# the legacy WebGPU fallback as an explicit emergency override.
GPU_BACKEND="${HYPRCANDY_AGENT_GPU_BACKEND:-hardware}"
if [[ "$GPU_BACKEND" == "swiftshader" ]]; then
  SWIFTSHADER_ICD="/usr/lib/chromium/vk_swiftshader_icd.json"
  if [[ -f "$SWIFTSHADER_ICD" ]]; then
    export VK_ICD_FILENAMES="$SWIFTSHADER_ICD"
    export HYPRCANDY_AGENT_GPU_BACKEND=swiftshader
    echo "[hyprcandy-electron-agent] using bundled SwiftShader Vulkan backend" >&2
  else
    echo "[hyprcandy-electron-agent] WARNING: SwiftShader ICD not found; using native GPU" >&2
    export HYPRCANDY_AGENT_GPU_BACKEND=hardware
  fi
else
  unset VK_ICD_FILENAMES
  export HYPRCANDY_AGENT_GPU_BACKEND=hardware
fi

# The parent GJS launcher needs libgtk4-layer-shell.so for its own Wayland
# surface, but Electron/Chromium must not inherit that preload. It causes the
# system libgtk-4.so to resolve Vulkan symbols unavailable to Electron
# (`vkCreateXlibSurfaceKHR`), making the worker exit before model requests.
unset LD_PRELOAD
# Keep the Electron agent quiet and on the same warning/error-only policy as
# the GJS/WebKit launcher; background renderer chatter is not useful here.
export ELECTRON_ENABLE_LOGGING=0
export ELECTRON_DISABLE_SECURITY_WARNINGS=true

echo "[hyprcandy-electron-agent] starting without LD_PRELOAD; url=$HYPRCANDY_AGENT_URL" >&2

# npm can leave Electron's package metadata installed while its platform
# binary is absent (for example after npm ci --ignore-scripts).  Repair that
# state before the GJS launcher decides that Chromium is unavailable.
if [[ -n "$NODE_BIN" && -f "$APP_DIR/node_modules/electron/install.js" && ! -x "$ELECTRON_BIN" ]]; then
  "$NODE_BIN" "$APP_DIR/node_modules/electron/install.js" >/dev/null 2>&1 || true
fi

# Try 1: direct electron binary
if [[ -x "$ELECTRON_BIN" ]]; then
  exec "$ELECTRON_BIN" --no-sandbox --disable-setuid-sandbox "$ELECTRON_MAIN"
fi

# Try 2: npx node via electron/cli
if [[ -n "$NODE_BIN" && -f "$APP_DIR/node_modules/electron/cli.js" ]]; then
  exec "$NODE_BIN" "$APP_DIR/node_modules/electron/cli.js" "$ELECTRON_MAIN"
fi

# Try 3: system electron
if command -v electron >/dev/null 2>&1; then
  exec electron --no-sandbox --disable-setuid-sandbox "$ELECTRON_MAIN"
fi

echo "[hyprcandy-electron-agent] ERROR: No electron runtime found. Installed? Tried:" >&2
echo "  - $ELECTRON_BIN (exists? $(test -f "$ELECTRON_BIN" && echo yes || echo no))" >&2
echo "  - node: $NODE_BIN, cli.js: $(test -f "$APP_DIR/node_modules/electron/cli.js" && echo yes || echo no)" >&2
echo "  - PATH electron: $(command -v electron || echo missing)" >&2
exit 127
