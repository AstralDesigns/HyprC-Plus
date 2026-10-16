import React, { useState, useEffect, useRef, useMemo } from 'react';
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
import { fileStatusClass, fileStatusLetter, buildFolderStatus } from '../utils/gitStatus';
import { FileIcon } from '../utils/fileIcons';

function getFileIcon(name: string, isDir: boolean) {
  // Centralized VSCode-style per-format glyphs (see utils/fileIcons); colors
  // stay on the live theme palette so they re-tint with the wallpaper.
  return <FileIcon name={name} isDir={isDir} size={13} />;
}

function formatSize(bytes?: number): string {
  if (bytes === undefined || bytes === null || bytes === 0) return '';
  if (bytes < 1024) return bytes + 'B';
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(0) + 'K';
  return (bytes / (1024 * 1024)).toFixed(1) + 'M';
}

type ProjectEntry = { name: string; isDir: boolean; size: number; path: string; relPath?: string };

export const Sidebar: React.FC = () => {
  const [store] = useStore();
  // One representative status per folder (highest-ranked descendant), used for
  // the aggregate dot on the right of each directory row.
  const folderStatus = useMemo(
    () => buildFolderStatus(store.projectPath, store.gitStatus, store.errorFiles),
    [store.projectPath, store.gitStatus, store.errorFiles],
  );
  const [filterSearch, setFilterSearch] = useState('');
  const [projectSearch, setProjectSearch] = useState('');
  const [projectFiles, setProjectFiles] = useState<ProjectEntry[]>([]);
  const [expandedFolders, setExpandedFolders] = useState<Set<string>>(new Set());
  const [folderChildren, setFolderChildren] = useState<Record<string, ProjectEntry[]>>({});
  const [loadingFolders, setLoadingFolders] = useState<Set<string>>(new Set());
  const [loadingProject, setLoadingProject] = useState(false);
  const [contextMenu, setContextMenu] = useState<{ x: number; y: number; entry: ProjectEntry } | null>(null);
  // In-app themed delete confirmation (QtWebEngine can't reliably show window.confirm).
  const [pendingDelete, setPendingDelete] = useState<ProjectEntry | null>(null);
  // Nautilus-style recursive search matches, surfaced as a flat top section.
  const [fileResults, setFileResults] = useState<ProjectEntry[] | null>(null);
  const [projectResults, setProjectResults] = useState<ProjectEntry[] | null>(null);
  // Folder the project tree should scroll to + flash after a search "jump to".
  const [revealPath, setRevealPath] = useState<string | null>(null);
  const projectTreeRef = useRef<HTMLDivElement>(null);
  // Last-seen mtime per watched directory, for the explorer auto-refresh poll.
  const dirMtimeRef = useRef<Record<string, number>>({});
  // Breadcrumb row slides horizontally on vertical wheel (it overflows, not scrolls).
  const breadcrumbsRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const el = breadcrumbsRef.current;
    if (!el) return;
    const onWheel = (e: WheelEvent) => {
      if (el.scrollWidth <= el.clientWidth) return;
      const delta = e.deltaY || e.deltaX;
      if (!delta) return;
      e.preventDefault();
      el.scrollLeft += delta;
    };
    el.addEventListener('wheel', onWheel, { passive: false });
    return () => el.removeEventListener('wheel', onWheel);
  }, [store.sidebarMode, store.currentPath]);

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

  // List a folder into sorted tree entries (dirs first, case-insensitive name).
  const listFolder = async (folderPath: string): Promise<ProjectEntry[]> => {
    const items = await bridge.listDirectory(folderPath);
    return items
      .map(i => ({ name: i.name, isDir: i.isDir, size: i.size, path: `${folderPath.replace(/\/$/, '')}/${i.name}` }))
      .sort((a, b) => Number(b.isDir) - Number(a.isDir) || a.name.localeCompare(b.name));
  };

  // Push freshly-listed entries into the right bucket: project root goes to
  // projectFiles, any nested folder updates its cached children.
  const applyFolderEntries = (folderPath: string, entries: ProjectEntry[]) => {
    const root = store.projectPath.replace(/\/$/, '');
    if (store.sidebarMode === 'project' && folderPath.replace(/\/$/, '') === root) {
      setProjectFiles(entries);
      setStore({ projectFiles: entries });
    } else {
      setFolderChildren(prev => ({ ...prev, [folderPath]: entries }));
    }
  };

  // Load project root
  const loadProjectDir = async (dirPath: string) => {
    setLoadingProject(true);
    try {
      const sorted = await listFolder(dirPath);
      setProjectFiles(sorted);
      setStore({ projectFiles: sorted, projectPath: dirPath });
      storeActions.refreshGitStatus();
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
  const parentDirOf = (p: string) => p.slice(0, p.lastIndexOf('/')) || '/';
  const navFolder = () => (store.sidebarMode === 'project' ? store.projectPath : store.currentPath);

  // After a copy/move/delete, refresh just the affected folder(s) in place so
  // the tree doesn't reset expansion, and nudge git status in project mode.
  const refreshAfterMutation = async (srcPath: string, destDir?: string) => {
    if (store.sidebarMode === 'project') {
      const parent = parentDirOf(srcPath);
      try { applyFolderEntries(parent, await listFolder(parent)); } catch { /* folder vanished */ }
      if (destDir && destDir.replace(/\/$/, '') !== parent.replace(/\/$/, '')) {
        try { applyFolderEntries(destDir, await listFolder(destDir)); } catch { /* dest not tracked */ }
      }
      storeActions.refreshGitStatus();
    } else {
      await storeActions.refreshDirectory();
    }
  };

  const runFileAction = async (action: 'copy' | 'move' | 'delete' | 'copy-path') => {
    const entry = contextMenu?.entry;
    setContextMenu(null);
    if (!entry) return;
    if (action === 'copy-path') { void bridge.copyToClipboard(entry.path); return; }
    if (action === 'delete') { setPendingDelete(entry); return; }
    if (action === 'copy' || action === 'move') {
      const destination = await bridge.openFileDialog({ directory: true, currentFolder: navFolder() });
      if (!destination) return;
      await bridge.execCommand(`${action === 'copy' ? 'cp -R' : 'mv'} ${shellQuote(entry.path)} ${shellQuote(destination)}`, navFolder() || undefined);
      await refreshAfterMutation(entry.path, destination);
    }
  };

  const confirmDelete = async () => {
    const entry = pendingDelete;
    setPendingDelete(null);
    if (!entry) return;
    await bridge.execCommand(`rm -rf -- ${shellQuote(entry.path)}`, navFolder() || undefined);
    await refreshAfterMutation(entry.path);
  };

  // Nautilus-style recursive search: debounce a query, fetch flat matches, and
  // render them as a top section (so a deep file shows even if its collapsed
  // ancestors aren't in the loaded tree).
  useEffect(() => {
    if (store.sidebarMode !== 'files') { setFileResults(null); return; }
    const q = filterSearch.trim();
    if (!q || !store.currentPath) { setFileResults(null); return; }
    let cancelled = false;
    setFileResults(null); // show "Searching…" while in flight
    const t = setTimeout(async () => {
      let rows: ProjectEntry[] = [];
      try {
        const r = await bridge.searchFiles(store.currentPath, q);
        if (Array.isArray(r)) rows = r.map(x => ({ name: x.name, isDir: x.isDir, size: x.size, path: x.path, relPath: x.relPath }));
      } catch { /* host offline / stale server: fall through to empty */ }
      if (!cancelled) setFileResults(rows); // always an array — never leaves it stuck
    }, 220);
    return () => { cancelled = true; clearTimeout(t); };
  }, [filterSearch, store.sidebarMode, store.currentPath]);

  useEffect(() => {
    if (store.sidebarMode !== 'project') { setProjectResults(null); return; }
    const q = projectSearch.trim();
    if (!q || !store.projectPath) { setProjectResults(null); return; }
    let cancelled = false;
    setProjectResults(null); // show "Searching…" while in flight
    const t = setTimeout(async () => {
      let rows: ProjectEntry[] = [];
      try {
        const r = await bridge.searchFiles(store.projectPath, q);
        if (Array.isArray(r)) rows = r.map(x => ({ name: x.name, isDir: x.isDir, size: x.size, path: x.path, relPath: x.relPath }));
      } catch { /* host offline / stale server: fall through to empty */ }
      if (!cancelled) setProjectResults(rows); // always an array — never leaves it stuck
    }, 220);
    return () => { cancelled = true; clearTimeout(t); };
  }, [projectSearch, store.sidebarMode, store.projectPath]);

  const handleSearchEntryClick = (entry: ProjectEntry) => {
    if (entry.isDir) {
      // Navigate/reveal the folder and drop the query so the listing is useful.
      if (store.sidebarMode === 'files') { setFilterSearch(''); storeActions.navigateTo(entry.path); }
      else {
        setProjectSearch('');
        const root = store.projectPath.replace(/\/$/, '');
        const segSrc = entry.relPath && entry.relPath !== '.'
          ? entry.relPath
          : entry.path.replace(/\/$/, '').slice(root.length);
        const segs = segSrc.replace(/\/$/, '').split('/').filter(Boolean);
        const paths: string[] = [];
        let a = root;
        for (const s of segs) { a = `${a}/${s}`; paths.push(a); }
        // Expand synchronously inside the click batch — this mirrors the manual
        // folder toggle (which works); setting expansion from a later async
        // continuation was silently not reaching the render. Then load each
        // folder's children async and queue the scroll.
        setExpandedFolders(prev => { const next = new Set(prev); paths.forEach(p => next.add(p)); return next; });
        void (async () => {
          for (const p of paths) {
            if (!folderChildren[p]) {
              try {
                const kids = await listFolder(p);
                setFolderChildren(prev => (prev[p] ? prev : { ...prev, [p]: kids }));
              } catch { /* noop */ }
            }
          }
          setRevealPath(paths[paths.length - 1] || root);
        })();
      }
      return;
    }
    storeActions.openFileByPath(entry.path);
  };

  // After a search jump the ancestors are expanded (above); scroll the hit into
  // view and flash it. The node only exists once the revealed branch has
  // re-rendered AND the taller tree has laid out, so poll across ~1.2s. Match
  // by walking [data-tree-path] nodes (avoids CSS.escape/attribute quirks) and
  // scroll the list container directly instead of scrollIntoView, which can
  // scroll an outer ancestor and land wrong for a deep node.
  useEffect(() => {
    if (!revealPath) return;
    let cancelled = false;
    let tries = 0;
    let timer: ReturnType<typeof setTimeout> | null = null;
    const attempt = () => {
      if (cancelled) return;
      const container = projectTreeRef.current;
      const all = container ? Array.from(container.querySelectorAll<HTMLElement>('[data-tree-path]')) : [];
      const node = all.find(el => el.getAttribute('data-tree-path') === revealPath);
      if (node && container) {
        const cRect = container.getBoundingClientRect();
        const nRect = node.getBoundingClientRect();
        container.scrollTop += (nRect.top - cRect.top) - (container.clientHeight / 2 - nRect.height / 2);
        node.classList.add('tree-item-revealed');
        setTimeout(() => node.classList.remove('tree-item-revealed'), 1200);
        setRevealPath(null);
        return;
      }
      if (tries++ < 40) { timer = setTimeout(attempt, 30); return; }
      setRevealPath(null);
    };
    timer = setTimeout(attempt, 30);
    return () => { cancelled = true; if (timer) clearTimeout(timer); };
  }, [revealPath]);

  // The exact, bounded set of directories the UI can currently see: the active
  // listing, any expanded project folders, and the parent of every open file.
  // Handed to the host inotify watcher (non-recursive) so it monitors just
  // these — small enough that no tree size can exhaust inotify watches.
  const visibleWatchDirs = (): string[] => {
    const dirs = new Set<string>();
    if (store.sidebarMode === 'project') { if (store.projectPath) dirs.add(store.projectPath); expandedFolders.forEach(d => dirs.add(d)); }
    else if (store.currentPath) dirs.add(store.currentPath);
    store.panes.forEach(p => { if (p.path) dirs.add(p.path.slice(0, p.path.lastIndexOf('/')) || '/'); });
    return Array.from(dirs);
  };

  // (Re)point the host watcher whenever the visible set changes.
  const panePathsKey = store.panes.map(p => p.path || '').join('|');
  useEffect(() => {
    void bridge.watchPaths(visibleWatchDirs());
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [store.sidebarMode, store.currentPath, store.projectPath, expandedFolders, panePathsKey]);

  // Explorer auto-refresh (mtime fallback): reload any visible folder whose
  // mtime moved since we last listed it. Runs regardless of focus; the inotify
  // fast path (below) usually beats it, but this covers a missing inotifywait.
  useEffect(() => {
    const pollDirs = async () => {
      const dirs = store.sidebarMode === 'project'
        ? Array.from(new Set([store.projectPath, ...expandedFolders].filter(Boolean)))
        : [store.currentPath].filter(Boolean) as string[];
      if (!dirs.length) return;
      let res: Record<string, number>;
      try { res = await bridge.statFiles([], dirs); } catch { return; }
      for (const d of dirs) {
        const m = res[d];
        if (!m) { delete dirMtimeRef.current[d]; continue; }
        const prev = dirMtimeRef.current[d];
        if (prev === undefined) { dirMtimeRef.current[d] = m; continue; }
        if (m === prev) continue;
        dirMtimeRef.current[d] = m;
        if (store.sidebarMode === 'files') { await storeActions.refreshDirectory(); }
        else { try { applyFolderEntries(d, await listFolder(d)); } catch { /* noop */ } }
      }
    };
    pollDirs();
    const id = setInterval(pollDirs, 5000);
    window.addEventListener('focus', pollDirs);
    return () => { clearInterval(id); window.removeEventListener('focus', pollDirs); };
  }, [store.sidebarMode, store.currentPath, store.projectPath, expandedFolders]);

  // Apply inotify-reported changes (drained in App.handleFsEvents): refresh just
  // the dirty folders in place, preserving tree expansion.
  useEffect(() => {
    if (!store.fsRev) return;
    const dirty = store.fsDirtyDirs || {};
    const reload = async (d: string) => { try { applyFolderEntries(d, await listFolder(d)); } catch { /* noop */ } };
    if (store.sidebarMode === 'files') {
      if (dirty[store.currentPath]) void storeActions.refreshDirectory();
    } else {
      if (dirty[store.projectPath]) void reload(store.projectPath);
      expandedFolders.forEach(d => { if (dirty[d]) void reload(d); });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [store.fsRev]);

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
        const sorted = await listFolder(folderPath);
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
          data-tree-path={entry.path}
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

          {!entry.isDir && fileStatusClass(entry.path, store.gitStatus, store.errorFiles) && (
            <span
              className={`tree-status-badge ${fileStatusClass(entry.path, store.gitStatus, store.errorFiles)}`}
              title={fileStatusLetter(entry.path, store.gitStatus, store.errorFiles) === '!' ? 'Syntax error' : `Git: ${store.gitStatus[entry.path]}`}
            >
              {fileStatusLetter(entry.path, store.gitStatus, store.errorFiles)}
            </span>
          )}

          {entry.isDir && folderStatus[entry.path] && (
            <span
              className={`tree-status-folder status-${folderStatus[entry.path].kind}`}
              title={`${folderStatus[entry.path].count} changed within (${folderStatus[entry.path].kind})`}
            >
              {folderStatus[entry.path].count > 1 && (
                <span className="tree-status-count">{folderStatus[entry.path].count}</span>
              )}
              <span className="tree-status-dot" />
            </span>
          )}

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
          </div>

          {/* Breadcrumbs path */}
          <div className="sidebar-breadcrumbs" ref={breadcrumbsRef}>
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
            {filterSearch.trim() ? (
              fileResults === null ? (
                <div className="sidebar-empty-notice">Searching…</div>
              ) : fileResults.length === 0 ? (
                <div className="sidebar-empty-notice">No matches in this folder</div>
              ) : (
                <>
                  <div className="sidebar-search-section-label">Matches (recursive)</div>
                  {fileResults.map(entry => (
                    <div
                      key={entry.path}
                      className="sidebar-file-row sidebar-search-row"
                      onClick={() => handleSearchEntryClick(entry)}
                      onContextMenu={(event) => { event.preventDefault(); event.stopPropagation(); setContextMenu({ x: event.clientX, y: event.clientY, entry }); }}
                      title={entry.path}
                    >
                      {getFileIcon(entry.name, entry.isDir)}
                      <span className="file-row-name">{entry.name}</span>
                      <span className="file-row-relpath">{entry.relPath}</span>
                    </div>
                  ))}
                </>
              )
            ) : filteredFiles.length === 0 ? (
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
                    onContextMenu={(event) => { event.preventDefault(); event.stopPropagation(); setContextMenu({ x: event.clientX, y: event.clientY, entry: { name: item.name, isDir: item.type === 'folder', size: item.size || 0, path: item.path } }); }}
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
          <div className="sidebar-items-list" ref={projectTreeRef}>
            {projectSearch.trim() ? (
              projectResults === null ? (
                <div className="sidebar-empty-notice">Searching…</div>
              ) : projectResults.length === 0 ? (
                <div className="sidebar-empty-notice">No matches in project</div>
              ) : (
                <>
                  <div className="sidebar-search-section-label">Matches (recursive)</div>
                  {projectResults.map(entry => (
                    <div
                      key={entry.path}
                      className="sidebar-file-row sidebar-search-row"
                      onClick={() => handleSearchEntryClick(entry)}
                      onContextMenu={(event) => { event.preventDefault(); event.stopPropagation(); setContextMenu({ x: event.clientX, y: event.clientY, entry }); }}
                      title={entry.path}
                    >
                      {getFileIcon(entry.name, entry.isDir)}
                      <span className="file-row-name">{entry.name}</span>
                      <span className="file-row-relpath">{entry.relPath}</span>
                    </div>
                  ))}
                </>
              )
            ) : projectFiles.length === 0 && !loadingProject ? (
              <div className="sidebar-empty-notice">No files in project</div>
            ) : (
              projectFiles.map(entry => renderProjectEntry(entry, 0))
            )}
          </div>
        </div>
      )}
      {contextMenu && createPortal(
        <div className="agent-context-menu tab-context-menu" style={{ left: contextMenu.x, top: contextMenu.y }} onPointerDown={(event) => event.stopPropagation()} onContextMenu={(event) => event.preventDefault()}>
          <button onClick={() => void runFileAction('copy')}><Copy size={12} /> Copy to...</button>
          <button onClick={() => void runFileAction('move')}><Move size={12} /> Move to...</button>
          <button onClick={() => void runFileAction('copy-path')}><Clipboard size={12} /> Copy path</button>
          <div className="menu-separator" />
          <button className="danger" onClick={() => void runFileAction('delete')}><Trash2 size={12} /> Delete</button>
        </div>,
        document.body,
      )}
      {pendingDelete && createPortal(
        <div className="agent-dialog-overlay" onPointerDown={() => setPendingDelete(null)}>
          <div className="agent-dialog" onPointerDown={(event) => event.stopPropagation()}>
            <div className="agent-dialog-title">Delete {pendingDelete.isDir ? 'folder' : 'file'}?</div>
            <div className="agent-dialog-body">
              <span className="agent-dialog-name">{pendingDelete.name}</span>
              {!pendingDelete.isDir && <span className="agent-dialog-hint">This removes it from disk. This can't be undone.</span>}
              {pendingDelete.isDir && <span className="agent-dialog-hint">This recursively removes the folder and everything in it.</span>}
            </div>
            <div className="agent-dialog-actions">
              <button type="button" className="agent-dialog-btn" onClick={() => setPendingDelete(null)}>Cancel</button>
              <button type="button" className="agent-dialog-btn danger" onClick={() => void confirmDelete()}>Delete</button>
            </div>
          </div>
        </div>,
        document.body,
      )}
    </div>
  );
};
