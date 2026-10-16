/**
 * Agent Engine: orchestrates chat sessions and inline tool-call detection for
 * the visible React UI. BYOK and managed-cloud inference run through the local
 * Python runtime server — see Agents/local_runtime/ — over
 * bridge.runtimeRequest(). There is no local inference backend: llama.cpp was
 * retired and WebLLM was removed after verifying Qt WebEngine cannot expose a
 * WebGPU adapter (see the §8.2 findings in the quest-flow plan).
 */
import { bridge } from '../bridge';
import {
  getStore,
  PRESET_MODELS,
  setStore,
  storeActions,
  ToolCallData,
  DiffData,
  MessageBlock,
  SuggestionsData,
} from '../store';

function createStreamUpdateScheduler(update: (content: string, tools: ToolCallData[] | undefined, blocks: MessageBlock[]) => void, intervalMs = 80) {
  let pending: { content: string; tools?: ToolCallData[]; blocks: MessageBlock[] } | null = null;
  let timer: ReturnType<typeof setTimeout> | null = null;
  const flush = () => {
    if (timer !== null) {
      clearTimeout(timer);
      timer = null;
    }
    if (!pending) return;
    const next = pending;
    pending = null;
    update(next.content, next.tools, next.blocks);
  };
  const schedule = (content: string, tools: ToolCallData[] | undefined, blocks: MessageBlock[]) => {
    pending = { content, tools, blocks };
    if (timer === null) timer = setTimeout(flush, intervalMs);
  };
  return { schedule, flush, cancel: () => { pending = null; if (timer !== null) clearTimeout(timer); timer = null; } };
}

let blockIdCounter = 0;
const nextBlockId = () => `block_${Date.now()}_${blockIdCounter++}`;

/** Client-generated id for a single agentic turn. Sent to the runtime as
 * `turn_id` so the per-turn edit ledger can group every write_file the turn
 * performs, and stored on the assistant Message so "Revert this turn" (and
 * edit-&-resend rollback) can restore the workspace to its pre-turn state. */
let turnIdCounter = 0;
const nextTurnId = () => `turn_${Date.now()}_${turnIdCounter++}`;

/** Turns a completed turn's own text into a short session title — used
 * once, the first time a session's first turn completes, so naming reflects
 * what the conversation is actually about rather than truncating whatever
 * the user happened to type first. */
