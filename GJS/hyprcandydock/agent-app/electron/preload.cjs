// HyprCandy Launcher Electron Preload
// Exposes the EXACT same window.webkit.messageHandlers.agent.postMessage()
// API that WebKitGTK provided, so the React bridge.ts / agent React app code
// changes 0 lines (no porting needed).  Also installs window.__hyprcandy_agent_dispatch
// on the main world (unsafe script injection into isolated world does not
// propagate to window unless via exposeInMainWorld with contextBridge + direct
// DOM manipulation via webFrame / executeJavaScript on main side).

const { contextBridge, ipcRenderer } = require('electron');

// ── 1. WebKitGTK-compatible messageHandlers shim ──────────────────────────
//    WebKit: window.webkit.messageHandlers.<name>.postMessage(obj_or_str)
//    We replicate: window.webkit.messageHandlers.agent.postMessage(envelopeJSONstr)
contextBridge.exposeInMainWorld('webkit', {
  messageHandlers: {
    agent: {
      postMessage(data) {
        let envelope;
        if (typeof data === 'string') {
          envelope = data;
        } else {
          try { envelope = JSON.stringify(data); }
          catch (e) { envelope = String(data); }
        }
        ipcRenderer.send('agent:post', envelope);
      },
    },
  },
});

// ── 2. Error reporter helper (called by main executeJavaScript on errors) ──
contextBridge.exposeInMainWorld('__electronReportError', function (info) {
  try { ipcRenderer.send('agent:error', info || {}); } catch (_) {}
});

// ── 3. Convenience: report that we're in Chromium/Electron mode ────────────
contextBridge.exposeInMainWorld('__hyprcandyElectronAgent', true);

// ── 4. Physical-disk model weight cache ─────────────────────────────────────
//    Chromium's Cache Storage API (used by Transformers.js when
//    env.useBrowserCache=true) is "best-effort" storage: without an explicit
//    navigator.storage.persist() grant, the browser is free to silently evict
//    large entries (multi-GB model weights) under disk pressure, which is why
//    "cached" models could appear to re-download from Hugging Face on a later
//    launch. Since Electron gives us real Node fs access in the main process,
//    we back the cache with real files on disk instead, at
//    ~/.local/share/hyprcandy/weights (see electron/main.cjs). This survives
//    browser storage-quota eviction entirely, same as any other app data.
contextBridge.exposeInMainWorld('__hyprcandyWeights', {
  match: (url) => ipcRenderer.invoke('weights:match', url),
  put: (modelId, url, buffer, headers) => ipcRenderer.invoke('weights:put', modelId, url, buffer, headers),
  hasModel: (modelId) => ipcRenderer.invoke('weights:hasModel', modelId),
  removeModel: (modelId) => ipcRenderer.invoke('weights:removeModel', modelId),
  clearAll: () => ipcRenderer.invoke('weights:clearAll'),
  diskUsage: () => ipcRenderer.invoke('weights:diskUsage'),
});

// ── 5. Worker inference output channel ──────────────────────────────────────
//    Allows executeJavaScript-injected inference scripts to stream tokens /
//    progress back to main.cjs, which writes them to stdout as JSONL for GJS.
//    Usage in renderer: window.__electronSendToMain(JSON.stringify({type,payload}))
contextBridge.exposeInMainWorld('__electronSendToMain', function (jsonStr) {
  try { ipcRenderer.send('agent:worker_out', String(jsonStr || '')); } catch (_) {}
});

// ── 6. Native llama.cpp server provider ─────────────────────────────────────
contextBridge.exposeInMainWorld('__llamaServer', {
  enabled: process.env.HYPRCANDY_INFERENCE_PROVIDER === 'llama.cpp',
  catalog: () => ipcRenderer.invoke('llama:catalog'),
  search: (query) => ipcRenderer.invoke('llama:search', query),
  inspect: (repo) => ipcRenderer.invoke('llama:inspect', repo),
  hasModel: (model) => ipcRenderer.invoke('llama:hasModel', model),
  status: () => ipcRenderer.invoke('llama:status'),
  health: () => ipcRenderer.invoke('llama:health'),
  pull: (modelId) => ipcRenderer.invoke('llama:pull', modelId),
  start: (modelId, options) => ipcRenderer.invoke('llama:start', modelId, options || {}),
  stop: () => ipcRenderer.invoke('llama:stop'),
});

// NOTE: __hyprcandy_agent_dispatch(msg) dispatch calls are injected by the
// main process via webContents.executeJavaScript() into the main world, so
// they reach the React bridge.ts constructor's installed hook directly.
// No preload action needed for the incoming direction.
