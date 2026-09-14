const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const http = require('http');
const https = require('https');
const os = require('os');

const DEFAULT_PORT = Number(process.env.HYPRCANDY_LLAMA_PORT || 17843);
const DEFAULT_MODELS_DIR = process.env.HYPRCANDY_LLAMA_MODELS_DIR || path.join(os.homedir(), '.local', 'share', 'hyprcandy', 'llama-models');
const ACTIVE_MODEL_STATE = process.env.HYPRCANDY_LLAMA_STATE || path.join(os.homedir(), '.local', 'share', 'hyprcandy', 'llama-server-state.json');
const DEFAULT_BINARY = process.env.HYPRCANDY_LLAMA_SERVER_BIN || path.join(__dirname, '..', '..', 'native', 'llama.cpp', 'build', 'bin', 'llama-server');
// Safety ceiling for auto-detected context size. Some GGUFs report a
// trained context in the hundreds of thousands to millions of tokens
// (long-context/YaRN models); blindly honoring that allocates a KV cache
// large enough to hang or OOM a modest machine. This caps what
// getEffectiveContext() will pick automatically — an explicit
// options.context from the caller always wins over both the GGUF's
// reported value and this cap.
const DEFAULT_MAX_AUTO_CTX = Number(process.env.HYPRCANDY_LLAMA_MAX_CTX) || 16384;
const MODEL_CATALOG = {
  'Qwen2.5-Coder-1.5B-Instruct': {
    id: 'Qwen2.5-Coder-1.5B-Instruct',
    repo: 'bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF',
    file: 'Qwen2.5-Coder-1.5B-Instruct-Q4_K_M.gguf',
  },
  'Qwen2.5-Coder-0.5B-Instruct': {
    id: 'Qwen2.5-Coder-0.5B-Instruct',
    repo: 'bartowski/Qwen2.5-Coder-0.5B-Instruct-GGUF',
    file: 'Qwen2.5-Coder-0.5B-Instruct-Q4_K_M.gguf',
  },
};

function mkdirp(dir) { fs.mkdirSync(dir, { recursive: true }); }
function modelPath(model) { return path.join(DEFAULT_MODELS_DIR, model.file); }
function readActiveModelState() {
  try {
    const state = JSON.parse(fs.readFileSync(ACTIVE_MODEL_STATE, 'utf8'));
    return state && typeof state === 'object' ? state : null;
  } catch (_) { return null; }
}
function writeActiveModelState(model) {
  try {
    mkdirp(path.dirname(ACTIVE_MODEL_STATE));
    fs.writeFileSync(ACTIVE_MODEL_STATE, JSON.stringify({ id: model.id, repo: model.repo, file: model.file, updatedAt: Date.now() }));
  } catch (_) {}
}

