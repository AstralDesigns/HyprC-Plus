import React, { useEffect, useRef, useState } from 'react';
import Editor, { DiffEditor } from '@monaco-editor/react';
import {
  Music,
  FolderOpen,
  FilePlus,
  Sparkles,
  Check,
  X,
  GitCompare,
  RotateCcw,
} from 'lucide-react';
import { useStoreSelector, storeActions, getStore } from '../store';
import { MediaGallery } from './MediaGallery';
import { bridge } from '../bridge';
import { registerMonacoThemes, applyMatugenThemeNow } from '../utils/monacoThemes';
import { getMediaUrl } from '../utils/media';

/**
 * Cross-file find navigation: Ctrl+Alt+Down / Ctrl+Alt+Up cycle to the next
 * /previous open tab that also contains the current find-widget search term,
 * carrying the term over and re-opening find there — convenient when editing
 * the same variable/instance across several files. Monaco's find controller
 * is a stable-but-"internal" contribution API (no public typing in
 * @monaco-editor/react), hence the `as any` casts; the shape has been
 * consistent across Monaco versions for years.
 */
let pendingCrossFileFind: string | null = null;

function jumpToPaneWithTerm(currentPaneId: string, term: string, direction: 1 | -1) {
  if (!term) return;
  const panes = getStore().panes.filter(p => p.type === 'code' || p.type === 'markdown');
  const idx = panes.findIndex(p => p.id === currentPaneId);
  if (idx === -1 || panes.length < 2) return;
  const needle = term.toLowerCase();
  for (let step = 1; step < panes.length; step++) {
    const rawIdx = (idx + direction * step) % panes.length;
    const next = panes[(rawIdx + panes.length) % panes.length];
    if (next.content.toLowerCase().includes(needle)) {
      pendingCrossFileFind = term;
      storeActions.setActivePane(next.id);
      return;
    }
  }
}

function registerFindWidgetCrossFileNav(editor: any, monaco: any, paneId: string) {
  const getFindController = () => editor.getContribution('editor.contrib.findController');

  const openFindWithTerm = (term: string) => {
    const controller = getFindController();
    if (!controller) return;
    try {
      controller.setSearchString(term);
      controller.start({
        forceRevealReplace: false,
        seedSearchStringFromSelection: 'none',
        seedSearchStringFromNonEmptySelection: false,
        shouldFocus: 1,
        shouldAnimate: true,
        updateSearchScope: false,
        loop: true,
      });
    } catch { /* best-effort — internal API, degrade silently if it changes */ }
  };

  // If we just switched panes to satisfy a cross-file jump, resume the
  // search here with the carried-over term.
  if (pendingCrossFileFind) {
    const term = pendingCrossFileFind;
    pendingCrossFileFind = null;
    setTimeout(() => openFindWithTerm(term), 30);
  }

  const currentTerm = () => {
    try { return getFindController()?.getState()?.searchString || ''; } catch { return ''; }
  };

  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyMod.Alt | monaco.KeyCode.DownArrow, () => {
    jumpToPaneWithTerm(paneId, currentTerm(), 1);
  });
  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyMod.Alt | monaco.KeyCode.UpArrow, () => {
    jumpToPaneWithTerm(paneId, currentTerm(), -1);
  });
}

/** Toolbar shown above the editor when the open file has a pending write_file
 * edit awaiting review — lets the user flip to a diff view and keep/undo
 * either this file or every pending file at once, without leaving Canvas. */
