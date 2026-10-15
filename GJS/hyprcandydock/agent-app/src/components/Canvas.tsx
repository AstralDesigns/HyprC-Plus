import React, { useCallback, useEffect, useRef, useState } from 'react';
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
import { registerCustomLanguages, attachDiagnostics } from '../utils/monacoLanguages';
import { getMediaUrl } from '../utils/media';

/**
 * Find-widget carry + cross-file navigation.
 *
 * The active pane's editor is remounted on every tab switch, so Monaco tears
 * its find/replace widget down with the old instance. We snapshot the widget
 * state live (search term, replace term, the matchCase/wholeWord/isRegex/
 * preserveCase toggles, and whether the replace row was shown) and silently
 * re-open it on the next code/markdown editor mount, so the widget appears to
 * stay open as you move between files — even with non-code canvases in between
 * — until you explicitly close it (a real close clears the carry). Editor
 * teardown disposes the find state without firing a close event, so switching
 * does NOT clear it.
 *
 * Ctrl+Alt+Down / Ctrl+Alt+Up additionally cycle to the next/previous open
 * code/markdown tab that CONTAINS the current term (a targeted find-across-
 * files), reusing the same carry to re-open find there. Monaco's find
 * controller is a stable-but-internal contribution API (no public typing in
 * @monaco-editor/react), hence the `any` casts.
 */
type CarriedFind = {
  searchTerm: string; replaceTerm: string;
  caseSensitive: boolean; wholeWord: boolean; isRegex: boolean; preserveCase: boolean;
  replaceRevealed: boolean;
};
let carriedFind: CarriedFind | null = null;

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
      // carriedFind already holds the live term/options; the target's mount
      // re-opens the widget from it. Just move focus to the matching pane.
      storeActions.setActivePane(next.id);
      return;
    }
  }
}

