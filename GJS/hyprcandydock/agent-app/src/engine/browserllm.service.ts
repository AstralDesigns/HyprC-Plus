/**
 * Local browser inference service.
 *
 * Persistent caching uses a three-tier strategy for maximum reliability:
 *   1. HTTP Cache (`transformers-cache`) for raw model files.
 *   2. IndexedDB catalog (`hyprcandy-browser-llm`) for completed-load records.
 *   3. LocalStorage manifest (`hyprcandy_model_cache_manifest`) to survive
 *      HTTP cache evictions and detect "previously active" models instantly
 *      at startup without touching the network or Cache API.
 */
import { CreateWebWorkerMLCEngine, prebuiltAppConfig } from '@mlc-ai/web-llm';
import type { AppConfig, ModelRecord } from '@mlc-ai/web-llm';
import type { CustomWebLLMModel } from './webllm-helpers';

export type BrowserLLMInitProgress = {
  text: string;
  progress: number;
  error?: string;
};

type StreamChunk = { choices: Array<{ delta: { content: string } }> };

type BrowserLLMEngine = {
  chat: {
    completions: {
      create: (request: Record<string, unknown>) => Promise<AsyncIterable<StreamChunk>>;
    };
  };
  unload?: () => Promise<void>;
  interruptGenerate?: () => Promise<void>;
};

type BrowserModel = {
  id: string;
  model?: string;
  model_lib?: string;
  required_features?: string[];
};

type CacheManifestEntry = {
  model: string;
  loadedAt: number;
  sizeEstimateBytes?: number;
  backend: 'webgpu' | 'wasm';
  dtype: string;
};

const CACHE_NAME = 'transformers-cache';
const CATALOG_DB = 'hyprcandy-browser-llm';
const CATALOG_STORE = 'models';
const MANIFEST_KEY = 'hyprcandy_model_cache_manifest';
const ACTIVE_MODEL_KEY = 'hyprcandy_active_cached_model';

const LEGACY_MODEL_IDS: Record<string, string> = {
  'SmolLM2-360M-Instruct-q4f16_1-MLC': 'onnx-community/SmolLM2-360M-Instruct-ONNX',
  'Qwen2.5-Coder-0.5B-Instruct-q4f16_1-MLC': 'onnx-community/Qwen2.5-Coder-0.5B-Instruct',
  'Qwen2.5-Coder-1.5B-Instruct-q4f16_1-MLC': 'onnx-community/Qwen2.5-Coder-1.5B-Instruct',
  'Qwen2.5-0.5B-Instruct-q4f16_1-MLC': 'onnx-community/Qwen2.5-0.5B-Instruct',
  'Llama-3.2-1B-Instruct-q4f16_1-MLC': 'onnx-community/Llama-3.2-1B-Instruct-ONNX',
};

const LLAMA_STOP_TOKENS = ['<|end_of_text|>', '<|eot_id|>', '</s>', '<|im_end|>', '<|finetune_right_pad_id|>'];
const DEFAULT_STOP_TOKENS = ['</s>', '<|endoftext|>', '<|end_of_text|>'];

const listeners = new Set<(report: BrowserLLMInitProgress) => void>();
const fileProgress = new Map<string, number>();

function emitProgress(report: BrowserLLMInitProgress) {
  listeners.forEach((listener) => {
    try {
      listener(report);
    } catch (error) {
      console.error('[Transformers.js] progress listener failed', error);
    }
  });
}

function progressFromTransformersEvent(event: any): BrowserLLMInitProgress {
  const status = String(event?.status || 'Loading model');
  const hasProgress = typeof event?.progress === 'number'
    || (typeof event?.loaded === 'number' && typeof event?.total === 'number' && event.total > 0)
    || event?.status === 'done';
  const currentProgress = event?.status === 'done'
    ? 1
    : typeof event?.progress === 'number'
    ? event.progress / (event.progress > 1 ? 100 : 1)
    : typeof event?.loaded === 'number' && typeof event?.total === 'number' && event.total > 0
      ? event.loaded / event.total
      : 0;
  const file = event?.file ? ` ${String(event.file).split('/').pop()}` : '';
  const fileKey = String(event?.file || event?.name || status);
  if (hasProgress) fileProgress.set(fileKey, Math.max(0, Math.min(1, currentProgress)));
  const progress = fileProgress.size
    ? Array.from(fileProgress.values()).reduce((sum, value) => sum + value, 0) / fileProgress.size
    : currentProgress;
  return {
    text: `${status}${file}`,
    progress: Math.max(0, Math.min(1, progress)),
  };
}