const PendingEditToolbar: React.FC<{
  path: string; additions: number; deletions: number; pendingCount: number;
  diffView: boolean; onToggleDiff: () => void;
}> = ({ path, additions, deletions, pendingCount, diffView, onToggleDiff }) => (
  <div className="canvas-pending-toolbar">
    <div className="canvas-pending-toolbar-info">
      <span className="canvas-pending-badge">Pending change</span>
      <span className="diff-card-stat-add">+{additions}</span>
      <span className="diff-card-stat-del">-{deletions}</span>
    </div>
    <div className="canvas-pending-toolbar-actions">
      <button type="button" className={`canvas-pending-btn ${diffView ? 'canvas-pending-btn-active' : ''}`} onClick={onToggleDiff} title="Toggle diff view">
        <GitCompare size={12} /> Diff
      </button>
      <button type="button" className="canvas-pending-btn canvas-pending-btn-reject" onClick={() => storeActions.rejectFile(path)} title="Undo this file">
        <X size={12} /> Undo
      </button>
      <button type="button" className="canvas-pending-btn canvas-pending-btn-accept" onClick={() => storeActions.acceptFile(path)} title="Keep this file">
        <Check size={12} /> Keep
      </button>
      {pendingCount > 1 && (
        <>
          <span className="canvas-pending-divider" />
          <button type="button" className="canvas-pending-btn canvas-pending-btn-reject" onClick={() => storeActions.rejectAllFiles()} title="Undo all pending files">
            <RotateCcw size={12} /> Undo all ({pendingCount})
          </button>
          <button type="button" className="canvas-pending-btn canvas-pending-btn-accept" onClick={() => storeActions.acceptAllFiles()} title="Keep all pending files">
            <Check size={12} /> Keep all ({pendingCount})
          </button>
        </>
      )}
    </div>
  </div>
);

