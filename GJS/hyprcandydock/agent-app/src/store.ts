/**
 * Agent App Global State & Store
 */
import { useState, useEffect } from 'react';
import type { CustomWebLLMModel } from './engine/webllm-helpers';
import { bridge } from './bridge';

export interface DiffData {
  filePath: string;
  originalCode: string;
  modifiedCode: string;
  status: 'pending' | 'accepted' | 'rejected';
}

export interface CommandData {
  command: string;
  cwd?: string;
  status: 'pending' | 'approved' | 'running' | 'completed' | 'rejected';
  exitCode?: number;
  stdout?: string;
  stderr?: string;
}

export interface ToolCallData {
  id: string;
  name: string;
  arguments: any;
  result?: any;
  status: 'running' | 'completed' | 'error';
}

export interface PlanTask {
  id: string;
  title: string;
  status: 'pending' | 'in_progress' | 'completed' | 'blocked';
  detail?: string;
}

export interface PlanData {
  tasks: PlanTask[];
  updatedAt: number;
}

export interface Message {
  id: string;
  role: 'user' | 'assistant' | 'system' | 'tool';
  content: string;
  timestamp: number;
  tools?: ToolCallData[];
  plan?: PlanData;
  diff?: DiffData;
  command?: CommandData;
  attachments?: AttachmentData[];
}

export interface AttachmentData {
  path: string;
  name: string;
  kind: 'text' | 'image' | 'video' | 'file';
}

export interface Session {
  id: string;
  title: string;
  createdAt: number;
  updatedAt: number;
  messages: Message[];
}

export interface ModelInfo {
  id: string;
  name: string;
  size: string;
  vram: string;
  description: string;
  isDefault?: boolean;
  model?: string;
  model_lib?: string;
  required_features?: string[];
  llamaRepo?: string;
  llamaFile?: string;
  toolSupport?: boolean;
  wllamaRepo?: string;
  wllamaFile?: string;
}

export type FilePaneType = 'code' | 'markdown' | 'image' | 'video' | 'audio' | 'image-gallery' | 'video-gallery';

export interface FilePane {
  id: string;
  name: string;
  path?: string;
  type: FilePaneType;
  content: string;
  isUnsaved?: boolean;
  language?: string;
  data?: any;
}

export interface FileSystemItem {
  name: string;
  path: string;
  type: 'file' | 'folder';
  size?: number;
}

export interface Breadcrumb {
  name: string;
  path: string;
}

export const PRESET_MODELS: ModelInfo[] = [
  {
    id: 'Qwen2.5-Coder-1.5B-Instruct',
    name: 'Qwen2.5 Coder 1.5B Instruct',
    size: '~940 MB',
    vram: '~1.2 GB',
    description: 'Compact coding model with tool-use-friendly chat formatting for llama-server.',
    llamaRepo: 'bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF',
    llamaFile: 'Qwen2.5-Coder-1.5B-Instruct-Q4_K_M.gguf',
    toolSupport: true,
    isDefault: true,
  },
  {
    id: 'Qwen2.5-Coder-0.5B-Instruct',
    name: 'Qwen2.5 Coder 0.5B Instruct',
    size: '~379 MB',
    vram: '~600 MB',
    description: 'Fast lightweight coding model with tool-use-friendly chat formatting for llama-server.',
    llamaRepo: 'bartowski/Qwen2.5-Coder-0.5B-Instruct-GGUF',
    llamaFile: 'Qwen2.5-Coder-0.5B-Instruct-Q4_K_M.gguf',
    toolSupport: true,
  },
];


export interface AppState {
  sessions: Session[];
  activeSessionId: string;
  activeModel: string;
  modelStatus: 'idle' | 'downloading' | 'loading' | 'ready' | 'error';
  downloadProgress: { progress: number; text: string };
  projectPath: string;
  projectFiles: Array<{ name: string; isDir: boolean; size: number; path: string }>;
  selectedFile: string | null;
  selectedFileContent: string | null;
  agentRunning: boolean;
  workspaceStartupEnabled: boolean;
  
  // Floating panel layout
  sidebarVisible: boolean;
  sidebarWidth: number;
  chatVisible: boolean;
  chatWidth: number;
  modelManagerOpen: boolean;

  // Mode in sidebar
  sidebarMode: 'files' | 'project';
  contextMode: 'minimal' | 'smart' | 'full';

  // Filesystem navigation state
  currentPath: string;
  directoryContent: FileSystemItem[];
  navigationHistory: string[];
  historyIndex: number;
  showDotfiles: boolean;

