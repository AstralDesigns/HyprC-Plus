import React, { useState } from 'react';
import { Check, FileCode, X, AlertTriangle, ExternalLink, ChevronDown, ChevronRight, FilePlus2 } from 'lucide-react';
import { useStore, storeActions } from '../store';

export const PendingFilesBar: React.FC = () => {
  const [store] = useStore();
  const [expanded, setExpanded] = useState(false);
  const files = Object.values(store.pendingFiles).sort((a, b) => a.timestamp - b.timestamp);

  if (files.length === 0) return null;

  const totalAdd = files.reduce((n, f) => n + f.additions, 0);
  const totalDel = files.reduce((n, f) => n + f.deletions, 0);

  return (
    <div className="pending-files-bar" role="region" aria-label="Pending file changes">
      <div className="pending-files-header" onClick={() => setExpanded(!expanded)} style={{ cursor: 'pointer' }}>
        <div className="pending-files-title">
          {expanded ? <ChevronDown size={12} /> : <ChevronRight size={12} />}
          <AlertTriangle size={12} color="var(--matugen-primary, #a0c9dc)" />
          <strong>{files.length} file{files.length === 1 ? '' : 's'} changed</strong>
          <span className="pending-stat-add">+{totalAdd}</span>
          <span className="pending-stat-del">-{totalDel}</span>
        </div>
        <div className="pending-files-actions" onClick={e => e.stopPropagation()}>
          <button type="button" className="pending-files-reject-all" onClick={() => storeActions.rejectAllFiles()}>
            <X size={11} /> Undo all
          </button>
          <button type="button" className="pending-files-accept-all" onClick={() => storeActions.acceptAllFiles()}>
            <Check size={11} /> Keep all
          </button>
        </div>
      </div>

      {expanded && (
        <div className="pending-files-list">
          {files.map((f) => {
            const filename = f.path.split('/').pop() || f.path;
            return (
              <div className="pending-file-row" key={f.path}>
                {f.isNew ? <FilePlus2 size={12} color="var(--matugen-secondary, #b2cbd6)" /> : <FileCode size={12} color="var(--matugen-secondary, #b2cbd6)" />}
                <span className="pending-file-path" title={f.path}>{filename}</span>
                <span className="pending-stat-add">+{f.additions}</span>
                <span className="pending-stat-del">-{f.deletions}</span>
                <button type="button" className="pending-file-open" onClick={() => storeActions.openFileByPath(f.path)} title="Open">
                  <ExternalLink size={11} />
                </button>
                <button type="button" className="pending-file-reject" onClick={() => storeActions.rejectFile(f.path)} title="Undo this file">
                  <X size={11} />
                </button>
                <button type="button" className="pending-file-accept" onClick={() => storeActions.acceptFile(f.path)} title="Keep this file">
                  <Check size={11} />
                </button>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};