function registerFindWidgetCrossFileNav(editor: any, monaco: any, paneId: string) {
  const controller = editor.getContribution?.('editor.contrib.findController');
  const state = controller && typeof controller.getState === 'function' ? controller.getState() : null;
  if (!controller || !state) return;

  const readCarry = (): CarriedFind => ({
    searchTerm: state.searchString || '',
    replaceTerm: state.replaceString || '',
    caseSensitive: !!state.matchCase,
    wholeWord: !!state.wholeWord,
    isRegex: !!state.isRegex,
    preserveCase: !!state.preserveCase,
    replaceRevealed: !!state.isReplaceRevealed,
  });

  // Re-open the carried widget on a plain tab switch (no keybind needed). Order
  // matters: controller.start() CONSTRUCTS/reveals the find widget, and the
  // widget only pushes state into its visible fields on a searchString change
  // event it receives AFTER it exists. So reveal first, then set the terms —
  // setting them before start() computed the match count but left the input
  // blank. Two short attempts cover a freshly-mounted editor not being ready on
  // the first pass; both no-op once the widget is already revealed.
  if (carriedFind) {
    const reopen = () => {
      const cf = carriedFind;
      if (!cf || state.isRevealed) return;
      try {
        controller.start({
          forceRevealReplace: cf.replaceRevealed,
          seedSearchStringFromSelection: 'none',
          seedSearchStringFromNonEmptySelection: false,
          shouldFocus: 1, shouldAnimate: false, updateSearchScope: false, loop: true,
        });
        // Widget now exists and is visible — populate the fields so the carried
        // search/replace text actually shows (not just the match count).
        state.change({
          searchString: cf.searchTerm,
          replaceString: cf.replaceTerm,
          matchCase: cf.caseSensitive, wholeWord: cf.wholeWord,
          isRegex: cf.isRegex, preserveCase: cf.preserveCase,
          isReplaceRevealed: cf.replaceRevealed,
        }, false, false);
      } catch { /* degrade silently */ }
    };
    setTimeout(reopen, 40);
    setTimeout(reopen, 160);
  }

  // Keep the carry current while the widget is open; drop it on an intentional
  // close (a change event that toggles isRevealed off). Non-reveal events while
  // hidden are ignored so nothing nulls the carry by accident.
  let sub: any = null;
  try {
    sub = state.onFindReplaceStateChange((e: any) => {
      try {
        if (state.isRevealed) carriedFind = readCarry();
        else if (e && e.isRevealed) carriedFind = null;
      } catch { /* noop */ }
    });
  } catch { /* internal API drift */ }
  try { editor.onDidDispose(() => { try { sub?.dispose?.(); } catch { /* noop */ } }); } catch { /* noop */ }

  const currentTerm = () => { try { return state.searchString || ''; } catch { return ''; } };
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
  const markerDispRef = useRef<any>(null);
  const editorRef = useRef<any>(null);
  const lastEmittedRef = useRef<string>('');
  const [diffView, setDiffView] = useState(false);

  // Stable change handler: a fresh closure every render makes the library
  // tear down/re-add its onDidChangeModelContent subscription on each commit,
  // which can drop a keystroke under rapid typing. Track what we emitted so the
  // external-sync effect can tell our own edits apart from a background reload.
  const activePaneId = store.activePaneId;
  const handleEditChange = useCallback((val: string | undefined) => {
    lastEmittedRef.current = val || '';
    if (activePaneId) storeActions.updatePaneContent(activePaneId, val || '');
  }, [activePaneId]);

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

  // Dispose the active editor's marker listener when Canvas itself unmounts.
  // Per-tab remounts dispose the previous listener inside onMount below.
  useEffect(() => () => {
    try { markerDispRef.current?.dispose(); } catch { /* noop */ }
    markerDispRef.current = null;
  }, []);

  // Push EXTERNAL content reloads (reject / revert / re-open) into the mounted
  // editor imperatively. Typing is uncontrolled (defaultValue below) so the
  // library's full-document value-sync can't fire mid-keystroke and collapse
  // the selection to the end of the file. External reloads always set
  // isUnsaved=false while the user's edits set it true, so gating on
  // !isUnsaved applies only the former — and restoring the position keeps a
  // background refresh seamless instead of yanking the caret.
  useEffect(() => {
    const ap = activePane;
    if (!ap?.path) return;
    const ed = editorRef.current;
    if (!ed) return;
    let model: any;
    try { model = ed.getModel(); } catch { return; }
    if (!model || model.isDisposed?.()) return;
    if (ap.isUnsaved) return;
    if (model.getValue() === ap.content) return;
    // A store update that just echoes our own keystroke isn't an external edit.
    if (lastEmittedRef.current === ap.content) return;
    const pos = ed.getPosition();
    try {
      ed.setValue(ap.content);
      if (pos) { ed.setPosition(pos); ed.revealPositionInCenterIfOutsideViewport(pos); }
    } catch { /* editor torn down mid-switch */ }
  }, [activePane?.id, activePane?.path, activePane?.content, activePane?.isUnsaved]);

  // When the app window regains focus with nothing else focused (e.g. coming
  // back from another workspace), hand the caret to the open Monaco file so
  // it's immediately typeable. Guarded on activeElement so it never steals
  // focus from the chat box or any other active input.
  useEffect(() => {
    const refocusCanvas = () => {
      const ae = document.activeElement;
      if (!ae || ae === document.body || ae === document.documentElement) {
        try { editorRef.current?.focus(); } catch { /* noop */ }
      }
    };
    window.addEventListener('focus', refocusCanvas);
    return () => window.removeEventListener('focus', refocusCanvas);
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
            <span className="shortcut-label">Open Folder</span>
            <kbd className="shortcut-key">Ctrl + O</kbd>
          </div>
          <div className="canvas-shortcut-row">
            <span className="shortcut-label">Save Current File</span>
            <kbd className="shortcut-key">Ctrl + S</kbd>
          </div>
          <div className="canvas-shortcut-row">
            <span className="shortcut-label">Toggle Files & Project</span>
            <kbd className="shortcut-key">Ctrl + 1</kbd>
          </div>
          <div className="canvas-shortcut-row">
            <span className="shortcut-label">Toggle Agent Chat</span>
            <kbd className="shortcut-key">Ctrl + 2</kbd>
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
                    beforeMount={(monaco) => { registerMonacoThemes(monaco); registerCustomLanguages(monaco); monacoRef.current = monaco; }}
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
                    path={pane.path}
                    theme={targetTheme}
                    beforeMount={(monaco) => { registerMonacoThemes(monaco); registerCustomLanguages(monaco); monacoRef.current = monaco; }}
                    onMount={(editor, monaco) => {
                      editorRef.current = editor;
                      // Explicitly force the correct theme after all themes are registered.
                      // The `theme` prop alone can race with defineTheme; this guarantees winner.
                      try { monaco.editor.setTheme(targetTheme); } catch (_) {}
                      // Live syntax markers for languages without a Monaco worker
                      // (Lua via luaparse, QML structural check); JSON/CSS/HTML/TS
                      // are validated by their own workers.
                      try { attachDiagnostics(monaco, editor); } catch (_) {}

                      // Mirror this file's error-marker state into the store so the
                      // tab + project tree can show a syntax-error badge. Only the
                      // active pane's editor is mounted, so one listener at a time.
                      try {
                        const model = editor.getModel();
                        if (model && pane.path) {
                          const p = pane.path;
                          const compute = () => {
                            try {
                              const ms = monaco.editor.getModelMarkers({ resource: model.uri });
                              const errSev = monaco.MarkerSeverity?.Error ?? 8;
                              storeActions.setFileError(p, ms.some((m: any) => m.severity === errSev));
                            } catch { /* noop */ }
                          };
                          try { markerDispRef.current?.dispose(); } catch { /* noop */ }
                          markerDispRef.current = monaco.editor.onDidChangeMarkers((uris: any[]) => {
                            if (uris.some(u => u && u.toString() === model.uri.toString())) compute();
                          });
                          compute();
                        }
                      } catch (_) {}

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
                      // Auto-focus the file on open / tab switch / workspace resume
                      // (each remounts the active pane's editor). Re-assert across
                      // the next frames because a new file also inserts a header tab
                      // whose re-render + Monaco re-layout can drop the caret. Focus
                      // only when the caret is nowhere (body) or already inside this
                      // editor. NOTE: files opened from the floating sidebar are left
                      // as-is — Qt WebEngine keeps active focus on the overlaid
                      // sidebar row, so an auto-handoff there is unreliable.
                      const editorNode = editor.getDomNode();
                      const focusEditor = () => {
                        try {
                          const ae = document.activeElement;
                          const insideEditor = !!(editorNode && ae && editorNode.contains(ae));
                          const nowhere = !ae || ae === document.body || ae === document.documentElement;
                          if (insideEditor || nowhere) editor.focus();
                        } catch { /* editor torn down mid-switch */ }
                      };
                      focusEditor();
                      requestAnimationFrame(focusEditor);
                      [60, 140, 260].forEach((d) => setTimeout(focusEditor, d));

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
                    defaultValue={pane.content}
                    onChange={handleEditChange}
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
