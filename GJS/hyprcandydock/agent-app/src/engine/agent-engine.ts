/**
 * Agent Engine: standalone WebLLM/WebGPU inference and function-calling orchestrator.
 *
 * This file intentionally owns the launcher process only. It consumes the local
 * WebLLM service and never imports or calls CandyCode at runtime.
 */
import type { ChatCompletionMessageParam } from '@mlc-ai/web-llm';
import { AGENT_SYSTEM_PROMPT, AGENT_TOOLS } from './tools';
import { bridge, isElectronMode } from '../bridge';
import {
  getStore,
  PRESET_MODELS,
  setStore,
  storeActions,
  DiffData,
  CommandData,
  ToolCallData,
  PlanTask,
  AttachmentData,
} from '../store';
import { webllmService, type WebLLMInitProgress } from './webllm.service';
import { shouldUseNativeWebLLMTools } from './webllm-helpers';
import { llamaCppService } from './llama-cpp.service';

export interface ProgressCallback {
  (report: WebLLMInitProgress): void;
}

export interface WebGPUAdapterInfo {
  name: string;
  vendor?: string;
  architecture?: string;
  device?: string;
  isFallback: boolean;
  powerPreference: 'high-performance' | 'low-power' | 'default' | 'fallback';
  f16: boolean;
}

export interface WebGPUInfo {
  supported: boolean;
  f16: boolean;
  adapterName?: string;
  backend?: 'webgpu';
  adapters?: WebGPUAdapterInfo[];
  error?: string;
}

function createStreamUpdateScheduler(update: (content: string, tools?: ToolCallData[]) => void, intervalMs = 80) {
  let pending: { content: string; tools?: ToolCallData[] } | null = null;
  let timer: ReturnType<typeof setTimeout> | null = null;
  const flush = () => {
    if (timer !== null) {
      clearTimeout(timer);
      timer = null;
    }
    if (!pending) return;
    const next = pending;
    pending = null;
    update(next.content, next.tools);
  };
  const schedule = (content: string, tools?: ToolCallData[]) => {
    pending = { content, tools };
    if (timer === null) timer = setTimeout(flush, intervalMs);
  };
  return { schedule, flush, cancel: () => { pending = null; if (timer !== null) clearTimeout(timer); timer = null; } };
}

function createTokenScheduler(emit: (token: string) => void) {
  const TOKEN_UPDATE_INTERVAL_MS = 80;
  let pending = '';
  let timer: ReturnType<typeof setTimeout> | null = null;
  const flush = () => {
    if (timer !== null) {
      clearTimeout(timer);
      timer = null;
    }
    if (!pending) return;
    const next = pending;
    pending = '';
    emit(next);
  };
  const schedule = (token: string) => {
    pending += token;
    if (timer === null) timer = setTimeout(flush, TOKEN_UPDATE_INTERVAL_MS);
  };
  return { schedule, flush, cancel: () => { pending = ''; if (timer !== null) clearTimeout(timer); timer = null; } };
}

export class AgentEngine {
  private abortController: AbortController | null = null;
  private currentModelId: string | null = null;
  private isInitializing = false;
  private activeLoadModelId: string | null = null;
  private cancelActiveLoad: (() => void) | null = null;
  private activeBackend: 'webgpu' | 'wasm' = 'wasm';
  private modelRequestGeneration = 0;
  private conversationGeneration = 0;
  private activeConversationSettled: Promise<void> | null = null;

  constructor() {
    this.syncCustomModels();
    // The WebLLM service is the single source of truth for loading progress.
    // Keeping this subscription in the launcher process makes the UI reflect
    // both network downloads and cache hits without a second engine path.
    webllmService.onProgress((report) => {
      if (report.text === 'Idle' || report.text === 'Unloaded') return;
      const progress = Math.round(Math.max(0, Math.min(1, report.progress || 0)) * 100);
      setStore({
        modelStatus: report.error ? 'error' : progress >= 100 ? 'ready' : 'downloading',
        downloadProgress: { progress, text: report.error || report.text },
      });
    });
    llamaCppService.onProgress((report) => {
      const loaded = Number(report.loaded || 0);
      const total = Number(report.total || 0);
      const progress = total > 0 ? Math.round(Math.max(0, Math.min(1, loaded / total)) * 100) : 0;
      setStore({
        modelStatus: progress >= 100 ? 'loading' : 'downloading',
        downloadProgress: { progress, text: report.text || 'Downloading llama-server model…' },
      });
    });
  }

  private syncCustomModels(): void {
    webllmService.setCustomModels(storeActions.getCustomWebLLMModels());
  }

  private resolveNativeLlamaModel(modelId?: string): string {
    return modelId || 'Qwen2.5-Coder-1.5B-Instruct';
  }

  private getNativeLlamaSpec(modelId: string): { repo?: string; file?: string } | undefined {
    const model = [...PRESET_MODELS, ...(getStore().customModels || [])].find((entry) => entry.id === modelId);
    return model?.llamaRepo && model.llamaFile ? { repo: model.llamaRepo, file: model.llamaFile } : undefined;
  }

  public async getWebGPUInfo(): Promise<WebGPUInfo> {
    // In WebKit UI mode, navigator.gpu is a stub with no requestAdapter.
    // Report that the Electron WebGPU worker handles inference instead of probing.
    if (!isElectronMode()) {
      return {
        supported: true,
        f16: true,
        adapterName: 'Electron WebGPU Worker',
        backend: 'webgpu',
        adapters: [],
      };
    }
    const info = await webllmService.getHardwareInfo();
    return { ...info, backend: 'webgpu', adapters: [], isFallback: false } as WebGPUInfo;
  }

