import { pipeline, TextStreamer, env } from '@huggingface/transformers';

type WorkerRequest =
  | { type: 'load'; modelId: string; useWebGPU: boolean; useDiskCache?: boolean }
  | { type: 'generate'; requestId: string; modelId: string; messages: Array<{ role: string; content: string }>; maxTokens: number; temperature: number }
  | { type: 'interrupt' }
  | { type: 'unload' };

type WorkerResponse =
  | { type: 'progress'; text: string; progress: number; error?: string }
  | { type: 'loaded'; modelId: string; device: string; dtype: string }
  | { type: 'token'; requestId: string; text: string }
  | { type: 'done'; requestId: string }
  | { type: 'error'; requestId?: string; message: string };

let generator: any = null;
let tokenizer: any = null;
let loadedModel: string | null = null;
let generationController: AbortController | null = null;
const fileProgress = new Map<string, number>();
const cacheRequests = new Map<string, (value: any) => void>();
const stopTokens = ['</s>', '<|endoftext|>', '<|end_of_text|>', '<|eot_id|>', '<|im_end|>'];

const post = (message: WorkerResponse) => self.postMessage(message);

function cacheRpc(op: 'match' | 'put', url: string, buffer?: ArrayBuffer, headers?: Record<string, string>): Promise<any> {
  const requestId = `cache_${Date.now()}_${Math.random().toString(36).slice(2)}`;
  return new Promise((resolve) => {
    cacheRequests.set(requestId, resolve);
    const message: any = { type: 'cache-request', requestId, op, url, headers };
    if (buffer) message.buffer = buffer;
    self.postMessage(message, buffer ? [buffer] : []);
  });
}

function emitProgress(event: any) {
  const status = String(event?.status || 'Loading model');
  const key = String(event?.file || event?.name || status);
  const value = event?.status === 'done'
    ? 1
    : typeof event?.progress === 'number'
      ? event.progress / (event.progress > 1 ? 100 : 1)
      : typeof event?.loaded === 'number' && typeof event?.total === 'number' && event.total > 0
        ? event.loaded / event.total
        : 0;
  fileProgress.set(key, Math.max(0, Math.min(1, value)));
  const progress = Array.from(fileProgress.values()).reduce((sum, item) => sum + item, 0) / Math.max(1, fileProgress.size);
  const file = event?.file ? ` ${String(event.file).split('/').pop()}` : '';
  post({ type: 'progress', text: `${status}${file}`, progress });
}

function formatMessages(messages: Array<{ role: string; content: string }>, modelId: string): string {
  if (/llama/i.test(modelId)) {
    return messages.map((message) => {
      const role = message.role === 'assistant' ? 'assistant' : message.role === 'system' ? 'system' : 'user';
      return `<|start_header_id|>${role}<|end_header_id|>\n\n${message.content}<|eot_id|>`;
    }).join('') + '<|start_header_id|>assistant<|end_header_id|>\n\n';
  }
  return messages.map((message) => `${message.role.toUpperCase()}:\n${message.content}`).join('\n\n') + '\n\nASSISTANT:\n';
}

