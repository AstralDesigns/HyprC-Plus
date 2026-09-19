// HyprCandy Launcher — Electron Embedded Agent Renderer
// Chromium/Electron host for the native llama bridge and legacy fallback tools.
// Loads the same dist/index.html that GJS serves via Soup3 loopback server
// on http://127.0.0.1:17842/index.html — identical JS code, but now with real
// Native llama.cpp owns inference; this process is not an inference GPU host.
//
// IPC with GJS launcher host uses NEWLINE-DELIMITED JSON on stdin/stdout so
// the existing GJS Gio.Subprocess stdin/stdout pipes work without any HTTP.
//
// Protocol:
//   GJS -> Electron (stdin line, JSON): { type: 'bounds', x, y, w, h }
//                                         { type: 'dispatch', payload: { type, id, payload, error } }
//   Electron -> GJS (stdout line, JSON): { type: 'postMessage', data: '<JSON envelope>' }
//                                         { type: 'ready' }
//                                         { type: 'console', level, msg }
//                                         { type: 'error', message, stack }

const { app, BrowserWindow, ipcMain, screen } = require('electron');
const path = require('path');
const { fileURLToPath } = require('url');
const fs = require('fs');
const crypto = require('crypto');
const readline = require('readline');
const { LlamaServerManager, MODEL_CATALOG } = require('./llama-server-manager.cjs');

const llamaServer = new LlamaServerManager();
ipcMain.handle('llama:catalog', () => llamaServer.catalog());
ipcMain.handle('llama:search', (_event, query) => llamaServer.searchModels(query));
ipcMain.handle('llama:inspect', (_event, repo) => llamaServer.inspectModel(repo));
ipcMain.handle('llama:hasModel', (_event, model) => llamaServer.hasModel(model));
ipcMain.handle('llama:status', () => llamaServer.status());
ipcMain.handle('llama:health', () => llamaServer.health());
ipcMain.handle('llama:pull', async (_event, modelId) => llamaServer.pull(modelId, (progress) => {
  try { process.stdout.write(JSON.stringify({ type: 'llama_progress', payload: { modelId, ...progress } }) + '\n'); } catch (_) {}
}));
ipcMain.handle('llama:start', async (_event, modelId, options) => llamaServer.start(modelId, options || {}, (progress) => {
  try { process.stdout.write(JSON.stringify({ type: 'llama_progress', payload: { modelId, ...progress } }) + '\n'); } catch (_) {}
}));
ipcMain.handle('llama:stop', () => llamaServer.stop());
process.once('exit', () => { try { void llamaServer.stop(); } catch (_) {} });

// ─── Chromium GPU flags — keep the legacy hidden bridge off the
// WebGPU/WebGL path entirely because GGUF inference is handled by llama-server.
const softwareRender = process.env.HYPRCANDY_SOFTWARE_RENDER === '1';
if (softwareRender) {
  app.commandLine.appendSwitch('disable-gpu');
  app.commandLine.appendSwitch('disable-gpu-compositing');
} else {
  // Leave Chromium in a renderer-light, non-GPU mode for the embedded
  // llama.cpp/llama-server native inference stack.
  app.commandLine.appendSwitch('disable-gpu');
  app.commandLine.appendSwitch('disable-gpu-compositing');
  app.commandLine.appendSwitch('disable-accelerated-2d-canvas');
  app.commandLine.appendSwitch('disable-gpu-sandbox');
}
app.commandLine.appendSwitch('no-sandbox');
app.commandLine.appendSwitch('disable-setuid-sandbox');
app.commandLine.appendSwitch('autoplay-policy', 'no-user-gesture-required');

// A legacy Vulkan driver can kill Chromium's GPU process without terminating
// the Electron main process. Without an explicit notification, the WebKit UI
// remains stuck in "thinking" forever because no worker_done/worker_error line
// is emitted. Tell GJS first, then exit so it can restart the worker on retry.
app.on('child-process-gone', (_event, details) => {
  if (details?.type !== 'GPU' && details?.name !== 'GPU Process') return;
  const reason = details.exitCode === 139
    ? 'Chromium GPU process crashed (exit 139 / WebGPU device lost). Retry the request; the worker will restart.'
    : `Chromium GPU process exited (reason=${details.reason || 'unknown'}, code=${details.exitCode ?? 'unknown'}).`;
  try {
    process.stdout.write(JSON.stringify({ type: 'worker_error', payload: { message: reason, fatal: true } }) + '\n');
  } catch (_) {}
  setTimeout(() => {
    try { app.quit(); } catch (_) {}
  }, 50);
});

