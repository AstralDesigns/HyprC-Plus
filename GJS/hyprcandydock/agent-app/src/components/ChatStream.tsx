import React, { useEffect, useRef, useState, useCallback } from 'react';
import ReactMarkdown from 'react-markdown';
import {
  Globe, FileText, Terminal, FileDiff,
  ChevronDown, ChevronRight, CheckCircle, Clock, Sparkles,
  Folder, Copy, Check, Edit2, RotateCcw,
  Brain, Zap, Eye, ListChecks,
  X,
} from 'lucide-react';
import { useStore, getStore, Message, ToolCallData, storeActions, setStore } from '../store';
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
    storeActions.editMessage(sessionId, message.id, text);
    try {
      const currentStore = getStore();
      if (currentStore.modelStatus !== 'ready') await agentEngine.loadModel(currentStore.activeModel);
      await agentEngine.runConversation(sessionId, text, historyBefore);
    } catch (e) {
      console.error('Resend error:', e);
    }
  };

  const handleCopy = () => {
    navigator.clipboard?.writeText(message.content || '').then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    });
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
                <FileText size={11} /> {att.name}
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

  const handleCopy = () => {
    navigator.clipboard?.writeText(message.content || '').then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    });
  };

  const taskComplete = message.tools?.find(tool => tool.name === 'task_complete' && tool.status === 'completed');
  const taskResult = taskComplete?.result as { summary?: string; remaining?: string } | undefined;
  const running = isLast && agentRunning;

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
              return <span key={att.path} className="bubble-file-chip"><FileText size={11} /> {att.name}</span>;
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