  public async loadModel(modelId: string, onProgress?: ProgressCallback, skipActiveConversationWait = false): Promise<void> {
    this.syncCustomModels();
    const requestedModelId = modelId || PRESET_MODELS[0].id;

    // ModelManager can be opened while a response is streaming. Never unload
    // the runtime underneath that stream; invalidate the conversation first
    // and let the serialized service transition drain the abort.
    if (!skipActiveConversationWait && this.currentModelId && this.currentModelId !== requestedModelId && this.abortController) {
      this.conversationGeneration++;
      this.abortController.abort();
      this.abortController = null;
      if (isElectronMode()) webllmService.interrupt();
      else bridge.fireWorkerRequest('worker_cancel_model', { reason: 'model_switch' });
      setStore({ agentRunning: false });
      await this.activeConversationSettled?.catch(() => undefined);
    }

    // A startup preload must never monopolize model selection. Selecting a
    // different model cancels the old worker/runtime load and starts the new
    // request immediately instead of waiting behind isInitializing.
    if (this.activeLoadModelId && this.activeLoadModelId !== requestedModelId) {
      this.cancelModelLoad();
    }
    const requestGeneration = ++this.modelRequestGeneration;

    if (llamaCppService.isEnabled()) {
      if (!(window as any).__hyprcandyLlamaEnabled) {
        throw new Error('Local llama-server is OFF. Use the launcher Llama toggle before loading a local model.');
      }
      const nativeModelId = this.resolveNativeLlamaModel(requestedModelId);
      setStore({ activeModel: nativeModelId, modelStatus: 'loading', downloadProgress: { progress: 0, text: `Starting llama.cpp for ${nativeModelId}…` } });
      await llamaCppService.ensureModel(nativeModelId, this.getNativeLlamaSpec(nativeModelId));
      if (requestGeneration !== this.modelRequestGeneration) throw new DOMException('Model load superseded', 'AbortError');
      this.currentModelId = nativeModelId;
      this.activeBackend = 'wasm';
      setStore({ activeModel: nativeModelId, modelStatus: 'ready', downloadProgress: { progress: 100, text: 'Ready (llama.cpp)' } });
      return;
    }

    // ── WebKit UI mode: delegate to the Electron inference worker via GJS bridge ──
    if (!isElectronMode()) {
      const requestId = `${requestedModelId}:${requestGeneration}`;
      setStore({
        activeModel: requestedModelId,
        modelStatus: 'downloading',
        downloadProgress: { progress: 0, text: 'Requesting model load from Electron worker…' },
      });
      this.currentModelId = requestedModelId;
      return new Promise<void>((resolve, reject) => {
        let timeoutId: ReturnType<typeof setTimeout> | null = null;
        let settled = false;
        let cancelLoad: (() => void) | null = null;
        const isTargetModel = (id?: string) => {
          if (!id) return true;
          if (id === requestedModelId) return true;
          const baseRequested = requestedModelId.replace(/-q4f(16|32)_\d+-MLC$/, '');
          const baseIncoming = id.replace(/-q4f(16|32)_\d+-MLC$/, '');
          return baseRequested === baseIncoming;
        };

        const onReady = (e: Event) => {
          const detail = (e as CustomEvent).detail || {};
          if (!isTargetModel(detail.modelId) || (detail.requestId && detail.requestId !== requestId)) return;
          cleanup();
          setStore({ activeModel: requestedModelId, modelStatus: 'ready', downloadProgress: { progress: 100, text: 'Ready' } });
          resolve();
        };
        const onError = (e: Event) => {
          const detail = (e as CustomEvent).detail || {};
          if (!isTargetModel(detail.modelId) || (detail.requestId && detail.requestId !== requestId)) return;
          cleanup();
          const msg = detail.message || 'Worker inference error';
          setStore({ modelStatus: 'error', downloadProgress: { progress: 0, text: msg } });
          reject(new Error(msg));
        };
        const onProgress = (e: Event) => {
          const detail = (e as CustomEvent).detail || {};
          if (!isTargetModel(detail.modelId) || (detail.requestId && detail.requestId !== requestId)) return;
          const progress = Math.round(Math.max(0, Math.min(1, detail.progress || 0)) * 100);
          setStore({
            modelStatus: progress >= 100 ? 'loading' : 'downloading',
            downloadProgress: { progress, text: detail.text || 'Loading…' },
          });
        };
        const cleanup = () => {
          if (timeoutId) clearTimeout(timeoutId);
          if (this.cancelActiveLoad === cancelLoad) this.cancelActiveLoad = null;
          if (this.activeLoadModelId === requestedModelId) this.activeLoadModelId = null;
          window.removeEventListener('agent_worker_model_ready', onReady);
          window.removeEventListener('agent_worker_error', onError);
          window.removeEventListener('agent_worker_progress', onProgress);
        };
        window.addEventListener('agent_worker_model_ready', onReady);
        window.addEventListener('agent_worker_error', onError);
        window.addEventListener('agent_worker_progress', onProgress);
        this.activeLoadModelId = requestedModelId;
        cancelLoad = () => {
          if (settled) return;
          settled = true;
          cleanup();
          bridge.fireWorkerRequest('worker_cancel_model', { modelId: requestedModelId });
          reject(new DOMException('Model load cancelled', 'AbortError'));
        };
        this.cancelActiveLoad = cancelLoad;
        bridge.fireWorkerRequest('worker_load_model', {
          modelId: requestedModelId,
          requestId,
          // The visible WebKit renderer and hidden Electron renderer have
          // separate stores. Forward the selected GGUF metadata explicitly.
          customModels: storeActions.getCustomWebLLMModels(),
        });
        // Timeout after 10 minutes — large model downloads can take a while.
        timeoutId = setTimeout(() => { cleanup(); reject(new Error('Model load timed out after 10 min')); }, 600_000);
      });
    }

    // ── Electron mode: local WebLLM path (unchanged) ───────────────────────────
    if (webllmService.isReady(requestedModelId)) {
      this.currentModelId = requestedModelId;
      setStore({
        activeModel: requestedModelId,
        modelStatus: 'ready',
        downloadProgress: { progress: 100, text: 'Ready (cached)' },
      });
      return;
    }

    const manifestKnown = await webllmService.isModelCached(requestedModelId);
    if (requestGeneration !== this.modelRequestGeneration) {
      throw new DOMException('Model load superseded', 'AbortError');
    }

    this.isInitializing = true;
    this.activeLoadModelId = requestedModelId;
    setStore({
      activeModel: requestedModelId,
      modelStatus: manifestKnown ? 'loading' : 'downloading',
      downloadProgress: manifestKnown
        ? { progress: 0, text: 'Loading previously active model from cache…' }
        : { progress: 0, text: 'Preparing local inference runtime…' },
    });

    const unsubscribe = onProgress
      ? webllmService.onProgress(onProgress)
      : undefined;

    try {
      await webllmService.ensureEngine(requestedModelId);
      if (requestGeneration !== this.modelRequestGeneration) {
        throw new DOMException('Model load superseded', 'AbortError');
      }
      this.activeBackend = 'webgpu';
      this.currentModelId = requestedModelId;
      setStore({
        activeModel: requestedModelId,
        modelStatus: 'ready',
        downloadProgress: { progress: 100, text: manifestKnown ? 'Ready (previously cached)' : 'Ready' },
      });
    } catch (error: any) {
      if (requestGeneration !== this.modelRequestGeneration || error?.name === 'AbortError') {
        throw error;
      }
      const message = error instanceof Error ? error.message : String(error);
      setStore({
        modelStatus: 'error',
        downloadProgress: { progress: 0, text: `Error: ${message}` },
      });
      throw error;
    } finally {
      unsubscribe?.();
      if (this.activeLoadModelId === requestedModelId) {
        this.activeLoadModelId = null;
        this.cancelActiveLoad = null;
        this.isInitializing = false;
      }
    }
  }

  public cancelModelLoad(): void {
    this.modelRequestGeneration++;
    this.cancelActiveLoad?.();
    this.cancelActiveLoad = null;
    this.activeLoadModelId = null;
    this.isInitializing = false;
    if (!isElectronMode()) {
      setStore({ modelStatus: 'idle', downloadProgress: { progress: 0, text: 'Model load cancelled' } });
    } else {
      webllmService.cancelLoading();
      webllmService.interrupt();
      setStore({ modelStatus: 'idle', downloadProgress: { progress: 0, text: 'Model load cancelled' } });
    }
  }

  public cancel(): void {
    this.conversationGeneration++;
    this.abortController?.abort();
    this.abortController = null;
    if (llamaCppService.isEnabled()) llamaCppService.cancelChat();
    this.cancelModelLoad();
    if (isElectronMode()) webllmService.interrupt();
    else bridge.fireWorkerRequest('worker_cancel_model', { reason: 'user_cancel' });
    setStore({ agentRunning: false });
  }

