import { useEffect, useState, type FC } from 'react';
import { BookOpen, ExternalLink, Trash2, Loader, Brain } from 'lucide-react';
import { useStore, setStore, storeActions } from '../store';
import { bridge } from '../bridge';

const PRIMARY    = 'var(--matugen-primary, #a0c9dc)';
const ON_PRIMARY = 'var(--matugen-on-secondary, #1d343c)';
const ERROR      = 'var(--matugen-error, #ffb4ab)';

interface MemoryItem {
  topic: string;
  path: string;
  updated: string;
  bytes: number;
  preview: string;
}

/**
 * Durable-memory browser. Lists the markdown topic notes the agent writes
 * under ~/.config/hyprcandy/cache/agent-memories. Opening a memory reuses the
 * workspace Markdown/Monaco pane (human editing happens there); deletion goes
 * straight through POST /api/memories/delete.
 */
export const MemoryPanel: FC = () => {
  const [store] = useStore();
  const [memories, setMemories] = useState<MemoryItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [busyTopic, setBusyTopic] = useState<string | null>(null);

  const load = async () => {
    setLoading(true);
    setError('');
    try {
      const res = await bridge.runtimeRequest('/api/memories', {}, 'GET');
      setMemories((res?.memories || []) as MemoryItem[]);
    } catch (e: any) {
      setError(e?.message || 'Could not reach the memory store.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (store.memoryPanelOpen) void load();
  }, [store.memoryPanelOpen]);

  // Live-refresh while open: the engine fires this after the agent's
  // save_memory / delete_memory tool completes, so a newly written memory
  // appears without any manual reload.
  useEffect(() => {
    if (!store.memoryPanelOpen) return;
    const onChanged = () => void load();
    window.addEventListener('agent-memories-changed', onChanged);
    return () => window.removeEventListener('agent-memories-changed', onChanged);
  }, [store.memoryPanelOpen]);

  const handleDelete = async (topic: string) => {
    setBusyTopic(topic);
    try {
      await bridge.runtimeRequest('/api/memories/delete', { topic });
      await load();
    } catch (e: any) {
      setError(e?.message || 'Delete failed.');
    } finally {
      setBusyTopic(null);
    }
  };

  const openMemory = (path: string) => {
    void storeActions.openFileByPath(path);
    setStore({ memoryPanelOpen: false });
  };

  if (!store.memoryPanelOpen) return null;

  return (
    <div
      onClick={() => setStore({ memoryPanelOpen: false })}
      className="memory-overlay"
      style={{
        position: 'absolute',
        inset: 0,
        background: 'rgba(0,0,0,.65)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        zIndex: 100,
      }}
    >
      <div
        className="animate-fade-in memory-panel"
        onClick={e => e.stopPropagation()}
        style={{
          width: '600px',
          maxWidth: '92vw',
          maxHeight: '86vh',
          background: 'var(--matugen-on-secondary, #1d343c)',
          border: '1px solid var(--border-glass)',
          borderRadius: 'var(--radius-lg)',
          boxShadow: '0 20px 60px rgba(0,0,0,.7)',
          display: 'flex',
          flexDirection: 'column',
          overflow: 'hidden',
          backdropFilter: 'blur(20px)',
        }}
      >
        {/* Header */}
        <div style={{
          padding: '16px 20px 12px',
          borderBottom: '1px solid var(--border-subtle)',
          display: 'flex',
          alignItems: 'center',
          gap: '10px',
        }}>
          <div style={{
            width: 34, height: 34, borderRadius: '50%',
            background: PRIMARY, color: ON_PRIMARY,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Brain size={18} color={ON_PRIMARY} />
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontWeight: 700, fontSize: '14px', color: 'var(--text-primary)' }}>
              Agent Memories
            </div>
          </div>
        </div>

        {/* Body */}
        <div style={{ flex: 1, overflowY: 'auto', padding: '14px 18px' }}>
          {error && (
            <div style={{ color: ERROR, fontSize: '12px', marginBottom: '12px' }}>{error}</div>
          )}
          {!loading && memories.length === 0 && !error && (
            <div style={{ textAlign: 'center', color: 'var(--text-muted)', padding: '40px 16px', fontSize: '13px' }}>
              <BookOpen size={26} style={{ marginBottom: 8, opacity: 0.6 }} />
              <div>No memories yet.</div>
              <div style={{ fontSize: '11px', marginTop: 4 }}>
                Ask the agent to remember something and it will save a topic note here.
              </div>
            </div>
          )}
          {memories.map(m => (
            <div
              key={m.path}
              className="memory-card"
              style={{
                border: '1px solid var(--border-subtle)',
                borderRadius: 'var(--radius-md)',
                padding: '10px 12px',
                marginBottom: '10px',
                background: 'color-mix(in srgb, var(--matugen-primary, #a0c9dc) 6%, transparent)',
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <BookOpen size={14} style={{ color: PRIMARY, flexShrink: 0 }} />
                <span style={{ fontWeight: 700, fontSize: '13px', color: 'var(--text-primary)', flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {m.topic}
                </span>
                <span style={{ fontSize: '10px', color: 'var(--text-muted)', flexShrink: 0 }}>
                  {m.updated ? new Date(m.updated).toLocaleDateString() : ''}
                </span>
              </div>
              {m.preview && (
                <div style={{ fontSize: '11.5px', color: 'var(--text-secondary)', marginTop: 6, lineHeight: 1.4, overflowWrap: 'anywhere' }}>
                  {m.preview}
                </div>
              )}
              <div style={{ display: 'flex', gap: '8px', marginTop: 10 }}>
                <button className="memory-btn" onClick={() => openMemory(m.path)}>
                  <ExternalLink size={12} /> Open &amp; edit
                </button>
                <button
                  className="memory-btn memory-btn-danger"
                  onClick={() => handleDelete(m.topic)}
                  disabled={busyTopic === m.topic}
                >
                  {busyTopic === m.topic ? <Loader size={12} className="agent-activity-spin" /> : <Trash2 size={12} />}
                  Forget
                </button>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};
