import React from 'react';
import Editor from '@monaco-editor/react';
import { Image as ImageIcon, Video, X } from 'lucide-react';
import { useStore, setStore, storeActions } from '../store';
import { getMediaUrl } from '../utils/media';
import { registerMonacoThemes } from '../utils/monacoThemes';
import { languageForPath, registerCustomLanguages, attachDiagnostics } from '../utils/monacoLanguages';

export const EditorPane: React.FC = () => {
  const [store] = useStore();
  const path = store.activeOpenFile;
  if (!path) {
    return <div className="editor-empty"><ImageIcon size={22} /><span>Open a file from Files or Project</span></div>;
  }
  const ext = path.split('.').pop()?.toLowerCase() || '';
  const source = getMediaUrl(path);
  const isImage = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'].includes(ext);
  const isVideo = ['mp4', 'webm', 'mov', 'mkv'].includes(ext);
  return <div className="editor-pane">
    <div className="editor-tabs">
      {store.openFiles.map(file => <div className={`editor-tab${file === path ? ' active' : ''}`} key={file}>
        <button onClick={() => setStore({ activeOpenFile: file })} title={file}>{file.split('/').pop()}</button>
        <button className="editor-tab-close" onClick={() => storeActions.closeFile(file)} title="Close tab"><X size={11} /></button>
      </div>)}
    </div>
    <div className="editor-content">
      {isImage && <div className="media-preview"><ImageIcon size={14} /><img src={source} alt={path} /></div>}
      {isVideo && <div className="media-preview"><Video size={14} /><video src={source} controls /></div>}
      {!isImage && !isVideo && <Editor
        height="100%"
        theme={store.monacoTheme === 'matugen' || !store.monacoTheme ? 'matugen' : store.monacoTheme}
        beforeMount={(monaco) => { registerMonacoThemes(monaco); registerCustomLanguages(monaco); }}
        onMount={(editor, monaco) => {
          const targetTheme = store.monacoTheme === 'matugen' || !store.monacoTheme ? 'matugen' : store.monacoTheme;
          try { monaco.editor.setTheme(targetTheme); } catch (_) {}
          try { attachDiagnostics(monaco, editor); } catch (_) {}
        }}
        language={languageForPath(path)}
        value={store.openFileContents[path] || ''}
        options={{ minimap: { enabled: false }, fontSize: 12, wordWrap: 'on', automaticLayout: true, padding: { top: 12 }, accessibilitySupport: 'off', experimentalGpuAcceleration: 'off' }}
      />}
    </div>
  </div>;
};
