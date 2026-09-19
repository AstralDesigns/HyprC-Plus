/**
 * Agent Engine: orchestrates chat sessions and inline tool-call detection for
 * the visible React UI. All model inference (local llama.cpp, BYOK, and
 * managed cloud) runs through the local Python runtime server — see
 * Agents/local_runtime/ — over bridge.runtimeRequest(). There is no
 * Electron/Chromium renderer or in-browser WebLLM/Wllama engine anymore;
 * WebKitGTK is the only UI and inference-client surface.
 */
import { bridge } from '../bridge';
import {
  getStore,
  PRESET_MODELS,
  setStore,
  storeActions,
  ToolCallData,
} from '../store';

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

export class AgentEngine {
  private abortController: AbortController | null = null;
  private currentModelId: string | null = null;
  private activeTaskId: string | null = null;   // Python runtime /api/chat task id, for cancellation
  private conversationGeneration = 0;
  private activeConversationSettled: Promise<void> | null = null;

  public async loadModel(modelId: string, skipActiveConversationWait = false): Promise<void> {
    const requestedModelId = modelId || PRESET_MODELS[0].id;

    // ModelManager can be opened while a response is streaming. Never unload
    // the runtime underneath that stream; invalidate the conversation first
    // and let the serialized service transition drain the abort.
    if (!skipActiveConversationWait && this.currentModelId && this.currentModelId !== requestedModelId && this.abortController) {
      this.conversationGeneration++;
      this.abortController.abort();
      this.abortController = null;
      this.cancelActiveTask();
      setStore({ agentRunning: false });
      await this.activeConversationSettled?.catch(() => undefined);
    }

    const currentStore = getStore();
    const runtimeMode = currentStore.inferenceMode;

    // Cloud and BYOK models are hosted elsewhere — there's nothing local to
    // start. The Model Manager's Cloud tab already validated the license/key.
    if (runtimeMode === 'cloud' || runtimeMode === 'byok') {
      this.currentModelId = requestedModelId;
      setStore({ activeModel: requestedModelId, modelStatus: 'ready' });
      return;
    }

    // Local GGUF inference: ask the Python runtime to (re)start llama-server
    // with this model. This is the only local-model path now — the Model
    // Manager's Local tab activation toggle calls the same endpoint, so this
    // is mainly a safety net for when Composer finds modelStatus !== 'ready'.
    setStore({
      activeModel: requestedModelId,
      modelStatus: 'loading',
      downloadProgress: { progress: 50, text: `Starting local runtime for ${requestedModelId}…` },
    });
    try {
      const res = await bridge.runtimeRequest('/api/server/start', {
        model_path: requestedModelId,
        ctx_size: 0,
        max_tokens: 2048,
      });
      const modelName = res?.model_name || requestedModelId.split('/').pop()?.replace('.gguf', '') || requestedModelId;
      this.currentModelId = modelName;
      setStore({
        activeModel: modelName,
        modelStatus: 'ready',
        downloadProgress: { progress: 100, text: 'Ready' },
      });
    } catch (err: any) {
      setStore({ modelStatus: 'error', downloadProgress: { progress: 0, text: err?.message || 'Failed to start local server' } });
      throw err;
    }
  }

  public cancelModelLoad(): void {
    setStore({ modelStatus: 'idle', downloadProgress: { progress: 0, text: 'Model load cancelled' } });
  }

  /** Best-effort: tell the Python runtime to stop generating for the in-flight task. */
  private cancelActiveTask(): void {
    const taskId = this.activeTaskId;
    this.activeTaskId = null;
    if (!taskId) return;
    bridge.runtimeRequest(`/api/chat/cancel/${taskId}`, {}).catch(() => { /* best-effort */ });
  }