async function loadModel(modelId: string, useWebGPU: boolean, useDiskCache = false) {
  if (generator && loadedModel === modelId) {
    post({ type: 'loaded', modelId, device: useWebGPU ? 'webgpu' : 'wasm', dtype: useWebGPU ? 'q4' : 'q8' });
    return;
  }
  if (generator?.dispose) {
    try { await generator.dispose(); } catch (_) {}
  }
  generator = null;
  tokenizer = null;
  loadedModel = null;
  fileProgress.clear();
  env.allowRemoteModels = true;
  env.allowLocalModels = false;
  env.useBrowserCache = !useDiskCache;
  (env as any).useCustomCache = useDiskCache;
  (env as any).customCache = {
    async match(key: string | Request) {
      const url = typeof key === 'string' ? key : key.url;
      const result = await cacheRpc('match', url);
      if (!result?.found) return undefined;
      return new Response(result.buffer, { headers: result.headers || {} });
    },
    async put(key: string | Request, response: Response) {
      const url = typeof key === 'string' ? key : key.url;
      const copy = await response.clone().arrayBuffer();
      const headers: Record<string, string> = {};
      response.headers.forEach((value, name) => { headers[name] = value; });
      await cacheRpc('put', url, copy, headers);
    },
  };
  let device = useWebGPU ? 'webgpu' : 'wasm';
  let dtype = useWebGPU ? 'q4' : 'q8';
  try {
    generator = await pipeline('text-generation', modelId, {
      device,
      dtype,
      progress_callback: emitProgress,
    } as any);
  } catch (error) {
    if (!useWebGPU) throw error;
    device = 'wasm';
    dtype = 'q8';
    post({ type: 'progress', text: `Loading ${modelId} (wasm fallback)…`, progress: 0 });
    generator = await pipeline('text-generation', modelId, {
      device,
      dtype,
      progress_callback: emitProgress,
    } as any);
  }
  tokenizer = generator.tokenizer;
  loadedModel = modelId;
  post({ type: 'loaded', modelId, device, dtype });
}

async function generate(message: Extract<WorkerRequest, { type: 'generate' }>) {
  if (!generator || loadedModel !== message.modelId) throw new Error('Model is not loaded in the inference worker.');
  generationController = new AbortController();
  const prompt = tokenizer?.apply_chat_template && !/llama/i.test(message.modelId)
    ? tokenizer.apply_chat_template(message.messages, { tokenize: false, add_generation_prompt: true })
    : formatMessages(message.messages, message.modelId);
  let emitted = '';
  const push = (raw: string) => {
    if (!raw) return;
    emitted += raw;
    let clean = emitted;
    for (const stop of stopTokens) {
      const index = clean.indexOf(stop);
      if (index >= 0) clean = clean.slice(0, index);
    }
    const delta = clean.slice((push as any).offset || 0);
    (push as any).offset = clean.length;
    if (delta) post({ type: 'token', requestId: message.requestId, text: delta });
  };
  try {
    const streamer = tokenizer && TextStreamer
      ? new TextStreamer(tokenizer, { skip_prompt: true, callback_function: push })
      : undefined;
    const output = await generator(prompt, {
      streamer,
      max_new_tokens: message.maxTokens,
      temperature: message.temperature,
      top_p: 0.92,
      top_k: 50,
      do_sample: true,
      return_full_text: false,
      stop_strings: stopTokens,
      pad_token_id: tokenizer?.eos_token_id ?? tokenizer?.pad_token_id ?? 0,
      signal: generationController.signal,
    } as any);
    if (!streamer) {
      const text = Array.isArray(output) ? output[0]?.generated_text : output?.generated_text;
      if (typeof text === 'string') push(text);
    }
    post({ type: 'done', requestId: message.requestId });
  } catch (error: any) {
    if (error?.name !== 'AbortError') post({ type: 'error', requestId: message.requestId, message: error?.message || String(error) });
    else post({ type: 'done', requestId: message.requestId });
  } finally {
    generationController = null;
  }
}

self.onmessage = (event: MessageEvent<WorkerRequest>) => {
  const message: any = event.data;
  if (message?.type === 'cache-response') {
    const resolve = cacheRequests.get(message.requestId);
    if (resolve) {
      cacheRequests.delete(message.requestId);
      resolve(message);
    }
    return;
  }
  void (async () => {
    try {
      if (message.type === 'load') await loadModel(message.modelId, message.useWebGPU, message.useDiskCache);
      else if (message.type === 'generate') await generate(message);
      else if (message.type === 'interrupt') generationController?.abort();
      else if (message.type === 'unload') {
        generationController?.abort();
        try { await generator?.dispose?.(); } catch (_) {}
        generator = null;
        tokenizer = null;
        loadedModel = null;
      }
    } catch (error: any) {
      post({ type: 'error', message: error?.message || String(error) });
    }
  })();
};