  private async runLlamaConversation(
    sessionId: string,
    userPrompt: string,
    history: Array<{ role: 'user' | 'assistant' | 'system' | 'tool'; content: string }>,
    onToken: ((token: string) => void) | undefined,
    conversationGeneration: number,
  ): Promise<void> {
    const modelId = this.resolveNativeLlamaModel(this.currentModelId || getStore().activeModel);
    const assistantMsgId = 'msg_' + Date.now() + '_llama';
    storeActions.addMessage(sessionId, { id: assistantMsgId, role: 'assistant', content: '', timestamp: Date.now(), tools: [] });
    const streamUi = createStreamUpdateScheduler((content, tools) => storeActions.updateMessage(sessionId, assistantMsgId, { content, tools: tools || [] }), 140);
    const workingHistory: Array<any> = history.map((message) => ({ role: message.role, content: message.content }));
    let fullText = '';
    try {
      await this.loadModel(modelId, undefined, true);
      const liveStore = getStore();
      const contextMode = liveStore.contextMode || 'minimal';
      const projectTree = (liveStore.projectFiles || [])
        .slice(0, contextMode === 'full' ? 600 : contextMode === 'smart' ? 80 : 600)
        .map((file) => `${file.isDir ? '[dir] ' : '[file]'} ${file.path || file.name}${file.size ? ` (${file.size} bytes)` : ''}`)
        .join('\n') || '(project tree is empty; use list_directory with the project root)';
      const explicitContext = contextMode === 'minimal' ? [] : await Promise.all(
        liveStore.contextFiles.slice(0, contextMode === 'full' ? 12 : 4).map(async (file) => {
          try {
            const content = await bridge.readFile(file.path);
            return `[Explicit context file: ${file.path}]\n${content.slice(0, contextMode === 'full' ? 20000 : 5000)}\n[End explicit context file]`;
          } catch (error: any) {
            return `[Explicit context file unavailable: ${file.path}] ${error?.message || String(error)}`;
          }
        }),
      );
      const projectContext = [
        '[HyprCandy project context]',
        `Project root: ${liveStore.projectPath || '(unknown)'}`,
        `Selected file: ${liveStore.selectedFile || '(none)'}`,
        'Project tree (provided on the first turn; inspect file contents with peek/read tools when needed):',
        projectTree,
        contextMode === 'minimal' ? '' : liveStore.selectedFileContent ? `Selected file content:\n${liveStore.selectedFileContent.slice(0, contextMode === 'full' ? 12000 : 2500)}` : 'Selected file content: (not loaded)',
        'Use tools to inspect files when the supplied context is insufficient. Do not invent project facts.',
        explicitContext.join('\n'),
        liveStore.contextImages.length ? `Image context attached (text model cannot inspect pixels directly): ${liveStore.contextImages.map(image => image.path).join(', ')}` : '',
        '[End HyprCandy project context]',
      ].join('\n');
      let taskCompleted = false;
      const repeatedCalls = new Map<string, number>();
      workingHistory.push({
        role: 'user',
        content: `${userPrompt}\n\n${projectContext}`,
      });
      while (!taskCompleted) {
        if (conversationGeneration !== this.conversationGeneration || this.abortController?.signal.aborted) break;
        const before = fullText;
        const nativeToolCallMap = new Map<string, any>();
        let iterationText = '';
        const messages = [
          { role: 'system' as const, content: AGENT_SYSTEM_PROMPT },
          ...workingHistory,
        ];
        for await (const chunk of llamaCppService.chat(messages, modelId, this.abortController?.signal, { tools: AGENT_TOOLS })) {
          if (conversationGeneration !== this.conversationGeneration || this.abortController?.signal.aborted) break;
          if (chunk.token) {
            iterationText += chunk.token;
            onToken?.(chunk.token);
            // Hide anything from the point a '<tool_call>' tag opens: the
            // raw JSON was streaming straight into the chat bubble as plain
            // text (rendering as a stray markdown/code block) for the whole
            // time between the tag opening and the turn finishing, instead
            // of showing a working/pulsing indicator like a real tool call.
            const openIdx = iterationText.search(/<tool_call>/i);
            const visible = openIdx === -1 ? iterationText : iterationText.slice(0, openIdx).trimEnd();
            fullText = before ? `${before}\n${visible}` : visible;
            streamUi.schedule(fullText);
          }
          if (chunk.tool_calls) {
            for (const delta of chunk.tool_calls) {
              const key = String(delta.id || delta.index || nativeToolCallMap.size);
              const current = nativeToolCallMap.get(key) || { id: delta.id, type: 'function', function: { name: '', arguments: '' } };
              const fn = delta.function || delta;
              current.function.name += String(fn.name || '');
              current.function.arguments += String(fn.arguments || delta.arguments || '');
              nativeToolCallMap.set(key, current);
            }
          }
        }
        streamUi.flush();
        const parsedCalls = [...Array.from(nativeToolCallMap.values()), ...this.parseInlineToolCalls(iterationText)]
          .map((call: any) => {
            const fn = call.function || call;
            let args = fn.arguments || call.args || {};
            if (typeof args === 'string') { try { args = JSON.parse(args); } catch { args = {}; } }
            return { id: call.id || `call_${Math.random().toString(36).slice(2, 9)}`, name: this.normalizeInlineToolName(String(fn.name || call.name || '')), args };
          })
          .filter((call, index, all) => call.name && all.findIndex((item) => item.name === call.name && JSON.stringify(item.args) === JSON.stringify(call.args)) === index);
        if (!parsedCalls.length) {
          workingHistory.push({ role: 'assistant', content: iterationText });
          // A native model response without a tool call is a completed
          // conversational turn. Re-prompting here creates an unbounded loop
          // where small models repeat the same request and starve GJS.
          break;
        }
        // Tool syntax belongs in the tool/plan widgets, not in the Markdown
        // answer bubble. Keep any previous natural-language context visible.
        fullText = before;
        streamUi.schedule(fullText);
        streamUi.flush();
        workingHistory.push({
          role: 'assistant',
          content: iterationText,
          tool_calls: parsedCalls.map((call) => ({
            id: call.id,
            type: 'function',
            function: { name: call.name, arguments: JSON.stringify(call.args || {}) },
          })),
        });
        const results: string[] = [];
        const toolMessages: Array<{ role: 'tool'; tool_call_id: string; content: string }> = [];
        for (const call of parsedCalls) {
          if (conversationGeneration !== this.conversationGeneration || this.abortController?.signal.aborted) break;
          const signature = `${call.name}:${JSON.stringify(call.args || {})}`;
          const repeatCount = (repeatedCalls.get(signature) || 0) + 1;
          repeatedCalls.set(signature, repeatCount);
          if (repeatCount > 3) {
            const content = `The tool call was repeated ${repeatCount} times with the same arguments and failed to make progress. Choose a different path or call task_complete with the limitation.`;
            results.push(`[Tool error: ${call.name}] ${content}`);
            toolMessages.push({ role: 'tool', tool_call_id: call.id, content });
            if (repeatCount >= 5) {
              fullText = `I stopped after the same ${call.name} operation failed repeatedly. Please verify the project path and permissions, then retry.`;
              taskCompleted = true;
            }
            continue;
          }
          try {
            const result = await this.executeToolDirectly(sessionId, assistantMsgId, call.name, call.args);
            const content = typeof result === 'string' ? result : JSON.stringify(result, null, 2).slice(0, 12000);
            results.push(`[Tool result: ${call.name}]\n${content}\n[End tool result: ${call.name}]`);
            toolMessages.push({ role: 'tool', tool_call_id: call.id, content });
            if (call.name === 'task_complete') {
              taskCompleted = true;
              if (call.args?.summary) {
                fullText = String(call.args.summary);
                streamUi.schedule(fullText);
                streamUi.flush();
              }
            }
          } catch (error: any) {
            const content = error?.message || String(error);
            results.push(`[Tool error: ${call.name}] ${content}\n[End tool error: ${call.name}]`);
            toolMessages.push({ role: 'tool', tool_call_id: call.id, content: `Tool error: ${content}` });
          }
        }
        if (!results.length) continue;
        if (toolMessages.length === parsedCalls.length) {
          workingHistory.push(...toolMessages);
        } else {
          workingHistory.push({ role: 'user', content: results.join('\n\n') });
        }
      }
    } catch (error: any) {
      if (error?.name !== 'AbortError') {
        streamUi.flush();
        storeActions.updateMessage(sessionId, assistantMsgId, { content: `${fullText}\n\n⚠️ **llama.cpp error**: ${error?.message || String(error)}` });
      }
    } finally {
      streamUi.cancel();
      if (conversationGeneration === this.conversationGeneration) {
        this.abortController = null;
        setStore({ agentRunning: false });
      }
    }
  }

