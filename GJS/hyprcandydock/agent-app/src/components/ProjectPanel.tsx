import React, { useEffect, useState } from 'react';
import {
  Folder, FolderOpen, File, FileCode, FileText, FileJson,
  RefreshCw, FolderSearch, ChevronRight, ChevronDown, X,
} from 'lucide-react';
import { useStore, setStore, storeActions } from '../store';
import { bridge } from '../bridge';

type Entry = { name: string; isDir: boolean; size: number; path: string };

function fileIcon(name: string) {
  const ext = name.split('.').pop()?.toLowerCase() || '';
  if (['ts', 'tsx', 'js', 'jsx', 'py', 'sh', 'bash', 'css', 'html', 'vue', 'svelte'].includes(ext)) return <FileCode size={13} color="var(--accent-cyan)" />;
  if (['json', 'yaml', 'yml', 'toml', 'ini'].includes(ext)) return <FileJson size={13} color="var(--accent-yellow)" />;
  if (['md', 'txt', 'rst'].includes(ext)) return <FileText size={13} color="var(--text-muted)" />;
  return <File size={13} color="var(--text-muted)" />;
}

function sortEntries(items: Array<Omit<Entry, 'path'>>, dirPath: string): Entry[] {
  return (items || []).map(item => ({ ...item, path: `${dirPath.replace(/\/$/, '')}/${item.name}` })).sort((a, b) => {
    if (a.isDir && !b.isDir) return -1;
    if (!a.isDir && b.isDir) return 1;
    return a.name.localeCompare(b.name);
  });
}

export const ProjectPanel: React.FC = () => {
  const [store] = useStore();
  const [loading, setLoading] = useState(false);
  const [loadingFolders, setLoadingFolders] = useState<Set<string>>(new Set());
  const [expandedFolders, setExpandedFolders] = useState<Set<string>>(new Set());
  const [childrenByPath, setChildrenByPath] = useState<Record<string, Entry[]>>({});

  const loadDirectory = async (dirPath: string, isRoot = false) => {
    if (isRoot) setLoading(true); else setLoadingFolders(prev => new Set(prev).add(dirPath));
    try {
      const items = sortEntries(await bridge.listDirectory(dirPath), dirPath);
      if (isRoot) {
        setStore({ projectFiles: items, projectPath: dirPath });
        setChildrenByPath({});
        setExpandedFolders(new Set());
      } else {
        setChildrenByPath(prev => ({ ...prev, [dirPath]: items }));
      }
    } catch (e) {
      console.warn('Failed to load directory:', dirPath, e);
    } finally {
      if (isRoot) setLoading(false); else setLoadingFolders(prev => { const next = new Set(prev); next.delete(dirPath); return next; });
    }
  };

  // Reload whenever projectPath changes — not just on mount — since it now
  // starts empty and is set asynchronously once GJS reports the real HOME
  // via 'runtime_config' (see bridge.ts).
  useEffect(() => { if (store.projectPath) loadDirectory(store.projectPath, true); }, [store.projectPath]);

  const handlePickDirectory = async () => {
    try {
      const chosen = await bridge.openFileDialog({ directory: true, currentFolder: store.projectPath });
      if (chosen) await loadDirectory(chosen, true);
    } catch (e) { console.warn('Dialog cancelled:', e); }
  };

  const handleFileClick = async (file: Entry) => {
    if (file.isDir) {
      const next = new Set(expandedFolders);
      if (next.has(file.path)) next.delete(file.path);
      else {
        next.add(file.path);
        if (!childrenByPath[file.path]) await loadDirectory(file.path);
      }
      setExpandedFolders(next);
    } else {
      try {
        const content = await bridge.readFile(file.path);
        setStore({ selectedFile: file.path, selectedFileContent: content });
        storeActions.openFile(file.path, content);
      } catch (e) { console.warn('Error reading file:', e); }
    }
  };

  const renderEntry = (file: Entry, depth: number): React.ReactNode => {
    const isSelected = store.selectedFile === file.path;
    const isExpanded = expandedFolders.has(file.path);
    const children = childrenByPath[file.path] || [];
    return <React.Fragment key={file.path}>
      <div className={`tree-item${isSelected ? ' selected' : ''}`} onClick={() => handleFileClick(file)} title={file.path} style={{ paddingLeft: `${8 + depth * 12}px` }}>
        {file.isDir ? (isExpanded ? <ChevronDown size={11} color="var(--text-muted)" /> : <ChevronRight size={11} color="var(--text-muted)" />) : <span style={{ width: '11px', flexShrink: 0 }} />}
        {file.isDir ? (isExpanded ? <FolderOpen size={13} color="var(--accent-yellow)" /> : <Folder size={13} color="var(--accent-yellow)" />) : fileIcon(file.name)}
        <span className="tree-item-name">{file.name}</span>
        {loadingFolders.has(file.path) && <RefreshCw size={10} className="spin" />}
        {!file.isDir && <span style={{ fontSize: '9.5px', color: 'var(--text-muted)', flexShrink: 0 }}>{file.size > 1024 * 1024 ? (file.size / 1024 / 1024).toFixed(1) + 'M' : file.size > 1024 ? (file.size / 1024).toFixed(0) + 'k' : file.size + 'B'}</span>}
      </div>
      {file.isDir && isExpanded && children.map(child => renderEntry(child, depth + 1))}
    </React.Fragment>;
  };

  const folderName = store.projectPath.split('/').filter(Boolean).pop() || store.projectPath;
  return <div className="agent-project-panel animate-slide-in" style={{ width: '220px', minWidth: '220px', height: '100%', background: 'var(--bg-sidebar)', borderRight: '1px solid var(--border-subtle)', display: 'flex', flexDirection: 'column', transition: 'width var(--transition-mid), min-width var(--transition-mid)', overflow: 'hidden', zIndex: 10, flexShrink: 0 }}>
    <div className="panel-header">
      <div style={{ display: 'flex', alignItems: 'center', gap: '6px', overflow: 'hidden', flex: 1 }}><div className="sidebar-mode-tabs"><button onClick={() => setStore({ sidebarMode: 'files' })}>Files</button><button className="active"><Folder size={12} /> {folderName}</button></div></div>
      <div style={{ display: 'flex', alignItems: 'center', gap: '2px' }}><button className="icon-btn" onClick={() => loadDirectory(store.projectPath, true)} title="Refresh" style={{ padding: '3px' }}><RefreshCw size={12} className={loading ? 'spin' : ''} /></button><button className="icon-btn" onClick={handlePickDirectory} title="Open Directory" style={{ padding: '3px' }}><FolderSearch size={13} /></button></div>
    </div>
    <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '4px 6px' }}>
      {(store.projectFiles || []).length === 0 && !loading && <div style={{ padding: '20px 10px', color: 'var(--text-muted)', fontSize: '11px', textAlign: 'center' }}>No files found</div>}
      {(store.projectFiles || []).map(file => renderEntry(file, 0))}
    </div>
    {store.selectedFile && <div style={{ padding: '6px 10px', borderTop: '1px solid var(--border-subtle)', display: 'flex', alignItems: 'center', gap: '6px', flexShrink: 0 }}><FileCode size={11} color="var(--accent-cyan)" /><span style={{ fontSize: '10.5px', color: 'var(--text-secondary)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', flex: 1, fontFamily: 'var(--font-mono)' }}>{store.selectedFile.split('/').pop()}</span><button className="icon-btn" style={{ padding: '2px' }} onClick={() => setStore({ selectedFile: null, selectedFileContent: null })} title="Deselect file"><X size={10} /></button></div>}
  </div>;
};
