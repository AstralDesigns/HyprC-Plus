import React, { useMemo, useState } from 'react';
import { Check, FileCode, X, AlertTriangle } from 'lucide-react';
import { useStore, storeActions, type DiffData, type Message } from '../store';
import { bridge } from '../bridge';

type PendingFile = { messageId: string; diff: DiffData };

export const PendingFilesBar: React.FC = () => {
  const [store] = useStore();
  const [busy, setBusy] = useState<string | null>(null);
  const session = store.sessions.find((item) => item.id === store.activeSessionId);
  const pending = useMemo<PendingFile[]>(() => (session?.messages || [])
    .filter((message: Message) => message.diff?.status === 'pending')
    .map((message) => ({ messageId: message.id, diff: message.diff! })), [session?.messages]);

  if (!pending.length) return null;

  const apply = async (item: PendingFile) => {
    setBusy(item.messageId);
    try {
      if (!item.diff.filePath || typeof item.diff.modifiedCode !== 'string') {
        throw new Error('The proposed file change is incomplete.');
      }
      await bridge.writeFile(item.diff.filePath, item.diff.modifiedCode);
      storeActions.updateDiffStatus(store.activeSessionId, item.messageId, 'accepted');
    } catch (error: any) {
      console.error('[pending-files] apply failed', error);
      window.alert(`Failed to write ${item.diff.filePath}: ${error?.message || String(error)}`);
    } finally {
      setBusy(null);
    }
  };

  const reject = (item: PendingFile) => {
    storeActions.updateDiffStatus(store.activeSessionId, item.messageId, 'rejected');
  };

  const applyAll = async () => {
    for (const item of pending) await apply(item);
  };

  const rejectAll = () => {
    pending.forEach(reject);
  };

  return (
    <div className="pending-files-bar" role="region" aria-label="Pending file changes">
      <div className="pending-files-header">
        <div className="pending-files-title">
          <AlertTriangle size={12} color="var(--matugen-primary, #a0c9dc)" />
          <strong>{pending.length} pending file{pending.length === 1 ? '' : 's'}</strong>
        </div>
        <div className="pending-files-actions">
          <button type="button" className="pending-files-accept-all" onClick={applyAll} disabled={busy !== null}>
            <Check size={11} /> Accept all
          </button>
          <button type="button" className="pending-files-reject-all" onClick={rejectAll} disabled={busy !== null}>
            <X size={11} /> Reject all
          </button>
        </div>
      </div>
      <div className="pending-files-list">
        {pending.map((item) => {
          const filename = item.diff.filePath.split('/').pop() || item.diff.filePath;
          return (
            <div className="pending-file-row" key={item.messageId}>
              <FileCode size={12} color="var(--matugen-secondary, #b2cbd6)" />
              <span className="pending-file-path" title={item.diff.filePath}>{filename}</span>
              <button type="button" className="pending-file-accept" onClick={() => void apply(item)} disabled={busy !== null} title="Accept and save this file">
                <Check size={11} />
              </button>
              <button type="button" className="pending-file-reject" onClick={() => reject(item)} disabled={busy !== null} title="Reject this file">
                <X size={11} />
              </button>
            </div>
          );
        })}
      </div>
    </div>
  );
};