function isElectronRenderer(): boolean {
  return typeof window !== 'undefined' && Boolean((window as any).__hyprcandyElectronAgent);
}

function hasDiskWeightBridge(): boolean {
  return isElectronRenderer() && Boolean((window as any).__hyprcandyWeights);
}

/**
 * Backs `env.customCache` with real files on disk (via the Electron main
 * process, see electron/main.cjs + preload.cjs) instead of the browser's
 * Cache Storage API. Cache Storage entries are "best-effort" and can be
 * silently evicted by Chromium under disk pressure unless the page has been
 * granted persistent storage — which is exactly what made multi-GB model
 * weights appear to "reinstall from Hugging Face" on a later launch even
 * though they were technically "cached" moments earlier. Real files under
 * ~/.local/share/hyprcandy/weights are not subject to that eviction.
 */
function createElectronDiskCache(modelId: string) {
  const bridge = (window as any).__hyprcandyWeights;
  return {
    async match(key: string | Request): Promise<Response | undefined> {
      const url = typeof key === 'string' ? key : key.url;
      try {
        const result = await bridge.match(url);
        if (!result?.found) return undefined;
        return new Response(result.buffer, { headers: result.headers });
      } catch (error) {
        console.warn('[Transformers.js] disk cache match failed', error);
        return undefined;
      }
    },
    async put(key: string | Request, response: Response): Promise<void> {
      const url = typeof key === 'string' ? key : key.url;
      try {
        const headers: Record<string, string> = {};
        response.headers.forEach((value, name) => { headers[name] = value; });
        const buffer = await response.clone().arrayBuffer();
        await bridge.put(modelId, url, buffer, headers);
      } catch (error) {
        console.warn('[Transformers.js] disk cache put failed', error);
      }
    },
  };
}

/**
 * Best-effort: ask the browser to promote our origin's storage (used by the
 * Cache Storage API fallback path below) to "persistent", exempting it from
 * automatic eviction under disk pressure. This matters most on the WebKitGTK
 * fallback path, which has no Electron main process / disk bridge available.
 */
async function requestPersistentStorage(): Promise<void> {
  try {
    if (typeof navigator !== 'undefined' && (navigator as any).storage?.persist) {
      const granted = await (navigator as any).storage.persist();
      if (!granted) {
        console.warn('[Transformers.js] Persistent storage was not granted; cached model weights may be silently evicted under disk pressure.');
      }
    }
  } catch (_) { /* not available in this environment - safe to ignore */ }
}

