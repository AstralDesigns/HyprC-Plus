import React, { useEffect, useRef, useState, useCallback } from 'react';
import ReactMarkdown from 'react-markdown';
import {
  Globe, FileText, Terminal, FileDiff,
  ChevronDown, ChevronRight, CheckCircle, Clock, Sparkles,
  Folder, Copy, Check, Edit2, RotateCcw,
  Brain, Zap, Eye, ListChecks,
  X,
} from 'lucide-react';
import { useStore, getStore, Message, ToolCallData, storeActions, setStore, type PlanTask, type SuggestionsData, type SuggestionOption } from '../store';
import { bridge } from '../bridge';
import { FileIcon } from '../utils/fileIcons';
import { DiffWidget } from './DiffWidget';
import { CommandWidget } from './CommandWidget';
import { agentEngine } from '../engine/agent-engine';

/* ── Empty chat screen ──────────────────────────────────────────────── */
const EmptyChatScreen: React.FC = () => (
  <div className="chat-empty-stream animate-fade-in">
    <div className="chat-empty-icon-box">
      <Sparkles size={20} color="var(--accent-cyan)" />
    </div>
    <p className="chat-empty-title">Ready for instructions</p>
    <p className="chat-empty-hint">
      Ask a question, request code modifications, or attach files below.
    </p>
  </div>
);

/* ── Inline agentic phase indicator ────────────────────────────────── */
interface AgentPhase {
  kind: 'thinking' | 'searching' | 'reading' | 'writing' | 'running' | 'planning' | 'todo';
  label?: string;
}

const PHASE_META: Record<string, { icon: React.ReactNode; label: string; color: string }> = {
  thinking: { icon: <Brain size={12} />, label: 'Thinking…', color: 'var(--matugen-primary, #a0c9dc)' },
  searching: { icon: <Globe size={12} />, label: 'Searching the web…', color: 'var(--matugen-primary, #a0c9dc)' },
  reading:   { icon: <Eye size={12} />, label: 'Reading files…', color: 'var(--matugen-secondary, #b2cbd6)' },
  writing:   { icon: <FileDiff size={12} />, label: 'Writing file…', color: 'var(--matugen-primary, #a0c9dc)' },
  running:   { icon: <Terminal size={12} />, label: 'Running command…', color: 'var(--matugen-secondary, #b2cbd6)' },
  planning:  { icon: <Zap size={12} />, label: 'Planning…', color: 'var(--matugen-primary, #a0c9dc)' },
  todo:      { icon: <ListChecks size={12} />, label: 'Updating plan…', color: 'var(--matugen-secondary, #b2cbd6)' },
};

function deriveAgentPhase(tools?: ToolCallData[]): AgentPhase | null {
  if (!tools || tools.length === 0) return { kind: 'thinking' };
  const running = [...tools].reverse().find(t => t.status === 'running');
  if (!running) return null;
  if (running.name === 'web_search') return { kind: 'searching', label: `Searching: "${running.arguments?.query || ''}"` };
  if (running.name === 'read_file') return { kind: 'reading', label: `Reading ${running.arguments?.path?.split('/').pop() || ''}` };
  if (running.name === 'write_file') return { kind: 'writing', label: `Writing ${running.arguments?.path?.split('/').pop() || ''}` };
  if (running.name === 'list_directory') return { kind: 'reading', label: `Listing ${running.arguments?.path || ''}` };
  if (running.name === 'exec_command') return { kind: 'running', label: `$ ${running.arguments?.command || ''}` };
  if (running.name === 'run_command') return { kind: 'running', label: `$ ${running.arguments?.command || ''}` };
  if (['todo_add', 'todo_start', 'todo_done', 'todo_skip', 'todo_list'].includes(running.name)) {
    return { kind: 'todo', label: 'Updating plan…' };
  }
  if (running.name === 'task_complete') return { kind: 'planning', label: 'Completing task…' };
  return { kind: 'thinking' };
}

const AgentPhaseIndicator: React.FC<{ phase: AgentPhase; label?: string }> = ({ phase, label }) => {
  const meta = PHASE_META[phase.kind] || PHASE_META.thinking;
  const displayLabel = label || phase.label || meta.label;
  return (
    <div className="agent-phase-indicator animate-fade-in">
      <span className="agent-phase-dot" style={{ background: meta.color }} />
      <span style={{ color: meta.color }}>{meta.icon}</span>
      <span className="agent-phase-label" style={{ color: meta.color }}>{displayLabel}</span>
    </div>
  );
};

/* ── Elevated vs ambient tool classification ──────────────────────────
   Elevated tools (file writes, shell commands) always render as their own
   foreground card — never hidden inside the collapsed activity line.
   Everything else ("ambient" — reads, listings, search, plan bookkeeping)
   collapses into a single line that morphs to show the current step, and
   expands into a cascading timeline on click. */
const ELEVATED_TOOLS = ['write_file', 'exec_command', 'run_command'];

function isElevatedTool(name: string) {
  return ELEVATED_TOOLS.includes(name) || name === 'task_complete';
}