const AGENT_URL = process.env.HYPRCANDY_AGENT_URL || 'http://127.0.0.1:17842/index.html';
// When HYPRCANDY_ELECTRON_EMBEDDED=1, Electron runs as a headless WebLLM inference
// co-process inside the GJS launcher. The BrowserWindow is never shown; the React
// app runs in the hidden Chromium renderer (full WebGPU/WebLLM access), streaming
// tokens back to GJS via stdout JSONL. GJS injects them into the WebKitGTK view.
const EMBEDDED_MODE = process.env.HYPRCANDY_ELECTRON_EMBEDDED === '1';
const USER_DATA_DIR = process.env.HYPRCANDY_ELECTRON_USERDATA
  || path.join(require('os').homedir(), '.local', 'share', 'hyprcandy', 'electron-agent');
try { fs.mkdirSync(USER_DATA_DIR, { recursive: true }); } catch (_) {}
app.setPath('userData', USER_DATA_DIR);
app.commandLine.appendSwitch('user-data-dir', USER_DATA_DIR);

// ─── Physical-disk model weight cache ───────────────────────────────────────
// Real files on disk, independent of Chromium's evictable Cache Storage quota.
// See preload.cjs for why this exists.
const WEIGHTS_DIR = process.env.HYPRCANDY_WEIGHTS_DIR
  || path.join(require('os').homedir(), '.local', 'share', 'hyprcandy', 'weights');
try { fs.mkdirSync(WEIGHTS_DIR, { recursive: true }); } catch (_) {}
const WEIGHTS_INDEX_PATH = path.join(WEIGHTS_DIR, 'index.json');

function weightFileBase(url) {
  const hash = crypto.createHash('sha256').update(String(url)).digest('hex');
  return path.join(WEIGHTS_DIR, hash);
}
function readWeightsIndex() {
  try {
    const parsed = JSON.parse(fs.readFileSync(WEIGHTS_INDEX_PATH, 'utf8'));
    if (parsed && typeof parsed === 'object') return parsed;
  } catch (_) {}
  const rebuilt = {};
  try {
    for (const file of fs.readdirSync(WEIGHTS_DIR)) {
      if (!file.endsWith('.json') || file === 'index.json') continue;
      const meta = JSON.parse(fs.readFileSync(path.join(WEIGHTS_DIR, file), 'utf8'));
      const base = path.join(WEIGHTS_DIR, file.slice(0, -5));
      if (meta.modelId && meta.url && fs.existsSync(base + '.bin')) {
        rebuilt[meta.modelId] = Array.from(new Set([...(rebuilt[meta.modelId] || []), meta.url]));
      }
    }
    writeWeightsIndex(rebuilt);
  } catch (_) {}
  return rebuilt;
}
function writeWeightsIndex(idx) {
  try { fs.writeFileSync(WEIGHTS_INDEX_PATH, JSON.stringify(idx)); } catch (_) { /* best effort */ }
}

ipcMain.handle('weights:match', async (_evt, url) => {
  try {
    const base = weightFileBase(url);
    const meta = JSON.parse(fs.readFileSync(base + '.json', 'utf8'));
    const data = fs.readFileSync(base + '.bin');
    return {
      found: true,
      headers: meta.headers || {},
      // Structured-clone the underlying ArrayBuffer slice across the IPC boundary.
      buffer: data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength),
    };
  } catch (_) {
    return { found: false };
  }
});

ipcMain.handle('weights:put', async (_evt, modelId, url, buffer, headers) => {
  try {
    const base = weightFileBase(url);
    fs.writeFileSync(base + '.bin', Buffer.from(buffer));
    fs.writeFileSync(base + '.json', JSON.stringify({ url, modelId, headers: headers || {}, savedAt: Date.now() }));
    if (modelId) {
      const idx = readWeightsIndex();
      idx[modelId] = Array.from(new Set([...(idx[modelId] || []), url]));
      writeWeightsIndex(idx);
    }
    return { ok: true };
  } catch (e) {
    return { ok: false, error: e.message };
  }
});

