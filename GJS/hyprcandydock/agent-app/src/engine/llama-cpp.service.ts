import { bridge as hostBridge } from '../bridge';

export type LlamaModel = { id: string; repo: string; file: string };
export type LlamaProgress = { loaded?: number; total?: number; text?: string };

type LlamaBridge = {
  enabled?: boolean;
  catalog: () => Promise<LlamaModel[]>;
  search: (query: string) => Promise<Array<{ id: string; downloads?: number; likes?: number }>>;
  inspect: (repo: string) => Promise<{ repo: string; files: string[] }>;
  hasModel: (model: string | { id: string; repo: string; file: string }) => Promise<boolean>;
  status: () => Promise<any>;
  pull: (model: string | { id: string; repo: string; file: string }) => Promise<any>;
  start: (model: string | { id: string; repo: string; file: string }, options?: { context?: number; maxTokens?: number }) => Promise<any>;
  stop: () => Promise<void>;
};

declare global {
  interface Window { __llamaServer?: LlamaBridge; }
}

export type LlamaChatMessage = { role: 'system' | 'user' | 'assistant' | 'tool'; content: string; tool_call_id?: string; tool_calls?: any[] };
export type LlamaChatOptions = { tools?: any[]; maxTokens?: number };

export class LlamaCppService {
  private loadedModel: string | null = null;
  private transition: Promise<void> = Promise.resolve();
  private activeReader: ReadableStreamDefaultReader<Uint8Array> | null = null;
  private listeners = new Set<(progress: LlamaProgress) => void>();

  constructor() {
    if (typeof window !== 'undefined') {
      window.addEventListener('agent_llama_progress', (event) => {
        const detail = (event as CustomEvent).detail || {};
        this.emit({
          loaded: Number(detail.loaded || 0),
          total: Number(detail.total || 0),
          text: detail.text || 'Downloading model…',
        });
      });
    }
  }

  private get bridge(): LlamaBridge {
    return {
      enabled: true,
      catalog: async () => (await hostBridge.runtimeRequest('/api/models', {}, 'GET'))?.models || [],
      search: async (query) => (await hostBridge.runtimeRequest(`/api/models/search?q=${encodeURIComponent(query)}`, {}, 'GET'))?.models || [],
      inspect: (repo) => hostBridge.runtimeRequest(`/api/models/inspect?repo=${encodeURIComponent(repo)}`, {}, 'GET'),
      hasModel: async (model) => {
        const rows = (await hostBridge.runtimeRequest('/api/models', {}, 'GET'))?.models || [];
        const id = typeof model === 'string' ? model : model.id;
        return rows.some((row: any) => row.id === id || row.filename === id || row.path === id);
      },
      status: () => hostBridge.runtimeRequest('/api/server/status', {}, 'GET'),
      pull: (model) => hostBridge.runtimeRequest('/api/models/pull/start', { url: typeof model === 'string' ? model : `https://huggingface.co/${model.repo}/resolve/main/${model.file}` }),
      start: (model, options) => hostBridge.runtimeRequest('/api/server/start', { model_path: typeof model === 'string' ? model : model.file, ctx_size: options?.context || 0, max_tokens: options?.maxTokens || 2048 }),
      stop: () => hostBridge.runtimeRequest('/api/server/stop'),
    };
  }

  isEnabled(): boolean { return true; }
  async searchModels(query: string) { return this.bridge.search(query); }
  async inspectModel(repo: string) { return this.bridge.inspect(repo); }
  async hasModel(model: string | { id: string; repo: string; file: string }) { return Boolean(await this.bridge.hasModel(model)); }
  getLoadedModel(): string | null { return this.loadedModel; }
  onProgress(listener: (progress: LlamaProgress) => void): () => void { this.listeners.add(listener); return () => this.listeners.delete(listener); }
  private emit(progress: LlamaProgress) { for (const listener of this.listeners) { try { listener(progress); } catch {} } }