const AMBIENT_META: Record<string, { icon: React.ReactNode; label: (a: any) => string }> = {
  web_search:     { icon: <Globe size={12} />, label: a => `Searched: "${a?.query || a?.q || ''}"` },
  fetch_url:      { icon: <Globe size={12} />, label: a => `Fetched ${a?.url || ''}` },
  read_file:      { icon: <Eye size={12} />, label: a => `Read ${(a?.path || '').split('/').pop() || a?.path || ''}` },
  list_directory: { icon: <Folder size={12} />, label: a => `Listed ${a?.path || '.'}` },
  todo_add:       { icon: <ListChecks size={12} />, label: a => `Planned: ${a?.title || a?.task || ''}` },
  todo_start:     { icon: <ListChecks size={12} />, label: a => `Started: ${a?.title || ''}` },
  todo_done:      { icon: <ListChecks size={12} />, label: a => `Done: ${a?.title || ''}` },
  todo_skip:      { icon: <ListChecks size={12} />, label: a => `Skipped: ${a?.title || ''}` },
  todo_list:      { icon: <ListChecks size={12} />, label: () => 'Reviewed the plan' },
};

function ambientLabel(tool: ToolCallData): { icon: React.ReactNode; text: string } {
  const meta = AMBIENT_META[tool.name] || { icon: <Brain size={12} />, label: () => tool.name };
  return { icon: meta.icon, text: meta.label(tool.arguments) };
}

/* ── Interstitial narration: brief text between tool calls, rendered as a
   thin gradient separator rather than a full response bubble. Never the
   final answer of a turn — only text a model emits mid-loop ("Let me check
   the config first…"). Skippable by nature: if the model doesn't emit any,
   nothing renders here at all. Not expandable/interactive — the chevron is
   purely a "this wrapped to more than one line" hint, shown only when the
   text actually doesn't fit on one line at the panel's current width. */