  public async runConversation(
    sessionId: string,
    userPrompt: string,
    history: Array<{ role: 'user' | 'assistant' | 'system' | 'tool'; content: string }>,
    onToken?: (token: string) => void
  ): Promise<void> {
    // A host event can arrive while a previous stream is still unwinding.
    // Give every run an identity so its late callbacks cannot clear the state
    // or append text belonging to a newer request.
    const previousConversation = this.activeConversationSettled;
    this.conversationGeneration++;
    let resolveConversation!: () => void;
    const conversationSettled = new Promise<void>((resolve) => { resolveConversation = resolve; });
    this.abortController?.abort();
    if (isElectronMode()) webllmService.interrupt();
    if (previousConversation) await previousConversation.catch(() => undefined);
    const conversationGeneration = ++this.conversationGeneration;
    const isCurrentConversation = () => conversationGeneration === this.conversationGeneration;
    this.activeConversationSettled = conversationSettled;
    this.abortController = new AbortController();
    setStore({ agentRunning: true });

    if (llamaCppService.isEnabled()) {
      try {
        await this.runLlamaConversation(sessionId, userPrompt, history, onToken, conversationGeneration);
      } finally {
        // The native path has its own streaming loop, so it must explicitly
        // settle the promise awaited by the next run/model switch. Leaving
        // this unresolved made Stop appear to hang the GJS host forever.
        resolveConversation();
        if (this.activeConversationSettled === conversationSettled) this.activeConversationSettled = null;
      }
      return;
    }

    // ── WebKit UI mode: delegate inference to Electron worker via GJS bridge ────
    if (!isElectronMode()) {
      const assistantMsgId = 'msg_' + Date.now() + '_worker';
      storeActions.addMessage(sessionId, {
        id: assistantMsgId,
        role: 'assistant',
        content: '',
        timestamp: Date.now(),
        tools: [],
      });
      let fullText = '';
      let rawStreamText = '';
      let thinkingVisible = false;
      const streamUi = createStreamUpdateScheduler((content, tools) => {
        storeActions.updateMessage(sessionId, assistantMsgId, { content, tools: tools || [] });
      });
      const settleDelegatedConversation = () => {
        resolveConversation();
        if (this.activeConversationSettled === conversationSettled) this.activeConversationSettled = null;
      };

      const visibleModelText = (raw: string): { text: string; thinking: boolean } => {
        // Qwen-style reasoning must remain an inline agent phase, never part
        // of the foreground answer. Keep incomplete tags hidden while tokens
        // are arriving so split <think> chunks cannot flash into the UI.
        const open = raw.search(/<(think|analysis)>/i);
        if (open < 0) return { text: raw, thinking: false };
        const closeMatch = raw.slice(open).match(/<\/(think|analysis)>/i);
        if (!closeMatch) return { text: raw.slice(0, open).trim(), thinking: true };
        const close = open + (closeMatch.index || 0) + closeMatch[0].length;
        return { text: (raw.slice(0, open) + raw.slice(close)).trim(), thinking: false };
      };

      const onToken_ = (e: Event) => {
        const detail = (e as CustomEvent).detail || {};
        if (!isCurrentConversation() || (detail.msgId && detail.msgId !== assistantMsgId) || this.abortController?.signal.aborted) { cleanup(); return; }
        const token = detail.token || '';
        rawStreamText += token;
        const parsed = visibleModelText(rawStreamText);
        fullText = parsed.text;
        thinkingVisible = parsed.thinking;
        onToken?.(parsed.text);
        streamUi.schedule(fullText, thinkingVisible
          ? [{ id: `${assistantMsgId}_thinking`, name: 'thinking', arguments: {}, status: 'running' }]
          : []);
      };
      const onDone_ = (e: Event) => {
        const detail = (e as CustomEvent).detail || {};
        if (!isCurrentConversation() || (detail.msgId && detail.msgId !== assistantMsgId)) { settleDelegatedConversation(); cleanup(); return; }
        streamUi.flush();
        cleanup();
        if (thinkingVisible) {
          storeActions.updateMessage(sessionId, assistantMsgId, {
            tools: [{ id: `${assistantMsgId}_thinking`, name: 'thinking', arguments: {}, status: 'completed' }],
          });
        }
        this.abortController = null;
        setStore({ agentRunning: false });
        settleDelegatedConversation();
      };
      const onError_ = (e: Event) => {
        const detail = (e as CustomEvent).detail || {};
        if (!isCurrentConversation() || (detail.msgId && detail.msgId !== assistantMsgId)) { settleDelegatedConversation(); cleanup(); return; }
        streamUi.cancel();
        cleanup();
        const msg = detail.message || 'Worker inference error';
        const prev = getStore().sessions.find(s => s.id === sessionId)?.messages.find(m => m.id === assistantMsgId)?.content || '';
        storeActions.updateMessage(sessionId, assistantMsgId, { content: prev + `\n\n⚠️ **Inference error**: ${msg}` });
        this.abortController = null;
        setStore({ agentRunning: false });
        settleDelegatedConversation();
      };

      function cleanup() {
        window.removeEventListener('agent_worker_token', onToken_);
        window.removeEventListener('agent_worker_done', onDone_);
        window.removeEventListener('agent_worker_error', onError_);
      }
      window.addEventListener('agent_worker_token', onToken_);
      window.addEventListener('agent_worker_done', onDone_);
      window.addEventListener('agent_worker_error', onError_);

      // Send the full conversation history so the Electron worker has full context.
      bridge.fireWorkerRequest('worker_chat', {
        sessionId,
        msgId: assistantMsgId,
        modelId: this.currentModelId || getStore().activeModel,
        messages: [
          ...history.map(m => ({ role: m.role, content: m.content })),
          { role: 'user', content: userPrompt },
        ],
        projectPath: getStore().projectPath,
        selectedFile: getStore().selectedFile,
        selectedFileContent: getStore().selectedFileContent,
        projectFiles: getStore().projectFiles,
        contextFiles: getStore().contextFiles,
        contextImages: getStore().contextImages.map(image => ({ path: image.path })),
      });
      return;
    }

    // ── Electron mode: full local WebLLM inference path (unchanged) ────────
    const MAX_AGENT_ITERATIONS = 6;
    const workingHistory: Array<any> = [...history.map(m => ({ role: m.role, content: m.content }))];
    let lastAssistantMsgId: string | null = null;
    let iterationCount = 0;

    try {
      if (!isCurrentConversation()) return;
      if (!webllmService.isReady(this.currentModelId || getStore().activeModel)) {
        await this.loadModel(this.currentModelId || getStore().activeModel || PRESET_MODELS[0].id, undefined, true);
      }
      if (!isCurrentConversation()) return;

      const liveStore = getStore();
      const contextFilePaths = liveStore.contextFiles.map(file => file.path);
      const explicitContext = await Promise.all(liveStore.contextFiles.slice(0, 12).map(async (file) => {
        try {
          const content = await bridge.readFile(file.path);
          return `\n[Explicit context file: ${file.path}]\n${content.slice(0, 20000)}\n[End explicit context file]`;
        } catch (error: any) {
          return `\n[Explicit context file unavailable: ${file.path}] ${error?.message || String(error)}`;
        }
      }));
      const projectContext = [
        `[HyprCandy project context]`,
        `Project root: ${liveStore.projectPath}`,
        `Selected file: ${liveStore.selectedFile || '(none)'}`,
        liveStore.selectedFileContent
          ? `Selected file content:\n${liveStore.selectedFileContent.slice(0, 16000)}`
          : `Selected file content: (not loaded)`,
        `Files explicitly added to context: ${contextFilePaths.length ? contextFilePaths.join(', ') : '(none)'}`,
        `Images explicitly added to context: ${liveStore.contextImages.length ? liveStore.contextImages.map(image => image.path).join(', ') : '(none)'}`,
        `Do not invent a project name or files. If a requested fact is not present in this context, inspect the project with list_directory/read_file before answering.`,
        `[End HyprCandy project context]`,
        ...explicitContext,
      ].join('\n');
      let initialTaskContext = `\n\n${projectContext}`;
      if (this.shouldAutoSearch(userPrompt)) {
        try {
          const results = await bridge.webSearch(userPrompt);
          initialTaskContext += `\n\n[Fresh web research from SearXNG — use this context and cite uncertainty when results conflict]\n${JSON.stringify(results).slice(0, 24000)}\n[End fresh web research]`;
        } catch (error: any) {
          initialTaskContext += `\n\n[Web research unavailable: ${error.message}]`;
        }
      }

      workingHistory.push({ role: 'user', content: userPrompt + initialTaskContext });

      while (iterationCount < MAX_AGENT_ITERATIONS) {
        if (!isCurrentConversation() || this.abortController?.signal.aborted) break;
        iterationCount++;

        const engine = webllmService.getEngine();
        if (!engine) throw new Error('Local browser inference engine is not ready.');

        const activeModelId = webllmService.getLoadedModel() || this.currentModelId || getStore().activeModel;
        const useNativeTools = shouldUseNativeWebLLMTools(activeModelId);

        const assistantMsgId = 'msg_' + Date.now() + '_' + iterationCount;
        lastAssistantMsgId = assistantMsgId;
        storeActions.addMessage(sessionId, {
          id: assistantMsgId,
          role: 'assistant',
          content: '',
          timestamp: Date.now(),
          tools: [],
        });
        const streamUi = createStreamUpdateScheduler((content) => {
          storeActions.updateMessage(sessionId, assistantMsgId, { content });
        });
        const tokenUi = createTokenScheduler((token) => onToken?.(token));

        const messages: ChatCompletionMessageParam[] = [
          // WebLLM injects the required Hermes-2-Pro/Hermes-3 function-calling
          // system prompt itself. Supplying any customized system message in
          // the same request raises CustomSystemPromptError and leaves the
          // launcher in a running-but-stalled state. Project context is already
          // appended to the user turn below, so no important context is lost.
          ...(!useNativeTools ? [{ role: 'system', content: AGENT_SYSTEM_PROMPT } as ChatCompletionMessageParam] : []),
          ...workingHistory.map((message): ChatCompletionMessageParam => {
            // Do not forward historical system messages to Hermes native tool
            // calls either; WebLLM rejects all customized system messages.
            if (useNativeTools && message.role === 'system') return null as any;
            if (message.role === 'assistant') return { role: 'assistant', content: message.content, ...(message.tool_calls ? { tool_calls: message.tool_calls } : {}) } as any;
            if (message.role === 'system') return { role: 'system', content: message.content };
            if (message.role === 'tool') return { role: 'tool', content: message.content, tool_call_id: message.tool_call_id } as any;
            return { role: 'user', content: message.content };
          }).filter(Boolean),
        ];

        let fullAssistantText = '';
        const nativeToolCalls: Array<{ id?: string; name: string; args: any }> = [];
        const completionStream: any = await engine.chat.completions.create({
          messages,
          model: activeModelId,
          temperature: 0.7,
          max_tokens: 1536,
          stream: true,
          abortSignal: this.abortController?.signal,
          ...(useNativeTools ? { tools: AGENT_TOOLS, tool_choice: 'auto' } : {}),
        });

        for await (const chunk of completionStream) {
          if (!isCurrentConversation() || this.abortController?.signal.aborted) break;
          const delta = chunk?.choices?.[0]?.delta?.content || '';
          if (delta) {
            fullAssistantText += delta;
            tokenUi.schedule(delta);
            streamUi.schedule(fullAssistantText);
          }
          const toolDeltas = chunk?.choices?.[0]?.delta?.tool_calls || [];
          for (const toolDelta of toolDeltas) {
            const index = Number(toolDelta.index || 0);
            const current = nativeToolCalls[index] || { id: '', name: '', args: '' };
            current.id = current.id || toolDelta.id || '';
            current.name += toolDelta.function?.name || '';
            current.args += toolDelta.function?.arguments || '';
            nativeToolCalls[index] = current;
          }
        }

        if (isCurrentConversation()) {
          tokenUi.flush();
          streamUi.flush();
        } else {
          tokenUi.cancel();
          streamUi.cancel();
        }
        if (!isCurrentConversation() || this.abortController?.signal.aborted) break;
        if (nativeToolCalls.length) {
          workingHistory.push({
            role: 'assistant',
            content: fullAssistantText || null,
            tool_calls: nativeToolCalls.map((call, index) => ({
              id: call.id || `call_${iterationCount}_${index}`,
              type: 'function',
              function: { name: call.name, arguments: call.args || '{}' },
            })),
          });
        } else {
          workingHistory.push({ role: 'assistant', content: fullAssistantText });
        }

        this.extractInlineAttachments(sessionId, assistantMsgId, fullAssistantText);

        const parsed: Array<{ id?: string; name: string; args: any }> = [
          ...nativeToolCalls.map((call) => {
            let args: any = {};
            try { args = JSON.parse(call.args || '{}'); } catch { args = {}; }
            return { id: call.id, name: call.name, args };
          }),
          ...this.parseInlineToolCalls(fullAssistantText),
        ].filter((call, index, all) => call.name && all.findIndex((item) => item.name === call.name && JSON.stringify(item.args) === JSON.stringify(call.args)) === index);
        if (parsed.length === 0) break;

        let hasAutoResult = false;
        let autoToolText = '';
        const nativeToolResults: Array<{ id: string; content: string }> = [];

        for (const call of parsed) {
          if (!isCurrentConversation() || this.abortController?.signal.aborted) break;
          const isSafeTool = ['read_file', 'list_directory', 'web_search', 'fetch_url', 'take_screenshot'].includes(call.name);
          if (!isSafeTool) {
            const result = await this.executeToolDirectly(sessionId, assistantMsgId, call.name, call.args);
            hasAutoResult = true;
            const resultText = JSON.stringify(result, null, 2);
            autoToolText += `\n\n[Tool result: ${call.name}]\n${resultText}\n[End tool result: ${call.name}]`;
            if (call.id) nativeToolResults.push({ id: call.id, content: resultText });
            continue;
          }

          const toolCallId = 'call_auto_' + Math.random().toString(36).substring(2, 7);
          const toolData: ToolCallData = {
            id: toolCallId,
            name: call.name,
            arguments: call.args,
            status: 'running',
          };

          setStore(prev => {
            const updated = prev.sessions.map(s => {
              if (s.id !== sessionId) return s;
              return {
                ...s,
                messages: s.messages.map(m => m.id === assistantMsgId
                  ? { ...m, tools: [...(m.tools || []), toolData] }
                  : m),
              };
            });
            return { sessions: updated };
          });

          try {
            let result: any;
            if (call.name === 'web_search') result = await bridge.webSearch(call.args.query || '');
            else if (call.name === 'read_file') result = await bridge.readFile(call.args.path || '', call.args.offset, call.args.limit);
            else if (call.name === 'fetch_url') result = await bridge.fetchUrl(call.args.url || '');
            else if (call.name === 'list_directory') result = await bridge.listDirectory(call.args.path || '.');
            else if (call.name === 'take_screenshot') result = await bridge.takeScreenshot(call.args.region || '');

            setStore(prev => {
              const updated = prev.sessions.map(s => {
                if (s.id !== sessionId) return s;
                return {
                  ...s,
                  messages: s.messages.map(m => m.id === assistantMsgId
                    ? { ...m, tools: (m.tools || []).map(t => t.id === toolCallId ? { ...t, status: 'completed' as const, result } : t) }
                    : m),
                };
              });
              return { sessions: updated };
            });

            hasAutoResult = true;
            const resultStr = typeof result === 'string' ? result : JSON.stringify(result, null, 2).slice(0, 12000);
            autoToolText += `\n\n[Tool result: ${call.name}]\n${resultStr}\n[End tool result: ${call.name}]`;
            if (call.id) nativeToolResults.push({ id: call.id, content: resultStr });
          } catch (err: any) {
            setStore(prev => {
              const updated = prev.sessions.map(s => {
                if (s.id !== sessionId) return s;
                return {
                  ...s,
                  messages: s.messages.map(m => m.id === assistantMsgId
                    ? { ...m, tools: (m.tools || []).map(t => t.id === toolCallId ? { ...t, status: 'error' as const, result: err.message } : t) }
                    : m),
                };
              });
              return { sessions: updated };
            });
            hasAutoResult = true;
            autoToolText += `\n\n[Tool error: ${call.name}] ${err.message}\n[End tool error]`;
            if (call.id) nativeToolResults.push({ id: call.id, content: `Tool error: ${err.message}` });
          }
        }

        if (!hasAutoResult) break;
        if (nativeToolResults.length) {
          nativeToolResults.forEach((result) => workingHistory.push({ role: 'tool', tool_call_id: result.id, content: result.content }));
        } else {
          workingHistory.push({ role: 'user', content: `Here are the tool results. Respond to the original user request using them. Do not repeat the results verbatim.\n${autoToolText}` });
        }
      }

      if (lastAssistantMsgId) {
        const finalContent = getStore().sessions.find(s => s.id === sessionId)?.messages.find(m => m.id === lastAssistantMsgId)?.content;
        if (finalContent) await this.checkForInlineToolCalls(sessionId, lastAssistantMsgId, finalContent);
      }
    } catch (err: any) {
      if (err?.name === 'AbortError') {
        console.log('Generation aborted by user.');
      } else {
        console.error('Inference error:', err);
        if (lastAssistantMsgId) {
          const prev = getStore().sessions.find(s => s.id === sessionId)?.messages.find(m => m.id === lastAssistantMsgId)?.content || '';
          storeActions.updateMessage(sessionId, lastAssistantMsgId, {
            content: prev + `\n\n⚠️ **Inference error**: ${err?.message || String(err)}`,
          });
        }
      }
    } finally {
      if (isCurrentConversation()) {
        this.abortController = null;
        setStore({ agentRunning: false });
      }
      resolveConversation();
      if (this.activeConversationSettled === conversationSettled) {
        this.activeConversationSettled = null;
      }
    }
  }