  async pull(modelId: string): Promise<any> {
    const result = await this.bridge.pull(modelId);
    this.emit({ text: result.cached ? `${modelId} already downloaded` : `${modelId} downloaded`, loaded: 1, total: 1 });
    return result;
  }

  async ensureModel(modelId: string, spec?: { repo?: string; file?: string }): Promise<void> {
    if (this.loadedModel === modelId) return;
    const operation = this.transition.then(async () => {
      if (this.loadedModel === modelId) return;
      this.emit({ text: `Starting llama-server for ${modelId}…`, loaded: 0, total: 1 });
      const model = spec?.repo && spec?.file ? { id: modelId, repo: spec.repo, file: spec.file } : modelId;
      if (this.loadedModel && this.loadedModel !== modelId) {
        await this.bridge.stop();
        this.loadedModel = null;
      }
      // context: 0 tells llama-server-manager to auto-detect from the
      // model's own GGUF metadata (capped for safety) instead of forcing
      // the same fixed size on every model regardless of how big it is.
      await this.bridge.start(model, { context: 0, maxTokens: 2048 });
      this.loadedModel = modelId;
      this.emit({ text: `Ready: ${modelId}`, loaded: 1, total: 1 });
    });
    this.transition = operation.catch(() => undefined);
    await operation;
  }

  async unload(): Promise<void> {
    const operation = this.transition.then(async () => { await this.bridge.stop(); this.loadedModel = null; });
    this.transition = operation.catch(() => undefined);
    await operation;
  }

  /** Stop the current streamed completion without stopping the cached model. */
  cancelChat(): void {
    const reader = this.activeReader;
    this.activeReader = null;
    if (reader) void reader.cancel().catch(() => undefined);
  }

  async *chat(messages: LlamaChatMessage[], modelId: string, signal?: AbortSignal, options: LlamaChatOptions = {}): AsyncGenerator<{ token?: string; tool_calls?: any[]; finish_reason?: string; done?: boolean }> {
    await this.ensureModel(modelId);
    const response = await fetch('http://127.0.0.1:17843/v1/chat/completions', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      signal,
      body: JSON.stringify({ model: modelId, messages, tools: options.tools, tool_choice: options.tools?.length ? 'auto' : undefined, parallel_tool_calls: true, stream: true, temperature: 0.2, max_tokens: options.maxTokens || 2048 }),
    });
    if (!response.ok || !response.body) {
      // llama-server's response body usually names the real cause (context
      // overflow, bad tool schema, malformed message history) — the
      // previous code discarded it, so every 400 just said "HTTP 400" with
      // no way to diagnose it.
      let detail = '';
      try { detail = (await response.text()).slice(0, 500); } catch {}
      throw new Error(`llama-server chat HTTP ${response.status}${detail ? `: ${detail}` : ''}`);
    }
    const reader = response.body.getReader();
    this.activeReader = reader;
    const decoder = new TextDecoder();
    let buffer = '';
    try {
      while (true) {
        const part = await reader.read();
        if (part.done) break;
        buffer += decoder.decode(part.value, { stream: true });
        const events = buffer.split('\n\n');
        buffer = events.pop() || '';
        for (const event of events) {
          const line = event.split('\n').find((entry) => entry.startsWith('data:'));
          if (!line) continue;
          const data = line.slice(5).trim();
          if (data === '[DONE]') { yield { done: true }; return; }
          try {
            const chunk = JSON.parse(data);
            const delta = chunk?.choices?.[0]?.delta || {};
            if (delta.content) yield { token: delta.content };
            if (delta.tool_calls) yield { tool_calls: delta.tool_calls };
            const finishReason = chunk?.choices?.[0]?.finish_reason;
            if (finishReason) yield { finish_reason: finishReason };
          } catch {}
        }
      }
    } finally {
      if (this.activeReader === reader) this.activeReader = null;
      try { reader.releaseLock(); } catch {}
    }
  }
}

export const llamaCppService = new LlamaCppService();
