import React from 'react';
import { MessageSquare, Plus, Trash2, X } from 'lucide-react';
import { useStore, setStore, storeActions } from '../store';

function relativeTime(ts: number) {
  const diff = Date.now() - ts;
  if (diff < 60_000)  return 'just now';
  if (diff < 3600_000) return Math.floor(diff / 60_000) + 'm ago';
  if (diff < 86400_000) return Math.floor(diff / 3600_000) + 'h ago';
  return Math.floor(diff / 86400_000) + 'd ago';
}

export const SessionsSidebar: React.FC = () => {
  const [store] = useStore();

  if (!store.chatVisible) return null;

  return (
    <div className="chat-sessions-popup animate-slide-in" style={{
      width: '190px', minWidth: '190px', height: '100%',
      background: 'var(--bg-sidebar)',
      border: '1px solid var(--border-subtle)',
      display: 'flex', flexDirection: 'column',
      flexShrink: 0, zIndex: 10, overflow: 'hidden',
    }}>
      {/* Header */}
      <div className="panel-header">
        <span className="panel-title">Chats</span>
        <div style={{ display: 'flex', gap: '2px' }}>
          <button
            className="icon-btn"
            style={{ padding: '3px 6px', display: 'flex', alignItems: 'center', gap: '3px', fontSize: '10.5px', color: 'var(--accent-cyan)' }}
            onClick={() => storeActions.createSession()}
            title="New chat"
          >
            <Plus size={12} />
            <span>New</span>
          </button>
          <button
            className="icon-btn" style={{ padding: '3px' }}
            onClick={() => setStore({ chatVisible: false })}
            title="Close sidebar"
          >
            <X size={12} />
          </button>
        </div>
      </div>

      {/* Session list */}
      <div style={{ flex: 1, overflowY: 'auto', padding: '6px' }}>
        {store.sessions.length === 0 && (
          <div style={{ padding: '20px 10px', color: 'var(--text-muted)', fontSize: '11px', textAlign: 'center' }}>
            No chats yet
          </div>
        )}

        {[...store.sessions].reverse().map(session => {
          const isActive = session.id === store.activeSessionId;
          const lastMsg = session.messages[session.messages.length - 1];
          return (
            <div
              key={session.id}
              className={`session-item${isActive ? ' active' : ''}`}
              onClick={() => setStore({ activeSessionId: session.id })}
              style={{ position: 'relative' }}
            >
              <MessageSquare size={13} color={isActive ? 'var(--accent-cyan)' : 'var(--text-muted)'} style={{ flexShrink: 0 }} />
              <div style={{ flex: 1, overflow: 'hidden' }}>
                <div className="session-title" style={{ color: isActive ? 'var(--text-primary)' : 'var(--text-secondary)' }}>
                  {session.title}
                </div>
                {lastMsg && (
                  <div style={{
                    fontSize: '10.5px', color: 'var(--text-muted)',
                    overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                    maxWidth: '130px', marginTop: '1px',
                  }}>
                    {lastMsg.content?.substring(0, 40) || '…'}
                  </div>
                )}
              </div>
              <span className="session-meta">{relativeTime(session.updatedAt)}</span>

              {/* Delete button (hover visible via CSS) */}
              <button
                className="icon-btn"
                style={{ padding: '2px', position: 'absolute', right: '6px', top: '50%', transform: 'translateY(-50%)', opacity: 0 }}
                title="Delete session"
                onClick={(e) => {
                  e.stopPropagation();
                  storeActions.deleteSession(session.id);
                }}
                onMouseEnter={e => (e.currentTarget.style.opacity = '1')}
                onMouseLeave={e => (e.currentTarget.style.opacity = '0')}
              >
                <Trash2 size={11} color="var(--accent-red)" />
              </button>
            </div>
          );
        })}
      </div>
    </div>
  );
};