const InterstitialLine: React.FC<{ text: string }> = ({ text }) => {
  const textRef = useRef<HTMLSpanElement>(null);
  const [wrapped, setWrapped] = useState(false);
  const trimmed = text.trim();

  useEffect(() => {
    const el = textRef.current;
    if (!el) return;
    const measure = () => setWrapped(el.scrollWidth > el.clientWidth + 1);
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, [trimmed]);

  if (!trimmed) return null;
  return (
    <div className="agent-interstitial">
      <span ref={textRef} className={`agent-interstitial-text ${wrapped ? 'agent-interstitial-text-wrap' : ''}`}>
        {trimmed}
      </span>
      {wrapped && <ChevronRight size={12} className="agent-interstitial-chevron" />}
    </div>
  );
};

/* ── Live task checklist (§3.5) ─────────────────────────────────────────
   The Python agent loop's todo_add/start/done/skip/list tools all carry the
   authoritative plan snapshot in their tool_result `list` string (rendered by
   _TodoList.format()), e.g.:
       Todo (1/3 done):
         ✓ [1] Read the config
         ▶ [2] Edit the composer
         ☐ [3] Verify build
   We replay the latest such snapshot across the session's assistant turns and
   promote it to a live PlanTask[] checklist card instead of the old
   "Updating plan…" activity line alone. Reuses the existing PlanTask type. */
const TODO_TOOL_NAMES = ['todo_add', 'todo_start', 'todo_done', 'todo_skip', 'todo_list'];

function parseTodoList(text: string): PlanTask[] {
  const tasks: PlanTask[] = [];
  for (const rawLine of (text || '').split('\n')) {
    const line = rawLine.trim();
    // "✓ [2] Edit the composer (skipped: …)" — mark, [id], title
    const m = line.match(/^([✓▶○☐])\s*\[(\d+)\]\s*(.*)$/);
    if (!m) continue;
    const [, mark, id, rest] = m;
    const status: PlanTask['status'] =
      mark === '✓' ? 'completed' :
      mark === '▶' ? 'in_progress' :
      mark === '○' ? 'blocked' : 'pending';
    // Strip a trailing "(skipped: reason)" note into detail.
    let detail: string | undefined;
    let title = rest.trim();
    const skipNote = title.match(/\s*\(skipped:\s*(.*)\)$/i);
    if (skipNote) { detail = skipNote[1]; title = title.replace(skipNote[0], '').trim(); }
    tasks.push({ id, title, status, detail });
  }
  return tasks;
}

/** Most recent plan snapshot present in a session's messages, if any. */
function deriveLivePlan(messages: Message[]): PlanTask[] {
  let latest: PlanTask[] = [];
  for (const msg of messages) {
    if (msg.role !== 'assistant') continue;
    for (const tool of msg.tools || []) {
      if (!TODO_TOOL_NAMES.includes(tool.name) || tool.status !== 'completed') continue;
      const list = (tool.result as any)?.list;
      if (typeof list === 'string' && list.includes('[')) {
        const parsed = parseTodoList(list);
        if (parsed.length > 0) latest = parsed;
      }
    }
  }
  return latest;
}

const PlanChecklistCard: React.FC<{ tasks: PlanTask[]; running: boolean }> = ({ tasks, running }) => {
  const [collapsed, setCollapsed] = useState(false);
  const done = tasks.filter(t => t.status === 'completed').length;
  const allDone = done === tasks.length && tasks.length > 0;
  const boxColor = (s: PlanTask['status']) =>
    s === 'completed' ? '#22c55e' : s === 'in_progress' ? 'var(--matugen-primary, #a0c9dc)' : s === 'blocked' ? 'var(--matugen-error, #ffb4ab)' : 'var(--text-muted)';
  return (
    <div className="plan-checklist-card animate-fade-in">
      <div className="plan-checklist-header" onClick={() => setCollapsed(c => !c)}>
        {collapsed ? <ChevronRight size={13} /> : <ChevronDown size={13} />}
        <ListChecks size={13} color={allDone ? '#22c55e' : 'var(--matugen-primary, #a0c9dc)'} />
        <span className="plan-checklist-title">Quest plan</span>
        <span className="plan-checklist-count">{done}/{tasks.length}</span>
        {running && !allDone && <Clock size={11} className="agent-activity-spin" />}
      </div>
      {!collapsed && (
        <div className="plan-checklist-body">
          {tasks.map(t => (
            <label key={t.id} className={`plan-checklist-row status-${t.status}`} title={t.detail}>
              <span className="plan-checklist-box" style={{ borderColor: boxColor(t.status), color: boxColor(t.status) }}>
                {t.status === 'completed' ? <Check size={11} />
                  : t.status === 'in_progress' ? <Zap size={10} />
                  : t.status === 'blocked' ? <X size={10} /> : null}
              </span>
              <span className="plan-checklist-text">{t.title}</span>
            </label>
          ))}
        </div>
      )}
    </div>
  );
};

/* ── Agent activity: single morphing line ↔ cascading timeline ────────── */
const AgentActivity: React.FC<{ tools: ToolCallData[]; running: boolean }> = ({ tools, running }) => {
  const [expanded, setExpanded] = useState(false);
  const ambient = tools.filter(t => !isElevatedTool(t.name));
  if (ambient.length === 0) return null;

  const activeStep = running ? [...ambient].reverse().find(t => t.status === 'running') : null;
  const lastStep = ambient[ambient.length - 1];
  const headerStep = activeStep || lastStep;
  const { icon, text } = ambientLabel(headerStep);
  const isLive = !!activeStep;

  return (
    <div className={`agent-activity ${expanded ? 'agent-activity-expanded' : ''}`}>
      <div className="agent-activity-line" onClick={() => setExpanded(!expanded)}>
        {expanded ? <ChevronDown size={12} /> : <ChevronRight size={12} />}
        <span className={`agent-activity-icon ${isLive ? 'agent-activity-icon-live' : ''}`}>{icon}</span>
        <span className="agent-activity-label">{text}</span>
        <span className="agent-activity-count">{ambient.length} step{ambient.length === 1 ? '' : 's'}</span>
      </div>

      {expanded && (
        <div className="agent-activity-cascade">
          {ambient.map(tool => {
            const row = ambientLabel(tool);
            return (
              <div key={tool.id} className="agent-activity-row">
                <span className={`agent-activity-row-icon status-${tool.status}`}>{row.icon}</span>
                <span className="agent-activity-row-label">{row.text}</span>
                {tool.status === 'running'
                  ? <Clock size={11} className="agent-activity-spin" />
                  : tool.status === 'error'
                  ? <X size={11} color="var(--matugen-error, #ef4444)" />
                  : <CheckCircle size={11} color="#22c55e" />}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};


const TaskCompleteWidget: React.FC<{ summary: string; remaining?: string }> = ({ summary, remaining }) => (
  <div style={{
    margin: '7px 0',
    padding: '10px 12px',
    border: '1px solid color-mix(in srgb, var(--matugen-primary, #a0c9dc) 38%, transparent)',
    borderRadius: 'var(--radius-sm)',
    background: 'color-mix(in srgb, var(--matugen-primary, #a0c9dc) 9%, transparent)'
  }}>
    <div style={{ display: 'flex', alignItems: 'center', gap: '6px', color: 'var(--matugen-primary, #a0c9dc)', fontSize: '11px', fontWeight: 600, marginBottom: '5px' }}>
      <CheckCircle size={13} color="#22c55e" /> Task complete
    </div>
    <div className="markdown-body" style={{ color: 'var(--text-primary)', fontSize: '12px' }}>
      <ReactMarkdown>{summary}</ReactMarkdown>
    </div>
    {remaining ? <div style={{ marginTop: '5px', color: 'var(--text-muted)', fontSize: '10px' }}>Remaining: {remaining}</div> : null}
  </div>
);

/* ── Main stream ────────────────────────────────────────────────────── */
/* ── Visible reasoning: collapsible, dimmed chain-of-thought ─────── */
const ReasoningSection: React.FC<{ content: string; live: boolean }> = ({ content, live }) => {
  const [expanded, setExpanded] = useState(false);
  return (
    <div className={`reasoning-section ${expanded ? 'reasoning-expanded' : ''}`}>
      <div className="reasoning-header" onClick={() => setExpanded(e => !e)}>
        {expanded ? <ChevronDown size={12} /> : <ChevronRight size={12} />}
        <Brain size={12} />
        <span className="reasoning-title">Thinking</span>
        {live && <Clock size={11} className="agent-activity-spin" />}
      </div>
      {expanded && <div className="reasoning-body">{content}</div>}
    </div>
  );
};

/* ── Steering marker: an instruction the user injected mid-run ─────── */
const SteerMarker: React.FC<{ content: string }> = ({ content }) => (
  <div className="steer-marker animate-fade-in">
    <Zap size={11} />
    <span className="steer-marker-label">Steered</span>
    <span className="steer-marker-text">{content}</span>
  </div>
);

/* Tapping a chip dispatches its promptText: steer the running turn when one is
   active (or when the option opts into it), otherwise start a fresh turn via the
   composer's agent_user_prompt path. Consumed chips clear the composer row. */
const dispatchSuggestion = (opt: SuggestionOption) => {
  const text = (opt.promptText || opt.label || '').trim();
  if (!text) return;
  setStore({ activeSuggestions: null });
  const running = getStore().agentRunning;
  if (opt.sendAs === 'steer' || running) {
    void agentEngine.steer(text).then((ok) => {
      if (!ok) window.dispatchEvent(new CustomEvent('agent_user_prompt', { detail: text }));
    });
  } else {
    window.dispatchEvent(new CustomEvent('agent_user_prompt', { detail: text }));
  }
};

/* ── Suggestion chips (clarify / next-step) ──────────────────── */
const SuggestionChips: React.FC<{ data: SuggestionsData }> = ({ data }) => (
  <div className="suggestion-block animate-fade-in">
    {data.question ? <div className="suggestion-question">{data.question}</div> : null}
    <div className="suggestion-chips">
      {data.options.map((opt, idx) => (
        <button
          key={`${opt.label}-${idx}`}
          type="button"
          className="suggestion-chip"
          onClick={() => dispatchSuggestion(opt)}
        >
          {opt.label}
        </button>
      ))}
    </div>
  </div>
);

/* ── Spec-driven plan card (§3.4): markdown + Approve/Revise/Cancel gate ── */
const SpecCard: React.FC<{ markdown: string; status: 'drafting' | 'ready'; actionable: boolean }> = ({ markdown, status, actionable }) => {
  const [revising, setRevising] = useState(false);
  const [reviseText, setReviseText] = useState('');
  const [busy, setBusy] = useState(false);
  const act = (fn: () => Promise<boolean>) => { setBusy(true); void fn().finally(() => setBusy(false)); };
  return (
    <div className="spec-card animate-fade-in">
      <div className="spec-card-header">
        <ListChecks size={14} />
        <span className="spec-card-title">Implementation plan</span>
        {status === 'drafting' && <span className="spec-card-badge">drafting…</span>}
      </div>
      <div className="spec-card-body">
        {status === 'drafting'
          ? <div className="spec-card-drafting">Drafting a plan for your review…</div>
          : <div className="markdown-body"><ReactMarkdown>{markdown}</ReactMarkdown></div>}
      </div>
      {actionable && status === 'ready' && (
        <div className="spec-card-actions">
          {revising ? (
            <div className="spec-revise">
              <textarea
                className="spec-revise-input"
                value={reviseText}
                onChange={e => setReviseText(e.target.value)}
                placeholder="What should change about this plan?"
                rows={2}
              />
              <div className="spec-revise-btns">
                <button className="spec-btn spec-btn-ghost" onClick={() => setRevising(false)} disabled={busy}>Back</button>
                <button className="spec-btn" onClick={() => act(() => agentEngine.approve('revise', reviseText).then(() => { setReviseText(''); setRevising(false); return true; }))} disabled={busy || !reviseText.trim()}>Send revision</button>
              </div>
            </div>
          ) : (
            <>
              <button className="spec-btn spec-btn-primary" onClick={() => act(() => agentEngine.approve('approve'))} disabled={busy}><CheckCircle size={13} /> Approve &amp; execute</button>
              <button className="spec-btn" onClick={() => setRevising(true)} disabled={busy}><Edit2 size={12} /> Revise</button>
              <button className="spec-btn spec-btn-ghost" onClick={() => act(() => agentEngine.approve('cancel'))} disabled={busy}><X size={12} /> Cancel</button>
            </>
          )}
        </div>
      )}
    </div>
  );
};

/* ── Verification gate card (§3.8): build/test result with log ─────── */
const VerificationCard: React.FC<{ command: string; status: 'running' | 'complete'; exitCode?: number; output?: string; passed?: boolean }> = ({ command, exitCode, output, passed }) => {
  const [open, setOpen] = useState(false);
  return (
    <div className={`verification-card animate-fade-in ${passed === true ? 'status-passed' : passed === false ? 'status-failed' : 'status-running'}`}>
      <div className="verification-header" onClick={() => output && setOpen(o => !o)}>
        {passed === true
          ? <CheckCircle size={13} color="#22c55e" />
          : passed === false
          ? <X size={13} color="var(--matugen-error, #ef4444)" />
          : <Clock size={13} className="agent-activity-spin" />}
        <Terminal size={12} />
        <code className="verification-cmd">{command}</code>
        <span className="verification-status">
          {passed === true ? 'passed' : passed === false ? `failed · exit ${exitCode}` : 'running…'}
        </span>
        {output ? <span className="verification-toggle">{open ? <ChevronDown size={12} /> : <ChevronRight size={12} />}</span> : null}
      </div>
      {open && output && <pre className="verification-output">{output}</pre>}
    </div>
  );
};

export const ChatStream: React.FC = () => {
  const [store] = useStore();
  const bottomRef = useRef<HTMLDivElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const [showJumpToBottom, setShowJumpToBottom] = useState(false);

  const activeSession = store.sessions.find(s => s.id === store.activeSessionId);
  const messages = activeSession?.messages || [];

  useEffect(() => {
    if (!store.chatVisible) return;
    const node = containerRef.current || bottomRef.current?.parentElement;
    if (!node) return;
    const nearBottom = node.scrollHeight - node.scrollTop - node.clientHeight < 160;
    if (nearBottom) {
      node.scrollTo({ top: node.scrollHeight, behavior: 'smooth' });
    }
  }, [messages, store.agentRunning, store.chatVisible]);

  useEffect(() => {
    const node = containerRef.current;
    if (!node) return;
    // Smooth-scroll animations (the auto-scroll-to-bottom effect above)
    // fire a 'scroll' event on essentially every animation frame — rAF-
    // throttle so this doesn't add a re-render per frame on top of that.
    let rafId: number | null = null;
    const onScroll = () => {
      if (rafId !== null) return;
      rafId = requestAnimationFrame(() => {
        rafId = null;
        const nearBottom = node.scrollHeight - node.scrollTop - node.clientHeight < 160;
        setShowJumpToBottom(prev => (prev === !nearBottom ? prev : !nearBottom));
      });
    };
    onScroll();
    node.addEventListener('scroll', onScroll, { passive: true });
    return () => {
      node.removeEventListener('scroll', onScroll);
      if (rafId !== null) cancelAnimationFrame(rafId);
    };
  }, [activeSession?.id]);

  // On session switch / resume — including the initial load of the last active
  // chat when the workspace starts — jump to the end so the panel focuses where
  // the conversation ended. The incremental follow effect above only scrolls
  // when already near the bottom, so a freshly-mounted list would otherwise
  // stay pinned to the top. The rAF + short settle re-scroll covers late
  // markdown/image/diff layout that grows scrollHeight after the first commit.
  useEffect(() => {
    if (!store.chatVisible) return;
    const node = containerRef.current || bottomRef.current?.parentElement;
    if (!node) return;
    const jump = () => node.scrollTo({ top: node.scrollHeight, behavior: 'auto' });
    jump();
    const raf = requestAnimationFrame(jump);
    const settle = setTimeout(jump, 120);
    return () => { cancelAnimationFrame(raf); clearTimeout(settle); };
  }, [activeSession?.id, store.chatVisible]);

  const jumpToBottom = () => {
    const node = containerRef.current || bottomRef.current?.parentElement;
    if (node) {
      node.scrollTo({ top: node.scrollHeight, behavior: 'smooth' });
    }
  };

  if (messages.length === 0) {
    return <EmptyChatScreen />;
  }

  // Live phase from the last assistant message
  const lastMsg = messages[messages.length - 1];
  const currentPhase = store.agentRunning ? deriveAgentPhase(lastMsg?.tools) : null;
  const livePlan = deriveLivePlan(messages);

  return (
    <>
      {showJumpToBottom && (
        <button type="button" className="chat-scroll-to-bottom-btn" onClick={jumpToBottom} title="Jump to latest">
          <ChevronDown size={15} />
        </button>
      )}
      <div ref={containerRef} className="chat-stream" style={{
        flex: 1, minHeight: 0, overflowY: 'auto', padding: '16px 14px',
        display: 'flex', flexDirection: 'column', gap: '4px',
      }}>
        {livePlan.length > 0 && (
          <PlanChecklistCard tasks={livePlan} running={store.agentRunning} />
        )}
        {messages.map((msg, idx) => (
        <MessageBlock
          key={msg.id || idx}
          sessionId={store.activeSessionId}
          message={msg}
          isLast={idx === messages.length - 1}
          agentRunning={store.agentRunning}
          previousMessages={messages.slice(0, idx)}
        />
      ))}

      {/* Live phase pill shown only when the last message is from user (before assistant turn is mounted) */}
      {store.agentRunning && currentPhase && lastMsg?.role === 'user' && (
        <div className="agent-phase-standalone animate-fade-in" style={{ marginTop: '4px', paddingLeft: '12px' }}>
          <AgentPhaseIndicator phase={currentPhase} />
        </div>
      )}
      <div ref={bottomRef} style={{ height: '4px' }} />
      </div>
    </>
  );
};

/* ── Message block ──────────────────────────────────────────────────── */
const MessageBlock: React.FC<{
  sessionId: string;
  message: Message;
  isLast: boolean;
  agentRunning: boolean;
  previousMessages: Message[];
}> = ({ sessionId, message, isLast, agentRunning, previousMessages }) => {
  if (message.role === 'user') {
    return (
      <UserBubble
        sessionId={sessionId}
        message={message}
        agentRunning={agentRunning}
        previousMessages={previousMessages}
      />
    );
  }

  return (
    <AgentTurn
      sessionId={sessionId}
      message={message}
      isLast={isLast}
      agentRunning={agentRunning}
    />
  );
};

/* ── User bubble ────────────────────────────────────────────────────── */
const UserBubble: React.FC<{
  sessionId: string;
  message: Message;
  agentRunning: boolean;
  previousMessages: Message[];
}> = ({ sessionId, message, agentRunning, previousMessages }) => {
  const [isEditing, setIsEditing] = useState(false);
  const [editValue, setEditValue] = useState(message.content);
  const [copied, setCopied] = useState(false);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  const ts = message.timestamp
    ? new Date(message.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
    : '';

  const handleEdit = () => {
    setEditValue(message.content);
    setIsEditing(true);
    setTimeout(() => textareaRef.current?.focus(), 50);
  };

  const handleCancelEdit = () => {
    setIsEditing(false);
    setEditValue(message.content);
  };

  const handleResend = async () => {
    const text = editValue.trim();
    if (!text) return;
    setIsEditing(false);
    if (agentRunning) agentEngine.cancel();
    const historyBefore = previousMessages.map(m => ({ role: m.role, content: m.content }));
    // Roll the workspace back to before this prompt's turn(s) *before* we
    // truncate them away, so edit-&-resend starts from the same state the
    // original prompt saw. Must read the doomed turn ids from the store
    // while they still exist.
    await storeActions.revertTurnsAfter(sessionId, previousMessages.length);
    storeActions.editMessage(sessionId, message.id, text);
    try {
      const currentStore = getStore();
      if (currentStore.modelStatus !== 'ready') await agentEngine.loadModel(currentStore.activeModel);
      await agentEngine.runConversation(sessionId, text, historyBefore);
    } catch (e) {
      console.error('Resend error:', e);
    }
  };

  const handleCopy = async () => {
    // Route through the host (wl-copy): navigator.clipboard is silently blocked
    // in the embedded QtWebEngine view.
    if (await bridge.copyToClipboard(message.content || '')) {
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    }
  };

  return (
    <div className="user-bubble-wrap animate-fade-in">
      <div className="user-bubble-meta">
        {ts && <span className="bubble-timestamp">{ts}</span>}
        <div className="bubble-actions">
          <button className="bubble-action-btn" onClick={handleCopy} title="Copy">
            {copied ? <Check size={11} color="var(--accent-green)" /> : <Copy size={11} />}
          </button>
          <button className="bubble-action-btn" onClick={handleEdit} title="Edit & resend">
            <Edit2 size={11} />
          </button>
        </div>
      </div>

      {message.attachments && message.attachments.length > 0 && (
        <div className="user-bubble-attachments">
          {message.attachments.map(att => {
            const src = att.path.startsWith('data:') ? att.path : `file://${att.path}`;
            if (att.kind === 'image') {
              return (
                <div key={att.path} className="bubble-image-thumb">
                  <img src={src} alt={att.name} />
                </div>
              );
            }
            return (
              <span key={att.path} className="bubble-file-chip">
                <FileIcon name={att.name} size={11} /> {att.name}
              </span>
            );
          })}
        </div>
      )}

      {!isEditing ? (
        <div className="user-bubble">
          <p className="user-bubble-text">{message.content}</p>
        </div>
      ) : (
        <div className="user-bubble-edit">
          <textarea
            ref={textareaRef}
            className="user-bubble-edit-textarea"
            value={editValue}
            onChange={e => setEditValue(e.target.value)}
            onKeyDown={e => {
              if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleResend(); }
              if (e.key === 'Escape') handleCancelEdit();
            }}
            rows={3}
          />
          <div className="user-bubble-edit-actions">
            <button className="bubble-edit-cancel" onClick={handleCancelEdit}>Cancel</button>
            <button className="bubble-edit-send" onClick={handleResend}>
              <RotateCcw size={11} />
              Resend
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

/* ── Agent turn — clean, no avatar/name header ──────────────────────── */
const AgentTurn: React.FC<{
  sessionId: string;
  message: Message;
  isLast: boolean;
  agentRunning: boolean;
}> = ({ sessionId, message, isLast, agentRunning }) => {
  const [copied, setCopied] = useState(false);
  const [lightbox, setLightbox] = useState<string | null>(null);

  const ts = message.timestamp
    ? new Date(message.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
    : '';

  const handleCopy = async () => {
    // Route through the host (wl-copy): navigator.clipboard is silently blocked
    // in the embedded QtWebEngine view.
    if (await bridge.copyToClipboard(message.content || '')) {
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    }
  };

  const taskComplete = message.tools?.find(tool => tool.name === 'task_complete' && tool.status === 'completed');
  const taskResult = taskComplete?.result as { summary?: string; remaining?: string } | undefined;
  const running = isLast && agentRunning;

  // Per-turn revert (P3 §3.7): only offered when this turn actually wrote
  // files (has diffs) and carries a turnId the runtime ledger can roll back.
  // Hidden while the turn is still running, and dims to a "reverted" state
  // once store.revertTurn has marked its diffs rejected.
  const touchedFiles = (message.diffs?.length || 0) > 0 || (message.blocks?.some(b => b.type === 'diff') ?? false);
  const diffsAllRejected = (() => {
    const ds = message.diffs || [];
    const bs = (message.blocks || []).filter(b => b.type === 'diff').map(b => (b as any).diff);
    const all = [...ds, ...bs];
    return all.length > 0 && all.every(d => d.status === 'rejected');
  })();
  const canRevert = !!message.turnId && touchedFiles && !running && !diffsAllRejected;
  const [reverting, setReverting] = useState(false);
  const handleRevert = () => {
    setReverting(true);
    void storeActions.revertTurn(sessionId, message.id).finally(() => setReverting(false));
  };

  // Fallback for messages persisted before the block model existed (or any
  // message that never got a blocks array attached) — reconstruct the old
  // fixed-order layout so old sessions don't render blank.
  const legacyElevatedCommandCards = !message.blocks ? (message.tools?.filter(tool =>
    (tool.name === 'exec_command' || tool.name === 'run_command') || (tool.status === 'error' && isElevatedTool(tool.name))
  ) || []) : [];

  const renderMarkdown = (content: string) => (
    <div className="markdown-body agent-turn-content">
      <ReactMarkdown
        components={{
          code({ node, className, children, ...props }: any) {
            const isInline = !className;
            if (isInline) {
              return <code {...props}>{children}</code>;
            }
            return (
              <pre>
                <code className={className} {...props}>{children}</code>
              </pre>
            );
          }
        }}
      >
        {content}
      </ReactMarkdown>
    </div>
  );

  return (
    <div className="agent-turn-flow animate-fade-in">
      <div className="agent-turn-body">
        {/* Timestamp + copy — minimal meta row, only when there's content */}
        {(message.content || taskComplete) && (
          <div className="agent-turn-meta">
            {ts && <span className="bubble-timestamp" style={{ marginLeft: 0 }}>{ts}</span>}
            {message.content && (
              <button className="bubble-action-btn" onClick={handleCopy} title="Copy response">
                {copied ? <Check size={10} color="#22c55e" /> : <Copy size={10} />}
              </button>
            )}
            {canRevert && (
              <button
                className="bubble-action-btn agent-turn-revert"
                onClick={handleRevert}
                disabled={reverting}
                title="Revert this turn's file changes"
              >
                <RotateCcw size={10} />
                <span>{reverting ? 'Reverting…' : 'Revert turn'}</span>
              </button>
            )}
          </div>
        )}

        {/* Blocks render in the order events actually happened: text,
            activity timelines, elevated command cards, and diffs can all
            appear and reappear as the turn progresses, instead of every
            widget being bunched before all of the response text. */}
        {message.blocks && message.blocks.length > 0 ? (
          message.blocks.map((block, i) => {
            const isFinalPosition = i === message.blocks!.length - 1;
            const isLastBlock = running && isFinalPosition;
            if (block.type === 'text') {
              // Only the very last block of a turn is ever the "real" answer
              // — a model's own tool-use narration always happens between
              // tool calls, so any earlier text block is by definition
              // transitional commentary ("Let me check the config first…").
              // Render those as thin gradient separators instead of full
              // response bubbles, matching how step-by-step agent traces
              // usually show this kind of narration.
              return isFinalPosition
                ? <React.Fragment key={block.id}>{renderMarkdown(block.content)}</React.Fragment>
                : <InterstitialLine key={block.id} text={block.content} />;
            }
            if (block.type === 'activity') {
              return <AgentActivity key={block.id} tools={block.tools} running={isLastBlock} />;
            }
            if (block.type === 'command') {
              return (
                <div key={block.id} className="agent-tools-flow">
                  <ToolCard tool={block.tool} />
                </div>
              );
            }
            if (block.type === 'diff') {
              return (
                <div key={block.id} style={{ marginTop: '4px' }}>
                  <DiffWidget sessionId={sessionId} messageId={message.id} diff={block.diff} />
                </div>
              );
            }
            if (block.type === 'reasoning') {
              return <ReasoningSection key={block.id} content={block.content} live={running && isFinalPosition} />;
            }
            if (block.type === 'steer') {
              return <SteerMarker key={block.id} content={block.content} />;
            }
            if (block.type === 'suggestions') {
              return <SuggestionChips key={block.id} data={block.suggestions} />;
            }
            if (block.type === 'spec') {
              return (
                <SpecCard
                  key={block.id}
                  markdown={block.markdown}
                  status={block.status}
                  actionable={running && isFinalPosition && getStore().specApprovalPending}
                />
              );
            }
            if (block.type === 'verification') {
              return (
                <VerificationCard
                  key={block.id}
                  command={block.command}
                  status={block.status}
                  exitCode={block.exitCode}
                  output={block.output}
                  passed={block.passed}
                />
              );
            }
            return null;
          })
        ) : (
          <>
            {message.tools && message.tools.length > 0 && <AgentActivity tools={message.tools} running={running} />}
            {legacyElevatedCommandCards.length > 0 && (
              <div className="agent-tools-flow">
                {legacyElevatedCommandCards.map(tool => <ToolCard key={tool.id} tool={tool} />)}
              </div>
            )}
            {message.diffs && message.diffs.length > 0 && (
              <div style={{ marginTop: '4px' }}>
                {message.diffs.map(diff => (
                  <DiffWidget key={diff.filePath} sessionId={sessionId} messageId={message.id} diff={diff} />
                ))}
              </div>
            )}
            {message.content && renderMarkdown(message.content)}
          </>
        )}

        {/* Task complete: end-of-turn summary/suggestions, after every block */}
        {taskComplete && taskResult?.summary && <TaskCompleteWidget summary={taskResult.summary} remaining={taskResult?.remaining} />}

        {/* Attachments from assistant */}
        {message.attachments && message.attachments.length > 0 && (
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px', marginTop: '8px' }}>
            {message.attachments.map((att) => {
              const source = `file://${att.path}`;
              if (att.kind === 'image') {
                return (
                  <button key={att.path} type="button" onClick={() => setLightbox(source)}
                    style={{ padding: 0, border: '1px solid var(--border-subtle)', borderRadius: 'var(--radius-sm)', overflow: 'hidden', background: 'transparent', cursor: 'zoom-in' }}>
                    <img src={source} alt={att.name} style={{ width: 96, height: 72, objectFit: 'cover', display: 'block' }} />
                  </button>
                );
              }
              if (att.kind === 'video') {
                return <video key={att.path} src={source} controls style={{ maxWidth: 220, maxHeight: 120, borderRadius: 'var(--radius-sm)' }} />;
              }
              return <span key={att.path} className="bubble-file-chip"><FileIcon name={att.name} size={11} /> {att.name}</span>;
            })}
          </div>
        )}

        {/* Command widget */}
        {message.command && (
          <div style={{ marginTop: '10px' }}>
            <CommandWidget sessionId={sessionId} messageId={message.id} command={message.command} />
          </div>
        )}
      </div>

      {lightbox && (
        <div onClick={() => setLightbox(null)} style={{ position: 'fixed', inset: 0, zIndex: 200, background: 'rgba(0,0,0,.82)', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'zoom-out' }}>
          <img src={lightbox} alt="Attachment preview" style={{ maxWidth: '90vw', maxHeight: '90vh', objectFit: 'contain' }} />
        </div>
      )}
    </div>
  );
};

/* ── Tool card ──────────────────────────────────────────────────────── */
const TOOL_META: Record<string, { icon: React.ReactNode; color: string; label: (args: any) => string }> = {
  web_search:     { icon: <Globe size={13} />,     color: 'var(--matugen-primary, #a0c9dc)',   label: a => `Search: "${a?.query || a?.q || ''}"` },
  read_file:      { icon: <FileText size={13} />,  color: 'var(--matugen-secondary, #b2cbd6)', label: a => `Read: ${(a?.path || a?.file_path || '').split('/').pop() || a?.path || ''}` },
  write_file:     { icon: <FileDiff size={13} />,  color: 'var(--matugen-primary, #a0c9dc)',  label: a => `Write: ${(a?.path || a?.file_path || '').split('/').pop() || a?.path || ''}` },
  list_directory: { icon: <Folder size={13} />,    color: 'var(--matugen-secondary, #b2cbd6)', label: a => `List: ${a?.path || a?.directory || '.'}` },
  exec_command:   { icon: <Terminal size={13} />,  color: 'var(--matugen-primary, #a0c9dc)',    label: a => `$ ${a?.command || a?.cmd || ''}` },
  run_command:    { icon: <Terminal size={13} />,  color: 'var(--matugen-primary, #a0c9dc)',    label: a => `$ ${a?.command || a?.cmd || ''}` },
  task_complete:  { icon: <CheckCircle size={13} />, color: 'var(--matugen-primary, #a0c9dc)', label: () => 'Task complete' },
};

const ToolCard: React.FC<{ tool: ToolCallData }> = ({ tool }) => {
  const [collapsed, setCollapsed] = useState(true);
  const meta = TOOL_META[tool.name] || {
    icon: <FileText size={13} />, color: 'var(--matugen-secondary, #b2cbd6)',
    label: () => tool.name,
  };

  return (
    <div className="tool-card">
      <div className="tool-card-header" onClick={() => setCollapsed(!collapsed)}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '7px', color: meta.color, flex: 1, overflow: 'hidden' }}>
          {collapsed
            ? <ChevronRight size={12} color="var(--matugen-secondary, #b2cbd6)" />
            : <ChevronDown size={12} color="var(--matugen-secondary, #b2cbd6)" />}
          {meta.icon}
          <span style={{ fontFamily: 'var(--font-mono)', color: 'var(--text-secondary)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {meta.label(tool.arguments)}
          </span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '5px', flexShrink: 0 }}>
          {tool.status === 'completed'
            ? <CheckCircle size={12} color="#22c55e" />
            : tool.status === 'error'
            ? <CheckCircle size={12} color="#ef4444" />
            : <Clock size={12} color="var(--matugen-secondary, #b2cbd6)" style={{ animation: 'spin 2s linear infinite' }} />}
          <span style={{ fontSize: '10px', color: tool.status === 'error' ? '#ef4444' : tool.status === 'completed' ? '#22c55e' : 'var(--text-muted)' }}>{tool.status}</span>
        </div>
      </div>

      {!collapsed && (tool.result || tool.arguments) && (
        <div className="tool-card-body">
          {tool.arguments && (
            <div style={{ marginBottom: tool.result ? '6px' : 0, color: 'var(--text-muted)' }}>
              <span style={{ color: 'var(--matugen-primary, #a0c9dc)', fontWeight: 600 }}>args: </span>
              {JSON.stringify(tool.arguments)}
            </div>
          )}
          {tool.result && (
            <pre style={{ margin: 0, whiteSpace: 'pre-wrap', color: tool.status === 'error' ? '#ef4444' : 'var(--text-secondary)' }}>
              {typeof tool.result === 'string' ? tool.result : JSON.stringify(tool.result, null, 2)}
            </pre>
          )}
        </div>
      )}
    </div>
  );
};