ipcMain.handle('weights:hasModel', async (_evt, modelId) => {
  try {
    const idx = readWeightsIndex();
    const urls = idx[modelId] || [];
    if (urls.length === 0) return { cached: false };
    const allPresent = urls.every((url) => fs.existsSync(weightFileBase(url) + '.bin'));
    return { cached: allPresent };
  } catch (_) {
    return { cached: false };
  }
});

ipcMain.handle('weights:removeModel', async (_evt, modelId) => {
  try {
    const idx = readWeightsIndex();
    const urls = idx[modelId] || [];
    for (const url of urls) {
      const base = weightFileBase(url);
      fs.rmSync(base + '.bin', { force: true });
      fs.rmSync(base + '.json', { force: true });
    }
    delete idx[modelId];
    writeWeightsIndex(idx);
    return { ok: true, removed: urls.length };
  } catch (e) {
    return { ok: false, error: e.message };
  }
});

ipcMain.handle('weights:clearAll', async () => {
  try {
    fs.rmSync(WEIGHTS_DIR, { recursive: true, force: true });
    fs.mkdirSync(WEIGHTS_DIR, { recursive: true });
    return { ok: true };
  } catch (e) {
    return { ok: false, error: e.message };
  }
});

ipcMain.handle('weights:diskUsage', async () => {
  try {
    let bytes = 0;
    for (const f of fs.readdirSync(WEIGHTS_DIR)) {
      if (f.endsWith('.bin')) bytes += fs.statSync(path.join(WEIGHTS_DIR, f)).size;
    }
    return { bytes, dir: WEIGHTS_DIR };
  } catch (_) {
    return { bytes: 0, dir: WEIGHTS_DIR };
  }
});

// Prevent multi-instance Electron lock collisions: when the user toggles the
// launcher off/on quickly, a previous embedded Electron process may still be
// running against the same userDataDir.  The default single-instance-lock
// behavior calls app.quit() in the second instance which would silently drop
// stdout and trigger the GJS WebKit fallback.  We disable the instance lock
// because each embedded renderer is tightly lifecycle-coupled to its parent
// GJS launcher (child of Subprocess, dies with parent / quit msg).
try {
  const hasLock = app.requestSingleInstanceLock();
  if (!hasLock) {
    // Previous instance is still alive and owns the lock.  Continue anyway by
    // releasing our attempt; this lets us run multiple Embedded Electrons.
    // NOTE: setPath('userData', ...) is called BELOW before app.whenReady()
    // so each launcher could have an independent userData dir.  Currently we
    // intentionally share one userData dir so WebLLM IndexedDB weights are
    // reusable across daemon restarts, so the instance lock sharing is OK
    // for us as long as we never quit the second instance before creating
    // our main window.
  }
  app.on('second-instance', () => {
    // Another launcher is starting another embedded Electron; do nothing,
    // do NOT quit our instance or focus.  Each launcher owns its own process.
  });
} catch (_) {}

let mainWin = null;