// Minimal GGUF key-value metadata reader — enough to find `<arch>.context_length`
// without loading the whole (multi-GB) model file. GGUF layout:
//   magic(4) version(u32) tensor_count(u64) kv_count(u64) [key/value]*kv_count
// then tensor info (which we never reach — we stop once all kv pairs are read).
// Growable read: metadata sections holding a full tokenizer vocab as a
// string array can run into the megabytes, so we grow the read window
// instead of assuming a fixed prefix size is always enough.
const GGUF_TYPE = { UINT8: 0, INT8: 1, UINT16: 2, INT16: 3, UINT32: 4, INT32: 5, FLOAT32: 6, BOOL: 7, STRING: 8, ARRAY: 9, UINT64: 10, INT64: 11, FLOAT64: 12 };
function parseGgufContextLength(buf) {
  let offset = 0;
  const needMore = () => { const e = new Error('NEED_MORE'); e.needMore = true; throw e; };
  const need = (n) => { if (offset + n > buf.length) needMore(); };
  const readU32 = () => { need(4); const v = buf.readUInt32LE(offset); offset += 4; return v; };
  const readU64 = () => { need(8); const v = Number(buf.readBigUInt64LE(offset)); offset += 8; return v; };
  const readI64 = () => { need(8); const v = Number(buf.readBigInt64LE(offset)); offset += 8; return v; };
  const readString = () => { const len = readU64(); need(len); const s = buf.toString('utf8', offset, offset + len); offset += len; return s; };
  const skipValue = (type) => {
    switch (type) {
      case GGUF_TYPE.UINT8: case GGUF_TYPE.INT8: case GGUF_TYPE.BOOL: need(1); offset += 1; return;
      case GGUF_TYPE.UINT16: case GGUF_TYPE.INT16: need(2); offset += 2; return;
      case GGUF_TYPE.UINT32: case GGUF_TYPE.INT32: case GGUF_TYPE.FLOAT32: need(4); offset += 4; return;
      case GGUF_TYPE.STRING: readString(); return;
      case GGUF_TYPE.ARRAY: {
        const elemType = readU32();
        const count = readU64();
        for (let i = 0; i < count; i++) skipValue(elemType);
        return;
      }
      case GGUF_TYPE.UINT64: case GGUF_TYPE.INT64: case GGUF_TYPE.FLOAT64: need(8); offset += 8; return;
      default: throw new Error(`unknown gguf value type ${type}`);
    }
  };
  const readScalar = (type) => {
    switch (type) {
      case GGUF_TYPE.UINT32: return readU32();
      case GGUF_TYPE.INT32: { need(4); const v = buf.readInt32LE(offset); offset += 4; return v; }
      case GGUF_TYPE.UINT64: return readU64();
      case GGUF_TYPE.INT64: return readI64();
      default: skipValue(type); return null;
    }
  };

  need(4);
  if (buf.toString('utf8', 0, 4) !== 'GGUF') return null;
  offset = 4;
  readU32(); // version
  readU64(); // tensor_count
  const kvCount = readU64();
  let contextLength = null;
  for (let i = 0; i < kvCount; i++) {
    const key = readString();
    const type = readU32();
    if (/\.context_length$/.test(key)) {
      contextLength = readScalar(type);
    } else {
      skipValue(type);
    }
  }
  return contextLength;
}

/** Reads a GGUF's trained context length (e.g. `qwen2.context_length`), or
 * null if it can't be determined. Grows the read window rather than
 * reading the whole file — metadata always precedes tensor data in GGUF. */
function readGgufContextLength(filePath, maxBytes = 32 * 1024 * 1024) {
  let fd;
  try { fd = fs.openSync(filePath, 'r'); } catch { return null; }
  try {
    for (let bufSize = 2 * 1024 * 1024; bufSize <= maxBytes; bufSize *= 4) {
      const buf = Buffer.alloc(bufSize);
      const bytesRead = fs.readSync(fd, buf, 0, bufSize, 0);
      try {
        return parseGgufContextLength(buf.subarray(0, bytesRead));
      } catch (e) {
        if (e.needMore && bytesRead === bufSize) continue; // grow and retry
        return null; // malformed / genuinely not present
      }
    }
    return null;
  } catch {
    return null;
  } finally {
    try { fs.closeSync(fd); } catch {}
  }
}

/** Picks the context size to launch with: an explicit request always wins;
 * otherwise auto-detect the model's trained context from its own GGUF
 * metadata and cap it for safety (see DEFAULT_MAX_AUTO_CTX above). */
function getEffectiveContext(modelPathOnDisk, requestedContext) {
  const requested = Number(requestedContext) || 0;
  if (requested > 0) return { value: requested, source: 'requested' };
  const trained = readGgufContextLength(modelPathOnDisk);
  if (trained && trained > 0) {
    return { value: Math.min(trained, DEFAULT_MAX_AUTO_CTX), source: trained > DEFAULT_MAX_AUTO_CTX ? `capped from model's ${trained}` : "model's trained context" };
  }
  return { value: DEFAULT_MAX_AUTO_CTX, source: 'fallback (context_length not found in GGUF)' };
}
function modelInfo(modelIdOrSpec) {
  const model = typeof modelIdOrSpec === 'object' && modelIdOrSpec
    ? { id: modelIdOrSpec.id || modelIdOrSpec.repo, repo: modelIdOrSpec.repo, file: modelIdOrSpec.file }
    : MODEL_CATALOG[modelIdOrSpec] || Object.values(MODEL_CATALOG).find((m) => m.file === modelIdOrSpec);
  if (!model?.repo || !model?.file) {
    const detail = modelIdOrSpec && typeof modelIdOrSpec === 'object'
      ? JSON.stringify(modelIdOrSpec)
      : String(modelIdOrSpec);
    throw new Error(`Unsupported llama-server model: ${detail}`);
  }
  return { ...model, path: modelPath(model) };
}
function requestJson(url, options = {}, body = null) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const transport = parsed.protocol === 'https:' ? https : http;
    const req = transport.request(parsed, { method: options.method || 'GET', headers: { ...(body ? { 'content-type': 'application/json' } : {}), ...(options.headers || {}) } }, (res) => {
      let data = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        let value = data;
        try { value = data ? JSON.parse(data) : null; } catch (_) {}
        if (res.statusCode >= 200 && res.statusCode < 300) resolve(value);
        else reject(new Error(`llama-server HTTP ${res.statusCode}: ${typeof value === 'string' ? value : JSON.stringify(value)}`));
      });
    });
    req.on('error', reject);
    req.setTimeout(options.timeout || 5000, () => req.destroy(new Error('llama-server request timed out')));
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