  private shouldAutoSearch(prompt: string): boolean {
    return /\b(latest|current|up[- ]to[- ]date|today|recent|newest|modern|recommended|best practice|how do I now|as of|release|version|api changes?|compatib|documentation|docs|method|approach)\b/i.test(prompt);
  }

  /**
   * Parses an assistant response for tool calls expressed as JSON blocks,
   * fenced code blocks with JSON, or inline tag syntax like:
   *   <Tool name="read_file" args='{"path":"/tmp/a"}' />
   * Returns a list of {name, args}.
   */
  // Small local models frequently emit near-valid JSON in tool calls —
  // trailing commas, smart quotes copy-pasted from training data, or a
  // stray comment. A strict JSON.parse throws on all of these and the
  // whole tool call is silently dropped (caught and ignored), which reads
  // to the user as "the model tried and nothing happened". Repair the
  // common cases before parsing instead of only ever trying the raw text.
  private tryParseJsonLenient(raw: string): any {
    try { return JSON.parse(raw); } catch {}
    const repaired = raw
      .replace(/[\u2018\u2019]/g, "'")
      .replace(/[\u201C\u201D]/g, '"')
      .replace(/,\s*([}\]])/g, '$1')
      .replace(/'([^'"\n]*?)'(\s*:)/g, '"$1"$2')
      .replace(/:\s*'([^'"\n]*?)'/g, ': "$1"');
    try { return JSON.parse(repaired); } catch { return null; }
  }

  private parseInlineToolCalls(text: string): Array<{ name: string; args: any }> {
    const results: Array<{ name: string; args: any }> = [];
    const seenKeys = new Set<string>();

    // Qwen local chat templates can emit a bare JSON object instead of an
    // XML/fenced block. Scan balanced objects so nested arguments survive.
    for (let start = 0; start < text.length; start++) {
      if (text[start] !== '{') continue;
      let depth = 0;
      let quoted = false;
      let escaped = false;
      for (let end = start; end < text.length; end++) {
        const ch = text[end];
        if (quoted) {
          if (escaped) escaped = false;
          else if (ch === '\\') escaped = true;
          else if (ch === '"') quoted = false;
          continue;
        }
        if (ch === '"') { quoted = true; continue; }
        if (ch === '{') depth++;
        if (ch === '}' && --depth === 0) {
          try {
            const parsed = this.tryParseJsonLenient(text.slice(start, end + 1));
            if (!parsed) throw new Error('unparseable');
            const name = this.normalizeInlineToolName(String(parsed.name || parsed.tool || parsed.function || '').trim());
            let args = parsed.arguments || parsed.args || parsed.params || {};
            if (typeof args === 'string') { try { args = JSON.parse(args); } catch { args = {}; } }
            if (name) {
              const k = name + JSON.stringify(args);
              if (!seenKeys.has(k)) { seenKeys.add(k); results.push({ name, args }); }
            }
          } catch { /* incomplete or unrelated JSON */ }
          break;
        }
      }
    }

    // 1) Fenced JSON code blocks that look like tool calls:
    //    ```json
    //    {"name": "read_file", "arguments": {"path": "/x"}}
    //    ```
    const jsonBlockRe = /```(?:json|tool|)\s*\n([\s\S]*?)```/g;
    let m: RegExpExecArray | null;
    while ((m = jsonBlockRe.exec(text)) !== null) {
      try {
        const parsed = this.tryParseJsonLenient(m[1].trim());
        if (parsed && typeof parsed === 'object') {
          const items = Array.isArray(parsed) ? parsed : [parsed];
          for (const it of items) {
            const name = this.normalizeInlineToolName(String(it.name || it.tool || it.function || '').trim());
            let args = it.arguments || it.args || it.params || {};
            if (typeof args === 'string') {
              try { args = JSON.parse(args); } catch { args = {}; }
            }
            if (name) {
              const k = name + JSON.stringify(args);
              if (!seenKeys.has(k)) { seenKeys.add(k); results.push({ name, args }); }
            }
          }
        }
      } catch { /* ignore malformed JSON */ }
    }

    // 1b) Common local-model XML calls: <tool_call>{"name":"..."...}</tool_call>
    const xmlCallRe = /<tool_call>\s*([\s\S]*?)\s*<\/tool_call>/gi;
    while ((m = xmlCallRe.exec(text)) !== null) {
      try {
        const parsed = this.tryParseJsonLenient(m[1].trim());
        if (!parsed) throw new Error('unparseable');
        const name = this.normalizeInlineToolName(String(parsed.name || parsed.tool || parsed.function || '').trim());
        let args = parsed.arguments || parsed.args || parsed.params || {};
        if (typeof args === 'string') args = JSON.parse(args);
        const k = name + JSON.stringify(args);
        if (name && !seenKeys.has(k)) { seenKeys.add(k); results.push({ name, args }); }
      } catch { /* ignore non-JSON XML calls */ }
    }

    // 2) XML-style tool tags: <Tool name="X" args="{}" />  or  <read_file path="..." />
    const tagRe = /<\s*([a-zA-Z_][\w]*)([^/>]*?)\/?>|<\s*Tool\s+name\s*=\s*["']([^"']+)["']([^/>]*?)\/?>/gi;
    while ((m = tagRe.exec(text)) !== null) {
      let name = (m[1] && m[1].toLowerCase() !== 'tool') ? m[1] : (m[3] || '');
      const attrStr = (m[2] || '') + ' ' + (m[4] || '');
      name = this.normalizeInlineToolName(String(name || '').trim());
      if (name === 'think' || name === 'analysis' || name === 'tool_call') continue;
      if (!name) continue;

      const args: any = {};
      const keyValRe = /(\w+)\s*=\s*(?:"([^"]*)"|'([^']*)'|({[\s\S]*?})|([^\s/>]+))/g;
      let av: RegExpExecArray | null;
      while ((av = keyValRe.exec(attrStr)) !== null) {
        const key = av[1];
        const raw = av[2] ?? av[3] ?? av[4] ?? av[5] ?? '';
        try {
          if (av[4]) args[key] = JSON.parse(av[4]);
          else if (/^(true|false)$/i.test(raw)) args[key] = raw.toLowerCase() === 'true';
          else if (/^-?\d+(\.\d+)?$/.test(raw)) args[key] = Number(raw);
          else args[key] = raw;
        } catch { args[key] = raw; }
      }

      const k = name + JSON.stringify(args);
      if (!seenKeys.has(k)) { seenKeys.add(k); results.push({ name, args }); }
    }

    // 3) Fallback: heuristic extraction from prose for known tool verbs.
    //    e.g. "I will read_file /etc/hosts"
    const known = new Set(['web_search', 'read_file', 'write_file', 'list_directory', 'exec_command', 'take_screenshot', 'plan_update', 'task_complete']);
    const proseRe = new RegExp(`\\b(${Array.from(known).join('|')})\\b\\s*[:(]?\\s*["']?([^"'\\s)\\n]+)?`, 'gi');
    while ((m = proseRe.exec(text)) !== null) {
      const name = m[1].toLowerCase();
      const param = m[2] || '';
      let args: any = {};
      if (name === 'web_search') args = { query: param || text.slice(0, 80) };
      else if (name === 'read_file') args = { path: param };
      else if (name === 'list_directory') args = { path: param || '.' };
      else if (name === 'take_screenshot') args = { region: param };
      else if (name === 'exec_command' && param) args = { command: text.slice(proseRe.lastIndex - 30, proseRe.lastIndex + 120) };
      else if (name === 'write_file' && param) args = { path: param };
      else continue;
      const k = name + JSON.stringify(args);
      if (!seenKeys.has(k)) { seenKeys.add(k); results.push({ name, args }); }
    }

    return results;
  }

  private normalizeInlineToolName(name: string): string {
    return name === 'list_files' ? 'list_directory' : name;
  }

  /**
   * Scans assistant output for image/file references like:
   *   </Image: /path/to/file.png>
   *   <Image: /path/to/a.jpg>
   *   ![](/path/to/b.png)
   *   ![caption](/path/to/c.jpeg)
   * and attaches them to the message so ChatStream renders thumbnails.
   */
  private extractInlineAttachments(sessionId: string, messageId: string, text: string) {
    const attachments: AttachmentData[] = [];
    const push = (rawPath: string, kind: AttachmentData['kind']) => {
      const path = rawPath.trim().replace(/^file:\/+/, '/');
      if (!path) return;
      const name = path.split('/').pop() || path;
      if (attachments.some(a => a.path === path)) return;
      attachments.push({ path, name, kind });
    };

    // </Image: path>  or  <Image: path>
    const imageTagRe = /<\/?\s*Image\s*:\s*([^>\n]+)\s*>/gi;
    let m: RegExpExecArray | null;
    while ((m = imageTagRe.exec(text)) !== null) push(m[1], 'image');

    // </File: path>  or  <File: path>
    const fileTagRe = /<\/?\s*File\s*:\s*([^>\n]+)\s*>/gi;
    while ((m = fileTagRe.exec(text)) !== null) {
      const p = m[1];
      const ext = p.split('.').pop()?.toLowerCase() || '';
      const kind: AttachmentData['kind'] = ['png', 'jpg', 'jpeg', 'gif', 'webp'].includes(ext)
        ? 'image'
        : ['mp4', 'webm', 'mov', 'mkv'].includes(ext)
          ? 'video'
          : 'file';
      push(p, kind);
    }

    // Markdown image: ![alt](path)
    const mdRe = /!\[[^\]]*\]\(\s*([^)\s]+)\s*\)/g;
    while ((m = mdRe.exec(text)) !== null) {
      const p = m[1];
      const ext = p.split('.').pop()?.toLowerCase() || '';
      if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'].includes(ext)) push(p, 'image');
      else if (['mp4', 'webm', 'mov', 'mkv'].includes(ext)) push(p, 'video');
    }

    if (attachments.length === 0) return;
    storeActions.updateMessage(sessionId, messageId, { attachments });
  }

  /** Evaluates text for file changes or tool instructions and executes via native bridge. */
  private async checkForInlineToolCalls(sessionId: string, messageId: string, text: string) {
    const commandMatch = text.match(/```(?:bash|sh)\s*\n([\s\S]*?)```/);
    if (commandMatch && commandMatch[1]) {
      const cmd = commandMatch[1].trim();
      const commandData: CommandData = {
        command: cmd,
        status: 'pending',
      };
      storeActions.updateMessage(sessionId, messageId, { command: commandData });
    }

    // Also detect write_file expressed as a fenced block with a path hint on the
    // opening fence, e.g. ```ts /path/to/file.ts  or  ``` /x.py
    const writeFenceRe = /```([\w+-]*)\s+(\/[^\n`]+?)\s*\n([\s\S]*?)```/g;
    let m: RegExpExecArray | null;
    while ((m = writeFenceRe.exec(text)) !== null) {
      const [, , filePath, content] = m;
      if (!filePath || filePath.includes(' ')) continue;
      const diffData: DiffData = {
        filePath: filePath.trim(),
        originalCode: '',
        modifiedCode: content,
        status: 'pending',
      };
      storeActions.updateMessage(sessionId, messageId, { diff: diffData });
      break;
    }
  }

  public async executeToolDirectly(
    sessionId: string,
    messageId: string,
    toolName: string,
    args: any
  ): Promise<any> {
    const toolCallId = 'call_' + Math.random().toString(36).substring(2, 7);
    const toolData: ToolCallData = {
      id: toolCallId,
      name: toolName,
      arguments: args,
      status: 'running',
    };

    setStore((prev) => {
      const updated = prev.sessions.map((session) => {
        if (session.id !== sessionId) return session;
        return {
          ...session,
          messages: session.messages.map((message) => {
            if (message.id !== messageId) return message;
            return { ...message, tools: [...(message.tools || []), toolData] };
          }),
        };
      });
      return { sessions: updated };
    });

    try {
      let result: any = null;
      if (toolName === 'plan_update') {
        const tasks = Array.isArray(args.tasks) ? args.tasks.map((task: any, index: number): PlanTask => ({
          id: String(task.id || `task-${index + 1}`),
          title: String(task.title || task.name || `Task ${index + 1}`),
          status: ['pending', 'in_progress', 'completed', 'blocked'].includes(task.status) ? task.status : 'pending',
          detail: task.detail ? String(task.detail) : undefined,
        })) : [];
        setStore((prev) => ({ sessions: prev.sessions.map((session) => session.id !== sessionId ? session : {
          ...session,
          messages: session.messages.map((message) => message.id !== messageId ? message : { ...message, plan: { tasks, updatedAt: Date.now() } }),
        }) }));
        result = { status: 'plan_updated', taskCount: tasks.length };
      } else if (toolName === 'task_complete') {
        result = { status: 'task_complete', summary: args.summary || '', remaining: args.remaining || '' };
      } else if (toolName === 'web_search') {
        result = await bridge.webSearch(args.query);
      } else if (toolName === 'read_file') {
        result = await bridge.readFile(this.resolveToolPath(args?.path), args?.offset, args?.limit);
      } else if (toolName === 'fetch_url') {
        const url = String(args?.url || '').trim();
        if (!/^https?:\/\//i.test(url)) throw new Error('fetch_url requires an absolute http(s) URL');
        result = await bridge.fetchUrl(url);
      } else if (toolName === 'write_file') {
        const filePath = String(args?.path || args?.file || '').trim();
        const fileContent = typeof args?.content === 'string'
          ? args.content
          : typeof args?.contents === 'string'
            ? args.contents
            : typeof args?.text === 'string'
              ? args.text
              : typeof args?.code === 'string' ? args.code : null;
        if (!filePath || fileContent === null) {
          throw new Error('write_file requires a path and string content');
        }
        let original = '';
        try {
          original = await bridge.readFile(filePath);
        } catch {
          original = '';
        }
        const diffData: DiffData = {
          filePath,
          originalCode: original,
          modifiedCode: fileContent,
          status: 'pending',
        };
        storeActions.updateMessage(sessionId, messageId, { diff: diffData });
        result = { status: 'diff_created_awaiting_review' };
      } else if (toolName === 'list_directory') {
        result = await bridge.listDirectory(this.resolveToolPath(args?.path));
      } else if (toolName === 'exec_command') {
        const cmdData: CommandData = {
          command: args.command,
          cwd: args.cwd,
          status: 'pending',
        };
        storeActions.updateMessage(sessionId, messageId, { command: cmdData });
        result = { status: 'command_awaiting_approval' };
      } else if (toolName === 'take_screenshot') {
        result = await bridge.takeScreenshot(args.region);
      }

      setStore((prev) => {
        const updated = prev.sessions.map((session) => {
          if (session.id !== sessionId) return session;
          return {
            ...session,
            messages: session.messages.map((message) => {
              if (message.id !== messageId || !message.tools) return message;
              return {
                ...message,
                tools: message.tools.map((tool) => tool.id === toolCallId
                  ? { ...tool, status: 'completed' as const, result }
                  : tool),
              };
            }),
          };
        });
        return { sessions: updated };
      });

      return result;
    } catch (err: any) {
      setStore((prev) => {
        const updated = prev.sessions.map((session) => {
          if (session.id !== sessionId) return session;
          return {
            ...session,
            messages: session.messages.map((message) => {
              if (message.id !== messageId || !message.tools) return message;
              return {
                ...message,
                tools: message.tools.map((tool) => tool.id === toolCallId
                  ? { ...tool, status: 'error' as const, result: err.message }
                  : tool),
              };
            }),
          };
        });
        return { sessions: updated };
      });
      throw err;
    }
  }

  private resolveToolPath(rawPath: unknown): string {
    // No hardcoded fallback path here — that used to be the original
    // developer's own home directory, which doesn't exist on other
    // machines and sent the model down repeated failed guesses. Prefer the
    // real project path once bridge.ts has set it from GJS's
    // 'runtime_config' message; if it genuinely isn't known yet, return an
    // empty string and let the host-side handlers (which already default
    // to the real GLib.get_home_dir()) resolve it instead of guessing here.
    const projectRoot = getStore().projectPath || (typeof window !== 'undefined' ? (window as any).__hyprcandyHome : '') || '';
    const value = String(rawPath || '').trim();
    if (!value || value === '.' || /^(?:\/)?(?:path\/to\/)?project(?:[-_]root)?$/i.test(value)) return projectRoot;
    return value;
  }

  public async clearCache(): Promise<void> {
    this.syncCustomModels();
    if (llamaCppService.isEnabled()) {
      await llamaCppService.unload();
      setStore({ modelStatus: 'idle', downloadProgress: { progress: 0, text: 'llama-server stopped; downloaded model files remain cached' } });
      return;
    }
    if (!isElectronMode()) {
      const requestId = 'cache_clear_' + Date.now() + '_' + Math.random().toString(36).slice(2, 8);
      await new Promise<void>((resolve, reject) => {
        let timeoutId: number | undefined;
        const onCleared = (event: Event) => {
          const detail = (event as CustomEvent).detail || {};
          if (detail.requestId !== requestId) return;
          cleanup();
          if (detail.error) reject(new Error(detail.error));
          else resolve();
        };
        const onError = (event: Event) => {
          const detail = (event as CustomEvent).detail || {};
          if (detail.requestId !== requestId) return;
          cleanup();
          reject(new Error(detail.message || 'Electron worker cache clear failed'));
        };
        const cleanup = () => {
          if (timeoutId !== undefined) window.clearTimeout(timeoutId);
          window.removeEventListener('agent_worker_cache_cleared', onCleared);
          window.removeEventListener('agent_worker_error', onError);
        };
        window.addEventListener('agent_worker_cache_cleared', onCleared);
        window.addEventListener('agent_worker_error', onError);
        bridge.fireWorkerRequest('worker_clear_cache', {
          requestId,
          modelIds: [
            ...PRESET_MODELS.map((model) => model.id),
            ...getStore().customModels.map((model) => model.id),
          ],
          customModels: storeActions.getCustomWebLLMModels(),
        });
        timeoutId = window.setTimeout(() => {
          cleanup();
          reject(new Error('Electron worker cache clear timed out'));
        }, 30_000);
      });
      setStore({
        modelStatus: 'idle',
        downloadProgress: { progress: 0, text: 'Model cache cleared' },
      });
      return;
    }
    // Delete model-specific cache entries, not every IndexedDB database. This
    // preserves unrelated browser data and makes cache state observable per model.
    await webllmService.unload();
    const modelIds = [
      ...PRESET_MODELS.map((model) => model.id),
      ...getStore().customModels.map((model) => model.id),
    ];
    for (const modelId of Array.from(new Set(modelIds))) {
      await webllmService.deleteModelCache(modelId);
    }
    setStore({
      modelStatus: 'idle',
      downloadProgress: { progress: 0, text: 'Model cache cleared' },
    });
  }

  public async getCachedModelIds(modelIds: string[]): Promise<string[]> {
    this.syncCustomModels();
    const unique = Array.from(new Set(modelIds));
    if (llamaCppService.isEnabled()) {
      try {
        const cached = await Promise.all(unique.map(async (modelId) => {
          const spec = this.getNativeLlamaSpec(modelId);
          const input = spec?.repo && spec.file ? { id: modelId, repo: spec.repo, file: spec.file } : modelId;
          return await llamaCppService.hasModel(input) ? modelId : null;
        }));
        return cached.filter((modelId): modelId is string => Boolean(modelId));
      } catch { return []; }
    }
    if (!isElectronMode()) {
      const requestId = 'cache_status_' + Date.now() + '_' + Math.random().toString(36).slice(2, 8);
      return new Promise<string[]>((resolve, reject) => {
        let timeoutId: number | undefined;
        const onStatus = (event: Event) => {
          const detail = (event as CustomEvent).detail || {};
          if (detail.requestId !== requestId) return;
          cleanup();
          if (detail.error) reject(new Error(detail.error));
          else resolve(Array.isArray(detail.cachedModelIds) ? detail.cachedModelIds : []);
        };
        const onError = (event: Event) => {
          const detail = (event as CustomEvent).detail || {};
          if (detail.requestId !== requestId) return;
          cleanup();
          reject(new Error(detail.message || 'Electron worker cache inspection failed'));
        };
        const cleanup = () => {
          if (timeoutId !== undefined) window.clearTimeout(timeoutId);
          window.removeEventListener('agent_worker_cache_status', onStatus);
          window.removeEventListener('agent_worker_error', onError);
        };
        window.addEventListener('agent_worker_cache_status', onStatus);
        window.addEventListener('agent_worker_error', onError);
        bridge.fireWorkerRequest('worker_cache_status', {
          requestId,
          modelIds: unique,
          customModels: storeActions.getCustomWebLLMModels(),
        });
        timeoutId = window.setTimeout(() => {
          cleanup();
          reject(new Error('Electron worker cache inspection timed out'));
        }, 30_000);
      });
    }
    return webllmService.listCachedModelIds(unique);
  }
}

export const agentEngine = new AgentEngine();