function createWindow() {
  const initX = Number(process.env.HYPRCANDY_INIT_X || 100);
  const initY = Number(process.env.HYPRCANDY_INIT_Y || 100);
  const initW = Number(process.env.HYPRCANDY_INIT_W || 960);
  const initH = Number(process.env.HYPRCANDY_INIT_H || 600);

  // In EMBEDDED_MODE the window is never shown to the user — it is an invisible
  // Chromium process that runs WebLLM/WebGPU inference only.  All other options
  // are identical so the React app + preload still boot normally.
  mainWin = new BrowserWindow({
    x: initX, y: initY, width: initW, height: initH,
    frame: false,
    transparent: true,
    backgroundColor: '#00000000',
    hasShadow: false,
    show: false, // always start hidden; embedded mode never shows
    resizable: false,
    movable: false,
    minimizable: false,
    maximizable: false,
    closable: false,
    focusable: !EMBEDDED_MODE,
    skipTaskbar: true,
    alwaysOnTop: !EMBEDDED_MODE,
    acceptFirstMouse: !EMBEDDED_MODE,
    title: EMBEDDED_MODE ? 'HyprCandyAgentWorker' : 'HyprCandyAgent',
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
      webSecurity: false,
      allowRunningInsecureContent: true,
      devTools: !app.isPackaged || process.env.HYPRCANDY_ELECTRON_DEVTOOLS === '1',
      autoplayPolicy: 'no-user-gesture-required',
      webgl: false,
      backgroundThrottling: false,
      offscreen: false,
    },
  });

  try { mainWin.setMenuBarVisibility(false); } catch (_) {}
  try { mainWin.setAutoHideMenuBar(true); } catch (_) {}

  // Hyprland window rule hints (optional): class=HyprCandyAgentElectron,
  // user can add: windowrule = float, class:^(HyprCandyAgentElectron)$
  //                windowrule = noanimations, class:^(HyprCandyAgentElectron)$
  //                windowrule = noblur, class:^(HyprCandyAgentElectron)$
  //                windowrule = noshadow, class:^(HyprCandyAgentElectron)$
  //                windowrule = bordercolor rgb(00000000), class:^(HyprCandyAgentElectron)$
  mainWin.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));

  mainWin.on('closed', () => {
    mainWin = null;
  });

  mainWin.webContents.on('console-message', (_event, level, message) => {
    try {
      const mapped = Number(level);
      const severity = ['verbose', 'info', 'warning', 'error'][mapped] || 'log';
      if (severity === 'warning') {
        process.stdout.write(JSON.stringify({ type: 'console', level: 'warn', msg: String(message).slice(0, 4000) }) + '\n');
      } else if (severity === 'error') {
        process.stdout.write(JSON.stringify({ type: 'console', level: 'error', msg: String(message).slice(0, 4000) }) + '\n');
      }
    } catch (_) {}
  });

  mainWin.webContents.on('did-finish-load', () => {
    // In embedded mode the window stays hidden; GJS renders the UI in its own
    // WebKitGTK view while this process handles inference and streams results back.
    if (!EMBEDDED_MODE) mainWin.showInactive();
    try { process.stdout.write(JSON.stringify({ type: 'ready', embedded: EMBEDDED_MODE }) + '\n'); } catch (_) {}
  });

  mainWin.webContents.on('did-fail-load', (_, code, desc) => {
    try { process.stdout.write(JSON.stringify({ type: 'error', message: `load failed ${code}: ${desc}` }) + '\n'); } catch (_) {}
  });

  // Capture uncaught exceptions from renderer
  mainWin.webContents.on('dom-ready', () => {
    mainWin.webContents.executeJavaScript(`
      window.addEventListener('error', (e) => {
        try { window.__electronReportError({ message: e.message, filename: e.filename, lineno: e.lineno, stack: (e.error||{}).stack||'' }); } catch(_) {}
      });
      window.addEventListener('unhandledrejection', (e) => {
        try { window.__electronReportError({ message: 'UnhandledRejection: ' + String(e.reason) }); } catch(_) {}
      });
      true;
    `).catch(() => {});
  });

  const loadPromise = AGENT_URL.startsWith('file:')
    ? mainWin.loadFile(fileURLToPath(AGENT_URL))
    : mainWin.loadURL(AGENT_URL);
  loadPromise.catch(err => {
    try { process.stdout.write(JSON.stringify({ type: 'error', message: 'agent load error: ' + err.message }) + '\n'); } catch (_) {}
  });
}