  public cancel(): void {
    this.conversationGeneration++;
    this.abortController?.abort();
    this.abortController = null;
    this.cancelActiveTask();
    setStore({ agentRunning: false });
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
    this.cancelActiveTask();
    if (previousConversation) await previousConversation.catch(() => undefined);
    const conversationGeneration = ++this.conversationGeneration;
    const isCurrentConversation = () => conversationGeneration === this.conversationGeneration;
    this.activeConversationSettled = conversationSettled;
    this.abortController = new AbortController();
    setStore({ agentRunning: true });

    const assistantMsgId = 'msg_' + Date.now() + '_runtime';
    storeActions.addMessage(sessionId, {
      id: assistantMsgId,
      role: 'assistant',
      content: '',
      timestamp: Date.now(),
      tools: [],
    });

    const streamUi = createStreamUpdateScheduler((content, tools) =>
      storeActions.updateMessage(sessionId, assistantMsgId, { content, tools: tools || [] })
    );

    let fullText = '';
    let currentTools: ToolCallData[] = [];
    const settleConversation = () => {
      this.activeTaskId = null;
      resolveConversation();
      if (this.activeConversationSettled === conversationSettled)
        this.activeConversationSettled = null;
    };

    try {
      const liveStore = getStore();
      const runtimeMode = liveStore.inferenceMode;
      const contextMode = liveStore.contextMode || 'minimal';

      // Project tree, sized by the user's chosen context level.
      const projectTree = (liveStore.projectFiles || [])
        .slice(0, contextMode === 'full' ? 600 : contextMode === 'smart' ? 80 : 600)
        .map((file) => `${file.isDir ? '[dir] ' : '[file]'} ${file.path || file.name}${file.size ? ` (${file.size} bytes)` : ''}`)
        .join('\n') || '(project tree is empty; use list_directory with the project root)';

      // Explicitly-attached context files (pasted/pinned by the user), read
      // through the GJS host so their live content is included every turn.
      const explicitContext = contextMode === 'minimal' ? [] : await Promise.all(
        (liveStore.contextFiles || []).slice(0, contextMode === 'full' ? 12 : 4).map(async (file) => {
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
        'Project tree (provided on the first turn; inspect file contents with tools when needed):',
        projectTree,
        contextMode === 'minimal' ? '' : liveStore.selectedFileContent
          ? `Selected file content:\n${liveStore.selectedFileContent.slice(0, contextMode === 'full' ? 12000 : 2500)}`
          : 'Selected file content: (not loaded)',
        'Use tools to inspect files when the supplied context is insufficient. Do not invent project facts.',
        explicitContext.join('\n'),
        (liveStore.contextImages || []).length
          ? `Image context attached (text model cannot inspect pixels directly): ${liveStore.contextImages.map(image => image.path).join(', ')}`
          : '',
        '[End HyprCandy project context]',
      ].join('\n');

      const payload: any = {
        messages: [
          ...history.map(m => ({ role: m.role, content: m.content })),
          { role: 'user', content: userPrompt },
        ],
        project_context: projectContext,
        inference_mode: runtimeMode,
      };
      if (runtimeMode === 'byok' && liveStore.byokProvider) {
        payload.byok_provider = liveStore.byokProvider;
        payload.byok_key = liveStore.byokKeys[liveStore.byokProvider] || '';
        payload.byok_model = liveStore.byokModel || '';
      } else if (runtimeMode === 'cloud') {
        payload.model_choice = liveStore.cloudModel || 'google/gemini-2.5-flash';
        payload.license_key = liveStore.licenseKey || undefined;
      }

      // Fire-and-forget: get task_id immediately, then poll for events.
      const startResult = await bridge.runtimeRequest('/api/chat/start', payload);
      if (!startResult?.task_id) throw new Error('Runtime did not return a task_id');

      const taskId: string = startResult.task_id;
      this.activeTaskId = taskId;
      let since = 0;
      const POLL_MS = 150;
      // 5-minute max poll timeout to prevent a spike on a crashed/stuck server.
      const POLL_TIMEOUT_MS = 5 * 60 * 1000;
      const pollStartTime = Date.now();

      await new Promise<void>((resolve, reject) => {
        const poll = async () => {
          if (!isCurrentConversation() || this.abortController?.signal.aborted) {
            return resolve();
          }
          if (Date.now() - pollStartTime > POLL_TIMEOUT_MS) {
            streamUi.cancel();
            this.cancelActiveTask();
            const prev = getStore().sessions.find(s => s.id === sessionId)
              ?.messages.find(m => m.id === assistantMsgId)?.content || '';
            storeActions.updateMessage(sessionId, assistantMsgId, {
              content: (prev || '') + '\n\n⚠️ **Agent timed out** — the runtime server may have crashed. Please restart it from the model manager.',
            });
            setStore({ agentRunning: false });
            this.abortController = null;
            settleConversation();
            return resolve();
          }

          try {
            const resp = await bridge.runtimeRequest(
              `/api/chat/poll/${taskId}?since=${since}`, {}, 'GET'
            );
            const events: any[] = resp.events || [];
            since = resp.total ?? since;

            for (const event of events) {
              if (!isCurrentConversation()) break;
              const type: string = event.type;
              // data is the nested payload — agent_loop yields {type, data}
              const data: any = event.data ?? event;

              if (type === 'token') {
                const token: string = typeof data === 'string' ? data : (data?.data ?? data ?? '');
                fullText += token;
                onToken?.(token);
                streamUi.schedule(fullText, currentTools.length ? currentTools : undefined);

              } else if (type === 'tool_start') {
                const tc: ToolCallData = {
                  id: data.id ?? `tool_${Date.now()}`,
                  name: data.name ?? 'unknown',
                  arguments: typeof data.arguments === 'string'
                    ? (() => { try { return JSON.parse(data.arguments || '{}'); } catch { return {}; } })()
                    : (data.arguments ?? {}),
                  status: 'running',
                };
                currentTools = [...currentTools, tc];
                streamUi.schedule(fullText, currentTools);

              } else if (type === 'tool_result') {
                currentTools = currentTools.map(t =>
                  t.id === data.id ? { ...t, status: 'completed', result: data.result } : t
                );
                streamUi.schedule(fullText, currentTools);

              } else if (type === 'tool_error') {
                currentTools = currentTools.map(t =>
                  t.id === data.id ? { ...t, status: 'error', result: data.error } : t
                );
                streamUi.schedule(fullText, currentTools);

              } else if (type === 'done') {
                if (data?.content && !fullText) {
                  fullText = data.content;
                  streamUi.schedule(fullText, currentTools.length ? currentTools : undefined);
                }
                streamUi.flush();
                setStore({ agentRunning: false });
                this.abortController = null;
                settleConversation();
                return resolve();

              } else if (type === 'error') {
                const errMsg = typeof data === 'string' ? data : (data?.message || 'Unknown runtime error');
                streamUi.cancel();
                const prev = getStore().sessions.find(s => s.id === sessionId)
                  ?.messages.find(m => m.id === assistantMsgId)?.content || '';
                storeActions.updateMessage(sessionId, assistantMsgId, {
                  content: (prev || '') + `\n\n⚠️ **Runtime error**: ${errMsg}`,
                });
                setStore({ agentRunning: false });
                this.abortController = null;
                settleConversation();
                return resolve();
              }
            }

            if (resp.done) {
              streamUi.flush();
              setStore({ agentRunning: false });
              this.abortController = null;
              settleConversation();
              return resolve();
            }

            setTimeout(poll, POLL_MS);
          } catch (err: any) {
            reject(err);
          }
        };
        setTimeout(poll, POLL_MS);
      });
    } catch (err: any) {
      streamUi.cancel();
      const prev = getStore().sessions.find(s => s.id === sessionId)
        ?.messages.find(m => m.id === assistantMsgId)?.content || '';
      storeActions.updateMessage(sessionId, assistantMsgId, {
        content: prev + `\n\n⚠️ **Runtime error**: ${err?.message || String(err)}`,
      });
      this.abortController = null;
      setStore({ agentRunning: false });
      settleConversation();
    }
  }


}

export const agentEngine = new AgentEngine();