  // Canvas Panes
  panes: FilePane[];
  activePaneId: string | null;

  // Legacy mappings for backwards compatibility
  openFiles: string[];
  activeOpenFile: string | null;
  openFileContents: Record<string, string>;
  customModels: ModelInfo[];

  // Context files and images for chat
  contextFiles: Array<{ path: string; name: string }>;
  contextImages: Array<{ path: string; data: string }>;

  // Monaco editor theme
  monacoTheme: string;
}

const STORAGE_KEY = 'hyprcandy_agent_state_v2';

function getHomeDir(): string {
  if (typeof window !== 'undefined' && (window as any).__USER_HOME__) {
    return (window as any).__USER_HOME__;
  }
  return '/home/king';
}

function createDefaultSession(): Session {
  const now = Date.now();
  return {
    id: 'session_' + now,
    title: 'New Conversation',
    createdAt: now,
    updatedAt: now,
    messages: []
  };
}

function getLanguageForExt(ext: string): string {
  const map: Record<string, string> = {
    ts: 'typescript',
    tsx: 'typescript',
    js: 'javascript',
    jsx: 'javascript',
    json: 'json',
    css: 'css',
    scss: 'scss',
    html: 'html',
    md: 'markdown',
    py: 'python',
    sh: 'shell',
    bash: 'shell',
    zsh: 'shell',
    c: 'c',
    cpp: 'cpp',
    h: 'c',
    hpp: 'cpp',
    rs: 'rust',
    go: 'go',
    yaml: 'yaml',
    yml: 'yaml',
    toml: 'toml',
    ini: 'ini',
    conf: 'shell',
    sql: 'sql',
    txt: 'plaintext',
  };
  return map[ext.toLowerCase()] || 'plaintext';
}

function loadInitialState(): AppState {
  const defSession = createDefaultSession();
  const home = getHomeDir();
  const defaultState: AppState = {
    sessions: [defSession],
    activeSessionId: defSession.id,
    activeModel: PRESET_MODELS[0].id,
    modelStatus: 'idle',
    downloadProgress: { progress: 0, text: '' },
    // Placeholder until the GJS host reports the real HOME via the
    // 'runtime_config' message (see bridge.ts) — never a hardcoded path,
    // since that used to be the original developer's own home directory.
    projectPath: '',
    projectFiles: [],
    selectedFile: null,
    selectedFileContent: null,
    agentRunning: false,
    workspaceStartupEnabled: true,
    
    // Floating panels default: both visible, matching CandyCode
    sidebarVisible: true,
    sidebarWidth: 260,
    chatVisible: true,
    chatWidth: 380,
    modelManagerOpen: false,
    sidebarMode: 'files',
    contextMode: 'minimal',

    currentPath: home,
    directoryContent: [],
    navigationHistory: [home],
    historyIndex: 0,
    showDotfiles: false,

    panes: [],
    activePaneId: null,

    openFiles: [],
    activeOpenFile: null,
    openFileContents: {},
    customModels: [],

    contextFiles: [],
    contextImages: [],

    monacoTheme: 'matugen',
  };

  try {
    const saved = localStorage.getItem(STORAGE_KEY) || localStorage.getItem('hyprcandy_agent_state_v1');
    if (saved) {
      const parsed = JSON.parse(saved);
      if (parsed.sessions && parsed.sessions.length > 0) {
        return {
          ...defaultState,
          ...parsed,
          sessions: Array.isArray(parsed.sessions)
            ? parsed.sessions.map((s: Session) => ({
                ...s,
                messages: Array.isArray(s.messages)
                  ? s.messages.filter((m: any) => m.id !== 'msg_welcome')
                  : []
              }))
            : [defSession],
          monacoTheme: 'matugen',
          projectFiles: Array.isArray(parsed.projectFiles) ? parsed.projectFiles : [],
          activeModel: (() => {
            const customIds = Array.isArray(parsed.customModels)
              ? parsed.customModels.map((model: ModelInfo) => model.id)
              : [];
            const knownIds = new Set([...PRESET_MODELS.map(model => model.id), ...customIds]);
            return knownIds.has(parsed.activeModel) ? parsed.activeModel : PRESET_MODELS[0].id;
          })(),
          modelStatus: 'idle',
          downloadProgress: { progress: 0, text: '' },
          agentRunning: false,
          selectedFile: null,
          selectedFileContent: null,
          workspaceStartupEnabled: typeof parsed.workspaceStartupEnabled === 'boolean' ? parsed.workspaceStartupEnabled : true,
          panes: Array.isArray(parsed.panes) ? parsed.panes : [],
          activePaneId: parsed.activePaneId || null,
          sidebarVisible: typeof parsed.sidebarVisible === 'boolean' ? parsed.sidebarVisible : true,
          chatVisible: typeof parsed.chatVisible === 'boolean' ? parsed.chatVisible : true,
          contextMode: 'minimal',
          sidebarWidth: typeof parsed.sidebarWidth === 'number' ? parsed.sidebarWidth : 260,
          chatWidth: typeof parsed.chatWidth === 'number' ? parsed.chatWidth : 380,
          customModels: Array.isArray(parsed.customModels)
            ? parsed.customModels.filter((model: ModelInfo) => model?.id)
            : [],
        };
      }
    }
  } catch (e) {
    console.warn('Failed to parse localStorage state:', e);
  }

  return defaultState;
}