// ─── IPC with preload: renderer posts an "agent" envelope string ────────────
ipcMain.on('agent:post', (_evt, envelopeStr) => {
  try {
    process.stdout.write(JSON.stringify({ type: 'postMessage', data: String(envelopeStr || '') }) + '\n');
  } catch (_) {}
});
ipcMain.on('agent:error', (_evt, info) => {
  try { process.stdout.write(JSON.stringify({ type: 'error', ...(info || {}) }) + '\n'); } catch (_) {}
});
// Worker inference output: streaming tokens/progress from the hidden Chromium
// renderer arrive here and are written to stdout for GJS to relay. Coalesce
// token events: one GJS evaluate_javascript call per token can consume an entire
// CPU core on older GTK/WebKit builds and starve pointer events.
let pendingWorkerToken = '';
let pendingWorkerTokenTimer = null;
function flushWorkerToken() {
  if (!pendingWorkerToken) return;
  const payload = JSON.stringify({ type: 'worker_token', payload: { token: pendingWorkerToken } });
  pendingWorkerToken = '';
  pendingWorkerTokenTimer = null;
  try { process.stdout.write(payload + '\n'); } catch (_) {}
}
function relayWorkerMessage(parsed) {
  if (parsed?.type === 'worker_token') {
    pendingWorkerToken += String(parsed.payload?.token || '');
    if (!pendingWorkerTokenTimer) pendingWorkerTokenTimer = setTimeout(flushWorkerToken, 32);
    return;
  }
  if (parsed?.type === 'worker_done' || parsed?.type === 'worker_error') flushWorkerToken();
  try { process.stdout.write(JSON.stringify(parsed) + '\n'); } catch (_) {}
}
ipcMain.on('agent:worker_out', (_evt, jsonStr) => {
  try {
    // Validate it's real JSON before writing to stdout
    const parsed = JSON.parse(String(jsonStr || '{}'));
    relayWorkerMessage(parsed);
  } catch (_) {}
});

app.whenReady().then(() => {
  createWindow();
  setupStdinReader();
});

app.on('window-all-closed', () => {
  // Keep running until GJS closes stdin / kills process.
});

// ─── GJS → Electron: stdin line-delimited JSON reader ───────────────────────
function executeWhenReady(js) {
  return new Promise((resolve, reject) => {
    if (!mainWin || mainWin.isDestroyed()) {
      return reject(new Error('Browser window destroyed'));
    }
    const run = () => {
      mainWin.webContents.executeJavaScript(js).then(resolve).catch(reject);
    };
    if (mainWin.webContents.isLoading()) {
      mainWin.webContents.once('did-finish-load', run);
    } else {
      run();
    }
  });
}

// WebLLM/Wllama is stateful: model load, unload, and chat stream scripts must
// not execute concurrently in the same renderer. Cancellation is intentionally
// sent directly so it can interrupt the operation currently holding the
// runtime; the next queued operation then observes the aborted state.
let workerOperationTail = Promise.resolve();
function enqueueWorkerOperation(js) {
  const operation = workerOperationTail
    .catch(() => undefined)
    .then(() => executeWhenReady(js));
  workerOperationTail = operation.catch(() => undefined);
  return operation;
}

