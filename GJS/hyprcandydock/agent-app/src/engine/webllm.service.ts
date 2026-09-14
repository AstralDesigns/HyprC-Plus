import { LoggerWithoutDebug, Wllama, type ChatCompletionParams } from '@wllama/wllama';
import wllamaWasmUrl from '@wllama/wllama/esm/wasm/wllama.wasm?url';

export type WebLLMInitProgress = {
  text: string;
  progress: number;
  error?: string;
};

type CompletionsEngine = {
  chat: {
    completions: {
      create: (request: Record<string, unknown>) => Promise<AsyncIterable<any>>;
    };
  };
  unload?: () => Promise<void>;
  interruptGenerate?: () => Promise<void>;
};

type ProgressListener = (report: WebLLMInitProgress) => void;

const WLLAMA_WASM_URL = wllamaWasmUrl;

const DEFAULT_GGUF = {
  // Keep the single GGUF below the browser/WASM addressable-file limit.
  // The 8B Q4 file is ~4.9GB and fails in Wllama with tensor size overflow.
  repo: 'NousResearch/Hermes-3-Llama-3.2-3B-GGUF',
  file: 'Hermes-3-Llama-3.2-3B.Q4_K_M.gguf',
};

const HERMES_2_GGUF = {
  // Hermes 2 Pro 8B Q4 is also above the safe single-file limit. Use the
  // safe Hermes 3B artifact until a sharded-model path is implemented.
  ...DEFAULT_GGUF,
};

// -1 asks llama.cpp/Wllama to offload every eligible layer to WebGPU.
export const WLLAMA_DEFAULT_GPU_LAYERS = -1;
export const WLLAMA_DEFAULT_CONTEXT = 4096;
export const WLLAMA_MODEL_REPO = DEFAULT_GGUF.repo;
export const WLLAMA_MODEL_FILE = DEFAULT_GGUF.file;
export const WLLAMA_MODEL_URL = `https://huggingface.co/${DEFAULT_GGUF.repo}/resolve/main/${encodeURIComponent(DEFAULT_GGUF.file)}?download=true`;

function envNumber(name: string, fallback: number): number {
  try {
    const value = Number((globalThis as any).process?.env?.[name]);
    return Number.isFinite(value) && value >= -1 ? value : fallback;
  } catch {
    return fallback;
  }
}

function downloadProgress(report: any, modelFile: string): WebLLMInitProgress {
  const loaded = Number(report?.loaded || 0);
  const total = Number(report?.total || 0);
  const progress = total > 0 ? Math.max(0, Math.min(1, loaded / total)) : 0;
  const loadedMb = Math.round(loaded / 1024 / 1024);
  const totalMb = total > 0 ? Math.round(total / 1024 / 1024) : '?';
  return {
    progress,
    text: total > 0 ? `Fetching ${modelFile}: ${loadedMb}/${totalMb} MB` : `Fetching ${modelFile}…`,
  };
}

function abortError(message = 'Model operation cancelled'): DOMException {
  return new DOMException(message, 'AbortError');
}

export class WebLLMService {
  private runtime: Wllama | null = null;
  private engine: CompletionsEngine | null = null;
  private loadedModel: string | null = null;
  private loadingModel: string | null = null;
  private loadPromise: Promise<CompletionsEngine> | null = null;
  private loadAbortController: AbortController | null = null;
  private progress: WebLLMInitProgress = { text: 'Idle', progress: 0 };
  private listeners = new Set<ProgressListener>();
  private customModels: any[] = [];
  private lastProgressAt = 0;
  private lastProgressValue = -1;

  // All runtime destruction and construction happens on this tail. Wllama
  // owns WebGPU buffers; overlapping exit()/loadModelFromHF() calls can race
  // mapAsync/destroy and take down the Chromium GPU process.
  private transitionTail: Promise<void> = Promise.resolve();
  private transitionGeneration = 0;

  setCustomModels(models: any[]) { this.customModels = Array.isArray(models) ? models : []; }
  getCustomModels() { return this.customModels; }

  onProgress(listener: ProgressListener): () => void {
    this.listeners.add(listener);
    listener(this.progress);
    return () => this.listeners.delete(listener);
  }

  private emit(report: WebLLMInitProgress) {
    this.progress = report;
    for (const listener of this.listeners) {
      try { listener(report); } catch (error) { console.error('[Wllama] progress listener failed', error); }
    }
  }

  private emitDownloadProgress(report: any, modelFile: string) {
    const next = downloadProgress(report, modelFile);
    const now = Date.now();
    // Do not relay every network chunk through GJS/WebKit: that can starve
    // pointer events during a multi-gigabyte download.
    if (next.progress < 1 && now - this.lastProgressAt < 250 &&
        Math.abs(next.progress - this.lastProgressValue) < 0.01) return;
    this.lastProgressAt = now;
    this.lastProgressValue = next.progress;
    this.emit(next);
  }

