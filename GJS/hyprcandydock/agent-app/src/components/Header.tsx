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
    store.modelStatus === 'ready'       ? 'ready'   :
    store.modelStatus === 'downloading' ||
    store.modelStatus === 'loading'     ? 'loading' :
    store.modelStatus === 'error'       ? 'error'   : 'idle';

  const handleWheelTabs = (e: React.WheelEvent) => {
    if (tabsContainerRef.current) {
      e.preventDefault();
      tabsContainerRef.current.scrollLeft += e.deltaX !== 0 ? e.deltaX : e.deltaY;
    }
  };

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
              className={`header-tab ${isActive ? 'active' : ''}`}
              onClick={() => storeActions.setActivePane(pane.id)}
              title={pane.path || pane.name}
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


        <button
          type="button"
          className="model-chip"
          onClick={() => setStore({ modelManagerOpen: true })}
          title="Manage local AI models"
        >
          <div className={`status-dot ${modelStatusClass}`} />
          <Cpu size={12} />
          <span className="model-chip-name">{activeModelInfo.name}</span>
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
