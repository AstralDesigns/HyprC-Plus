import React, { useEffect, useRef } from 'react';
import Editor from '@monaco-editor/react';
import {
  Music,
  FolderOpen,
  FilePlus,
  Sparkles,
} from 'lucide-react';
import { useStore, storeActions } from '../store';
import { MediaGallery } from './MediaGallery';
import { bridge } from '../bridge';
import { registerMonacoThemes, applyMatugenThemeNow } from '../utils/monacoThemes';
import { getMediaUrl } from '../utils/media';

export const Canvas: React.FC = () => {
  const [store] = useStore();
  const activePane = store.panes.find(p => p.id === store.activePaneId);
  const monacoRef = useRef<any>(null);

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

    // Re-apply matugen monaco theme when GJS host injects new wallpaper colors
    const onThemeRefresh = () => {
      if (monacoRef.current) applyMatugenThemeNow(monacoRef.current);
    };
    window.addEventListener('matugen_theme_changed', onThemeRefresh);

    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('matugen_theme_changed', onThemeRefresh);
    };
  }, [store.activePaneId]);

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
          return (
            <div key={pane.id} className="canvas-editor-pane">
              <Editor
                height="100%"
                theme={store.monacoTheme === 'matugen' || !store.monacoTheme ? 'matugen' : store.monacoTheme}
                beforeMount={(monaco) => { registerMonacoThemes(monaco); monacoRef.current = monaco; }}
                onMount={(_editor, monaco) => {
                  // Explicitly force the correct theme after all themes are registered.
                  // The `theme` prop alone can race with defineTheme; this guarantees winner.
                  const targetTheme = store.monacoTheme === 'matugen' || !store.monacoTheme ? 'matugen' : store.monacoTheme;
                  try { monaco.editor.setTheme(targetTheme); } catch (_) {}
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
                }}
              />
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
