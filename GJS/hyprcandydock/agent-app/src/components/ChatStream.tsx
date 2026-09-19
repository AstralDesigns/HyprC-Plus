import React, { useEffect, useRef, useState, useCallback } from 'react';
import ReactMarkdown from 'react-markdown';
import {
  Globe, FileText, Terminal, FileDiff,
  ChevronDown, ChevronRight, CheckCircle, Clock, Sparkles,
  Folder, Copy, Check, Edit2, RotateCcw,
  Brain, Zap, Eye, ListChecks,
  X,
} from 'lucide-react';
import { useStore, Message, ToolCallData, storeActions, setStore } from '../store';
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

  const activeSession = store.sessions.find(s => s.id === store.activeSessionId);
  const messages = activeSession?.messages || [];

  useEffect(() => {
    const node = bottomRef.current?.parentElement;
    if (!node) return;
    const nearBottom = node.scrollHeight - node.scrollTop - node.clientHeight < 160;
    if (nearBottom) bottomRef.current?.scrollIntoView({ behavior: 'smooth', block: 'end' });
  }, [messages, store.agentRunning]);

  if (messages.length === 0) {
    return <EmptyChatScreen />;
  }

  // Live phase from the last assistant message
  const lastMsg = messages[messages.length - 1];
  const currentPhase = store.agentRunning ? deriveAgentPhase(lastMsg?.tools) : null;

  return (
    <div className="chat-stream" style={{
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
    if (!editValue.trim()) return;
    setIsEditing(false);
    if (agentRunning) agentEngine.cancel();
    const historyBefore = previousMessages.map(m => ({ role: m.role, content: m.content }));
    storeActions.editMessage(sessionId, message.id, editValue.trim());
    try {
      await agentEngine.runConversation(sessionId, editValue.trim(), historyBefore);
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

  const phase = (isLast && agentRunning) ? deriveAgentPhase(message.tools) : null;
  const taskComplete = message.tools?.find(tool => tool.name === 'task_complete' && tool.status === 'completed');
  const taskResult = taskComplete?.result as { summary?: string; remaining?: string } | undefined;

  // Filter tool cards — show write_file, exec_command, list_directory, read_file, web_search, errors
  // Skip internal todo tools (shown via phase indicator), skip task_complete (shown as widget)
  const visibleToolCards = message.tools?.filter(tool =>
    ['write_file', 'exec_command', 'run_command', 'list_directory', 'read_file', 'web_search', 'fetch_url'].includes(tool.name) ||
    tool.status === 'error'
  ) || [];

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

        {/* Task complete widget (shown before markdown content) */}
        {taskComplete && <TaskCompleteWidget summary={taskResult?.summary || message.content} remaining={taskResult?.remaining} />}

        {/* Visible tool cards (styled with Matugen tokens) */}
        {visibleToolCards.length > 0 && (
          <div className="agent-tools-flow">
            {visibleToolCards.map(tool => <ToolCard key={tool.id} tool={tool} />)}
          </div>
        )}

        {/* Live phase indicator while this turn is running */}
        {phase && <AgentPhaseIndicator phase={phase} />}

        {/* Markdown content */}
        {message.content && (!taskComplete || message.content !== taskResult?.summary) && (
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
              {message.content}
            </ReactMarkdown>
          </div>
        )}

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

        {/* Diff widget */}
        {message.diff && (
          <div data-diff-id={message.id} style={{ marginTop: '10px' }}>
            <DiffWidget sessionId={sessionId} messageId={message.id} diff={message.diff} />
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
