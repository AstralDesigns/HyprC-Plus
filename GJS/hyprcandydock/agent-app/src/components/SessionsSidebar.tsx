import React, { useState } from 'react';
import { ScrollText, Plus, Trash2, Check } from 'lucide-react';
import { useStore, storeActions } from '../store';

function relativeTime(ts: number) {
  const diff = Date.now() - ts;
  if (diff < 60_000)  return 'just now';
  if (diff < 3600_000) return Math.floor(diff / 60_000) + 'm ago';
  if (diff < 86400_000) return Math.floor(diff / 3600_000) + 'h ago';
  return Math.floor(diff / 86400_000) + 'd ago';
}

/** Strip inline markdown to a single readable preview line for a quest row. */
function oneLine(content: string): string {
  return (content || '')
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/[#*_>`~]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 48);
}

/**
 * Persistent left "Quests" rail (§3.1). Supersedes the old ChatPanel header
 * dropdown as the primary way to see/jump between sessions. Each row is a
 * quest; double-click the title to rename inline (§3.2 — a manual rename sets
 * titleSource 'user' so the auto-title from deriveSessionTitle() never
 * overwrites it again, see store.autoNameSession/renameSession).
 */
export const SessionsSidebar: React.FC = () => {
  const [store] = useStore();
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renameValue, setRenameValue] = useState('');

  const startRename = (id: string, currentTitle: string) => {
    setRenamingId(id);
    setRenameValue(currentTitle);
  };
  const commitRename = (id: string) => {
    storeActions.renameSession(id, renameValue);
    setRenamingId(null);
  };

  return (
    <aside className="quests-rail">
      {/* Header */}
      <div className="quests-rail-header">
        <span className="quests-rail-title">
          <ScrollText size={13} /> Quests
        </span>
        <button
          className="quests-new-btn"
          onClick={() => storeActions.createSession()}
          title="New Quest (Ctrl/Cmd+N)"
        >
          <Plus size={12} />
          <span>New</span>
        </button>
      </div>

      {/* Quest list */}
      <div className="quests-rail-list">
        {store.sessions.length === 0 && (
          <div className="quests-empty">No quests yet</div>
        )}

        {[...store.sessions].reverse().map(session => {
          const isActive = session.id === store.activeSessionId;
          const lastMsg = session.messages[session.messages.length - 1];
          const preview = oneLine(lastMsg?.content || '');
          return (
            <div
              key={session.id}
              className={`quest-item${isActive ? ' active' : ''}`}
              onClick={() => storeActions.switchSession(session.id)}
              onDoubleClick={(e) => { e.stopPropagation(); startRename(session.id, session.title); }}
              title="Double-click to rename"
            >
              {renamingId === session.id ? (
                <input
                  autoFocus
                  className="quest-rename-input"
                  value={renameValue}
                  onClick={(e) => e.stopPropagation()}
                  onChange={(e) => setRenameValue(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') { e.preventDefault(); commitRename(session.id); }
                    if (e.key === 'Escape') { e.preventDefault(); setRenamingId(null); }
                  }}
                  onBlur={() => commitRename(session.id)}
                />
              ) : (
                <div className="quest-item-text">
                  <div className="quest-title">{session.title}</div>
                  {preview && <div className="quest-preview">{preview}</div>}
                </div>
              )}

              <span className="quest-meta">{relativeTime(session.updatedAt)}</span>

              <div className="quest-actions">
                {renamingId === session.id ? (
                  <button
                    className="quest-action-btn"
                    onClick={(e) => { e.stopPropagation(); commitRename(session.id); }}
                    title="Save name"
                  >
                    <Check size={11} />
                  </button>
                ) : (
                  <button
                    className="quest-action-btn"
                    onClick={(e) => { e.stopPropagation(); startRename(session.id, session.title); }}
                    title="Rename quest"
                  >
                    <ScrollText size={11} />
                  </button>
                )}
                <button
                  className="quest-action-btn quest-delete-btn"
                  onClick={(e) => { e.stopPropagation(); storeActions.deleteSession(session.id); }}
                  title="Delete quest"
                >
                  <Trash2 size={11} />
                </button>
              </div>
            </div>
          );
        })}
      </div>
    </aside>
  );
};
