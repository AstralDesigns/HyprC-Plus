import React, { useState, useEffect, useRef } from 'react';
import { createPortal } from 'react-dom';
import {
  Folder,
  FolderOpen,
  File,
  FileCode,
  FileText,
  FileJson,
  Image as ImageIcon,
  Video,
  Music,
  Home,
  ChevronLeft,
  ChevronRight,
  ChevronDown,
  ChevronUp,
  RefreshCw,
  Eye,
  EyeOff,
  Search,
  X,
  FolderSearch,
  Plus,
  Check,
  Copy,
  Clipboard,
  Trash2,
  Move,
} from 'lucide-react';
import { useStore, setStore, storeActions, FileSystemItem } from '../store';
import { bridge } from '../bridge';

function getFileIcon(name: string, isDir: boolean) {
  if (isDir) return <Folder size={13} color="var(--accent-yellow)" />;
  const ext = name.split('.').pop()?.toLowerCase() || '';
  if (['ts', 'tsx', 'js', 'jsx', 'py', 'sh', 'bash', 'c', 'cpp', 'rs', 'go', 'html', 'css'].includes(ext)) {
    return <FileCode size={13} color="var(--accent-cyan)" />;
  }
  if (['json', 'yaml', 'yml', 'toml', 'ini'].includes(ext)) {
    return <FileJson size={13} color="var(--accent-yellow)" />;
  }
  if (['png', 'jpg', 'jpeg', 'webp', 'svg', 'gif'].includes(ext)) {
    return <ImageIcon size={13} color="var(--accent-teal)" />;
  }
  if (['mp4', 'webm', 'mov', 'mkv'].includes(ext)) {
    return <Video size={13} color="var(--accent-gold)" />;
  }
  if (['mp3', 'wav', 'ogg', 'flac'].includes(ext)) {
    return <Music size={13} color="var(--accent-purple)" />;
  }
  if (['md', 'txt', 'log'].includes(ext)) {
    return <FileText size={13} color="var(--text-secondary)" />;
  }
  return <File size={13} color="var(--text-muted)" />;
}

function formatSize(bytes?: number): string {
  if (bytes === undefined || bytes === null || bytes === 0) return '';
  if (bytes < 1024) return bytes + 'B';
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(0) + 'K';
  return (bytes / (1024 * 1024)).toFixed(1) + 'M';
}

type ProjectEntry = { name: string; isDir: boolean; size: number; path: string };

