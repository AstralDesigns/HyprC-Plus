import React, { useState, useRef, useEffect } from 'react';
import {
  Menu,
  ChevronDown,
  FilePlus,
  FolderOpen,
  FolderSearch,
  Save,
  MessageSquare,
  Cpu,
  Plus,
  X,
  Code,
  FileText,
  Image as ImageIcon,
  Video,
  Music,
  Files,
} from 'lucide-react';
import { useStore, setStore, storeActions, PRESET_MODELS, FilePane } from '../store';
import { bridge } from '../bridge';

function getTabIcon(pane: FilePane) {
  if (pane.type === 'image-gallery' || pane.type === 'image') return <ImageIcon size={12} color="var(--accent-cyan)" />;
  if (pane.type === 'video-gallery' || pane.type === 'video') return <Video size={12} color="var(--accent-yellow)" />;
  if (pane.type === 'audio') return <Music size={12} color="var(--accent-purple)" />;
  if (pane.type === 'markdown') return <FileText size={12} color="var(--text-secondary)" />;
  return <Code size={12} color="var(--accent-green)" />;
}

export const Header: React.FC = () => {
  const [store] = useStore();
  const [showDropdown, setShowDropdown] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);
  const tabsContainerRef = useRef<HTMLDivElement>(null);
  const [draggedId, setDraggedId] = useState<string | null>(null);
  const [dragOverId, setDragOverId] = useState<string | null>(null);
  const tabRefs = useRef<Record<string, HTMLDivElement | null>>({});
  const pointerStartRef = useRef<{ x: number; y: number; id: string } | null>(null);
  const suppressClickRef = useRef(false);

  // Close dropdown on click outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setShowDropdown(false);
      }
    };
    if (showDropdown) {
      document.addEventListener('mousedown', handleClickOutside);
    }
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [showDropdown]);

  const activeModelInfo = [...PRESET_MODELS, ...(store.customModels || [])]
    .find(m => m.id === store.activeModel) || PRESET_MODELS[0];

  const modelStatusClass =
    store.modelStatus === 'ready' ? 'ready' :
      store.modelStatus === 'downloading' ||
        store.modelStatus === 'loading' ? 'loading' :
        store.modelStatus === 'error' ? 'error' : 'idle';

  const handleWheelTabs = (e: React.WheelEvent) => {
    // Kept only as a fallback for environments where the native listener
    // below doesn't attach in time; the real fix is the useEffect listener,
    // since React's onWheel is passive by default and preventDefault() here
    // is otherwise silently ignored.
    if (tabsContainerRef.current) {
      tabsContainerRef.current.scrollLeft += e.deltaX !== 0 ? e.deltaX : e.deltaY;
    }
  };

  useEffect(() => {
    const el = tabsContainerRef.current;
    if (!el) return;
    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      e.stopPropagation();
      el.scrollLeft += e.deltaX !== 0 ? e.deltaX : e.deltaY;
    };
    el.addEventListener('wheel', onWheel, { passive: false });
    return () => el.removeEventListener('wheel', onWheel);
  }, []);

  // Manual pointer-based tab reordering (see onPointerDown above for why
  // this isn't native HTML5 drag-and-drop). A small movement threshold
  // before "drag" actually starts keeps ordinary clicks unaffected.
  useEffect(() => {
    const DRAG_THRESHOLD = 6;
    let dragging = false;

    const hitTest = (clientX: number): string | null => {
      for (const [id, node] of Object.entries(tabRefs.current)) {
        if (!node) continue;
        const rect = node.getBoundingClientRect();
        if (clientX >= rect.left && clientX <= rect.right) return id;
      }
      return null;
    };

    const onMove = (e: PointerEvent) => {
      const start = pointerStartRef.current;
      if (!start) return;
      if (!dragging) {
        if (Math.abs(e.clientX - start.x) < DRAG_THRESHOLD && Math.abs(e.clientY - start.y) < DRAG_THRESHOLD) return;
        dragging = true;
        suppressClickRef.current = true;
        setDraggedId(start.id);
      }
      const overId = hitTest(e.clientX);
      setDragOverId(overId && overId !== start.id ? overId : null);
    };

    const onUp = () => {
      const start = pointerStartRef.current;
      pointerStartRef.current = null;
      if (dragging && start) {
        setDragOverId(current => {
          if (current && current !== start.id) storeActions.reorderPanes(start.id, current);
          return null;
        });
      }
      dragging = false;
      setDraggedId(null);
      // Swallow the click that follows a real drag; let a plain click
      // (no movement past the threshold) through normally.
      if (suppressClickRef.current) {
        setTimeout(() => { suppressClickRef.current = false; }, 0);
      }
    };

    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
    return () => {
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
    };
  }, []);

  const handleNewFile = () => {
    setShowDropdown(false);
    storeActions.createNewFile();
  };

  const handleOpenFile = async () => {
    setShowDropdown(false);
    try {
      const picked = await bridge.openFileDialog({ directory: false, currentFolder: store.projectPath });
      if (picked) storeActions.openFileByPath(picked);
    } catch (e) {
      console.warn('Open file error:', e);
    }
  };

  const handleOpenFolder = async () => {
    setShowDropdown(false);
    try {
      const picked = await bridge.openFileDialog({ directory: true, currentFolder: store.projectPath });
      if (picked) {
        setStore({ projectPath: picked });
        storeActions.navigateTo(picked);
      }
    } catch (e) {
      console.warn('Open folder error:', e);
    }
  };

  const handleSaveActive = async () => {
    setShowDropdown(false);
    if (store.activePaneId) {
      await storeActions.saveFile(store.activePaneId);
    }
  };

  const activePane = store.panes.find(p => p.id === store.activePaneId);

  return (
    <header className="app-top-header">
      {/* Left controls: Sidebar toggle & File dropdown menu */}
      <div className="header-left">
        <button
          type="button"
          onClick={() => storeActions.toggleSidebar()}
          className={`header-icon-btn ${store.sidebarVisible ? 'active' : ''}`}
          title={store.sidebarVisible ? 'Hide explorer panel' : 'Show explorer panel'}
        >
          <Menu size={15} />
        </button>

        <div className="relative-wrap" ref={dropdownRef}>
          <button
            type="button"
            onClick={() => setShowDropdown(!showDropdown)}
            className={`header-menu-toggle-btn ${showDropdown ? 'active' : ''}`}
            title="File menu"
          >
            <span>File</span>
            <ChevronDown size={11} className={showDropdown ? 'rotate-180' : ''} />
          </button>

          {showDropdown && (
            <div className="header-dropdown-menu animate-fade-in">
              <button type="button" className="dropdown-item" onClick={handleNewFile}>
                <FilePlus size={13} color="var(--accent-cyan)" />
                <span>New File</span>
                <span className="dropdown-shortcut">Ctrl+N</span>
              </button>
              <button type="button" className="dropdown-item" onClick={handleOpenFile}>
                <FolderOpen size={13} color="var(--accent-cyan)" />
                <span>Open File...</span>
                <span className="dropdown-shortcut">Ctrl+O</span>
              </button>
              <button type="button" className="dropdown-item" onClick={handleOpenFolder}>
                <FolderSearch size={13} color="var(--accent-yellow)" />
                <span>Open Project Folder...</span>
              </button>
              <div className="dropdown-divider" />
              <button
                type="button"
                className="dropdown-item"
                onClick={handleSaveActive}
                disabled={!activePane?.isUnsaved}
              >
                <Save size={13} color={activePane?.isUnsaved ? 'var(--accent-green)' : 'var(--text-muted)'} />
                <span>Save Current</span>
                <span className="dropdown-shortcut">Ctrl+S</span>
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Center: Open Pane Tabs */}
      <div className="header-center-tabs" ref={tabsContainerRef} onWheel={handleWheelTabs}>
        {store.panes.map(pane => {
          const isActive = pane.id === store.activePaneId;
          return (
            <div
              key={pane.id}
              ref={(el) => { tabRefs.current[pane.id] = el; }}
              className={`header-tab ${isActive ? 'active' : ''} ${dragOverId === pane.id ? 'tab-drag-over' : ''} ${draggedId === pane.id ? 'tab-dragging' : ''}`}
              onClick={() => { if (!suppressClickRef.current) storeActions.setActivePane(pane.id); }}
              title={pane.path || pane.name}
              onPointerDown={(e) => {
                // Manual pointer-based reordering instead of native HTML5
                // drag-and-drop: the native DnD API depends on platform
                // integration that embedded WebKitGTK views don't reliably
                // provide (drag sessions can get stuck with no drop ever
                // firing). Plain pointer events work the same everywhere.
                if (e.button !== 0) return;
                pointerStartRef.current = { x: e.clientX, y: e.clientY, id: pane.id };
              }}
            >
              {getTabIcon(pane)}
              {pane.isUnsaved && <span className="tab-unsaved-dot" title="Unsaved changes" />}
              <span className="tab-title">{pane.name}</span>
              <button
                type="button"
                className="tab-close-btn"
                onClick={(e) => {
                  e.stopPropagation();
                  storeActions.closePane(pane.id);
                }}
                title="Close tab"
              >
                <X size={11} />
              </button>
            </div>
          );
        })}
      </div>

      {/* Right controls: Processing, Model Chip, Chat Toggle */}
      <div className="header-right">
        {store.agentRunning && (
          <div className="processing-indicator">
            <span className="processing-dot" />
            <span>Agent Busy…</span>
          </div>
        )}


        {/* Active model chip — doubles as active model display and ModelManager toggle */}
        <button
          type="button"
          className="model-chip"
          onClick={() => setStore({ modelManagerOpen: true })}
          title="Configure inference backend"
        >
          <div
            className={`status-dot ${modelStatusClass}`}
            style={store.modelStatus === 'ready' ? {
              background: 'var(--matugen-primary, #a0c9dc)',
              boxShadow: '0 0 6px var(--matugen-primary, #a0c9dc)',
            } : undefined}
          />
          <Cpu
            size={12}
            style={{
              color: store.modelStatus === 'ready' ? 'var(--matugen-primary, #a0c9dc)' : 'inherit',
              transition: 'color var(--transition-fast)',
            }}
          />
          <span className="model-chip-name">
            {(() => {
              const KNOWN_LABELS: Record<string, string> = {
                'openrouter/free': 'OpenRouter Free',
                'anthropic/claude-3.7-sonnet': 'Claude 3.7 Sonnet',
                'claude-3-7-sonnet-20250219': 'Claude 3.7 Sonnet',
                'claude-opus-4': 'Claude Opus 4',
                'claude-sonnet-4-5': 'Claude Sonnet 4.5',
                'claude-haiku-4-5': 'Claude Haiku 4.5',
                'gpt-4.5-preview': 'GPT-4.5 Orion',
                'openai/gpt-4.5-preview': 'GPT-4.5 Orion',
                'gpt-4o': 'GPT-4o',
                'openai/gpt-4o': 'GPT-4o',
                'gpt-4o-mini': 'GPT-4o mini',
                'openai/gpt-4o-mini': 'GPT-4o mini',
                'o3-mini': 'o3-mini',
                'openai/o3-mini': 'o3-mini',
                'o3': 'o3',
                'deepseek/deepseek-r1': 'DeepSeek R1',
                'deepseek/deepseek-chat': 'DeepSeek V3',
                'meta-llama/llama-3.3-70b-instruct': 'Llama 3.3 70B',
                'llama-3.3-70b-versatile': 'Llama 3.3 70B',
                'llama-3.1-8b-instant': 'Llama 3.1 8B',
                'qwen-2.5-coder-32b': 'Qwen 2.5 Coder 32B',
                'qwen/qwen-2.5-coder-32b-instruct': 'Qwen 2.5 Coder 32B',
                'deepseek-r1-distill-llama-70b': 'DeepSeek R1 70B',
                'mixtral-8x7b-32768': 'Mixtral 8x7B',
                'gemma2-9b-it': 'Gemma 2 9B',
                'gemini-3.8-flash': 'Gemini 3.8 Flash',
                'gemini-3.6-flash': 'Gemini 3.6 Flash',
                'gemini-3.1-pro-preview': 'Gemini 3.1 Pro',
                'gemini-3.1-flash-lite': 'Gemini 3.1 Flash-Lite',
                'google/gemini-2.5-pro': 'Gemini 2.5 Pro',
                'google/gemini-2.5-flash': 'Gemini 2.5 Flash',
                'grok-3': 'Grok 3',
                'grok-3-mini': 'Grok 3 Mini',
                'grok-2-1212': 'Grok 2',
                'x-ai/grok-3': 'Grok 3',
              };

              if (store.inferenceMode === 'byok') {
                const raw = store.byokModel;
                if (store.byokProvider === 'openrouter') {
                  if (!raw || raw === 'openrouter/free') return 'OpenRouter Free';
                }
                if (store.byokProvider === 'groq') {
                  if (!raw || raw === 'llama-3.3-70b-versatile') return 'Llama 3.3 70B';
                }
                if (raw && KNOWN_LABELS[raw]) return KNOWN_LABELS[raw];
                if (raw) {
                  const seg = raw.split('/').pop() || raw;
                  return seg.replace(/-20\d{6}$/, '').replace(/-preview$/, '').replace(/-/g, ' ').replace(/\b\w/g, c => c.toUpperCase()).slice(0, 24);
                }
                const prov = store.byokProvider;
                return prov ? prov.charAt(0).toUpperCase() + prov.slice(1) : 'Candy Agent';
              }
              if (store.inferenceMode === 'cloud') {
                return KNOWN_LABELS[store.cloudModel || ''] || store.cloudModel || 'Candy Agent';
              }
              if (store.inferenceMode === 'local') {
                return store.activeModel
                  ? store.activeModel.replace(/\.gguf$/i, '').replace(/_/g, ' ').slice(0, 24)
                  : 'Local Model';
              }
              return 'Candy Agent';
            })()}&nbsp;
            <span style={{
              fontSize: '10px',
              padding: '1px 7px',
              borderRadius: 'var(--radius-full)',
              background: store.modelStatus === 'ready'
                ? 'color-mix(in srgb, var(--matugen-primary, #a0c9dc) 18%, transparent)'
                : store.modelStatus === 'loading' || store.modelStatus === 'downloading'
                  ? 'color-mix(in srgb, var(--wallust-color5, #BA8C40) 20%, transparent)'
                  : 'rgba(255,255,255,.08)',
              border: `1px solid ${store.modelStatus === 'ready'
                ? 'color-mix(in srgb, var(--matugen-primary, #a0c9dc) 35%, transparent)'
                : 'transparent'}`,
              color: store.modelStatus === 'ready'
                ? 'var(--matugen-primary, #a0c9dc)'
                : store.modelStatus === 'loading' || store.modelStatus === 'downloading'
                  ? 'var(--wallust-color5, #BA8C40)'
                  : 'var(--text-muted)',
              fontWeight: 700,
              transition: 'all var(--transition-fast)',
            }}>
              {store.modelStatus === 'ready' ? 'Active' : store.modelStatus === 'loading' || store.modelStatus === 'downloading' ? 'Loading' : 'Idle'}
            </span>
          </span>
        </button>

        <button
          type="button"
          onClick={() => setStore({ chatVisible: !store.chatVisible })}
          className={`header-icon-btn ${store.chatVisible ? 'active' : ''}`}
          title={store.chatVisible ? 'Hide chat panel' : 'Show chat panel'}
        >
          <MessageSquare size={15} />
        </button>
      </div>
    </header>
  );
};