class LlamaServerManager {
  constructor() {
    this.child = null;
    this.model = null;
    this.port = DEFAULT_PORT;
    this.modelsDir = DEFAULT_MODELS_DIR;
    this.binary = DEFAULT_BINARY;
    this.startPromise = null;
    this.activePulls = new Map();
    this.stderr = '';
  }

  catalog() { return Object.values(MODEL_CATALOG); }
  activeModelState() { return readActiveModelState(); }
  async searchModels(query) {
    const base = String(query).trim();
    // Use HF's own gguf tag filter (reliable, tag-based) instead of
    // appending free-text like "tool calling" to the query — that phrase
    // narrows/derails HF's relevance search and was silently hiding
    // legitimate quant repos (e.g. bartowski's) that don't happen to
    // mention "tool calling" anywhere in their model card text.
    const url = `https://huggingface.co/api/models?search=${encodeURIComponent(base)}&filter=gguf&sort=downloads&direction=-1&limit=15`;
    const results = await requestJson(url, { timeout: 15000 });
    return Array.isArray(results)
      ? results.filter((model) => typeof (model?.id || model?.modelId) === 'string')
        .map((model) => ({ id: model.id || model.modelId, downloads: model.downloads, likes: model.likes, tags: model.tags }))
        .slice(0, 15)
      : [];
  }
  async inspectModel(repo) {
    const safeRepo = String(repo || '').trim();
    if (!/^[^/]+\/[^/]+$/.test(safeRepo)) throw new Error('Invalid Hugging Face repository; expected owner/name');
    const metadata = await requestJson(`https://huggingface.co/api/models/${safeRepo}?full=true`, { timeout: 20000 });
    const files = (metadata?.siblings || []).map((file) => file?.rfilename).filter((file) => typeof file === 'string');
    return { repo: safeRepo, files };
  }
  hasModel(modelIdOrSpec) { try { const model = modelInfo(modelIdOrSpec); return fs.existsSync(model.path) && fs.statSync(model.path).size > 1024 * 1024; } catch (_) { return false; } }
  status() { return { running: Boolean(this.child && this.child.exitCode === null), pid: this.child?.pid || null, port: this.port, model: this.model, binary: this.binary, modelsDir: this.modelsDir, stderr: this.stderr.slice(-4000) }; }
  async health() { return requestJson(`http://127.0.0.1:${this.port}/health`, { timeout: 2000 }); }
  async runningModel() {
    const result = await requestJson(`http://127.0.0.1:${this.port}/v1/models`, { timeout: 2000 });
    return result?.data?.[0]?.id || result?.models?.[0]?.id || null;
  }

