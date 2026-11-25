import React, { useEffect, useState } from 'react';
import { createPortal } from 'react-dom';
import { DiffEditor } from '@monaco-editor/react';
import {
  X,
  FileCode,
  FilePlus2,
  ChevronDown,
  ChevronRight,
  ChevronUp,
  ExternalLink,
  Eye,
  Check,
  CheckCircle2,
  XCircle,
} from 'lucide-react';
import { DiffData, storeActions, useStore } from '../store';
import { registerMonacoThemes } from '../utils/monacoThemes';
import { registerCustomLanguages, languageForPath } from '../utils/monacoLanguages';

interface DiffPreviewModalProps {
  diffs: DiffData[];
  onClose: () => void;
}

export const DiffPreviewModal: React.FC<DiffPreviewModalProps> = ({ diffs, onClose }) => {
  const [store] = useStore();
  const [expandedFiles, setExpandedFiles] = useState<Record<string, boolean>>(() => {
    // Expand the first 3 files by default
    const map: Record<string, boolean> = {};
    diffs.slice(0, 3).forEach(d => { map[d.filePath] = true; });
    return map;
  });
  const [diffNavigators, setDiffNavigators] = useState<Record<string, any>>({});

  const targetTheme = store.monacoTheme === 'matugen' || !store.monacoTheme ? 'matugen' : store.monacoTheme;

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onClose]);

  const toggleExpand = (path: string) => {
    setExpandedFiles(prev => ({ ...prev, [path]: !prev[path] }));
  };

  const expandAll = () => {
    const map: Record<string, boolean> = {};
    diffs.forEach(d => { map[d.filePath] = true; });
    setExpandedFiles(map);
  };

  const collapseAll = () => {
    setExpandedFiles({});
  };

  const totalAdd = diffs.reduce((n, d) => n + (d.additions || 0), 0);
  const totalDel = diffs.reduce((n, d) => n + (d.deletions || 0), 0);

  return createPortal(
    <div className="diff-preview-modal-backdrop" onClick={onClose} role="dialog" aria-modal="true">
      <div className="diff-preview-modal-container" onClick={e => e.stopPropagation()}>
        {/* Header */}
        <div className="diff-preview-modal-header">
          <div className="diff-preview-modal-title">
            <FileCode size={16} color="var(--matugen-primary, #a0c9dc)" />
            <h3>Changes Preview ({diffs.length} file{diffs.length === 1 ? '' : 's'})</h3>
            {totalAdd > 0 && <span className="stat-add">+{totalAdd}</span>}
            {totalDel > 0 && <span className="stat-del">-{totalDel}</span>}
          </div>
          <div className="diff-preview-modal-actions">
            <button type="button" className="diff-preview-btn-subtle" onClick={expandAll}>Expand all</button>
            <button type="button" className="diff-preview-btn-subtle" onClick={collapseAll}>Collapse all</button>
          </div>
        </div>

        {/* Scrollable list of diff cards */}
        <div className="diff-preview-modal-body">
          {diffs.map(diff => {
            const isExpanded = !!expandedFiles[diff.filePath];
            const filename = diff.filePath.split('/').pop() || diff.filePath;
            const dir = diff.filePath.split('/').slice(0, -1).join('/');
            const nav = diffNavigators[diff.filePath];

            return (
              <div key={diff.filePath} className="diff-preview-card">
                <div className="diff-preview-card-header" onClick={() => toggleExpand(diff.filePath)}>
                  <div className="diff-preview-card-title">
                    {isExpanded ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                    {diff.isNew ? (
                      <FilePlus2 size={14} color="var(--matugen-primary, #a0c9dc)" />
                    ) : (
                      <FileCode size={14} color="var(--matugen-primary, #a0c9dc)" />
                    )}
                    <span className="diff-preview-filename">{filename}</span>
                    {dir && <span className="diff-preview-filedir">{dir}</span>}
                    {diff.additions != null && diff.additions > 0 && (
                      <span className="stat-add">+{diff.additions}</span>
                    )}
                    {diff.deletions != null && diff.deletions > 0 && (
                      <span className="stat-del">-{diff.deletions}</span>
                    )}
                  </div>

                  <div className="diff-preview-card-actions" onClick={e => e.stopPropagation()}>
                    {/* Monaco navigator buttons when expanded */}
                    {isExpanded && nav && (
                      <div className="diff-preview-nav-btns">
                        <button
                          type="button"
                          className="diff-nav-arrow-btn"
                          title="Previous change"
                          onClick={() => nav.previous()}
                        >
                          <ChevronUp size={12} />
                        </button>
                        <button
                          type="button"
                          className="diff-nav-arrow-btn"
                          title="Next change"
                          onClick={() => nav.next()}
                        >
                          <ChevronDown size={12} />
                        </button>
                      </div>
                    )}
                    <button
                      type="button"
                      className="diff-preview-icon-btn"
                      title="Open in editor canvas"
                      onClick={() => {
                        storeActions.openFileByPath(diff.filePath);
                        onClose();
                      }}
                    >
                      <ExternalLink size={12} /> Open
                    </button>
                  </div>
                </div>

                {isExpanded && (
                  <div className="diff-preview-card-editor">
                    <DiffEditor
                      key={`${diff.filePath}:${diff.status || 'preview'}`}
                      height="240px"
                      theme={targetTheme}
                      beforeMount={(monaco) => { registerMonacoThemes(monaco); registerCustomLanguages(monaco); }}
                      onMount={(diffEditor, monaco) => {
                        try {
                          const navigator = monaco.editor.createDiffNavigator(diffEditor, {
                            followsCaret: true,
                            ignoreCharChanges: true,
                          });
                          setDiffNavigators(prev => ({ ...prev, [diff.filePath]: navigator }));
                        } catch { /* noop */ }
                      }}
                      language={languageForPath(diff.filePath)}
                      original={diff.originalCode || ''}
                      modified={diff.modifiedCode || ''}
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
                        padding: { top: 6, bottom: 6 },
                        accessibilitySupport: 'off',
                        experimentalGpuAcceleration: 'off',
                      }}
                    />
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>
    </div>,
    document.body
  );
};