  getProgress() { return this.progress; }
  getLoadedModel() { return this.loadedModel; }
  getEngine() { return this.engine; }

  hasWebGPU(): boolean {
    return typeof navigator !== 'undefined' && Boolean((navigator as any).gpu?.requestAdapter);
  }

  async getHardwareInfo(): Promise<{ supported: boolean; f16: boolean; adapterName?: string; error?: string }> {
    try {
      const gpu = (navigator as any)?.gpu;
      if (!gpu?.requestAdapter) return { supported: false, f16: false, error: 'WebGPU is unavailable.' };
      const adapter = await gpu.requestAdapter({ powerPreference: 'high-performance' });
      if (!adapter) return { supported: false, f16: false, error: 'No WebGPU adapter was found.' };
      const info = adapter.info || {};
      return {
        supported: true,
        f16: Boolean(adapter.features?.has?.('shader-f16')),
        adapterName: info.device || info.description || info.architecture || 'WebGPU adapter',
      };
    } catch (error: any) {
      return { supported: false, f16: false, error: error?.message || String(error) };
    }
  }

  isReady(modelId?: string): boolean {
    return Boolean(this.engine && this.loadedModel && (!modelId || modelId === this.loadedModel));
  }

  private modelFor(modelId?: string) {
    const custom = this.customModels.find((model) => model.id === modelId && model.wllamaRepo && model.wllamaFile);
    if (custom) return { repo: custom.wllamaRepo, file: custom.wllamaFile };
    return modelId?.includes('Hermes-2-Pro-Llama-3') ? HERMES_2_GGUF : DEFAULT_GGUF;
  }

  private makeRuntime(): Wllama {
    const runtime = new Wllama(
      { default: WLLAMA_WASM_URL },
      // Cache hits are used automatically; allowOffline=false lets Wllama
      // repair an incomplete cache entry instead of failing permanently.
      { allowOffline: false, parallelDownloads: 2, logger: LoggerWithoutDebug as any }
    );
    // Wllama's constructor enables CDN compatibility mode by default when the
    // browser lacks its feature probe. The Electron worker is Chromium;
    // never silently fetch executable WASM from jsDelivr here.
    runtime.setCompat(null);
    return runtime;
  }

  async isModelCached(modelId?: string): Promise<boolean> {
    try {
      const runtime = this.runtime || this.makeRuntime();
      if (!this.runtime) this.runtime = runtime;
      const model = this.modelFor(modelId);
      const entries = await runtime.cacheManager.list();
      return entries.some((entry) => entry.metadata?.originalURL?.includes(model.file));
    } catch {
      return false;
    }
  }

  async listCachedModelIds(candidateIds: string[]): Promise<string[]> {
    const hits: string[] = [];
    for (const id of Array.from(new Set(candidateIds))) {
      if (await this.isModelCached(id)) hits.push(id);
    }
    return hits;
  }

  async deleteModelCache(modelId: string): Promise<void> {
    // Never delete cache entries while a load/generation-owned runtime is live.
    await this.unload();
    const runtime = this.runtime || this.makeRuntime();
    if (!this.runtime) this.runtime = runtime;
    const model = this.modelFor(modelId);
    await runtime.cacheManager.deleteMany((entry) => entry.metadata?.originalURL?.includes(model.file));
  }

  private async disposeRuntime(): Promise<void> {
    const runtime = this.runtime;
    this.engine = null;
    this.loadedModel = null;
    this.loadingModel = null;
    this.runtime = null;
    if (runtime) {
      try { await runtime.exit(); } catch (error) {
        console.warn('[Wllama] runtime exit failed; continuing with a fresh runtime', error);
      }
    }
  }

  async unload(): Promise<void> {
    const generation = ++this.transitionGeneration;
    this.loadAbortController?.abort();
    this.loadAbortController = null;
    const pending = this.transitionTail;
    await pending.catch(() => undefined);
    // A newer load owns the runtime now; do not tear it down from this stale
    // unload request.
    if (generation !== this.transitionGeneration) return;
    await this.disposeRuntime();
    this.loadPromise = null;
    this.emit({ text: 'Unloaded', progress: 0 });
  }