  async pull(modelIdOrSpec, onProgress) {
    const model = modelInfo(modelIdOrSpec);
    mkdirp(this.modelsDir);
    if (fs.existsSync(model.path) && fs.statSync(model.path).size > 1024 * 1024) return { ...model, cached: true };
    const existingPull = this.activePulls.get(model.path);
    if (existingPull) return existingPull;
    const url = `https://huggingface.co/${model.repo}/resolve/main/${encodeURIComponent(model.file)}?download=true`;
    const destination = `${model.path}.part`;
    const pullPromise = new Promise((resolve, reject) => {
      const file = fs.createWriteStream(destination);
      let settled = false;
      const fail = (error) => {
        if (settled) return;
        settled = true;
        try { file.destroy(); } catch (_) {}
        try { if (fs.existsSync(destination)) fs.unlinkSync(destination); } catch (_) {}
        reject(error);
      };
      const follow = (target) => {
        const parsed = new URL(target);
        const req = (parsed.protocol === 'https:' ? https : http).get(parsed, (res) => {
          if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) return follow(new URL(res.headers.location, target).toString());
          if (res.statusCode !== 200) return fail(new Error(`Model download HTTP ${res.statusCode}`));
          const total = Number(res.headers['content-length'] || 0);
          let loaded = 0;
          res.on('data', (chunk) => { loaded += chunk.length; onProgress?.({ loaded, total, text: total ? `Downloading ${model.file}: ${Math.round(loaded / 1024 / 1024)}/${Math.round(total / 1024 / 1024)} MB` : `Downloading ${model.file}…` }); });
          res.pipe(file);
          res.on('end', () => file.close(() => {
            if (settled) return;
            settled = true;
            resolve();
          }));
        });
        req.on('error', fail);
      };
      follow(url);
    });
    this.activePulls.set(model.path, pullPromise);
    try {
      await pullPromise;
      fs.renameSync(destination, model.path);
      return { ...model, cached: false };
    } finally {
      this.activePulls.delete(model.path);
    }
  }

  async start(modelIdOrSpec, options = {}, onProgress) {
    const model = await this.pull(modelIdOrSpec, onProgress);
    if (this.child && this.model === model.id) {
      await this.waitHealthy();
      writeActiveModelState(model);
      return this.status();
    }
    if (!this.child) {
      try {
        await this.health();
        const runningModel = await this.runningModel();
        if (!runningModel || runningModel === model.id) {
          this.model = model.id;
          writeActiveModelState(model);
          return this.status();
        }
        throw new Error(`llama-server port ${this.port} is occupied by model ${runningModel}`);
      } catch (error) {
        if (String(error?.message || '').includes('occupied by model')) throw error;
      }
    }
    await this.stop();
    if (!fs.existsSync(this.binary)) throw new Error(`llama-server binary not found at ${this.binary}; run agent-app/build.sh first`);
    const ctx = getEffectiveContext(model.path, options.context);
    const args = ['-m', model.path, '--host', '127.0.0.1', '--port', String(this.port), '--jinja', '--alias', model.id, '--ctx-size', String(ctx.value), '--n-predict', String(options.maxTokens || 2048)];
    if (process.env.HYPRCANDY_LLAMA_GPU_LAYERS) args.push('--n-gpu-layers', process.env.HYPRCANDY_LLAMA_GPU_LAYERS);
    this.stderr = '';
    this.child = spawn(this.binary, args, { stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, GGML_CUDA_NO_PINNED: process.env.GGML_CUDA_NO_PINNED || '1' } });
    this.model = model.id;
    // Electron stdout is a JSONL IPC channel to GJS. Never forward raw
    // llama-server diagnostics into it: each line would become a failed JSON
    // parse in app-launcher.js and can starve the GTK main loop during chat.
    this.child.stderr.on('data', (chunk) => { this.stderr += chunk.toString(); });
    this.child.stdout.on('data', () => {});
    const childPid = this.child.pid;
    this.child.once('exit', () => { if (this.child?.pid === childPid) { this.child = null; this.model = null; } });
    await this.waitHealthy();
    writeActiveModelState(model);
    return this.status();
  }

  async waitHealthy(timeout = 180000) {
    const started = Date.now();
    while (Date.now() - started < timeout) {
      if (!this.child || this.child.exitCode !== null) throw new Error(`llama-server exited while loading: ${this.stderr.slice(-2000)}`);
      try { await this.health(); return true; } catch (_) { await new Promise((resolve) => setTimeout(resolve, 500)); }
    }
    throw new Error(`llama-server health timeout: ${this.stderr.slice(-2000)}`);
  }

  async stop() {
    const child = this.child;
    if (!child) { this.model = null; return; }
    this.child = null;
    this.model = null;
    await new Promise((resolve) => {
      const timer = setTimeout(() => { try { child.kill('SIGKILL'); } catch (_) {} resolve(); }, 10000);
      child.once('exit', () => { clearTimeout(timer); resolve(); });
      try { child.kill('SIGTERM'); } catch (_) { clearTimeout(timer); resolve(); }
    });
  }
}

module.exports = { LlamaServerManager, MODEL_CATALOG };