function deriveSessionTitle(tools: ToolCallData[], fullText: string): string {
  const taskComplete = tools.find(t => t.name === 'task_complete' && t.status === 'completed');
  const summary = (taskComplete?.result as any)?.summary;
  const source = (typeof summary === 'string' && summary.trim()) ? summary : fullText;
  const firstLine = (source || '').split('\n').find(l => l.trim().length > 0) || '';
  const cleaned = firstLine.replace(/[#*`_>~]/g, '').trim();
  if (!cleaned) return '';
  const firstSentence = cleaned.split(/(?<=[.!?])\s/)[0] || cleaned;
  return firstSentence.length > 48 ? firstSentence.slice(0, 48).trim() + '…' : firstSentence;
}

const AMBIENT_TOOL_NAMES = new Set([
  'read_file', 'list_directory', 'web_search', 'fetch_url', 'capture_preview',
  'todo_add', 'todo_start', 'todo_done', 'todo_skip', 'todo_list',
  'list_memories', 'read_memory', 'save_memory', 'delete_memory',
]);

export class AgentEngine {
  private abortController: AbortController | null = null;
  private currentModelId: string | null = null;
  private activeTaskId: string | null = null;   // Python runtime /api/chat task id, for cancellation
  private conversationGeneration = 0;
  private activeConversationSettled: Promise<void> | null = null;
  private activeResolveConversation: (() => void) | null = null;
  /** Steering text the user queued for the in-flight turn. The poll loop drains
   *  this into the running block list for immediate visual feedback; the backend
   *  confirms receipt separately via a steer_ack event. */
  private pendingSteers: string[] = [];

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

    this.currentModelId = requestedModelId;
    setStore({ activeModel: requestedModelId, modelStatus: 'ready' });
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
    this.pendingSteers = [];
    setStore({ agentRunning: false, specApprovalPending: false });
    if (this.activeResolveConversation) {
      this.activeResolveConversation();
      this.activeResolveConversation = null;
    }
    this.activeConversationSettled = null;
  }

  /** Inject a steering instruction into the currently running turn.
   *  Returns true when the backend accepted it (so the caller can skip starting
   *  a fresh message); false when there's no active task or the turn already
   *  finished, in which case the composer falls back to a normal send. */
  public async steer(text: string): Promise<boolean> {
    const clean = (text || '').trim();
    const taskId = this.activeTaskId;
    if (!clean || !taskId) return false;
    try {
      const res: any = await bridge.runtimeRequest(`/api/chat/steer/${taskId}`, { text: clean });
      if (res?.ok) {
        this.pendingSteers.push(clean);
        return true;
      }
      return false;
    } catch {
      return false;
    }
  }

  /** Resolve a spec-driven Approve/Revise gate on the active turn.
   *  'approve' executes the plan; 'revise' re-drafts with `text` as feedback;
   *  'cancel' aborts. Returns true when the backend accepted it. */
  public async approve(action: 'approve' | 'revise' | 'cancel', text?: string): Promise<boolean> {
    const taskId = this.activeTaskId;
    if (!taskId) return false;
    try {
      const res: any = await bridge.runtimeRequest(
        `/api/chat/approve/${taskId}`,
        { action, text: text && text.trim() ? text.trim() : undefined },
      );
      if (res?.ok) {
        // Approving resumes execution; cancelling clears the gate. Revising keeps
        // it open — the loop re-emits drafting + awaiting_approval for the new plan.
        if (action === 'approve' || action === 'cancel') setStore({ specApprovalPending: false });
        return true;
      }
      if (res?.done) setStore({ specApprovalPending: false });
      return false;
    } catch {
      return false;
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
    this.activeResolveConversation = resolveConversation;
    this.abortController?.abort();
    this.cancelActiveTask();
    if (previousConversation) {
      // Race previous conversation drain with a strict timeout so a cancelled or stuck turn never deadlocks.
      await Promise.race([
        previousConversation,
        new Promise(r => setTimeout(r, 400)),
      ]).catch(() => undefined);
    }
    const conversationGeneration = ++this.conversationGeneration;
    const isCurrentConversation = () => conversationGeneration === this.conversationGeneration;
    this.activeConversationSettled = conversationSettled;
    this.abortController = new AbortController();
    this.pendingSteers = [];
    setStore({ agentRunning: true, activeSuggestions: null, specApprovalPending: false });

    const assistantMsgId = 'msg_' + Date.now() + '_runtime';
    const turnId = nextTurnId();
    storeActions.addMessage(sessionId, {
      id: assistantMsgId,
      role: 'assistant',
      content: '',
      timestamp: Date.now(),
      tools: [],
      turnId,
    });

    const streamUi = createStreamUpdateScheduler((content, tools, blocks) =>
      storeActions.updateMessage(sessionId, assistantMsgId, { content, tools: tools || [], blocks })
    );

    let fullText = '';
    let currentTools: ToolCallData[] = [];
    let blocks: MessageBlock[] = [];

    const appendToken = (token: string) => {
      const last = blocks[blocks.length - 1];
      if (last && last.type === 'text') {
        last.content += token;
        blocks = [...blocks.slice(0, -1), last];
      } else {
        blocks = [...blocks, { type: 'text', id: nextBlockId(), content: token }];
      }
    };

    // Consecutive reasoning deltas group into one collapsible block, mirroring
    // how tokens coalesce into a text block. Display-only — never fed back to
    // the model context (see plan §3.3).
    const appendReasoning = (text: string) => {
      const last = blocks[blocks.length - 1];
      if (last && last.type === 'reasoning') {
        blocks = [...blocks.slice(0, -1), { ...last, content: last.content + text }];
      } else {
        blocks = [...blocks, { type: 'reasoning', id: nextBlockId(), content: text }];
      }
    };

    const startAmbientTool = (tc: ToolCallData) => {
      const last = blocks[blocks.length - 1];
      if (last && last.type === 'activity') {
        blocks = [...blocks.slice(0, -1), { ...last, tools: [...last.tools, tc] }];
      } else {
        blocks = [...blocks, { type: 'activity', id: nextBlockId(), tools: [tc] }];
      }
    };

    const startCommandTool = (tc: ToolCallData) => {
      // Elevated: shell commands always get their own foreground block, never
      // grouped or hidden inside the collapsed activity timeline.
      blocks = [...blocks, { type: 'command', id: nextBlockId(), tool: tc }];
    };

    /** Applies a tool_result/tool_error update to whichever block holds that
     * tool id — an 'activity' block's grouped tools array, or a standalone
     * 'command' block. */
    const updateToolInBlocks = (id: string, updater: (t: ToolCallData) => ToolCallData) => {
      blocks = blocks.map(b => {
        if (b.type === 'activity') {
          if (!b.tools.some(t => t.id === id)) return b;
          return { ...b, tools: b.tools.map(t => t.id === id ? updater(t) : t) };
        }
        if (b.type === 'command' && b.tool.id === id) {
          return { ...b, tool: updater(b.tool) };
        }
        return b;
      });
    };

    let settled = false;
    const settleConversation = () => {
      if (settled) return;
      settled = true;
      this.activeTaskId = null;
      if (this.activeResolveConversation === resolveConversation) {
        this.activeResolveConversation = null;
      }
      resolveConversation();
      if (this.activeConversationSettled === conversationSettled) {
        this.activeConversationSettled = null;
      }
    };

    try {
      const liveStore = getStore();
      const runtimeMode = liveStore.inferenceMode;
      const contextMode = liveStore.contextMode || 'minimal';

      // Project tree, sized by the user's chosen context level. This is
      // *automatic* orientation context, separate from explicit attachments
      // below — 'minimal' means "barely any auto-discovered tree", not "drop
      // everything the user explicitly attached".
      const treeLimit = contextMode === 'full' ? 600 : contextMode === 'smart' ? 80 : 25;
      const projectTree = (liveStore.projectFiles || [])
        .slice(0, treeLimit)
        .map((file) => `${file.isDir ? '[dir] ' : '[file]'} ${file.path || file.name}${file.size ? ` (${file.size} bytes)` : ''}`)
        .join('\n') || '(project tree is empty; use list_directory with the project root)';

      // Explicit context (files the user attached via the composer's Context
      // chips) is never gated by contextMode — the user deliberately picked
      // these, already capped to a handful of files, so they always make it
      // into the prompt regardless of how much *automatic* project context
      // the current mode allows.
      const explicitContext = await Promise.all(
        (liveStore.contextFiles || []).slice(0, contextMode === 'full' ? 12 : 6).map(async (file) => {
          try {
            const content = await bridge.readFile(file.path);
            return `[Explicit context file: ${file.path}]\n${content.slice(0, contextMode === 'full' ? 20000 : 8000)}\n[End explicit context file]`;
          } catch (error: any) {
            return `[Explicit context file unavailable: ${file.path}] ${error?.message || String(error)}`;
          }
        }),
      );
      const hasExplicitContext = explicitContext.length > 0;

      const projectContext = [
        '[HyprCandy project context]',
        `Project root: ${liveStore.projectPath || '(unknown)'}`,
        `Selected file: ${liveStore.selectedFile || '(none)'}`,
        hasExplicitContext
          ? [
              'The user explicitly attached the following file(s) as context for this request.',
              'Treat them as the authoritative source for this turn — read and answer from them',
              'directly. Only fall back to list_directory/read_file if the attached files genuinely',
              "don't contain what's needed to answer.",
              ...explicitContext,
            ].join('\n')
          : '',
        'Project tree (for orientation only; inspect file contents with tools when needed):',
        projectTree,
        contextMode === 'minimal' ? '' : liveStore.selectedFileContent
          ? `Selected file content:\n${liveStore.selectedFileContent.slice(0, contextMode === 'full' ? 12000 : 2500)}`
          : 'Selected file content: (not loaded)',
        'Do not invent project facts.',
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
      if (liveStore.specMode) payload.spec_enabled = true;
      if (liveStore.projectPath) payload.project_path = liveStore.projectPath;
      payload.turn_id = turnId;

      // Fire-and-forget: get task_id immediately, then poll for events.
      const startResult = await bridge.runtimeRequest('/api/chat/start', payload);
      if (!startResult?.task_id) throw new Error('Runtime did not return a task_id');

      const taskId: string = startResult.task_id;
      this.activeTaskId = taskId;
      let since = 0;
      const POLL_MS = 150;
      // Idle-based timeout: a turn is treated as hung only when NO events have
      // arrived for this long. The loop emits heartbeats while blocked on the
      // spec-approval gate and verification runs are non-blocking, so long
      // legitimate waits stay alive; a genuinely stuck runtime still trips here.
      const IDLE_TIMEOUT_MS = 6 * 60 * 1000;
      let lastActivity = Date.now();

      await new Promise<void>((resolve, reject) => {
        const poll = async () => {
          if (!isCurrentConversation() || this.abortController?.signal.aborted) {
            streamUi.cancel();
            settleConversation();
            return resolve();
          }
          if (Date.now() - lastActivity > IDLE_TIMEOUT_MS) {
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
            if (events.length) lastActivity = Date.now();

            // Render any steering the user queued since the last poll immediately,
            // so it shows in the stream ahead of the model's next output.
            if (this.pendingSteers.length) {
              const drained = this.pendingSteers.splice(0, this.pendingSteers.length);
              for (const s of drained) {
                blocks = [...blocks, { type: 'steer', id: nextBlockId(), content: s }];
              }
              streamUi.schedule(fullText, currentTools.length ? currentTools : undefined, blocks);
            }

            for (const event of events) {
              if (!isCurrentConversation()) break;
              const type: string = event.type;
              // data is the nested payload — agent_loop yields {type, data}
              const data: any = event.data ?? event;

              if (type === 'token') {
                const token: string = typeof data === 'string' ? data : (data?.data ?? data ?? '');
                fullText += token;
                onToken?.(token);
                appendToken(token);
                streamUi.schedule(fullText, currentTools.length ? currentTools : undefined, blocks);

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
                // write_file and task_complete get no placeholder block — the
                // former becomes a diff block once the write actually lands
                // (near-instant), the latter is rendered separately as the
                // end-of-turn summary once it completes.
                if (tc.name === 'exec_command' || tc.name === 'run_command') {
                  startCommandTool(tc);
                } else if (AMBIENT_TOOL_NAMES.has(tc.name)) {
                  startAmbientTool(tc);
                }
                streamUi.schedule(fullText, currentTools, blocks);

              } else if (type === 'tool_result') {
                const matched = currentTools.find(t => t.id === data.id);
                currentTools = currentTools.map(t =>
                  t.id === data.id ? { ...t, status: 'completed', result: data.result } : t
                );
                updateToolInBlocks(data.id, t => ({ ...t, status: 'completed', result: data.result }));

                // Durable-memory edits land on disk here; tell the Memories panel
                // to refresh live so it never needs a manual reload.
                if (matched?.name === 'save_memory' || matched?.name === 'delete_memory') {
                  if (typeof window !== 'undefined') {
                    window.dispatchEvent(new CustomEvent('agent-memories-changed'));
                  }
                }

                if (matched?.name === 'write_file' && data.result && typeof data.result === 'object' && data.result.success) {
                  const r = data.result;
                  const diff: DiffData = {
                    filePath: r.path,
                    originalCode: r.old_content || '',
                    modifiedCode: r.new_content || '',
                    status: 'pending',
                    additions: r.additions || 0,
                    deletions: r.deletions || 0,
                    isNew: !!r.is_new,
                  };
                  storeActions.registerPendingFile({
                    path: r.path, additions: diff.additions!, deletions: diff.deletions!,
                    isNew: diff.isNew!, oldContent: diff.originalCode, newContent: diff.modifiedCode,
                    timestamp: Date.now(),
                  });
                  storeActions.appendDiff(sessionId, assistantMsgId, diff);
                  blocks = [...blocks, { type: 'diff', id: nextBlockId(), diff }];
                }
                streamUi.schedule(fullText, currentTools, blocks);

              } else if (type === 'tool_error') {
                currentTools = currentTools.map(t =>
                  t.id === data.id ? { ...t, status: 'error', result: data.error } : t
                );
                updateToolInBlocks(data.id, t => ({ ...t, status: 'error', result: data.error }));
                streamUi.schedule(fullText, currentTools, blocks);

              } else if (type === 'reasoning') {
                const rt: string = typeof data === 'string' ? data : (data?.text ?? '');
                if (rt) {
                  appendReasoning(rt);
                  streamUi.schedule(fullText, currentTools.length ? currentTools : undefined, blocks);
                }

              } else if (type === 'suggestions') {
                const sd = (typeof data === 'string' ? null : data) as SuggestionsData | null;
                if (sd && Array.isArray(sd.options) && sd.options.length) {
                  blocks = [...blocks, { type: 'suggestions', id: nextBlockId(), suggestions: sd }];
                  // Mirror to the composer chip row; clarify chips stay live after
                  // the turn ends, next-step ones are refreshed by the next run.
                  setStore({ activeSuggestions: sd });
                  streamUi.schedule(fullText, currentTools.length ? currentTools : undefined, blocks);
                }

              } else if (type === 'steer_ack') {
                // The composer already rendered this steer optimistically via
                // pendingSteers; the backend ack is receipt-confirmation only.

              } else if (type === 'spec') {
                const status: 'drafting' | 'ready' = data?.status === 'ready' ? 'ready' : 'drafting';
                const markdown: string = data?.markdown ?? '';
                const lastIdx = blocks.reduce((acc, b, i) => (b.type === 'spec' ? i : acc), -1);
                const lastSpec = lastIdx >= 0 ? blocks[lastIdx] : undefined;
                if (status === 'ready' && lastSpec && lastSpec.type === 'spec' && lastSpec.status === 'drafting') {
                  // Fill the trailing drafting placeholder with the finished plan.
                  blocks = blocks.map((b, i) => i === lastIdx ? { type: 'spec', id: b.id, status: 'ready', markdown } : b);
                } else {
                  blocks = [...blocks, { type: 'spec', id: nextBlockId(), status, markdown }];
                }
                streamUi.schedule(fullText, currentTools.length ? currentTools : undefined, blocks);

              } else if (type === 'awaiting_approval') {
                setStore({ specApprovalPending: true });

              } else if (type === 'verification') {
                const command: string = data?.command ?? '';
                const status: 'running' | 'complete' = data?.status === 'complete' ? 'complete' : 'running';
                const lastIdx = blocks.reduce((acc, b, i) => (b.type === 'verification' ? i : acc), -1);
                const lastVer = lastIdx >= 0 ? blocks[lastIdx] : undefined;
                const id = lastVer ? lastVer.id : nextBlockId();
                const vblk: MessageBlock = { type: 'verification', id, command, status, exitCode: data?.exitCode, output: data?.output, passed: data?.passed };
                if (status === 'complete' && lastVer && lastVer.type === 'verification' && lastVer.status === 'running') {
                  // Update the running card in place with the result.
                  blocks = blocks.map((b, i) => i === lastIdx ? vblk : b);
                } else {
                  blocks = [...blocks, vblk];
                }
                streamUi.schedule(fullText, currentTools.length ? currentTools : undefined, blocks);

              } else if (type === 'heartbeat') {
                // Keepalive while the loop is blocked (spec gate); already
                // refreshed lastActivity above since it counts as an event.
              } else if (type === 'done') {
                if (data?.content && !fullText) {
                  fullText = data.content;
                  appendToken(fullText);
                  streamUi.schedule(fullText, currentTools.length ? currentTools : undefined, blocks);
                }
                streamUi.flush();
                setStore({ agentRunning: false });
                this.abortController = null;
                // Name the session from its own first exchange rather than
                // the raw prompt — only while it's still on the placeholder
                // title (a manual rename always wins, see autoNameSession).
                const owningSession = getStore().sessions.find(s => s.id === sessionId);
                if (owningSession && owningSession.titleSource !== 'user' &&
                    owningSession.messages.filter(m => m.role === 'user').length === 1) {
                  const title = deriveSessionTitle(currentTools, fullText);
                  if (title) storeActions.autoNameSession(sessionId, title);
                }
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
      if (isCurrentConversation()) {
        streamUi.cancel();
        const prev = getStore().sessions.find(s => s.id === sessionId)
          ?.messages.find(m => m.id === assistantMsgId)?.content || '';
        storeActions.updateMessage(sessionId, assistantMsgId, {
          content: prev + `\n\n⚠️ **Runtime error**: ${err?.message || String(err)}`,
        });
      }
    } finally {
      streamUi.flush();
      if (isCurrentConversation()) {
        setStore({ agentRunning: false });
        this.abortController = null;
      }
      settleConversation();
    }
  }


}

export const agentEngine = new AgentEngine();