function setupStdinReader() {
  const rl = readline.createInterface({ input: process.stdin, terminal: false });
  rl.on('line', (line) => {
    if (!line || !line.trim()) return;
    let msg;
    try { msg = JSON.parse(line); } catch { return; }
    if (!msg || typeof msg !== 'object') return;

    if (msg.type === 'bounds' && mainWin && !mainWin.isDestroyed()) {
      const { x, y, w, h } = msg;
      try {
        if (typeof x === 'number' && typeof y === 'number' && typeof w === 'number' && typeof h === 'number') {
          mainWin.setContentBounds({ x: Math.round(x), y: Math.round(y), width: Math.max(200, Math.round(w)), height: Math.max(200, Math.round(h)) }, false);
        }
      } catch (_) {}
    } else if (msg.type === 'dispatch' && msg.payload && mainWin && !mainWin.isDestroyed()) {
      const payload = msg.payload;

      if (payload.type === 'llama_request') {
        const requestId = String(payload.requestId || '');
        const action = String(payload.action || '');
        const reply = (value, error) => {
          try { process.stdout.write(JSON.stringify({ type: 'llama_response', payload: { requestId, value, error } }) + '\n'); } catch (_) {}
        };
        (async () => {
          try {
            const model = payload.payload?.model;
            const options = payload.payload?.options || {};
            if (action === 'llama_catalog') return reply(llamaServer.catalog());
            if (action === 'llama_search') return reply(await llamaServer.searchModels(payload.payload?.query || ''));
            if (action === 'llama_inspect') return reply(await llamaServer.inspectModel(payload.payload?.repo || ''));
            if (action === 'llama_has_model') return reply(llamaServer.hasModel(model));
            if (action === 'llama_status') return reply(llamaServer.status());
            if (action === 'llama_pull') return reply(await llamaServer.pull(model, (progress) => {
              try { process.stdout.write(JSON.stringify({ type: 'llama_progress', payload: { modelId: model, ...progress } }) + '\n'); } catch (_) {}
            }));
            if (action === 'llama_start') return reply(await llamaServer.start(model, options, (progress) => {
              try { process.stdout.write(JSON.stringify({ type: 'llama_progress', payload: { modelId: model, ...progress } }) + '\n'); } catch (_) {}
            }));
            if (action === 'llama_stop') return reply(await llamaServer.stop());
            return reply(null, `Unknown native llama action: ${action}`);
          } catch (error) { reply(null, error?.message || String(error)); }
        })();
        return;
      }

      // ── Inference delegation: worker_load_model ───────────────────────────
      if (payload.type === 'worker_load_model') {
        const modelId = String(payload.modelId || '');
        const requestId = String(payload.requestId || '');
        const customModels = Array.isArray(payload.customModels) ? payload.customModels : [];
        // Inject a self-contained script that calls the global agentEngine
        // exposed by the React app (via window.__hyprcandyEngine), loads the
        // model, and streams progress back through stdout JSONL.
        const js = `(async function(){
  try {
    let unsub = null;
    // Large production bundles can take several seconds to publish the
    // engine on older CPUs; wait before reporting a bootstrap failure.
    let retries = 300;
    while (!window.__hyprcandyEngine && retries > 0) {
      await new Promise(r => setTimeout(r, 100));
      retries--;
    }
    const eng = window.__hyprcandyEngine;
    if (!eng) throw new Error('agentEngine not exposed on window.__hyprcandyEngine');
    if (window.__webllmService && typeof window.__webllmService.setCustomModels === 'function') {
      window.__webllmService.setCustomModels(${JSON.stringify(customModels)});
    }
    if (window.agent && typeof window.agent.setStore === 'function' && ${JSON.stringify(customModels)}.length) {
      window.agent.setStore({ customModels: ${JSON.stringify(customModels)} });
    }
    // Subscribe to WebLLM download/init progress before loading
    unsub = window.__webllmService && typeof window.__webllmService.onProgress === 'function'
      ? window.__webllmService.onProgress(function(rpt) {
          var data = JSON.stringify({ type: 'worker_progress', payload: {
            modelId: ${JSON.stringify(modelId)},
            requestId: ${JSON.stringify(requestId)},
            progress: typeof rpt.progress === 'number' ? rpt.progress : 0,
            text: rpt.text || '',
            error: rpt.error || null,
          }});
          if (window.__electronSendToMain) window.__electronSendToMain(data);
        })
      : null;
    await eng.loadModel(${JSON.stringify(modelId)});
    if (typeof unsub === 'function') { try { unsub(); } catch (_) {} }
    if (window.__electronSendToMain) window.__electronSendToMain(JSON.stringify({
      type: 'worker_model_ready', payload: { modelId: ${JSON.stringify(modelId)}, requestId: ${JSON.stringify(requestId)} }
    }));
  } catch(e) {
    if (typeof unsub === 'function') { try { unsub(); } catch (_) {} }
    if (window.__electronSendToMain) window.__electronSendToMain(JSON.stringify({
      type: 'worker_error', payload: { modelId: ${JSON.stringify(modelId)}, requestId: ${JSON.stringify(requestId)}, message: e.message || String(e) }
    }));
  }
})();`;
        enqueueWorkerOperation(js).catch((e) => {
          try { process.stdout.write(JSON.stringify({ type: 'worker_error', payload: { modelId, requestId, message: e.message || String(e) } }) + '\n'); } catch(_){}
        });
        return;
      }

      if (payload.type === 'worker_cancel_model') {
        const js = `(() => {
  try {
    if (window.__hyprcandyEngine && typeof window.__hyprcandyEngine.cancel === 'function') {
      window.__hyprcandyEngine.cancel();
    } else if (window.__webllmService && typeof window.__webllmService.interrupt === 'function') {
      window.__webllmService.interrupt();
    }
  } catch (_) {}
})();`;
        executeWhenReady(js).catch(() => {});
        return;
      }

      // ── Inference delegation: worker_chat ──────────────────────────────
      if (payload.type === 'worker_chat') {
        const { sessionId, msgId, modelId, messages, projectPath, selectedFile,
          selectedFileContent, projectFiles, contextFiles, contextImages } = payload;
        const msgsJson  = JSON.stringify(messages  || []);
        const modelJson = JSON.stringify(modelId   || '');
        const sessJson  = JSON.stringify(sessionId || '');
        const projJson  = JSON.stringify(projectPath || '');
        const fileJson  = JSON.stringify(selectedFile || '');
        const projectContextJson = JSON.stringify({
          projectPath: projectPath || '',
          selectedFile: selectedFile || null,
          selectedFileContent: selectedFileContent || null,
          projectFiles: Array.isArray(projectFiles) ? projectFiles : [],
          contextFiles: Array.isArray(contextFiles) ? contextFiles : [],
          contextImages: Array.isArray(contextImages) ? contextImages : [],
        });
        // Runs agentEngine.runConversation() in the Electron renderer with full
        // WebGPU access. Tokens are sent back to GJS via preload's IPC channel
        // (__electronSendToMain), which calls ipcRenderer.send → ipcMain →
        // process.stdout, arriving as worker_token/worker_done/worker_error lines.
        const js = `(async function(){
  try {
    // Match the model-load grace period so chat cannot race renderer startup.
    let retries = 300;
    while (!window.__hyprcandyEngine && retries > 0) {
      await new Promise(r => setTimeout(r, 100));
      retries--;
    }
    const eng = window.__hyprcandyEngine;
    if (!eng) throw new Error('agentEngine not exposed on window.__hyprcandyEngine');
    const projectContext = ${projectContextJson};
    if (window.agent && typeof window.agent.setStore === 'function') {
      window.agent.setStore(projectContext);
    }
    const msgs = ${msgsJson};
    // The last message is the user turn; everything before it is history.
    const userMsg = msgs.length ? msgs[msgs.length - 1].content : '';
    const history = msgs.slice(0, -1);
    await eng.runConversation(
      ${sessJson},
      userMsg,
      history,
      (token) => {
        if (window.__electronSendToMain) window.__electronSendToMain(JSON.stringify({
          type: 'worker_token', payload: { token, msgId: ${JSON.stringify(msgId)} }
        }));
      }
    );
    if (window.__electronSendToMain) window.__electronSendToMain(JSON.stringify({
      type: 'worker_done', payload: { sessionId: ${sessJson}, msgId: ${JSON.stringify(msgId)} }
    }));
  } catch(e) {
    if (window.__electronSendToMain) window.__electronSendToMain(JSON.stringify({
      type: 'worker_error', payload: { message: e.message || String(e), msgId: ${JSON.stringify(msgId)} }
    }));
  }
})();`;
        enqueueWorkerOperation(js).catch((e) => {
          try { process.stdout.write(JSON.stringify({ type: 'worker_error', payload: { message: e.message || String(e), msgId } }) + '\n'); } catch(_){}
        });
        return;
      }

      // ── Model-cache inspection: worker_cache_status ──────────────────────
      // The visible WebKitGTK page has a different IndexedDB origin from this
      // Chromium worker. Ask the worker that owns WebLLM to inspect its cache
      // so the Model Manager's badges do not report every model as uncached.
      if (payload.type === 'worker_cache_status') {
        const requestId = String(payload.requestId || '');
        const idsJson = JSON.stringify(Array.isArray(payload.modelIds) ? payload.modelIds : []);
        const customJson = JSON.stringify(Array.isArray(payload.customModels) ? payload.customModels : []);
        const js = `(async function(){
  const requestId = ${JSON.stringify(requestId)};
  try {
    const svc = window.__webllmService;
    if (!svc || typeof svc.isModelCached !== 'function') throw new Error('WebLLM service not exposed in Electron worker');
    svc.setCustomModels(${customJson});
    const ids = Array.from(new Set(${idsJson}));
    const cachedModelIds = [];
    for (const id of ids) {
      if (await svc.isModelCached(String(id))) cachedModelIds.push(String(id));
    }
    if (window.__electronSendToMain) window.__electronSendToMain(JSON.stringify({
      type: 'worker_cache_status', payload: { requestId, cachedModelIds }
    }));
  } catch (e) {
    if (window.__electronSendToMain) window.__electronSendToMain(JSON.stringify({
      type: 'worker_cache_status', payload: { requestId, cachedModelIds: [], error: e.message || String(e) }
    }));
  }
})();`;
        enqueueWorkerOperation(js).catch((e) => {
          try { process.stdout.write(JSON.stringify({
            type: 'worker_cache_status',
            payload: { requestId, cachedModelIds: [], error: e.message || String(e) },
          }) + '\n'); } catch (_) {}
        });
        return;
      }

      // ── Model-cache clearing: worker_clear_cache ──────────────────────────
      // Delete through the same WebLLM service/cache origin used by inference;
      // clearing from WebKitGTK itself would only delete unrelated UI-origin
      // entries and leave the actual Electron model weights behind.
      if (payload.type === 'worker_clear_cache') {
        const requestId = String(payload.requestId || '');
        const idsJson = JSON.stringify(Array.isArray(payload.modelIds) ? payload.modelIds : []);
        const customJson = JSON.stringify(Array.isArray(payload.customModels) ? payload.customModels : []);
        const js = `(async function(){
  const requestId = ${JSON.stringify(requestId)};
  try {
    const svc = window.__webllmService;
    if (!svc || typeof svc.deleteModelCache !== 'function') throw new Error('WebLLM service not exposed in Electron worker');
    svc.setCustomModels(${customJson});
    await svc.unload();
    for (const id of Array.from(new Set(${idsJson}))) {
      await svc.deleteModelCache(String(id));
    }
    if (window.__electronSendToMain) window.__electronSendToMain(JSON.stringify({
      type: 'worker_cache_cleared', payload: { requestId }
    }));
  } catch (e) {
    if (window.__electronSendToMain) window.__electronSendToMain(JSON.stringify({
      type: 'worker_cache_cleared', payload: { requestId, error: e.message || String(e) }
    }));
  }
})();`;
        enqueueWorkerOperation(js).catch((e) => {
          try { process.stdout.write(JSON.stringify({
            type: 'worker_cache_cleared',
            payload: { requestId, error: e.message || String(e) },
          }) + '\n'); } catch (_) {}
        });
        return;
      }

      // ── Generic dispatch (theme_update, user_prompt, etc.) ────────────────
      const payloadJson = JSON.stringify(payload);
      executeWhenReady(`
        (function(){ try { if (window.__hyprcandy_agent_dispatch) { window.__hyprcandy_agent_dispatch(${payloadJson}); return true; } } catch(e){} try { window.dispatchEvent(new CustomEvent('agent_host_message', { detail: ${payloadJson} })); } catch(e){} return false; })()
      `).catch(() => {});
    } else if (msg.type === 'show' && mainWin && !mainWin.isDestroyed()) {
      // In embedded mode we never surface a window — ignore show/hide commands.
      if (!EMBEDDED_MODE) try { mainWin.showInactive(); } catch (_) {}
    } else if (msg.type === 'hide' && mainWin && !mainWin.isDestroyed()) {
      if (!EMBEDDED_MODE) try { mainWin.hide(); } catch (_) {}
    } else if (msg.type === 'focus' && mainWin && !mainWin.isDestroyed()) {
      try { mainWin.focus(); } catch (_) {}
    } else if (msg.type === 'quit') {
      try { app.quit(); } catch (_) { process.exit(0); }
    } else if (msg.type === 'reload' && mainWin && !mainWin.isDestroyed()) {
      mainWin.webContents.reloadIgnoringCache();
    } else if (msg.type === 'devtools' && mainWin && !mainWin.isDestroyed()) {
      if (mainWin.webContents.isDevToolsOpened()) mainWin.webContents.closeDevTools();
      else mainWin.webContents.openDevTools({ mode: 'detach' });
    }
  });
  rl.on('close', () => {
    try { app.quit(); } catch (_) { process.exit(0); }
  });
}

process.on('uncaughtException', (e) => {
  try { process.stdout.write(JSON.stringify({ type: 'error', message: e.message || String(e), stack: e.stack || '' }) + '\n'); } catch (_) {}
});
process.on('unhandledRejection', (reason) => {
  const message = reason?.message || String(reason || 'Unhandled promise rejection');
  const stack = reason?.stack || '';
  try { process.stdout.write(JSON.stringify({ type: 'error', message: `UnhandledRejection: ${message}`, stack }) + '\n'); } catch (_) {}
});