function readManifest(): Record<string, CacheManifestEntry> {
  try {
    const raw = localStorage.getItem(MANIFEST_KEY);
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

function writeManifest(manifest: Record<string, CacheManifestEntry>): void {
  try {
    localStorage.setItem(MANIFEST_KEY, JSON.stringify(manifest));
  } catch (_) { /* localStorage full / disabled – safe to ignore */ }
}

function touchManifestEntry(model: string, backend: 'webgpu' | 'wasm', dtype: string): void {
  const manifest = readManifest();
  manifest[model] = {
    model,
    loadedAt: Date.now(),
    backend,
    dtype,
  };
  writeManifest(manifest);
  try { localStorage.setItem(ACTIVE_MODEL_KEY, model); } catch (_) {}
}

function getPreviouslyActiveModel(): string | null {
  try { return localStorage.getItem(ACTIVE_MODEL_KEY); } catch { return null; }
}

function listManifestCachedIds(): string[] {
  return Object.keys(readManifest());
}

function isLlamaFamily(resolvedModel: string): boolean {
  return /llama/i.test(resolvedModel);
}

function resolveStopTokens(resolvedModel: string): string[] {
  if (isLlamaFamily(resolvedModel)) return LLAMA_STOP_TOKENS;
  return DEFAULT_STOP_TOKENS;
}

function formatMessages(messages: Array<{ role: string; content: string }>, resolvedModel: string): string {
  if (isLlamaFamily(resolvedModel)) {
    return messages
      .map((m) => {
        const role = m.role === 'assistant' ? 'assistant' : m.role === 'system' ? 'system' : 'user';
        return `<|start_header_id|>${role}<|end_header_id|>\n\n${m.content}<|eot_id|>`;
      })
      .join('') + '<|start_header_id|>assistant<|end_header_id|>\n\n';
  }
  return messages
    .map((message) => `${message.role.toUpperCase()}:\n${message.content}`)
    .join('\n\n') + '\n\nASSISTANT:\n';
}

function openCatalog(): Promise<IDBDatabase | null> {
  if (typeof indexedDB === 'undefined') return Promise.resolve(null);
  return new Promise((resolve) => {
    try {
      const request = indexedDB.open(CATALOG_DB, 1);
      request.onupgradeneeded = () => {
        request.result.createObjectStore(CATALOG_STORE, { keyPath: 'id' });
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => resolve(null);
    } catch {
      resolve(null);
    }
  });
}

async function setCatalogModel(id: string): Promise<void> {
  const db = await openCatalog();
  if (!db) return;
  await new Promise<void>((resolve) => {
    const transaction = db.transaction(CATALOG_STORE, 'readwrite');
    transaction.objectStore(CATALOG_STORE).put({ id, loadedAt: Date.now() });
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => resolve();
  });
  db.close();
}

async function getCatalogModels(): Promise<string[]> {
  const db = await openCatalog();
  if (!db) return [];
  return new Promise((resolve) => {
    const request = db.transaction(CATALOG_STORE, 'readonly').objectStore(CATALOG_STORE).getAllKeys();
    request.onsuccess = () => {
      db.close();
      resolve(request.result.map(String));
    };
    request.onerror = () => {
      db.close();
      resolve([]);
    };
  });
}

async function deleteCatalog(): Promise<void> {
  if (typeof indexedDB === 'undefined') return;
  await new Promise<void>((resolve) => {
    const request = indexedDB.deleteDatabase(CATALOG_DB);
    request.onsuccess = request.onerror = request.onblocked = () => resolve();
  });
}

export class BrowserLLMService {
  private engine: BrowserLLMEngine | null = null;
  private loadedModel: string | null = null;
  private loadingModel: string | null = null;
  private loadPromise: Promise<BrowserLLMEngine> | null = null;
  private lastProgress: BrowserLLMInitProgress = { text: 'Idle', progress: 0 };
  private customModels: BrowserModel[] = [];
  private generationController: AbortController | null = null;

  setCustomModels(models: BrowserModel[]) {
    this.customModels = models
      .filter((model) => model?.id?.trim())
      .map((model) => ({ ...model, id: model.id.trim(), model: model.model?.trim() }));
  }

  onProgress(listener: (report: BrowserLLMInitProgress) => void): () => void {
    listeners.add(listener);
    listener(this.lastProgress);
    return () => listeners.delete(listener);
  }

  getProgress(): BrowserLLMInitProgress {
    return this.lastProgress;
  }

  getLoadedModel(): string | null {
    return this.loadedModel;
  }

  getEngine(): BrowserLLMEngine | null {
    return this.engine;
  }

  private resolveModel(modelId?: string): string {
    const custom = this.customModels.find((model) => model.id === modelId);
    return custom?.model_lib ? custom.id
      : custom?.model
      || LEGACY_MODEL_IDS[modelId || '']
      || modelId
      || this.customModels[0]?.model
      || 'onnx-community/SmolLM2-360M-Instruct-ONNX';
  }

  isReady(modelId?: string): boolean {
    return Boolean(this.engine && (!modelId || this.loadedModel === this.resolveModel(modelId)));
  }

  getPreviouslyActiveCachedModel(): string | null {
    const active = getPreviouslyActiveModel();
    if (!active) return null;
    const manifest = readManifest();
    if (manifest[active]) return active;
    return null;
  }

  async isModelCached(modelId: string): Promise<boolean> {
    const resolved = this.resolveModel(modelId);
    if (readManifest()[resolved]) return true;
    if ((await getCatalogModels()).includes(resolved)) return true;
    if (hasDiskWeightBridge()) {
      try {
        const result = await (window as any).__hyprcandyWeights.hasModel(resolved);
        if (result?.cached) return true;
      } catch (_) { /* fall through to Cache Storage check */ }
    }
    if (typeof caches === 'undefined') return false;
    try {
      const cache = await caches.open(CACHE_NAME);
      const keys = await cache.keys();
      const encoded = resolved.replaceAll('/', '%2F');
      return keys.some((request) => request.url.includes(resolved) || request.url.includes(encoded));
    } catch {
      return false;
    }
  }

  listManifestCachedModelIds(candidateIds: string[]): string[] {
    const manifest = readManifest();
    const manifestIds = Object.keys(manifest);
    if (candidateIds.length === 0) return manifestIds;
    const candidateSet = new Set(candidateIds.map((id) => this.resolveModel(id)));
    return manifestIds.filter((id) => candidateSet.has(id));
  }

  classifyManifestCachedModelIds(candidateIds: string[]): { manifest: string[]; toCheck: string[] } {
    const manifestData = readManifest();
    const manifestIds = Object.keys(manifestData);
    if (candidateIds.length === 0) {
      return { manifest: manifestIds, toCheck: [] };
    }
    const resolvedMap = new Map<string, string>();
    for (const id of candidateIds) {
      resolvedMap.set(this.resolveModel(id), id);
    }
    const resolvedSet = new Set(resolvedMap.keys());
    const manifestMatches: string[] = [];
    const manifestResolved = new Set<string>();
    for (const mid of manifestIds) {
      if (resolvedSet.has(mid)) {
        manifestResolved.add(mid);
        const original = resolvedMap.get(mid);
        if (original) manifestMatches.push(original);
      }
    }
    const toCheck = candidateIds.filter((id) => !manifestResolved.has(this.resolveModel(id)));
    return { manifest: manifestMatches, toCheck };
  }

  async deleteModelCache(modelId: string): Promise<void> {
    const resolved = this.resolveModel(modelId);
    if (this.loadedModel === resolved) await this.unload();
    if (hasDiskWeightBridge()) {
      try { await (window as any).__hyprcandyWeights.removeModel(resolved); } catch (_) {}
    }
    if (typeof caches !== 'undefined') {
      try {
        const cache = await caches.open(CACHE_NAME);
        const keys = await cache.keys();
        await Promise.all(keys
          .filter((request) => request.url.includes(resolved) || request.url.includes(resolved.replaceAll('/', '%2F')))
          .map((request) => cache.delete(request)));
      } catch (error) {
        console.warn('[Transformers.js] failed to remove model cache', error);
      }
    }
    const manifest = readManifest();
    delete manifest[resolved];
    writeManifest(manifest);
    try {
      if (localStorage.getItem(ACTIVE_MODEL_KEY) === resolved) {
        localStorage.removeItem(ACTIVE_MODEL_KEY);
      }
    } catch (_) {}
    await deleteCatalog();
  }

  async clearCache(): Promise<void> {
    await this.unload();
    if (hasDiskWeightBridge()) {
      try { await (window as any).__hyprcandyWeights.clearAll(); } catch (_) {}
    }
    if (typeof caches !== 'undefined') {
      try { await caches.delete(CACHE_NAME); } catch {}
    }
    try {
      localStorage.removeItem(MANIFEST_KEY);
      localStorage.removeItem(ACTIVE_MODEL_KEY);
    } catch (_) {}
    await deleteCatalog();
  }

  interrupt() {
    this.generationController?.abort();
    this.generationController = null;
    try { void this.engine?.interruptGenerate?.(); } catch {}
  }

  async unload() {
    const engine = this.engine;
    this.engine = null;
    this.loadedModel = null;
    this.loadingModel = null;
    this.loadPromise = null;
    this.interrupt();
    try { await engine?.unload?.(); } catch {}
    this.lastProgress = { text: 'Unloaded', progress: 0 };
    emitProgress(this.lastProgress);
  }

  private async createEngine(modelId: string): Promise<BrowserLLMEngine> {
    const custom = this.customModels.find((model) => model.id === modelId);
    if (custom && !custom.model_lib) return this.createTransformersEngine(custom.model || modelId);
    try {
      return await this.createWebLLMEngine(modelId);
    } catch (error) {
      console.warn('[WebLLM] Native MLC engine unavailable; falling back to Transformers.js', error);
      return this.createTransformersEngine(modelId);
    }
  }

  private async createWebLLMEngine(modelId: string): Promise<BrowserLLMEngine> {
    const custom = this.customModels.find((model) => model.id === modelId);
    const modelRecords: ModelRecord[] = [
      ...prebuiltAppConfig.model_list,
      ...(custom ? [{
        model: custom.model!,
        model_id: custom.id,
        model_lib: custom.model_lib!,
        required_features: custom.required_features,
      }] : []),
    ];
    const appConfig: AppConfig = {
      model_list: modelRecords.filter((record, index, all) => all.findIndex((item) => item.model_id === record.model_id) === index),
      cacheBackend: 'cache',
    };
    const worker = new Worker(new URL('./webllm.worker.ts', import.meta.url), { type: 'module' });
    const engine = await CreateWebWorkerMLCEngine(worker, modelId, {
      appConfig,
      initProgressCallback: (report: any) => {
        const progress = typeof report?.progress === 'number' ? report.progress : 0;
        const text = String(report?.text || report?.status || 'Loading WebLLM model…');
        this.lastProgress = { text, progress };
        emitProgress(this.lastProgress);
      },
    } as any);
    return {
      chat: {
        completions: {
          create: (request) => engine.chat.completions.create(request as any) as unknown as Promise<AsyncIterable<StreamChunk>>,
        },
      },
      interruptGenerate: async () => { engine.interruptGenerate(); },
      unload: async () => { await engine.unload(); worker.terminate(); },
    };
  }

  private async createTransformersEngine(modelId: string): Promise<BrowserLLMEngine> {
    return this.createWorkerEngine(modelId);
  }

  private async createWorkerEngine(modelId: string): Promise<BrowserLLMEngine> {
    const worker = new Worker(new URL('./transformers.worker.ts', import.meta.url), { type: 'module' });
    const useWebGPU = Boolean(typeof navigator !== 'undefined' && (navigator as any).gpu);
    let loadedResolve: (() => void) | null = null;
    let loadedReject: ((error: Error) => void) | null = null;
    const progressByFile = new Map<string, number>();
    const pending = new Map<string, {
      chunks: string[];
      waiters: Array<{ resolve: (result: IteratorResult<StreamChunk>) => void; reject: (error: Error) => void }>;
      finished: boolean;
      failure: Error | null;
    }>();

    const finishRequest = (requestId: string, error?: Error) => {
      const state = pending.get(requestId);
      if (!state) return;
      state.finished = true;
      state.failure = error || state.failure;
      while (state.waiters.length) {
        const waiter = state.waiters.shift()!;
        if (state.failure) waiter.reject(state.failure);
        else waiter.resolve({ value: undefined, done: true });
      }
    };

    worker.onmessage = (event: MessageEvent<any>) => {
      const message = event.data || {};
      if (message.type === 'cache-request') {
        void (async () => {
          try {
            if (!hasDiskWeightBridge()) {
              worker.postMessage({ type: 'cache-response', requestId: message.requestId, found: false });
              return;
            }
            const cache = createElectronDiskCache(modelId);
            if (message.op === 'match') {
              const response = await cache.match(message.url);
              if (!response) {
                worker.postMessage({ type: 'cache-response', requestId: message.requestId, found: false });
                return;
              }
              const buffer = await response.arrayBuffer();
              const headers: Record<string, string> = {};
              response.headers.forEach((value, name) => { headers[name] = value; });
              worker.postMessage({ type: 'cache-response', requestId: message.requestId, found: true, buffer, headers }, [buffer]);
            } else {
              await cache.put(message.url, new Response(message.buffer, { headers: message.headers || {} }));
              worker.postMessage({ type: 'cache-response', requestId: message.requestId, found: true });
            }
          } catch (error: any) {
            worker.postMessage({ type: 'cache-response', requestId: message.requestId, found: false, error: error?.message || String(error) });
          }
        })();
        return;
      }
      if (message.type === 'progress') {
        const key = String(message.text || 'model');
        progressByFile.set(key, Number(message.progress) || 0);
        const progress = Array.from(progressByFile.values()).reduce((sum, value) => sum + value, 0) / Math.max(1, progressByFile.size);
        this.lastProgress = { text: message.text || 'Loading model…', progress };
        emitProgress(this.lastProgress);
      } else if (message.type === 'loaded') {
        loadedResolve?.();
        loadedResolve = null;
        loadedReject = null;
      } else if (message.type === 'error') {
        const error = new Error(message.message || 'Transformers.js worker error');
        if (loadedReject) loadedReject(error);
        loadedResolve = null;
        loadedReject = null;
        if (message.requestId) finishRequest(message.requestId, error);
      } else if (message.type === 'token') {
        const state = pending.get(message.requestId);
        if (!state) return;
        const chunk = { choices: [{ delta: { content: message.text || '' } }] };
        const waiter = state.waiters.shift();
        if (waiter) waiter.resolve({ value: chunk, done: false });
        else state.chunks.push(message.text || '');
      } else if (message.type === 'done' && message.requestId) {
        finishRequest(message.requestId);
      }
    };

    const loadPromise = new Promise<void>((resolve, reject) => {
      loadedResolve = resolve;
      loadedReject = reject;
      worker.postMessage({ type: 'load', modelId, useWebGPU, useDiskCache: hasDiskWeightBridge() });
    });
    await loadPromise;

    return {
      chat: {
        completions: {
          create: async (request: Record<string, unknown>) => {
            const requestId = `generation_${Date.now()}_${Math.random().toString(36).slice(2)}`;
            pending.set(requestId, { chunks: [], waiters: [], finished: false, failure: null });
            worker.postMessage({
              type: 'generate',
              requestId,
              modelId,
              messages: (request.messages || []) as Array<{ role: string; content: string }>,
              maxTokens: Number(request.max_tokens || 1024),
              temperature: Number(request.temperature ?? 0.7),
            });
            const state = pending.get(requestId)!;
            return {
              [Symbol.asyncIterator]: () => ({
                next: (): Promise<IteratorResult<StreamChunk>> => {
                  if (state.chunks.length) return Promise.resolve({ value: { choices: [{ delta: { content: state.chunks.shift()! } }] }, done: false });
                  if (state.failure) return Promise.reject(state.failure);
                  if (state.finished) {
                    pending.delete(requestId);
                    return Promise.resolve({ value: undefined, done: true });
                  }
                  return new Promise((resolve, reject) => state.waiters.push({ resolve, reject }));
                },
              }),
            };
          },
        },
      },
      interruptGenerate: async () => { worker.postMessage({ type: 'interrupt' }); },
      unload: async () => {
        worker.postMessage({ type: 'unload' });
        worker.terminate();
      },
    } as BrowserLLMEngine;
  }

  private async createLegacyMainThreadEngine(modelId: string): Promise<BrowserLLMEngine> {
    fileProgress.clear();
    const transformers = await import('@huggingface/transformers');
    const { pipeline, TextStreamer, env } = transformers;
    env.allowRemoteModels = true;
    env.allowLocalModels = false;

    if (hasDiskWeightBridge()) {
      // Electron: persist weights as real files on the user's physical disk.
      env.useBrowserCache = false;
      (env as any).useCustomCache = true;
      (env as any).customCache = createElectronDiskCache(modelId);
    } else {
      // WebKitGTK / plain browser fallback: best we can do is the browser's
      // own Cache Storage, upgraded to "persistent" where possible.
      env.useBrowserCache = true;
      await requestPersistentStorage();
    }

    const adapter = typeof navigator !== 'undefined' && (navigator as any).gpu
      && typeof (navigator as any).gpu.requestAdapter === 'function'
      ? await (navigator as any).gpu.requestAdapter({ powerPreference: 'high-performance' }).catch(() => null)
      : null;
    const useWebGPU = Boolean(adapter);
    let device: 'webgpu' | 'wasm' = useWebGPU ? 'webgpu' : 'wasm';
    let dtype: string = useWebGPU ? 'q4' : 'q8';
    this.lastProgress = { text: `Loading ${modelId} (${device})…`, progress: 0 };
    emitProgress(this.lastProgress);

    let generator: any;
    try {
      generator = await pipeline('text-generation', modelId, {
        device,
        dtype,
        progress_callback: (event: any) => {
          this.lastProgress = progressFromTransformersEvent(event);
          emitProgress(this.lastProgress);
        },
      } as any);
    } catch (error) {
      if (!useWebGPU) throw error;
      console.warn('[Transformers.js] WebGPU initialization failed; retrying WASM', error);
      device = 'wasm';
      dtype = 'q8';
      this.lastProgress = { text: `Loading ${modelId} (wasm fallback)…`, progress: 0 };
      emitProgress(this.lastProgress);
      generator = await pipeline('text-generation', modelId, {
        device: 'wasm',
        dtype: 'q8',
        progress_callback: (event: any) => {
          this.lastProgress = progressFromTransformersEvent(event);
          emitProgress(this.lastProgress);
        },
      } as any);
    }

    await setCatalogModel(modelId);
    touchManifestEntry(modelId, device, dtype);
    return {
      chat: {
        completions: {
          create: (request) => this.createCompletion(generator, TextStreamer, request, modelId),
        },
      },
      unload: async () => {
        try { await generator.dispose?.(); } catch {}
      },
    };
  }

  private async createCompletion(
    generator: any,
    TextStreamer: any,
    request: Record<string, unknown>,
    resolvedModelId: string,
  ): Promise<AsyncIterable<StreamChunk>> {
    const messages = (request.messages || []) as Array<{ role: string; content: string }>;
    const tokenizer = generator.tokenizer;
    const stopTokens = resolveStopTokens(resolvedModelId);

    let prompt = formatMessages(messages, resolvedModelId);
    if (tokenizer?.apply_chat_template && !isLlamaFamily(resolvedModelId)) {
      try {
        const tpl = tokenizer.apply_chat_template(messages, { tokenize: false, add_generation_prompt: true });
        if (typeof tpl === 'string' && tpl.trim().length > 0) {
          prompt = tpl;
        }
      } catch {
        // fall back to formatMessages result
      }
    }

    const chunks: string[] = [];
    const waiters: Array<(result: IteratorResult<StreamChunk>) => void> = [];
    let finished = false;
    let failure: unknown = null;
    let accumulatedText = '';
    let lastTokenAt = Date.now();
    let totalPushed = 0;
    let stuckWatchdog: number | undefined;
    let endedViaStop = false;

    const stripStopTokens = (text: string): { clean: string; matched: boolean } => {
      let clean = text;
      let matched = false;
      for (const stop of stopTokens) {
        const idx = clean.indexOf(stop);
        if (idx !== -1) {
          clean = clean.substring(0, idx);
          matched = true;
        }
      }
      if (/<\|[a-z_]+\|>/i.test(clean)) {
        const re = /<\|[a-z_]+\|>/i;
        const idx = clean.search(re);
        if (idx !== -1) {
          clean = clean.substring(0, idx);
          matched = true;
        }
      }
      return { clean, matched };
    };

    const push = (rawText: string) => {
      if (!rawText) return;
      accumulatedText += rawText;
      const { clean, matched } = stripStopTokens(accumulatedText);
      lastTokenAt = Date.now();

      const toEmit = clean.substring(totalPushed);
      if (toEmit) {
        totalPushed = clean.length;
        const chunk = { choices: [{ delta: { content: toEmit } }] };
        const waiter = waiters.shift();
        if (waiter) waiter({ value: chunk, done: false });
        else chunks.push(toEmit);
      }
      if (matched) {
        endedViaStop = true;
        if (stuckWatchdog !== undefined) window.clearTimeout(stuckWatchdog);
        finish();
      }
    };
    const finish = () => {
      if (finished) return;
      finished = true;
      if (stuckWatchdog !== undefined) window.clearTimeout(stuckWatchdog);
      while (waiters.length) waiters.shift()!({ value: undefined, done: true });
    };

    this.generationController = new AbortController();
    const run = (async () => {
      try {
        const streamer = tokenizer && TextStreamer
          ? new TextStreamer(tokenizer, { skip_prompt: true, callback_function: push })
          : undefined;

        stuckWatchdog = window.setInterval(() => {
          if (finished) return;
          const idle = Date.now() - lastTokenAt;
          if (totalPushed === 0 && idle > 30_000) {
            const err = new Error('Model failed to produce output within 30s.');
            if (stuckWatchdog !== undefined) window.clearInterval(stuckWatchdog);
            this.generationController?.abort();
            failure = err;
            finish();
            return;
          }
          if (totalPushed > 0 && idle > 45_000) {
            if (stuckWatchdog !== undefined) window.clearInterval(stuckWatchdog);
            this.generationController?.abort();
            finish();
            return;
          }
        }, 2000);

        const genArgs: any = {
          streamer,
          max_new_tokens: Number(request.max_tokens || 1024),
          temperature: Number(request.temperature ?? 0.7),
          top_p: 0.92,
          top_k: 50,
          do_sample: true,
          return_full_text: false,
          stop_strings: stopTokens,
          pad_token_id: tokenizer?.eos_token_id ?? tokenizer?.pad_token_id ?? 0,
          signal: this.generationController?.signal,
        };

        const generation = generator(prompt, genArgs);
        let timeoutId: number | undefined;
        const timeout = new Promise<never>((_, reject) => {
          timeoutId = window.setTimeout(() => {
            this.generationController?.abort();
            reject(new Error('Model generation timed out after 300 seconds.'));
          }, 300_000);
        });
        const output = await Promise.race([generation, timeout]);
        if (timeoutId !== undefined) window.clearTimeout(timeoutId);

        if (!streamer) {
          const generated = Array.isArray(output) ? output[0]?.generated_text : output?.generated_text;
          if (typeof generated === 'string' && generated.length > 0) {
            push(generated);
          }
        }

        if (!endedViaStop && totalPushed === 0 && !failure) {
          try {
            const genArgsRetry: any = {
              max_new_tokens: Number(request.max_tokens || 1024),
              temperature: 0.8,
              top_p: 0.95,
              top_k: 80,
              do_sample: true,
              return_full_text: false,
              pad_token_id: tokenizer?.eos_token_id ?? tokenizer?.pad_token_id ?? 0,
              signal: this.generationController?.signal,
            };
            const retryOut = await generator(prompt, genArgsRetry);
            const retryText = Array.isArray(retryOut) ? retryOut[0]?.generated_text : retryOut?.generated_text;
            if (typeof retryText === 'string' && retryText.length > 0) push(retryText);
          } catch (_retryErr) {
            // retry failed – silently accept empty output
          }
        }
      } catch (error) {
        if ((error as any)?.name !== 'AbortError') {
          failure = error;
        }
      } finally {
        this.generationController = null;
        finish();
      }
    })();
    void run;

    return {
      [Symbol.asyncIterator]: () => ({
        next: (): Promise<IteratorResult<StreamChunk>> => {
          if (chunks.length) return Promise.resolve({ value: { choices: [{ delta: { content: chunks.shift()! } }] }, done: false });
          if (failure) return Promise.reject(failure);
          if (finished) return Promise.resolve({ value: undefined, done: true });
          return new Promise((resolve) => waiters.push(resolve));
        },
      }),
    };
  }

  async ensureEngine(modelId?: string): Promise<BrowserLLMEngine> {
    const resolved = this.resolveModel(modelId);
    if (this.engine && this.loadedModel === resolved) return this.engine;
    if (this.loadPromise && this.loadingModel === resolved) return this.loadPromise;
    if (this.engine) await this.unload();

    this.loadingModel = resolved;
    this.loadPromise = this.createEngine(resolved)
      .then((engine) => {
        this.engine = engine;
        this.loadedModel = resolved;
        this.loadingModel = null;
        this.lastProgress = { text: 'Ready', progress: 1 };
        emitProgress(this.lastProgress);
        return engine;
      })
      .catch((error) => {
        this.loadingModel = null;
        this.loadPromise = null;
        const message = error instanceof Error ? error.message : String(error);
        this.lastProgress = { text: message, progress: 0, error: message };
        emitProgress(this.lastProgress);
        throw error;
      });
    return this.loadPromise;
  }
}

export const browserLLMService = new BrowserLLMService();