export const Sidebar: React.FC = () => {
  const [store] = useStore();
  const [filterSearch, setFilterSearch] = useState('');
  const [projectSearch, setProjectSearch] = useState('');
  const [projectFiles, setProjectFiles] = useState<ProjectEntry[]>([]);
  const [expandedFolders, setExpandedFolders] = useState<Set<string>>(new Set());
  const [folderChildren, setFolderChildren] = useState<Record<string, ProjectEntry[]>>({});
  const [loadingFolders, setLoadingFolders] = useState<Set<string>>(new Set());
  const [loadingProject, setLoadingProject] = useState(false);
  const [contextMenu, setContextMenu] = useState<{ x: number; y: number; entry: ProjectEntry } | null>(null);

  // Resize handling
  const isResizing = useRef(false);
  const startX = useRef(0);
  const startWidth = useRef(0);

  const startResize = (e: React.MouseEvent) => {
    e.preventDefault();
    isResizing.current = true;
    startX.current = e.clientX;
    startWidth.current = store.sidebarWidth;

    const onMouseMove = (moveEvent: MouseEvent) => {
      if (!isResizing.current) return;
      const delta = moveEvent.clientX - startX.current;
      const newWidth = Math.max(180, Math.min(window.innerWidth * 0.6, startWidth.current + delta));
      storeActions.setSidebarWidth(newWidth);
    };

    const onMouseUp = () => {
      isResizing.current = false;
      window.removeEventListener('mousemove', onMouseMove);
      window.removeEventListener('mouseup', onMouseUp);
    };

    window.addEventListener('mousemove', onMouseMove);
    window.addEventListener('mouseup', onMouseUp);
  };

  // Initial load of filesystem directory
  useEffect(() => {
    storeActions.refreshDirectory();
  }, [store.currentPath]);

  // Load project root
  const loadProjectDir = async (dirPath: string) => {
    setLoadingProject(true);
    try {
      const items = await bridge.listDirectory(dirPath);
      const sorted: ProjectEntry[] = items
        .map(i => ({ ...i, path: `${dirPath.replace(/\/$/, '')}/${i.name}` }))
        .sort((a, b) => Number(b.isDir) - Number(a.isDir) || a.name.localeCompare(b.name));
      setProjectFiles(sorted);
        setStore({ projectFiles: sorted, projectPath: dirPath });
      setFolderChildren({});
      setExpandedFolders(new Set());
    } catch (e) {
      console.warn('Error loading project directory:', e);
    } finally {
      setLoadingProject(false);
    }
  };

  useEffect(() => {
    if (store.projectPath) {
      loadProjectDir(store.projectPath);
    }
  }, [store.projectPath]);

  const shellQuote = (value: string) => `'${value.replace(/'/g, `'\\''`)}'`;
  const runFileAction = async (action: 'copy' | 'move' | 'delete' | 'copy-path') => {
    const entry = contextMenu?.entry;
    setContextMenu(null);
    if (!entry) return;
    if (action === 'copy-path') {
      await navigator.clipboard?.writeText(entry.path);
      return;
    }
    if (action === 'delete' && !window.confirm(`Delete ${entry.name}?`)) return;
    if (action === 'copy' || action === 'move') {
      const destination = await bridge.openFileDialog({ directory: true, currentFolder: store.projectPath });
      if (!destination) return;
      await bridge.execCommand(`${action === 'copy' ? 'cp -R' : 'mv'} ${shellQuote(entry.path)} ${shellQuote(destination)}`, store.projectPath);
    } else if (action === 'delete') {
      await bridge.execCommand(`rm -rf -- ${shellQuote(entry.path)}`, store.projectPath);
    }
    await loadProjectDir(store.projectPath);
  };

  // Expand / collapse folder in project tree
  const toggleProjectFolder = async (folderPath: string) => {
    const next = new Set(expandedFolders);
    if (next.has(folderPath)) {
      next.delete(folderPath);
      setExpandedFolders(next);
      return;
    }

    next.add(folderPath);
    setExpandedFolders(next);

    if (!folderChildren[folderPath]) {
      setLoadingFolders(prev => new Set(prev).add(folderPath));
      try {
        const items = await bridge.listDirectory(folderPath);
        const sorted: ProjectEntry[] = items
          .map(i => ({ ...i, path: `${folderPath.replace(/\/$/, '')}/${i.name}` }))
          .sort((a, b) => Number(b.isDir) - Number(a.isDir) || a.name.localeCompare(b.name));
        setFolderChildren(prev => ({ ...prev, [folderPath]: sorted }));
        setStore(prev => ({ projectFiles: [...prev.projectFiles, ...sorted.filter(item => !prev.projectFiles.some(existing => existing.path === item.path))] }));

      } catch (e) {
        console.warn('Failed to load subfolder:', folderPath, e);
      } finally {
        setLoadingFolders(prev => {
          const upd = new Set(prev);
          upd.delete(folderPath);
          return upd;
        });
      }
    }
  };

  // Filtered files for Files mode
  const filteredFiles = store.directoryContent.filter(item => {
    if (!filterSearch.trim()) return true;
    return item.name.toLowerCase().includes(filterSearch.toLowerCase());
  });

  const breadcrumbs = storeActions.getBreadcrumbs();

  const handlePickProjectFolder = async () => {
    try {
      const picked = await bridge.openFileDialog({ directory: true, currentFolder: store.projectPath });
      if (picked) {
        setStore({ projectPath: picked });
        loadProjectDir(picked);
      }
    } catch (e) {
      console.warn('Dialog cancelled:', e);
    }
  };

  const isFileInContext = (path: string): boolean => {
    return store.contextFiles.some(f => f.path === path) || store.contextImages.some(i => i.path === path);
  };

  const handleToggleContext = (e: React.MouseEvent, path: string, name: string) => {
    e.stopPropagation();
    const ext = name.split('.').pop()?.toLowerCase() || '';
    const isImg = ['png', 'jpg', 'jpeg', 'webp', 'svg', 'gif'].includes(ext);

    if (isImg) {
      if (store.contextImages.some(i => i.path === path)) {
        storeActions.removeContextImage(path);
      } else {
        storeActions.addContextImage({ path, data: `file://${path}` });
      }
    } else {
      if (store.contextFiles.some(f => f.path === path)) {
        storeActions.removeContextFile(path);
      } else {
        storeActions.addContextFile({ path, name });
      }
    }
  };

  const renderProjectEntry = (entry: ProjectEntry, depth: number): React.ReactNode => {
    const isExpanded = expandedFolders.has(entry.path);
    const isLoading = loadingFolders.has(entry.path);
    const children = folderChildren[entry.path] || [];
    const inContext = isFileInContext(entry.path);

    if (projectSearch.trim() && !entry.isDir && !entry.name.toLowerCase().includes(projectSearch.toLowerCase())) {
      return null;
    }

    return (
      <React.Fragment key={entry.path}>
        <div
          className="sidebar-tree-item"
          style={{ paddingLeft: `${8 + depth * 12}px` }}
          onContextMenu={(event) => { event.preventDefault(); event.stopPropagation(); setContextMenu({ x: event.clientX, y: event.clientY, entry }); }}
          onClick={() => {
            if (entry.isDir) toggleProjectFolder(entry.path);
            else storeActions.openFileByPath(entry.path);
          }}
          title={entry.path}
        >
          {entry.isDir ? (
            isExpanded ? <ChevronDown size={11} className="tree-arrow" /> : <ChevronRight size={11} className="tree-arrow" />
          ) : (
            <span className="tree-arrow-spacer" />
          )}

          {entry.isDir ? (
            isExpanded ? <FolderOpen size={13} color="var(--accent-yellow)" /> : <Folder size={13} color="var(--accent-yellow)" />
          ) : (
            getFileIcon(entry.name, false)
          )}

          <span className="tree-item-label">{entry.name}</span>

          {isLoading && <RefreshCw size={10} className="spin" />}
          {!entry.isDir && <span className="tree-item-size">{formatSize(entry.size)}</span>}

          {!entry.isDir && (
            <button
              type="button"
              className={`item-context-btn ${inContext ? 'active' : ''}`}
              onClick={(e) => handleToggleContext(e, entry.path, entry.name)}
              title={inContext ? 'Remove from agent context' : 'Add to agent context'}
            >
              {inContext ? <Check size={10} /> : <Plus size={10} />}
            </button>
          )}
        </div>

        {entry.isDir && isExpanded && children.map(child => renderProjectEntry(child, depth + 1))}
      </React.Fragment>
    );
  };

  const projectFolderName = store.projectPath.split('/').filter(Boolean).pop() || 'Project';

  return (
    <div className="sidebar-inner-panel">
      {/* Right resize handle */}
      <div className="resize-handle resize-handle-right" onMouseDown={startResize} />

      {/* Mode switcher tabs (CandyCode style) */}
      <div className="sidebar-mode-header">
        <div className="sidebar-mode-switcher">
          <button
            type="button"
            className={`mode-btn ${store.sidebarMode === 'files' ? 'active' : ''}`}
            onClick={() => setStore({ sidebarMode: 'files' })}
          >
            <Home size={12} />
            <span>Files</span>
          </button>
          <button
            type="button"
            className={`mode-btn ${store.sidebarMode === 'project' ? 'active' : ''}`}
            onClick={() => setStore({ sidebarMode: 'project' })}
          >
            <Folder size={12} />
            <span>Project</span>
          </button>
        </div>

      </div>

      {store.sidebarMode === 'files' ? (
        /* Files Mode */
        <div className="sidebar-files-mode">
          {/* Navigation action bar */}
          <div className="sidebar-nav-actions">
            <button type="button" className="nav-btn" onClick={() => storeActions.goHome()} title="Home directory">
              <Home size={13} />
            </button>
            <button
              type="button"
              className="nav-btn"
              onClick={() => storeActions.navigateBack()}
              disabled={store.historyIndex <= 0}
              title="Navigate back"
            >
              <ChevronLeft size={13} />
            </button>
            <button
              type="button"
              className="nav-btn"
              onClick={() => storeActions.navigateForward()}
              disabled={store.historyIndex >= store.navigationHistory.length - 1}
              title="Navigate forward"
            >
              <ChevronRight size={13} />
            </button>
            <button type="button" className="nav-btn" onClick={() => storeActions.navigateUp()} title="Parent directory">
              <ChevronUp size={13} />
            </button>
            <button
              type="button"
              className={`nav-btn ${store.showDotfiles ? 'active' : ''}`}
              onClick={() => storeActions.toggleDotfiles()}
              title={store.showDotfiles ? 'Hide hidden files' : 'Show hidden files'}
            >
              {store.showDotfiles ? <Eye size={13} /> : <EyeOff size={13} />}
            </button>
            <button type="button" className="nav-btn" onClick={() => storeActions.refreshDirectory()} title="Refresh">
              <RefreshCw size={13} />
            </button>
          </div>

          {/* Breadcrumbs path */}
          <div className="sidebar-breadcrumbs">
            {breadcrumbs.map((crumb, idx) => (
              <span key={crumb.path} className="breadcrumb-segment-wrap">
                {idx > 0 && <span className="breadcrumb-separator">/</span>}
                <button
                  type="button"
                  className="breadcrumb-segment"
                  onClick={() => storeActions.navigateTo(crumb.path)}
                  title={crumb.path}
                >
                  {crumb.name}
                </button>
              </span>
            ))}
          </div>

          {/* Search filter input */}
          <div className="sidebar-search-bar">
            <Search size={12} className="sidebar-search-icon" />
            <input
              type="text"
              placeholder="Search files..."
              value={filterSearch}
              onChange={(e) => setFilterSearch(e.target.value)}
              className="sidebar-search-input"
            />
            {filterSearch && (
              <button type="button" className="clear-search-btn" onClick={() => setFilterSearch('')}>
                <X size={11} />
              </button>
            )}
          </div>

          {/* Files List */}
          <div className="sidebar-items-list">
            {filteredFiles.length === 0 ? (
              <div className="sidebar-empty-notice">No files found</div>
            ) : (
              filteredFiles.map(item => {
                const inContext = isFileInContext(item.path);
                return (
                  <div
                    key={item.path}
                    className="sidebar-file-row"
                    onClick={() => {
                      if (item.type === 'folder') {
                        storeActions.navigateTo(item.path);
                      } else {
                        storeActions.openFileByPath(item.path);
                      }
                    }}
                    title={item.path}
                  >
                    {getFileIcon(item.name, item.type === 'folder')}
                    <span className="file-row-name">{item.name}</span>
                    {item.type === 'file' && <span className="file-row-size">{formatSize(item.size)}</span>}

                    {item.type === 'file' && (
                      <button
                        type="button"
                        className={`item-context-btn ${inContext ? 'active' : ''}`}
                        onClick={(e) => handleToggleContext(e, item.path, item.name)}
                        title={inContext ? 'Remove from agent context' : 'Add to agent context'}
                      >
                        {inContext ? <Check size={10} /> : <Plus size={10} />}
                      </button>
                    )}
                  </div>
                );
              })
            )}
          </div>
        </div>
      ) : (
        /* Project Mode */
        <div className="sidebar-project-mode">
          {/* Project header */}
          <div className="project-root-bar">
            <div className="project-root-info" title={store.projectPath}>
              <Folder size={13} color="var(--accent-cyan)" />
              <span className="project-root-name">{projectFolderName}</span>
            </div>
            <div className="project-actions">
              <button type="button" className="nav-btn" onClick={() => loadProjectDir(store.projectPath)} title="Refresh">
                <RefreshCw size={12} className={loadingProject ? 'spin' : ''} />
              </button>
              <button type="button" className="nav-btn" onClick={handlePickProjectFolder} title="Open project folder...">
                <FolderSearch size={13} />
              </button>
            </div>
          </div>

          {/* Search filter in project */}
          <div className="sidebar-search-bar">
            <Search size={12} className="sidebar-search-icon" />
            <input
              type="text"
              placeholder="Search project..."
              value={projectSearch}
              onChange={(e) => setProjectSearch(e.target.value)}
              className="sidebar-search-input"
            />
            {projectSearch && (
              <button type="button" className="clear-search-btn" onClick={() => setProjectSearch('')}>
                <X size={11} />
              </button>
            )}
          </div>

          {/* Project tree */}
          <div className="sidebar-items-list">
            {projectFiles.length === 0 && !loadingProject ? (
              <div className="sidebar-empty-notice">No files in project</div>
            ) : (
              projectFiles.map(entry => renderProjectEntry(entry, 0))
            )}
          </div>
        </div>
      )}
      {contextMenu && createPortal(
        <div className="agent-context-menu" style={{ left: contextMenu.x, top: contextMenu.y }} onPointerDown={(event) => event.stopPropagation()}>
          <button onClick={() => void runFileAction('copy')}><Copy size={12} /> Copy to...</button>
          <button onClick={() => void runFileAction('move')}><Move size={12} /> Move to...</button>
          <button onClick={() => void runFileAction('copy-path')}><Clipboard size={12} /> Copy path</button>
          <button className="danger" onClick={() => void runFileAction('delete')}><Trash2 size={12} /> Delete</button>
        </div>,
        document.body,
      )}
    </div>
  );
};