let currentState: AppState = loadInitialState();
const listeners = new Set<(state: AppState) => void>();

let storeDirty = false;
let storePersistScheduled = false;
let storePersistTimer: ReturnType<typeof setTimeout> | null = null;
const STORE_PERSIST_DEBOUNCE_MS = 250;

function persistStore() {
  storePersistScheduled = false;
  if (!storeDirty) return;
  storeDirty = false;
  try {
    const next = currentState;
    localStorage.setItem(STORAGE_KEY, JSON.stringify({
      sessions: next.sessions,
      activeSessionId: next.activeSessionId,
      activeModel: next.activeModel,
      projectPath: next.projectPath,
      projectFiles: next.projectFiles,
      sidebarVisible: next.sidebarVisible,
      sidebarWidth: next.sidebarWidth,
      chatVisible: next.chatVisible,
      chatWidth: next.chatWidth,
      sidebarMode: next.sidebarMode,
      contextMode: next.contextMode,
      customModels: next.customModels,
      contextFiles: next.contextFiles,
      contextImages: next.contextImages,
      currentPath: next.currentPath,
      panes: next.panes.map(p => ({ ...p, isUnsaved: false })),
      activePaneId: next.activePaneId,
      workspaceStartupEnabled: next.workspaceStartupEnabled,
    }));
  } catch (e) {
    console.warn('Failed to save to localStorage:', e);
  }
}

function schedulePersist() {
  storeDirty = true;
  if (storePersistScheduled) return;
  storePersistScheduled = true;
  storePersistTimer = setTimeout(() => {
    storePersistTimer = null;
    persistStore();
  }, STORE_PERSIST_DEBOUNCE_MS);
}

export function persistStoreNow() {
  if (storePersistTimer !== null) {
    clearTimeout(storePersistTimer);
    storePersistTimer = null;
  }
  persistStore();
}

export function getStore(): AppState {
  return currentState;
}

export function setStore(updater: Partial<AppState> | ((prev: AppState) => Partial<AppState>)) {
  const partial = typeof updater === 'function' ? updater(currentState) : updater;
  const next: AppState = { ...currentState, ...partial };
  currentState = next;

  schedulePersist();

  try {
    listeners.forEach(fn => fn(currentState));
  } catch (listenerErr) {
    console.error('Listener threw in setStore:', listenerErr);
  }
}

export function useStore(): [AppState, typeof setStore] {
  const [state, setState] = useState<AppState>(currentState);

  useEffect(() => {
    listeners.add(setState);
    return () => {
      listeners.delete(setState);
    };
  }, []);

  return [state, setStore];
}

let untitledCount = 1;

