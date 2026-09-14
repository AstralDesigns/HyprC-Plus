import React, { useEffect, useState } from 'react';
import { File, FileCode, FileJson, FileText, Folder, FolderOpen, FolderTree, RefreshCw, X } from 'lucide-react';
import { useStore, setStore, storeActions } from '../store';
import { bridge } from '../bridge';

type Entry = { name: string; isDir: boolean; size: number; path: string };
const icon = (name: string) => {
  const ext = name.split('.').pop()?.toLowerCase();
  if (['ts', 'tsx', 'js', 'jsx', 'py', 'css', 'html'].includes(ext || '')) return <FileCode size={13} color="var(--accent-cyan)" />;
  if (['json', 'yaml', 'yml', 'toml'].includes(ext || '')) return <FileJson size={13} color="var(--accent-yellow)" />;
  if (['md', 'txt'].includes(ext || '')) return <FileText size={13} color="var(--text-muted)" />;
  return <File size={13} color="var(--text-muted)" />;
};

export const FilePanel: React.FC = () => {
  const [store] = useStore();
  const [entries, setEntries] = useState<Entry[]>([]);
  const [loading, setLoading] = useState(false);
  const load = async () => {
    setLoading(true);
    try {
      const items = await bridge.listDirectory(store.projectPath);
      setEntries(items.map(item => ({ ...item, path: `${store.projectPath.replace(/\/$/, '')}/${item.name}` }))
        .sort((a, b) => Number(b.isDir) - Number(a.isDir) || a.name.localeCompare(b.name)));
    } finally { setLoading(false); }
  };
  useEffect(() => { if (store.sidebarVisible && store.sidebarMode === 'files') void load(); }, [store.sidebarVisible, store.sidebarMode, store.projectPath]);
  return <aside className="file-panel">
    <div className="panel-header">
      <div className="sidebar-mode-tabs"><button className="active"><Folder size={12} /> Files</button><button onClick={() => setStore({ sidebarMode: 'project' })}><FolderTree size={12} /> Project</button></div>
      <button className="icon-btn" onClick={() => void load()} title="Refresh"><RefreshCw size={12} className={loading ? 'spin' : ''} /></button>
    </div>
    <div className="file-panel-root">{store.projectPath}</div>
    <div className="file-panel-list">
      {entries.map(entry => <button className="file-panel-item" key={entry.path} disabled={entry.isDir}
        onClick={async () => { if (!entry.isDir) storeActions.openFile(entry.path, await bridge.readFile(entry.path)); }}>
        {entry.isDir ? <FolderOpen size={13} color="var(--accent-yellow)" /> : icon(entry.name)}
        <span>{entry.name}</span>
      </button>)}
    </div>
  </aside>;
};
