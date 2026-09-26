import React, { useState } from 'react';
import { DiffEditor } from '@monaco-editor/react';
import { Check, X, ChevronDown, ChevronRight, FileCode, FilePlus2, CheckCircle2, XCircle, ExternalLink, Eye } from 'lucide-react';
import { DiffData, storeActions, useStore } from '../store';
import { registerMonacoThemes } from '../utils/monacoThemes';

interface DiffWidgetProps {
  sessionId: string;
  messageId: string;
  diff: DiffData;
}

export const DiffWidget: React.FC<DiffWidgetProps> = ({ sessionId, messageId, diff }) => {
  const [store] = useStore();
  const [collapsed, setCollapsed] = useState(true);
  const [busy, setBusy] = useState(false);
  const targetTheme = store.monacoTheme === 'matugen' || !store.monacoTheme ? 'matugen' : store.monacoTheme;

  const handleAccept = async () => {
    setBusy(true);
    try {
      await storeActions.acceptFile(diff.filePath);
      storeActions.updateDiffStatus(sessionId, messageId, 'accepted', diff.filePath);
    } finally {
      setBusy(false);
    }
  };

  const handleReject = async () => {
    setBusy(true);
    try {
      await storeActions.rejectFile(diff.filePath);
      storeActions.updateDiffStatus(sessionId, messageId, 'rejected', diff.filePath);
    } finally {
      setBusy(false);
    }
  };

  const handleOpen = () => storeActions.openFileByPath(diff.filePath);
  const isHtml = getLanguageFromPath(diff.filePath) === 'html';
  const filename = diff.filePath.split('/').pop() || diff.filePath;

  return (
    <div className="diff-card">
      <div className="diff-card-header" onClick={() => setCollapsed(!collapsed)}>
        <div className="diff-card-title">
          {collapsed ? <ChevronRight size={13} color="var(--matugen-secondary, #b2cbd6)" /> : <ChevronDown size={13} color="var(--matugen-secondary, #b2cbd6)" />}
          {diff.isNew ? <FilePlus2 size={14} color="var(--matugen-primary, #a0c9dc)" /> : <FileCode size={14} color="var(--matugen-primary, #a0c9dc)" />}
          <span className="diff-card-filename" title={diff.filePath}>{filename}</span>
          <span className="diff-card-stat-add">+{diff.additions ?? 0}</span>
          <span className="diff-card-stat-del">-{diff.deletions ?? 0}</span>
        </div>

        <div className="diff-card-actions" onClick={e => e.stopPropagation()}>
          {diff.status === 'accepted' ? (
            <div className="diff-card-status diff-card-status-accepted" title="Kept">
              <CheckCircle2 size={14} />
            </div>
          ) : diff.status === 'rejected' ? (
            <div className="diff-card-status diff-card-status-rejected" title="Undone">
              <XCircle size={14} />
            </div>
          ) : (
            <>
              {isHtml && (
                <button className="diff-card-icon-btn diff-card-icon-open" onClick={() => storeActions.openPreview(diff.filePath)} title="Open live preview">
                  <Eye size={13} />
                </button>
              )}
              <button className="diff-card-icon-btn diff-card-icon-open" onClick={handleOpen} title="Open in editor">
                <ExternalLink size={13} />
              </button>
              <button className="diff-card-icon-btn diff-card-icon-reject" onClick={handleReject} disabled={busy} title="Undo this file">
                <X size={13} />
              </button>
              <button className="diff-card-icon-btn diff-card-icon-accept" onClick={handleAccept} disabled={busy} title="Keep this change">
                <Check size={13} />
              </button>
            </>
          )}
        </div>
      </div>

      {!collapsed && (
        <div className="diff-card-editor">
          <DiffEditor
            // Force a clean mount/teardown per file+status instead of an
            // in-place model update — @monaco-editor/react's DiffEditor has
            // a known race ("TextModel got disposed before DiffEditorWidget
            // model got reset") when its original/modified props change
            // identity while a previous model swap is still settling. A key
            // sidesteps it entirely by never attempting the in-place swap.
            key={`${diff.filePath}:${diff.status}`}
            height="260px"
            theme={targetTheme}
            beforeMount={(monaco) => registerMonacoThemes(monaco)}
            language={getLanguageFromPath(diff.filePath)}
            original={diff.originalCode}
            modified={diff.modifiedCode}
            options={{
              readOnly: true,
              renderSideBySide: true,
              minimap: { enabled: false },
              scrollBeyondLastLine: false,
              fontSize: 12,
              fontFamily: 'var(--font-mono)',
              lineNumbersMinChars: 3,
              automaticLayout: true,
              smoothScrolling: true,
              padding: { top: 8, bottom: 8 },
              // Monaco's "auto" accessibility detection probes browser
              // permissions (clipboard among them) to guess whether a
              // screen reader is active; WebKitGTK doesn't grant those, so
              // "auto" retries and logs NotAllowedError repeatedly instead
              // of settling. Off avoids the probing entirely.
              accessibilitySupport: 'off',
              experimentalGpuAcceleration: 'off',
            }}
          />
        </div>
      )}
    </div>
  );
};

export function getLanguageFromPath(filePath: string): string {
  const ext = filePath.split('.').pop()?.toLowerCase() || '';
  const map: Record<string, string> = {
    js: 'javascript', jsx: 'javascript', ts: 'typescript', tsx: 'typescript',
    py: 'python', sh: 'shell', bash: 'shell', json: 'json', css: 'css',
    html: 'html', md: 'markdown', yml: 'yaml', yaml: 'yaml', rs: 'rust',
    go: 'go', c: 'c', cpp: 'cpp',
  };
  return map[ext] || 'plaintext';
}