export const Canvas: React.FC = () => {
  // Selective subscription: Canvas/Monaco must not re-render on every chat
  // token (sessions update ~every 80ms while streaming) — only when the
  // slices it actually reads change.
  const store = useStoreSelector(s => ({
    panes: s.panes,
    activePaneId: s.activePaneId,
    pendingFiles: s.pendingFiles,
    projectPath: s.projectPath,
    monacoTheme: s.monacoTheme,
  }));
  const activePane = store.panes.find(p => p.id === store.activePaneId);
  const monacoRef = useRef<any>(null);
  const [diffView, setDiffView] = useState(false);

  const pendingEdit = activePane?.path ? store.pendingFiles[activePane.path] : undefined;
  const pendingCount = Object.keys(store.pendingFiles).length;

  // Diff view only makes sense while the file actually has a pending edit;
  // drop back to the normal editor the moment it's kept/undone.
  useEffect(() => { if (!pendingEdit) setDiffView(false); }, [pendingEdit]);

  // Keyboard shortcut Ctrl+S to save
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key === 's') {
        e.preventDefault();
        if (store.activePaneId) {
          storeActions.saveFile(store.activePaneId);
        }
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [store.activePaneId]);

  // Re-apply the matugen Monaco theme whenever GJS pushes new wallpaper
  // colors. Registered once for Canvas's whole lifetime (not per tab
  // switch) — bundling this with the keydown effect above meant every tab
  // switch briefly tore down and re-added this listener, and a theme_update
  // landing in that gap would be silently missed, leaving Monaco stuck on
  // whatever (possibly fallback) colors it mounted with.
  useEffect(() => {
    const onThemeRefresh = () => {
      if (monacoRef.current) applyMatugenThemeNow(monacoRef.current);
    };
    window.addEventListener('matugen_theme_changed', onThemeRefresh);
    return () => window.removeEventListener('matugen_theme_changed', onThemeRefresh);
  }, []);

  if (!activePane) {
    return (
      <div className="canvas-empty-state animate-fade-in">
        <div className="canvas-empty-icon-wrap">
          <Sparkles size={36} color="var(--accent-cyan)" />
        </div>
        <h3 className="canvas-empty-title">HyprCandy Agent Workspace</h3>
        <p className="canvas-empty-subtitle">
          Open a file or directory from the explorer, ask the agent to edit code, or create a new file to get started.
        </p>

        <div className="canvas-shortcuts-card">
          <div className="canvas-shortcut-row">
            <span className="shortcut-label">Open Directory / File</span>
            <kbd className="shortcut-key">Explorer</kbd>
          </div>
          <div className="canvas-shortcut-row">
            <span className="shortcut-label">Save Current File</span>
            <kbd className="shortcut-key">Ctrl + S</kbd>
          </div>
          <div className="canvas-shortcut-row">
            <span className="shortcut-label">Toggle Files & Project</span>
            <kbd className="shortcut-key">Left Panel</kbd>
          </div>
          <div className="canvas-shortcut-row">
            <span className="shortcut-label">Toggle Agent Chat</span>
            <kbd className="shortcut-key">Right Panel</kbd>
          </div>
        </div>

        <div className="canvas-empty-actions">
          <button
            type="button"
            className="empty-action-btn"
            onClick={() => storeActions.createNewFile()}
          >
            <FilePlus size={14} />
            <span>New File</span>
          </button>
          <button
            type="button"
            className="empty-action-btn"
            onClick={async () => {
              const picked = await bridge.openFileDialog({ directory: false, currentFolder: store.projectPath });
              if (picked) storeActions.openFileByPath(picked);
            }}
          >
            <FolderOpen size={14} />
            <span>Open File...</span>
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="canvas-content-wrapper">
      {store.panes.map(pane => {
        const isActive = pane.id === store.activePaneId;
        if (!isActive) return null;

        if (pane.type === 'code' || pane.type === 'markdown') {
          const targetTheme = store.monacoTheme === 'matugen' || !store.monacoTheme ? 'matugen' : store.monacoTheme;
          const showDiff = !!pendingEdit && diffView;
          return (
            <div key={pane.id} className="canvas-editor-pane-wrap">
              {pendingEdit && (
                <PendingEditToolbar
                  path={pane.path!}
                  additions={pendingEdit.additions}
                  deletions={pendingEdit.deletions}
                  pendingCount={pendingCount}
                  diffView={diffView}
                  onToggleDiff={() => setDiffView(v => !v)}
                />
              )}
              <div className="canvas-editor-pane">
                {showDiff ? (
                  <DiffEditor
                    // Same dispose-race concern as DiffWidget: a repeated
                    // write_file to this same path while the diff view is
                    // open changes pendingEdit's content identity — key by
                    // its timestamp so that's a clean remount, not an
                    // in-place model swap.
                    key={`${pane.path}:${pendingEdit!.timestamp}`}
                    height="100%"
                    theme={targetTheme}
                    beforeMount={(monaco) => { registerMonacoThemes(monaco); monacoRef.current = monaco; }}
                    language={pane.language || 'plaintext'}
                    original={pendingEdit!.oldContent}
                    modified={pane.content}
                    options={{
                      readOnly: true,
                      renderSideBySide: true,
                      minimap: { enabled: false },
                      fontSize: 13,
                      fontFamily: 'var(--font-mono)',
                      automaticLayout: true,
                      scrollBeyondLastLine: false,
                      accessibilitySupport: 'off',
                      experimentalGpuAcceleration: 'off',
                    }}
                  />
                ) : (
                  <Editor
                    height="100%"
                    theme={targetTheme}
                    beforeMount={(monaco) => { registerMonacoThemes(monaco); monacoRef.current = monaco; }}
                    onMount={(editor, monaco) => {
                      // Explicitly force the correct theme after all themes are registered.
                      // The `theme` prop alone can race with defineTheme; this guarantees winner.
                      try { monaco.editor.setTheme(targetTheme); } catch (_) {}

                      // Restore where you left off — Canvas unmounts/remounts
                      // a fresh editor on every tab switch (only the active
                      // pane renders), so without this every switch lands
                      // back at line 1 with no focus.
                      if (pane.cursorPosition) {
                        editor.setPosition(pane.cursorPosition);
                        editor.revealPositionInCenter(pane.cursorPosition);
                      }
                      if (typeof pane.scrollTop === 'number') {
                        editor.setScrollTop(pane.scrollTop);
                      }
                      editor.focus();

                      registerFindWidgetCrossFileNav(editor, monaco, pane.id);

                      let saveTimer: ReturnType<typeof setTimeout> | null = null;
                      editor.onDidChangeCursorPosition((e) => {
                        if (saveTimer) clearTimeout(saveTimer);
                        saveTimer = setTimeout(() => {
                          storeActions.setPaneViewState(pane.id, {
                            cursorPosition: { lineNumber: e.position.lineNumber, column: e.position.column },
                            scrollTop: editor.getScrollTop(),
                          });
                        }, 400);
                      });
                    }}
                    language={pane.language || 'plaintext'}
                    value={pane.content}
                    onChange={(value) => storeActions.updatePaneContent(pane.id, value || '')}
                    options={{
                      minimap: { enabled: true, side: 'right', showSlider: 'always', renderCharacters: false, maxColumn: 120 },
                      fontSize: 13,
                      lineNumbers: 'on',
                      wordWrap: 'on',
                      automaticLayout: true,
                      padding: { top: 14, bottom: 14 },
                      scrollBeyondLastLine: false,
                      renderLineHighlight: 'all',
                      fontFamily: 'var(--font-mono)',
                      cursorBlinking: 'smooth',
                      smoothScrolling: true,
                      accessibilitySupport: 'off',
                      experimentalGpuAcceleration: 'off',
                    }}
                  />
                )}
              </div>
            </div>
          );
        }

        if (pane.type === 'preview' && pane.path) {
          const src = /^https?:\/\//.test(pane.path) ? pane.path : `file://${pane.path}`;
          return (
            <div key={pane.id} className="canvas-preview-pane">
              <div className="canvas-preview-bar">
                <span className="canvas-preview-url">{src}</span>
                <button type="button" className="canvas-pending-btn" onClick={() => {
                  const frame = document.getElementById(`preview-frame-${pane.id}`) as HTMLIFrameElement | null;
                  if (frame) frame.src = frame.src;
                }}>
                  Reload
                </button>
              </div>
              <iframe id={`preview-frame-${pane.id}`} src={src} className="canvas-preview-frame" title={pane.name} />
            </div>
          );
        }

        if (pane.type === 'image-gallery') {
          return (
            <div key={pane.id} className="canvas-media-pane">
              <MediaGallery
                mediaItems={pane.data || (pane.path ? [{ name: pane.name, path: pane.path, type: 'file', size: 0 }] : [])}
                mediaType="image"
              />
            </div>
          );
        }

        if (pane.type === 'video-gallery') {
          return (
            <div key={pane.id} className="canvas-media-pane">
              <MediaGallery
                mediaItems={pane.data || (pane.path ? [{ name: pane.name, path: pane.path, type: 'file', size: 0 }] : [])}
                mediaType="video"
              />
            </div>
          );
        }

        if (pane.type === 'image' && pane.path) {
          return (
            <div key={pane.id} className="canvas-single-media">
              <img src={getMediaUrl(pane.path)} alt={pane.name} className="single-image-view" />
            </div>
          );
        }

        if (pane.type === 'video' && pane.path) {
          return (
            <div key={pane.id} className="canvas-single-media">
              <video src={getMediaUrl(pane.path)} controls autoPlay className="single-video-view" />
            </div>
          );
        }

        if (pane.type === 'audio' && pane.path) {
          return (
            <div key={pane.id} className="canvas-single-audio">
              <Music size={48} color="var(--accent-cyan)" />
              <div className="audio-title">{pane.name}</div>
              <audio src={getMediaUrl(pane.path)} controls autoPlay className="single-audio-player" />
            </div>
          );
        }

        return (
          <div key={pane.id} className="canvas-unsupported">
            <p>Unsupported view for {pane.name}</p>
          </div>
        );
      })}
    </div>
  );
};