  private makeEngine(runtime: Wllama): CompletionsEngine {
    return {
      chat: {
        completions: {
          create: (request) => runtime.createChatCompletion(
            request as unknown as ChatCompletionParams & { stream: true }
          ) as Promise<AsyncIterable<any>>,
        },
      },
      unload: () => runtime.exit(),
      interruptGenerate: async () => {
        // Wllama keeps abort internal in V3; abort() is best-effort. The
        // transition queue still prevents exit() from racing active GPU work.
        try { await (runtime as any).abort?.(); } catch {}
      },
    };
  }

  async ensureEngine(modelId?: string): Promise<CompletionsEngine> {
    const requested = modelId || 'Hermes-3-Llama-3.1-8B-q4f16_1-MLC';
    if (this.isReady(requested)) return this.engine as CompletionsEngine;
    if (this.loadPromise && this.loadingModel === requested) return this.loadPromise;

    const generation = ++this.transitionGeneration;
    this.loadAbortController?.abort();
    const previousTransition = this.transitionTail;
    const model = this.modelFor(requested);

    const operation = previousTransition.catch(() => undefined).then(async () => {
      if (generation !== this.transitionGeneration) throw abortError();
      await this.disposeRuntime();
      if (generation !== this.transitionGeneration) throw abortError();

      this.lastProgressAt = 0;
      this.lastProgressValue = -1;
      this.loadingModel = requested;
      this.emit({ text: `Preparing Wllama WebGPU runtime for ${model.file}…`, progress: 0 });
      const runtime = this.makeRuntime();
      this.runtime = runtime;
      const gpuLayers = envNumber('HYPRCANDY_WLLAMA_GPU_LAYERS', WLLAMA_DEFAULT_GPU_LAYERS);
      this.emit({ text: `Resolving GGUF metadata before download…`, progress: 0 });
      const controller = new AbortController();
      this.loadAbortController = controller;
      const signal = controller.signal;
      this.emit({ text: `Loading ${model.file} with full WebGPU offload…`, progress: 0 });
      const loadParams = {
        n_gpu_layers: gpuLayers,
        n_ctx: WLLAMA_DEFAULT_CONTEXT,
        n_batch: 256,
        n_ubatch: 128,
        n_threads: 2,
        jinja: true,
        warmup: false,
        signal,
        progressCallback: (report: any) => this.emitDownloadProgress(report, model.file),
      };

      try {
        try {
          await runtime.loadModelFromHF({ repo: model.repo, file: model.file }, loadParams);
        } catch (firstError: any) {
          const message = firstError?.message || String(firstError);
          // A stopped first download may leave an incomplete OPFS entry. Wllama
          // rejects it on the next startup; remove only this model and retry.
          const recoverable = !signal.aborted && /invalid|cache|open file|not found/i.test(message);
          if (!recoverable) throw firstError;
          console.warn('[Wllama] cached model could not be opened; refreshing cache entry', message);
          await runtime.cacheManager.deleteMany((entry) => entry.metadata?.originalURL?.includes(model.file));
          await runtime.loadModelFromHF({ repo: model.repo, file: model.file }, loadParams);
        }

        if (generation !== this.transitionGeneration || signal.aborted) throw abortError();
        const engine = this.makeEngine(runtime);
        this.engine = engine;
        this.loadedModel = requested;
        this.loadingModel = null;
        this.emit({ text: 'Ready (Wllama WebGPU)', progress: 1 });
        this.loadAbortController = null;
        return engine;
      } catch (error) {
        if (this.runtime === runtime) {
          this.runtime = null;
          this.engine = null;
          this.loadedModel = null;
          this.loadingModel = null;
        }
        this.loadAbortController = null;
        try { await runtime.exit(); } catch {}
        throw error;
      }
    });

    this.loadPromise = operation;
    this.loadingModel = requested;
    this.transitionTail = operation.then(() => undefined, () => undefined);

    try {
      return await operation;
    } catch (error: any) {
      if (this.loadPromise === operation) {
        this.loadPromise = null;
        this.loadingModel = null;
        this.loadAbortController = null;
      }
      if (generation === this.transitionGeneration && error?.name !== 'AbortError') {
        const message = error?.message || 'Wllama model load failed';
        this.emit({ text: message, progress: 0, error: message });
      }
      throw error;
    } finally {
      if (this.loadPromise === operation && this.isReady(requested)) {
        this.loadPromise = null;
      }
    }
  }

  // Invalidate a pending load without destroying the currently loaded model.
  // A subsequent ensureEngine() will perform the actual serialized transition.
  cancelLoading(): void {
    this.transitionGeneration++;
    this.loadAbortController?.abort();
    this.loadAbortController = null;
  }

  interrupt(): void {
    this.loadAbortController?.abort();
    try { void (this.runtime as any)?.abort?.(); } catch {}
  }
}

export const webllmService = new WebLLMService();
export type { CompletionsEngine };