/* Store Actions */
export const storeActions = {
  // Floating panel toggles
  toggleSidebar: () => setStore(prev => ({ sidebarVisible: !prev.sidebarVisible })),
  toggleChat: () => setStore(prev => ({ chatVisible: !prev.chatVisible })),
  setSidebarWidth: (width: number) => setStore({ sidebarWidth: width }),
  setChatWidth: (width: number) => setStore({ chatWidth: width }),
  setMonacoTheme: (theme: string) => {
    try { localStorage.setItem('hyprcandy_monaco_theme', theme); } catch (_) {}
    setStore({ monacoTheme: theme });
  },

  // Chat sessions
  createSession: () => {
    const newSession = createDefaultSession();
    setStore(prev => ({
      sessions: [newSession, ...prev.sessions],
      activeSessionId: newSession.id,
    }));
    return newSession.id;
  },

  deleteSession: (id: string) => {
    setStore(prev => {
      const filtered = prev.sessions.filter(s => s.id !== id);
      if (filtered.length === 0) {
        const fresh = createDefaultSession();
        return { sessions: [fresh], activeSessionId: fresh.id };
      }
      return {
        sessions: filtered,
        activeSessionId: prev.activeSessionId === id ? filtered[0].id : prev.activeSessionId,
      };
    });
  },

  switchSession: (id: string) => {
    setStore({ activeSessionId: id });
  },

  clearCurrentMessages: () => {
    setStore(prev => {
      const updated = prev.sessions.map(s => {
        if (s.id !== prev.activeSessionId) return s;
        return { ...s, messages: [] };
      });
      return { sessions: updated };
    });
  },

  addMessage: (sessionId: string, msg: Message) => {
    setStore(prev => {
      const updated = prev.sessions.map(s => {
        if (s.id !== sessionId) return s;
        return {
          ...s,
          updatedAt: Date.now(),
          messages: [...s.messages, msg],
        };
      });
      return { sessions: updated };
    });
  },

  updateMessage: (sessionId: string, messageId: string, updater: Partial<Message>) => {
    setStore(prev => {
      const updated = prev.sessions.map(s => {
        if (s.id !== sessionId) return s;
        return {
          ...s,
          messages: s.messages.map(m => m.id === messageId ? { ...m, ...updater } : m),
        };
      });
      return { sessions: updated };
    });
  },

  /**
   * Edit a user message content and truncate all subsequent messages (the
   * agent responses that follow it), so that re-sending starts fresh from
   * that edit point.
   */
  editMessage: (sessionId: string, messageId: string, newContent: string) => {
    setStore(prev => {
      const updated = prev.sessions.map(s => {
        if (s.id !== sessionId) return s;
        const idx = s.messages.findIndex(m => m.id === messageId);
        if (idx === -1) return s;
        const truncated = s.messages.slice(0, idx + 1).map(m =>
          m.id === messageId ? { ...m, content: newContent } : m
        );
        return { ...s, messages: truncated, updatedAt: Date.now() };
      });
      return { sessions: updated };
    });
  },

  updateDiffStatus: (sessionId: string, messageId: string, status: 'accepted' | 'rejected') => {
    setStore(prev => {
      const updated = prev.sessions.map(s => {
        if (s.id !== sessionId) return s;
        return {
          ...s,
          messages: s.messages.map(m => {
            if (m.id === messageId && m.diff) {
              return { ...m, diff: { ...m.diff, status } };
            }
            return m;
          }),
        };
      });
      return { sessions: updated };
    });
  },

  updateCommandStatus: (sessionId: string, messageId: string, updater: Partial<CommandData>) => {
    setStore(prev => {
      const updated = prev.sessions.map(s => {
        if (s.id !== sessionId) return s;
        return {
          ...s,
          messages: s.messages.map(m => {
            if (m.id === messageId && m.command) {
              return { ...m, command: { ...m.command, ...updater } };
            }
            return m;
          }),
        };
      });
      return { sessions: updated };
    });
  },

  // Canvas / Pane Management (Matching CandyCode)
  openPane: (pane: FilePane) => {
    setStore(prev => {
      const exists = prev.panes.find(p => p.id === pane.id);
      if (exists) {
        return { activePaneId: pane.id };
      }
      return {
        panes: [...prev.panes, pane],
        activePaneId: pane.id,
      };
    });
  },

  closePane: (id: string) => {
    setStore(prev => {
      const index = prev.panes.findIndex(p => p.id === id);
      if (index === -1) return {};
      const newPanes = prev.panes.filter(p => p.id !== id);
      let newActiveId = prev.activePaneId;
      if (prev.activePaneId === id) {
        if (newPanes.length > 0) {
          const nextIndex = Math.min(index, newPanes.length - 1);
          newActiveId = newPanes[nextIndex].id;
        } else {
          newActiveId = null;
        }
      }
      return {
        panes: newPanes,
        activePaneId: newActiveId,
        openFiles: prev.openFiles.filter(f => f !== id),
        activeOpenFile: newActiveId,
      };
    });
  },

  setActivePane: (id: string | null) => {
    setStore({ activePaneId: id, activeOpenFile: id });
  },

  updatePaneContent: (id: string, content: string) => {
    setStore(prev => ({
      panes: prev.panes.map(p => p.id === id ? { ...p, content, isUnsaved: true } : p),
      openFileContents: { ...prev.openFileContents, [id]: content },
    }));
  },

  saveFile: async (paneId: string) => {
    const pane = currentState.panes.find(p => p.id === paneId);
    if (!pane || !pane.path) return;
    try {
      const res = await bridge.writeFile(pane.path, pane.content);
      if (res && res.success !== false) {
        setStore(prev => ({
          panes: prev.panes.map(p => p.id === paneId ? { ...p, isUnsaved: false } : p),
        }));
      }
    } catch (e) {
      console.error('Failed to save file:', e);
    }
  },

  createNewFile: () => {
    const id = `untitled-${untitledCount++}.ts`;
    const newPane: FilePane = {
      id,
      name: id,
      type: 'code',
      content: '',
      language: 'typescript',
      isUnsaved: true,
    };
    setStore(prev => ({
      panes: [...prev.panes, newPane],
      activePaneId: id,
    }));
  },

  openFileByPath: async (filePath: string) => {
    const name = filePath.split('/').pop() || filePath;
    const ext = name.split('.').pop()?.toLowerCase() || '';

    const imageExtensions = ['png', 'jpg', 'jpeg', 'webp', 'svg', 'gif'];
    const videoExtensions = ['mp4', 'webm', 'mov', 'mkv'];
    const audioExtensions = ['mp3', 'wav', 'ogg', 'flac'];

    let type: FilePaneType = 'code';
    let language = 'plaintext';
    let content = '';
    let data: any = null;

    if (ext === 'md') {
      type = 'markdown';
      language = 'markdown';
      try { content = await bridge.readFile(filePath); } catch (e) { console.warn(e); }
    } else if (imageExtensions.includes(ext)) {
      type = 'image-gallery';
      const dirPath = filePath.substring(0, filePath.lastIndexOf('/')) || '/';
      try {
        const items = await bridge.listDirectory(dirPath);
        const mediaFiles = items
          .filter(i => !i.isDir && imageExtensions.includes(i.name.split('.').pop()?.toLowerCase() || ''))
          .map(i => ({ name: i.name, path: `${dirPath.replace(/\/$/, '')}/${i.name}`, type: 'file' as const, size: i.size }));
        data = mediaFiles.length > 0 ? mediaFiles : [{ name, path: filePath, type: 'file', size: 0 }];
      } catch (e) {
        data = [{ name, path: filePath, type: 'file', size: 0 }];
      }
    } else if (videoExtensions.includes(ext)) {
      type = 'video-gallery';
      const dirPath = filePath.substring(0, filePath.lastIndexOf('/')) || '/';
      try {
        const items = await bridge.listDirectory(dirPath);
        const mediaFiles = items
          .filter(i => !i.isDir && videoExtensions.includes(i.name.split('.').pop()?.toLowerCase() || ''))
          .map(i => ({ name: i.name, path: `${dirPath.replace(/\/$/, '')}/${i.name}`, type: 'file' as const, size: i.size }));
        data = mediaFiles.length > 0 ? mediaFiles : [{ name, path: filePath, type: 'file', size: 0 }];
      } catch (e) {
        data = [{ name, path: filePath, type: 'file', size: 0 }];
      }
    } else if (audioExtensions.includes(ext)) {
      type = 'audio';
    } else {
      type = 'code';
      language = getLanguageForExt(ext);
      try { content = await bridge.readFile(filePath); } catch (e) { console.warn(e); }
    }

    const existing = currentState.panes.find(p => p.id === filePath);
    if (existing) {
      setStore({ activePaneId: filePath, activeOpenFile: filePath });
      return;
    }

    const newPane: FilePane = {
      id: filePath,
      name,
      path: filePath,
      type,
      content,
      language,
      data,
      isUnsaved: false,
    };

    setStore(prev => ({
      panes: [...prev.panes, newPane],
      activePaneId: newPane.id,
      openFiles: prev.openFiles.includes(filePath) ? prev.openFiles : [...prev.openFiles, filePath],
      activeOpenFile: filePath,
      openFileContents: { ...prev.openFileContents, [filePath]: content },
    }));
  },

  // Legacy openFile
  openFile: (path: string, content: string) => {
    storeActions.openFileByPath(path);
  },

  closeFile: (path: string) => {
    storeActions.closePane(path);
  },

  // Filesystem Navigation (Matching CandyCode useFileSystem)
  navigateTo: (path: string) => {
    const history = [...currentState.navigationHistory];
    const currentIndex = currentState.historyIndex;
    if (currentIndex < history.length - 1) {
      history.splice(currentIndex + 1);
    }
    const current = history[history.length - 1];
    if (current !== path) {
      history.push(path);
      setStore({
        navigationHistory: history,
        historyIndex: history.length - 1,
        currentPath: path,
      });
      storeActions.refreshDirectory();
    }
  },

  navigateBack: () => {
    if (currentState.historyIndex > 0) {
      const newIndex = currentState.historyIndex - 1;
      setStore({
        historyIndex: newIndex,
        currentPath: currentState.navigationHistory[newIndex],
      });
      storeActions.refreshDirectory();
    }
  },

  navigateForward: () => {
    if (currentState.historyIndex < currentState.navigationHistory.length - 1) {
      const newIndex = currentState.historyIndex + 1;
      setStore({
        historyIndex: newIndex,
        currentPath: currentState.navigationHistory[newIndex],
      });
      storeActions.refreshDirectory();
    }
  },

  navigateUp: () => {
    const current = currentState.currentPath;
    if (current === '/' || current === '') return;
    const parent = current.substring(0, current.lastIndexOf('/')) || '/';
    storeActions.navigateTo(parent);
  },

  goHome: () => {
    storeActions.navigateTo(getHomeDir());
  },

  toggleDotfiles: () => {
    setStore(prev => ({ showDotfiles: !prev.showDotfiles }));
    storeActions.refreshDirectory();
  },

  refreshDirectory: async () => {
    try {
      const path = currentState.currentPath;
      const items = await bridge.listDirectory(path);
      const filtered = currentState.showDotfiles
        ? items
        : items.filter(i => !i.name.startsWith('.'));
      const sorted: FileSystemItem[] = filtered.map(i => ({
        name: i.name,
        path: `${path.replace(/\/$/, '')}/${i.name}`,
        type: (i.isDir ? 'folder' : 'file') as 'file' | 'folder',
        size: i.size,
      })).sort((a, b) => {
        if (a.type === 'folder' && b.type === 'file') return -1;
        if (a.type === 'file' && b.type === 'folder') return 1;
        return a.name.localeCompare(b.name);
      });
      setStore({ directoryContent: sorted });
    } catch (e) {
      console.warn('Failed to refresh directory:', e);
      setStore({ directoryContent: [] });
    }
  },

  getBreadcrumbs: (): Breadcrumb[] => {
    const path = currentState.currentPath;
    if (!path || path === '/') return [{ name: '/', path: '/' }];
    const parts = path.split('/').filter(Boolean);
    const breadcrumbs: Breadcrumb[] = [{ name: '/', path: '/' }];
    let accum = '';
    for (const part of parts) {
      accum += '/' + part;
      breadcrumbs.push({ name: part, path: accum });
    }
    return breadcrumbs;
  },

  // Context files & images for agent
  addContextFile: (file: { path: string; name: string }) => {
    setStore(prev => ({
      contextFiles: prev.contextFiles.some(f => f.path === file.path) ? prev.contextFiles : [...prev.contextFiles, file],
    }));
  },

  removeContextFile: (path: string) => {
    setStore(prev => ({
      contextFiles: prev.contextFiles.filter(f => f.path !== path),
    }));
  },

  addContextImage: (img: { path: string; data: string }) => {
    setStore(prev => ({
      contextImages: prev.contextImages.some(i => i.path === img.path) ? prev.contextImages : [...prev.contextImages, img],
    }));
  },

  removeContextImage: (path: string) => {
    setStore(prev => ({
      contextImages: prev.contextImages.filter(i => i.path !== path),
    }));
  },

  // Model management helpers
  addCustomModel: (model: ModelInfo) => {
    setStore(prev => ({
      customModels: [
        ...prev.customModels.filter(existing => existing.id !== model.id),
        model,
      ],
    }));
  },

  removeCustomModel: (id: string) => {
    setStore(prev => ({
      customModels: prev.customModels.filter(m => m.id !== id),
      activeModel: prev.activeModel === id ? PRESET_MODELS[0].id : prev.activeModel,
    }));
  },

  getCustomWebLLMModels: (): CustomWebLLMModel[] => {
    return currentState.customModels.filter(
      (model): model is ModelInfo & CustomWebLLMModel => Boolean(
        model.id?.trim() && (
          (model.model?.trim() && model.model_lib?.trim()) ||
          (model.wllamaRepo?.trim() && model.wllamaFile?.trim())
        )
      )
    );
  },
};
