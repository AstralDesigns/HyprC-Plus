/**
 * Agent App Global State & Store
 */
import { useState, useEffect, useRef } from 'react';
import { bridge } from './bridge';
import { EXTENSION_LANGUAGE_MAP } from './utils/monacoLanguages';
import { fetchGitStatus, GitFileStatus } from './utils/gitStatus';

export interface DiffData {
  filePath: string;
  originalCode: string;
  modifiedCode: string;
  status: 'pending' | 'accepted' | 'rejected';
  additions?: number;
  deletions?: number;
  isNew?: boolean;
}

export interface PendingFileEdit {
  path: string;
  additions: number;
  deletions: number;
  isNew: boolean;
  oldContent: string;
  newContent: string;
  timestamp: number;
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

/**
 * A turn is stored as an ordered sequence of blocks, built in the order
 * events actually arrive — this is what lets a diff card or activity
 * timeline appear inline exactly where it happened, with normal response
 * text before and after it, instead of all text being concatenated into one
 * block rendered after every widget.
 */
export interface SuggestionOption {
  label: string;
  promptText: string;
  /** How the chip is dispatched when tapped: send as a fresh turn, or steer the running one. */
  sendAs?: 'send' | 'steer';
}

export interface SuggestionsData {
  mode: 'clarify' | 'next-step';
  question: string;
  options: SuggestionOption[];
}

export type MessageBlock =
  | { type: 'text'; id: string; content: string }
  | { type: 'activity'; id: string; tools: ToolCallData[] }   // grouped ambient tool calls (read/list/search/plan)
  | { type: 'command'; id: string; tool: ToolCallData }        // elevated: exec_command / run_command
  | { type: 'diff'; id: string; diff: DiffData }              // elevated: write_file result
  | { type: 'reasoning'; id: string; content: string }         // real chain-of-thought (display-only)
  | { type: 'steer'; id: string; content: string }             // user instruction injected mid-run
  | { type: 'suggestions'; id: string; suggestions: SuggestionsData } // tappable clarify/next-step chips
  | { type: 'spec'; id: string; status: 'drafting' | 'ready'; markdown: string }   // spec-driven plan (§3.4)
  | { type: 'verification'; id: string; command: string; status: 'running' | 'complete'; exitCode?: number; output?: string; passed?: boolean }; // verification gate (§3.8)

export interface Message {
  id: string;
  role: 'user' | 'assistant' | 'system' | 'tool';
  content: string;
  timestamp: number;
  /** Client-generated id tagging an assistant turn's file edits so the whole
   *  turn can be rolled back at once ("Revert this turn", plan §3.7). */
  turnId?: string;
  blocks?: MessageBlock[];
  tools?: ToolCallData[];
  plan?: PlanData;
  diff?: DiffData;
  diffs?: DiffData[];
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
  titleSource?: 'auto' | 'user';
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
  toolSupport?: boolean;
}

export type FilePaneType = 'code' | 'markdown' | 'image' | 'video' | 'audio' | 'image-gallery' | 'video-gallery' | 'preview';

export interface FilePane {
  id: string;
  name: string;
  path?: string;
  type: FilePaneType;
  content: string;
  isUnsaved?: boolean;
  language?: string;
  data?: any;
  cursorPosition?: { lineNumber: number; column: number };
  scrollTop?: number;
  /** mtime (ms) recorded at the last poll baseline; undefined until first probe. */
  diskMtime?: number;
  /** On-disk file changed while this tab held unsaved edits — surfaced as a badge. */
  externalChanged?: boolean;
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
    description: 'Compact coding model with tool-use-friendly chat formatting.',
    toolSupport: true,
    isDefault: true,
  },
  {
    id: 'Qwen2.5-Coder-0.5B-Instruct',
    name: 'Qwen2.5 Coder 0.5B Instruct',
    size: '~379 MB',
    vram: '~600 MB',
    description: 'Fast lightweight coding model with tool-use-friendly chat formatting.',
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
  /** Clarifying / next-step options the agent last offered for the running turn.
   *  Rendered as tappable chips above the composer; cleared when a new turn starts. */
  activeSuggestions: SuggestionsData | null;
  /** True while the agentic loop is blocked on the spec-driven Approve/Revise gate. */
  specApprovalPending: boolean;
  /** Composer "Spec-driven" toggle — drafts a plan and waits for approval before executing. */
  specMode: boolean;
  /** Open the durable-memories panel (agent markdown notes under the HyprCandy cache). */
  memoryPanelOpen: boolean;
  workspaceStartupEnabled: boolean;

  // Floating panel layout
  sidebarVisible: boolean;
  sidebarWidth: number;
  chatVisible: boolean;
  chatWidth: number;
  modelManagerOpen: boolean;
  profileOpen: boolean;
  githubToken: string;
  githubUser: {
    login: string;
    name: string;
    avatar_url: string;
    html_url: string;
    bio?: string;
    public_repos?: number;
  } | null;
  selectedRepo: string;

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

  // Pending write_file edits awaiting accept/reject, keyed by absolute path.
  // Mirrors the Python runtime's PENDING_EDITS registry (see /api/files/pending).
  pendingFiles: Record<string, PendingFileEdit>;

  // Git working-tree status per absolute path (from `git status --porcelain`).
  gitStatus: Record<string, GitFileStatus>;
  // Absolute paths whose open editor currently reports >=1 error marker.
  errorFiles: Record<string, true>;

  // Filesystem event feed (inotify): a revision bumped on each drain batch, and
  // the directories touched in the latest batch (keyed for O(1) membership).
  fsRev: number;
  fsDirtyDirs: Record<string, true>;

  // Monaco editor theme
  monacoTheme: string;

  // ── Hybrid inference ─────────────────────────────────────────────────────
  /** 'byok' = user's own API key (OpenRouter/Groq), 'cloud' = Vercel AI Gateway (Pro).
   *  The old 'local' (WebLLM/llama.cpp) mode is fully removed — persisted states
   *  with 'local' migrate to 'byok' in loadPersistedState(). */
  inferenceMode: 'byok' | 'cloud';
  /** Validated Lemon Squeezy license key — stored via GJS libsecret on save */
  licenseKey: string;
  /** Selected cloud model id (e.g. 'google/gemini-2.5-flash') */
  cloudModel: string;
  /** Remaining token allowance shown in Cloud tab */
  cloudCredits: number;
  /** True once the local Python runtime server at :17900 responds to /health */
  runtimeServerReady: boolean;

  // ── BYOK (Bring Your Own Key) ─────────────────────────────────────────────
  /** Active BYOK provider: 'google' | 'openai' | 'anthropic' | 'xai' | null */
  byokProvider: string | null;
  /** Per-provider API keys saved in browser (synced to Python runtime on use) */
  byokKeys: Record<string, string>;
  /** Selected model id for the active BYOK provider */
  byokModel: string;
  /** Lemon Squeezy license key for BYOK subscription ($5/mo) — validated against LS License API directly */
  byokLicenseKey: string;
  /** Lemon Squeezy instance_id returned on first activation — stored for periodic re-validation */
  byokLicenseInstanceId: string;
}

const STORAGE_KEY = 'hyprcandy_agent_state_v2';

function getHomeDir(): string {
  // The real user's HOME is only known at runtime: the host delivers it via
  // the 'runtime_config' bridge message (bridge.ts sets __hyprcandyHome).
  // Before that arrives (fresh install) we return a neutral '' placeholder —
  // never a hardcoded path, which used to leak the original developer's own
  // home directory into new users' file browser. bridge.ts
  // corrects currentPath/navigationHistory once the real home is known.
  if (typeof window !== 'undefined') {
    const w = window as any;
    return w.__hyprcandyHome || w.__USER_HOME__ || '';
  }
  return '';
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
  return EXTENSION_LANGUAGE_MAP[ext.toLowerCase()] || 'plaintext';
}

function loadInitialState(): AppState {
  const defSession = createDefaultSession();
  const home = getHomeDir();
  const defaultState: AppState = {
    sessions: [defSession],
    activeSessionId: defSession.id,
    activeModel: 'openrouter/free',
    modelStatus: 'ready',
    downloadProgress: { progress: 0, text: '' },
    // Projects stay empty until the user picks a folder in the Project tab
    // (Sidebar.tsx). Nothing auto-seeds this — the host's HOME only drives the
    // Files tab (currentPath below), never a project root.
    projectPath: '',
    projectFiles: [],
    selectedFile: null,
    selectedFileContent: null,
    agentRunning: false,
    activeSuggestions: null,
    specApprovalPending: false,
    specMode: false,
    memoryPanelOpen: false,
    workspaceStartupEnabled: true,
    
    // Floating panels default: both visible, matching CandyCode
    sidebarVisible: true,
    sidebarWidth: 260,
    chatVisible: true,
    chatWidth: 380,
    modelManagerOpen: false,
    profileOpen: false,
    githubToken: '',
    githubUser: null,
    selectedRepo: '',
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
    pendingFiles: {},
    gitStatus: {},
    errorFiles: {},
    fsRev: 0,
    fsDirtyDirs: {},

    monacoTheme: 'matugen',

    // Hybrid inference defaults
    inferenceMode: 'byok' as const,
    licenseKey: '',
    cloudModel: 'google/gemini-2.5-flash',
    cloudCredits: 0,
    runtimeServerReady: true,

    // BYOK defaults
    byokProvider: 'openrouter',
    byokKeys: {},
    byokModel: 'openrouter/free',
    byokLicenseKey: '',
    byokLicenseInstanceId: '',
  };

  const persisted = readPersistedBlob();
  if (persisted) return sanitizePersisted(defaultState, defSession, persisted);

  return defaultState;
}

// The exact subset of state the durable mirror (localStorage + the bridge's
// store_persist file) carries. Shared by both persist sinks so the on-disk
// JSON stays byte-compatible with the historical localStorage payload.
function persistedSnapshot() {
  const next = currentState;
  return {
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
    // Which backend was active — restored on next launch so the header
    // chip and Model Manager view reflect it instead of resetting to the
    // default. Secrets themselves (byokKeys, licenseKey) stay out of the
    // blob; they're synced through secret-tool/libsecret instead.
    inferenceMode: next.inferenceMode,
    byokProvider: next.byokProvider,
    byokModel: next.byokModel,
    cloudModel: next.cloudModel,
    specMode: next.specMode,
    githubToken: next.githubToken,
    githubUser: next.githubUser,
    selectedRepo: next.selectedRepo,
  };
}

function readPersistedBlob(): any | null {
  try {
    const saved = localStorage.getItem(STORAGE_KEY) || localStorage.getItem('hyprcandy_agent_state_v1');
    if (!saved) return null;
    const parsed = JSON.parse(saved);
    if (parsed && Array.isArray(parsed.sessions) && parsed.sessions.length > 0) return parsed;
  } catch (e) {
    console.warn('Failed to parse localStorage state:', e);
  }
  return null;
}

function sanitizePersisted(defaultState: AppState, defSession: Session, parsed: any): AppState {
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
      if (parsed.inferenceMode === 'cloud') {
        return (typeof parsed.cloudModel === 'string' && parsed.cloudModel)
          ? parsed.cloudModel
          : (typeof parsed.activeModel === 'string' ? parsed.activeModel : 'google/gemini-2.5-flash');
      }
      if (parsed.inferenceMode === 'byok') {
        return (typeof parsed.byokModel === 'string' && parsed.byokModel)
          ? parsed.byokModel
          : (typeof parsed.activeModel === 'string' ? parsed.activeModel : 'openrouter/free');
      }
      return (typeof parsed.byokModel === 'string' && parsed.byokModel) || 'openrouter/free';
    })(),
    modelStatus: 'ready',
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
    inferenceMode: parsed.inferenceMode === 'cloud' ? 'cloud' : 'byok',
    byokProvider: typeof parsed.byokProvider === 'string' && parsed.byokProvider ? parsed.byokProvider : 'openrouter',
    byokModel: typeof parsed.byokModel === 'string' && parsed.byokModel ? parsed.byokModel : 'openrouter/free',
    cloudModel: typeof parsed.cloudModel === 'string' ? parsed.cloudModel : defaultState.cloudModel,
  };
}

let currentState: AppState = loadInitialState();
const listeners = new Set<(state: AppState) => void>();

// True once anything changed the store locally. The bridge's durable
// store_state (mirrored from agent-state.json) is authoritative at boot, but
// if the session already diverged (e.g. runtime_config set projectPath) a
// late arrival must not clobber that — it merges only over an untouched store.
let localMutated = false;

let storeDirty = false;
let storePersistScheduled = false;
let storePersistTimer: ReturnType<typeof setTimeout> | null = null;
const STORE_PERSIST_DEBOUNCE_MS = 250;

function persistStore() {
  storePersistScheduled = false;
  if (!storeDirty) return;
  storeDirty = false;
  const blob = JSON.stringify(persistedSnapshot());
  try {
    localStorage.setItem(STORAGE_KEY, blob);
  } catch (e) {
    console.warn('Failed to save to localStorage:', e);
  }
  // Durable mirror: the quickshell loopback server writes this blob to
  // ~/.local/share/hyprcandy/agent-state.json immediately, so a hard kill
  // (which never flushes Chromium leveldb) can no longer reset the store.
  bridge.storePersist(blob).catch(() => {});
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

// ── Bridge-backed durable hydration ────────────────────────────────────
// The loopback shim dispatches {type:'store_state'} from the bootstrap reply
// (bridge.ts re-emits it as the agent_store_state event). localStorage may be
// empty on a fresh session (Chromium flush timing); the server file is not.
function hydrateFromDurable(parsed: any) {
  try {
    if (!parsed || !Array.isArray(parsed.sessions) || parsed.sessions.length === 0) return;
    if (localMutated) return;
    const defSession = createDefaultSession();
    currentState = sanitizePersisted({ ...currentState, sessions: [defSession], activeSessionId: defSession.id }, defSession, parsed);
    listeners.forEach(fn => { fn(currentState); });
  } catch (e) {
    console.warn('Failed to hydrate from bridge store_state:', e);
  }
}

if (typeof window !== 'undefined') {
  window.addEventListener('agent_store_state', (e: any) => {
    if (e.detail) hydrateFromDurable(e.detail);
  });
  const pending = (window as any).__hyprcandyPendingStoreState;
  if (pending) {
    (window as any).__hyprcandyPendingStoreState = null;
    hydrateFromDurable(pending);
  }
}

export function setStore(updater: Partial<AppState> | ((prev: AppState) => Partial<AppState>)) {
  const partial = typeof updater === 'function' ? updater(currentState) : updater;
  const next: AppState = { ...currentState, ...partial };
  currentState = next;

  localMutated = true;
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

function shallowEqual(a: any, b: any): boolean {
  if (Object.is(a, b)) return true;
  if (typeof a !== 'object' || a === null || typeof b !== 'object' || b === null) return false;
  const keysA = Object.keys(a);
  const keysB = Object.keys(b);
  if (keysA.length !== keysB.length) return false;
  for (const key of keysA) {
    if (!Object.is(a[key], b[key])) return false;
  }
  return true;
}

/**
 * Selective subscription: only re-renders when the selected slice actually
 * changes (per isEqual, shallow by default) — unlike useStore(), which
 * re-renders on every single setStore() call anywhere in the app. Use this
 * for components that don't need to react to the high-frequency updates
 * (e.g. chat streaming touches `sessions` roughly every 80ms) but do read
 * from the store — Canvas/Monaco being the main example, since re-rendering
 * an editor that often produces visible flicker with no functional benefit.
 */
export function useStoreSelector<T>(selector: (s: AppState) => T, isEqual: (a: T, b: T) => boolean = shallowEqual): T {
  const selectorRef = useRef(selector);
  selectorRef.current = selector;
  const isEqualRef = useRef(isEqual);
  isEqualRef.current = isEqual;

  const [selected, setSelected] = useState<T>(() => selector(currentState));
  const selectedRef = useRef(selected);
  selectedRef.current = selected;

  useEffect(() => {
    const check = () => {
      const next = selectorRef.current(currentState);
      if (!isEqualRef.current(selectedRef.current, next)) {
        selectedRef.current = next;
        setSelected(next);
      }
    };
    check(); // catch any change that happened between initial render and this effect mounting
    listeners.add(check);
    return () => { listeners.delete(check); };
  }, []);

  return selected;
}

let untitledCount = 1;

/* Store Actions */
export const storeActions = {
  // Floating panel toggles
  toggleSidebar: () => setStore(prev => ({ sidebarVisible: !prev.sidebarVisible })),
  toggleChat: () => setStore(prev => ({ chatVisible: !prev.chatVisible })),
  // Open a directory through the native folder picker and load it as the project.
  openFolderDialog: async () => {
    try {
      const picked = await bridge.openFileDialog({ directory: true, currentFolder: currentState.projectPath });
      if (picked) {
        setStore({ projectPath: picked });
        storeActions.navigateTo(picked);
      }
    } catch (e) {
      console.warn('Open folder error:', e);
    }
  },
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

  /**
   * Called once a session's first turn completes (see agent-engine.ts). Only
   * takes effect while the title is still auto-assigned — a manual rename
   * (renameSession) always wins and is never overwritten again.
   */
  autoNameSession: (sessionId: string, title: string) => {
    const clean = title.trim();
    if (!clean) return;
    setStore(prev => ({
      sessions: prev.sessions.map(s =>
        s.id === sessionId && s.titleSource !== 'user' ? { ...s, title: clean, titleSource: 'auto' } : s
      ),
    }));
  },

  renameSession: (sessionId: string, title: string) => {
    const clean = title.trim();
    if (!clean) return;
    setStore(prev => ({
      sessions: prev.sessions.map(s =>
        s.id === sessionId ? { ...s, title: clean, titleSource: 'user' } : s
      ),
    }));
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

  updateDiffStatus: (sessionId: string, messageId: string, status: 'accepted' | 'rejected', filePath?: string) => {
    setStore(prev => {
      const updated = prev.sessions.map(s => {
        if (s.id !== sessionId) return s;
        return {
          ...s,
          messages: s.messages.map(m => {
            if (m.id !== messageId) return m;
            const diff = (m.diff && (!filePath || m.diff.filePath === filePath)) ? { ...m.diff, status } : m.diff;
            const diffs = m.diffs?.map(d => (!filePath || d.filePath === filePath) ? { ...d, status } : d);
            return { ...m, diff, diffs };
          }),
        };
      });
      return { sessions: updated };
    });
  },

  /**
   * Register a write_file result as a pending edit — called from
   * agent-engine.ts's poll loop as soon as a write_file tool_result arrives.
   * The file is already on disk (Python writes immediately); this only
   * tracks the snapshot for the accept/reject UI.
   */
  registerPendingFile: (edit: PendingFileEdit) => {
    setStore(prev => ({ pendingFiles: { ...prev.pendingFiles, [edit.path]: edit } }));
  },

  /** Attaches a per-file diff card to a turn — a turn can touch several files. */
  appendDiff: (sessionId: string, messageId: string, diff: DiffData) => {
    setStore(prev => ({
      sessions: prev.sessions.map(s => {
        if (s.id !== sessionId) return s;
        return {
          ...s,
          messages: s.messages.map(m => {
            if (m.id !== messageId) return m;
            const existing = m.diffs || [];
            const withoutSame = existing.filter(d => d.filePath !== diff.filePath);
            return { ...m, diffs: [...withoutSame, diff] };
          }),
        };
      }),
    }));
  },

  refreshPendingFiles: async () => {
    try {
      const res = await bridge.runtimeRequest('/api/files/pending', {}, 'GET');
      const files = (res?.files || []) as Array<any>;
      const map: Record<string, PendingFileEdit> = {};
      for (const f of files) {
        map[f.path] = {
          path: f.path, additions: f.additions, deletions: f.deletions,
          isNew: f.is_new, oldContent: f.old_content, newContent: f.new_content,
          timestamp: f.timestamp,
        };
      }
      setStore({ pendingFiles: map });
    } catch { /* runtime not up yet — fine, list stays empty */ }
  },

  /**
   * Diffs live inside per-message `diff`/`diffs`/`blocks` fields, but accept
   * /reject can originate from the global pending-files bar which has no
   * reference back to which message/session a file's diff card lives in.
   * Sweep every session's messages and update any diff card matching this
   * path — this is what keeps a DiffWidget's buttons in sync (Open + a kept
   * /undone indicator, instead of Keep/Undo staying visible) no matter which
   * UI surface actually performed the accept/reject.
   */
  syncDiffStatusEverywhere: (path: string, status: 'accepted' | 'rejected') => {
    setStore(prev => ({
      sessions: prev.sessions.map(s => ({
        ...s,
        messages: s.messages.map(m => {
          const touchesPath = (m.diff?.filePath === path) || m.diffs?.some(d => d.filePath === path)
            || m.blocks?.some(b => b.type === 'diff' && b.diff.filePath === path);
          if (!touchesPath) return m;
          return {
            ...m,
            diff: m.diff && m.diff.filePath === path ? { ...m.diff, status } : m.diff,
            diffs: m.diffs?.map(d => d.filePath === path ? { ...d, status } : d),
            blocks: m.blocks?.map(b => b.type === 'diff' && b.diff.filePath === path
              ? { ...b, diff: { ...b.diff, status } } : b),
          };
        }),
      })),
    }));
  },

  acceptFile: async (path: string) => {
    setStore(prev => {
      const next = { ...prev.pendingFiles };
      delete next[path];
      return { pendingFiles: next };
    });
    storeActions.syncDiffStatusEverywhere(path, 'accepted');
    try { await bridge.runtimeRequest('/api/files/accept', { path }); } catch { /* best-effort */ }
  },

  rejectFile: async (path: string) => {
    const edit = getStore().pendingFiles[path];
    setStore(prev => {
      const next = { ...prev.pendingFiles };
      delete next[path];
      return { pendingFiles: next };
    });
    storeActions.syncDiffStatusEverywhere(path, 'rejected');
    try { await bridge.runtimeRequest('/api/files/reject', { path }); } catch { /* best-effort */ }
    // If the reverted file is open in a pane, refresh its content from disk.
    if (edit) {
      const pane = getStore().panes.find(p => p.path === path);
      if (pane) {
        try {
          const content = await bridge.readFile(path);
          setStore(prev => ({ panes: prev.panes.map(p => p.id === pane.id ? { ...p, content, isUnsaved: false } : p) }));
        } catch { /* best-effort */ }
      }
    }
  },

  acceptAllFiles: async () => {
    const paths = Object.keys(getStore().pendingFiles);
    setStore({ pendingFiles: {} });
    for (const path of paths) storeActions.syncDiffStatusEverywhere(path, 'accepted');
    try { await bridge.runtimeRequest('/api/files/accept-all', {}); } catch { /* best-effort */ }
  },

  rejectAllFiles: async () => {
    const paths = Object.keys(getStore().pendingFiles);
    setStore({ pendingFiles: {} });
    for (const path of paths) storeActions.syncDiffStatusEverywhere(path, 'rejected');
    try { await bridge.runtimeRequest('/api/files/reject-all', {}); } catch { /* best-effort */ }
    for (const path of paths) {
      const pane = getStore().panes.find(p => p.path === path);
      if (!pane) continue;
      try {
        const content = await bridge.readFile(path);
        setStore(prev => ({ panes: prev.panes.map(p => p.id === pane.id ? { ...p, content, isUnsaved: false } : p) }));
      } catch { /* best-effort */ }
    }
  },

  /**
   * Roll a completed turn's file changes back to their pre-turn state (§3.7).
   * The Python runtime keeps a per-turn snapshot of every file the turn wrote
   * (see tools.CURRENT_TURN_ID / TURN_EDITS); this asks it to restore them, then
   * reflects the rollback in the UI — the turn's diff cards flip to "reverted",
   * the files leave the pending bar, and any open editor reloads from disk.
   */
  revertTurn: async (sessionId: string, messageId: string) => {
    const msg = getStore().sessions.find(s => s.id === sessionId)?.messages.find(m => m.id === messageId);
    if (!msg?.turnId) return;
    const paths = new Set<string>();
    msg.blocks?.forEach(b => { if (b.type === 'diff') paths.add(b.diff.filePath); });
    msg.diffs?.forEach(d => paths.add(d.filePath));
    let res: any;
    try { res = await bridge.runtimeRequest('/api/turns/revert', { turn_id: msg.turnId }); } catch { return; }
    if (!res?.ok) return;
    setStore(prev => ({
      pendingFiles: Object.fromEntries(Object.entries(prev.pendingFiles).filter(([p]) => !paths.has(p))),
      sessions: prev.sessions.map(s => s.id !== sessionId ? s : { ...s, messages: s.messages.map(m => m.id !== messageId ? m : {
        ...m,
        diff: m.diff ? { ...m.diff, status: 'rejected' as const } : m.diff,
        diffs: m.diffs?.map(d => ({ ...d, status: 'rejected' as const })),
        blocks: m.blocks?.map(b => b.type === 'diff' ? { ...b, diff: { ...b.diff, status: 'rejected' as const } } : b),
      }) }),
    }));
    for (const path of paths) {
      const pane = getStore().panes.find(p => p.path === path);
      if (!pane) continue;
      try {
        const content = await bridge.readFile(path);
        setStore(prev => ({ panes: prev.panes.map(p => p.id === pane.id ? { ...p, content, isUnsaved: false } : p) }));
      } catch { /* best-effort */ }
    }
  },

  /**
   * Revert every assistant turn at/after `fromIndex` — run just before an
   * edit&resend truncates those messages, so the workspace rolls back to the
   * state prior to the edited prompt. Newest-first so each
   * turn's snapshot restores cleanly; best-effort per turn.
   */
  revertTurnsAfter: async (sessionId: string, fromIndex: number) => {
    const msgs = getStore().sessions.find(s => s.id === sessionId)?.messages || [];
    const doomed = msgs.slice(fromIndex);
    const paths = new Set<string>();
    for (const m of doomed) {
      m.blocks?.forEach(b => { if (b.type === 'diff') paths.add(b.diff.filePath); });
      m.diffs?.forEach(d => paths.add(d.filePath));
    }
    const turnIds = doomed.filter(m => m.role === 'assistant' && m.turnId).map(m => m.turnId as string).reverse();
    for (const turnId of turnIds) {
      try { await bridge.runtimeRequest('/api/turns/revert', { turn_id: turnId }); } catch { /* best-effort */ }
    }
    await storeActions.refreshPendingFiles();
    for (const path of paths) {
      const pane = getStore().panes.find(p => p.path === path);
      if (!pane) continue;
      try {
        const content = await bridge.readFile(path);
        setStore(prev => ({ panes: prev.panes.map(p => p.id === pane.id ? { ...p, content, isUnsaved: false } : p) }));
      } catch { /* best-effort */ }
    }
  },

  /** Opens a live file:// preview of a web page/asset in a new Canvas pane. */
  openPreview: (path: string, name?: string) => {
    setStore(prev => {
      const id = `preview_${path}`;
      const existing = prev.panes.find(p => p.id === id);
      if (existing) return { activePaneId: id };
      const pane: FilePane = {
        id, name: name || path.split('/').pop() || path, path,
        type: 'preview', content: '',
      };
      return { panes: [...prev.panes, pane], activePaneId: id };
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

  /** Close a set of panes at once (tab context-menu bulk actions), choosing a
   * sensible surviving active pane. Mirrors closePane's bookkeeping. */
  closePanes: (ids: string[]) => {
    if (!ids.length) return;
    const idSet = new Set(ids);
    setStore(prev => {
      const remaining = prev.panes.filter(p => !idSet.has(p.id));
      let newActiveId = prev.activePaneId;
      if (newActiveId && idSet.has(newActiveId)) {
        newActiveId = remaining.length ? remaining[remaining.length - 1].id : null;
      }
      return {
        panes: remaining,
        activePaneId: newActiveId,
        activeOpenFile: newActiveId,
        openFiles: prev.openFiles.filter(f => !idSet.has(f)),
      };
    });
  },

  closeOtherPanes: (id: string) => {
    const ids = getStore().panes.filter(p => p.id !== id).map(p => p.id);
    storeActions.closePanes(ids);
    storeActions.setActivePane(id);
  },

  closePanesToRight: (id: string) => {
    const panes = getStore().panes;
    const idx = panes.findIndex(p => p.id === id);
    if (idx === -1) return;
    storeActions.closePanes(panes.slice(idx + 1).map(p => p.id));
  },

  closeAllPanes: () => {
    storeActions.closePanes(getStore().panes.map(p => p.id));
  },

  /** Close every pane with no unsaved edits (keeps the dirty ones). */
  closeSavedPanes: () => {
    storeActions.closePanes(getStore().panes.filter(p => !p.isUnsaved).map(p => p.id));
  },

  /** Drag-to-rearrange for the Canvas tab row. */
  reorderPanes: (draggedId: string, targetId: string) => {
    if (draggedId === targetId) return;
    setStore(prev => {
      const from = prev.panes.findIndex(p => p.id === draggedId);
      const to = prev.panes.findIndex(p => p.id === targetId);
      if (from === -1 || to === -1) return {};
      const next = [...prev.panes];
      const [moved] = next.splice(from, 1);
      next.splice(to, 0, moved);
      return { panes: next };
    });
  },

  setActivePane: (id: string | null) => {
    setStore({ activePaneId: id, activeOpenFile: id });
  },

  // Cycle the active canvas tab (Ctrl+Tab forward, Ctrl+Shift+Tab back).
  // Wraps around the full pane list, including non-code canvases.
  cycleActivePane: (direction: 1 | -1) => {
    setStore(prev => {
      const panes = prev.panes;
      if (panes.length < 2) return {};
      const idx = panes.findIndex(p => p.id === prev.activePaneId);
      const next = panes[(((idx + direction) % panes.length) + panes.length) % panes.length];
      return { activePaneId: next.id, activeOpenFile: next.id };
    });
  },

  updatePaneContent: (id: string, content: string) => {
    setStore(prev => ({
      panes: prev.panes.map(p => p.id === id ? { ...p, content, isUnsaved: true } : p),
      openFileContents: { ...prev.openFileContents, [id]: content },
    }));
  },

  /** Remembers cursor/scroll position per pane so re-opening or switching
   * back to a tab restores exactly where you left off, instead of always
   * landing at line 1. Persistence is already debounced (schedulePersist),
   * so frequent cursor moves coalesce into one write rather than one per
   * keystroke. */
  setPaneViewState: (id: string, viewState: { cursorPosition?: { lineNumber: number; column: number }; scrollTop?: number }) => {
    setStore(prev => ({
      panes: prev.panes.map(p => p.id === id ? { ...p, ...viewState } : p),
    }));
  },

  // Coalescing refresh of the git status map. Runs at most one `git status`
  // at a time; a request arriving mid-flight sets a flag so the next loop
  // iteration picks up the newer on-disk state instead of racing.
  refreshGitStatus: (() => {
    let inFlight = false;
    let queued = false;
    return async () => {
      if (inFlight) { queued = true; return; }
      inFlight = true;
      try {
        do {
          queued = false;
          const root = getStore().projectPath;
          if (!root) {
            if (Object.keys(getStore().gitStatus).length) setStore({ gitStatus: {} });
            continue;
          }
          const { map, isRepo } = await fetchGitStatus(root);
          setStore({ gitStatus: isRepo ? map : {} });
        } while (queued);
      } finally {
        inFlight = false;
      }
    };
  })(),

  setFileError: (path: string | undefined, hasError: boolean) => {
    if (!path) return;
    if (!!getStore().errorFiles[path] === hasError) return;
    const next = { ...getStore().errorFiles };
    if (hasError) next[path] = true; else delete next[path];
    setStore({ errorFiles: next });
  },

  saveFile: async (paneId: string) => {
    const pane = currentState.panes.find(p => p.id === paneId);
    if (!pane || !pane.path) return;
    try {
      const res = await bridge.writeFile(pane.path, pane.content);
      if (res && res.success !== false) {
        // Clear diskMtime so the next poll re-baselines against our own write
        // instead of mistaking it for an external edit and reloading.
        setStore(prev => ({
          panes: prev.panes.map(p => p.id === paneId ? { ...p, isUnsaved: false, diskMtime: undefined, externalChanged: false } : p),
        }));
        storeActions.refreshGitStatus();
      }
    } catch (e) {
      console.error('Failed to save file:', e);
    }
  },

  /** Reload a single open pane's content straight from disk, clearing the
   * unsaved + external-change flags. Used when the user accepts an on-disk
   * edit that landed while their tab was dirty. */
  reloadPaneFromDisk: async (id: string) => {
    const pane = getStore().panes.find(p => p.id === id);
    if (!pane?.path) return;
    try {
      const content = await bridge.readFile(pane.path);
      setStore(prev => ({
        panes: prev.panes.map(p => p.id === id ? { ...p, content, isUnsaved: false, externalChanged: false, diskMtime: undefined } : p),
        openFileContents: { ...prev.openFileContents, [id]: content },
      }));
    } catch (e) { console.warn('reloadPaneFromDisk failed:', e); }
  },

  /**
   * Poll open text-backed editors for external on-disk changes (focus + a
   * coalescing interval call this). A clean tab reloads silently from disk so
   * Monaco shows the new content; a dirty tab is left untouched and only
   * flagged (externalChanged) so the user's unsaved work is never clobbered.
   * The first probe per tab just records a baseline mtime without acting.
   */
  pollFilesystem: (() => {
    let inFlight = false;
    return async () => {
      if (inFlight) return;
      const st = getStore();
      const editable = st.panes.filter(p => p.path && (p.type === 'code' || p.type === 'markdown'));
      if (!editable.length) return;
      inFlight = true;
      try {
        const paths = Array.from(new Set(editable.map(p => p.path!)));
        const res = await bridge.statFiles(paths, []);
        for (const p of editable) {
          const m = res[p.path!];
          if (m === undefined || m === 0) continue;
          if (p.diskMtime === undefined) {
            setStore(prev => ({ panes: prev.panes.map(x => x.id === p.id ? { ...x, diskMtime: m } : x) }));
            continue;
          }
          if (m === p.diskMtime) continue;
          if (p.isUnsaved) {
            setStore(prev => ({ panes: prev.panes.map(x => x.id === p.id ? { ...x, externalChanged: true } : x) }));
          } else {
            try {
              const content = await bridge.readFile(p.path!);
              setStore(prev => ({
                panes: prev.panes.map(x => x.id === p.id ? { ...x, content, isUnsaved: false, externalChanged: false, diskMtime: m } : x),
                openFileContents: { ...prev.openFileContents, [p.id]: content },
              }));
            } catch { /* file may be gone; retry next poll */ }
          }
        }
      } catch { /* best-effort: loopback offline */ }
      finally { inFlight = false; }
    };
  })(),

  /**
   * Apply a batch of inotify-reported paths (drained from the loopback server):
   * reload/flag open editors whose exact file changed, and record the touched
   * directories so the explorer refreshes just those (see the Sidebar fsRev
   * effect). This is the instant fast path; the mtime poll stays as the net for
   * dirs/files inotify isn't watching (e.g. when inotifywait is unavailable).
   */
  handleFsEvents: async (paths: string[]) => {
    if (!paths || !paths.length) return;
    const changed = new Set(paths);
    const st = getStore();
    for (const p of st.panes) {
      if (!p.path || !changed.has(p.path)) continue;
      if (p.type !== 'code' && p.type !== 'markdown') continue;
      if (p.isUnsaved) {
        setStore(prev => ({ panes: prev.panes.map(x => x.id === p.id ? { ...x, externalChanged: true } : x) }));
      } else {
        try {
          const content = await bridge.readFile(p.path);
          setStore(prev => ({
            panes: prev.panes.map(x => x.id === p.id ? { ...x, content, isUnsaved: false, externalChanged: false, diskMtime: undefined } : x),
            openFileContents: { ...prev.openFileContents, [p.id]: content },
          }));
        } catch { /* file may be gone */ }
      }
    }
    const dirty: Record<string, true> = {};
    for (const path of paths) {
      dirty[path.slice(0, path.lastIndexOf('/')) || '/'] = true;
      dirty[path] = true; // a watched dir that itself moved/created matches by its own path
    }
    setStore(prev => ({ fsDirtyDirs: dirty, fsRev: prev.fsRev + 1 }));
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
    // Guard on the real current path, not the history tail: on startup resume
    // currentPath is persisted but navigationHistory resets to [home], so the
    // tail can equal a breadcrumb target while we're actually deeper (made the
    // $USER crumb a no-op until another crumb was clicked first).
    if (currentState.currentPath === path) return;
    const history = [...currentState.navigationHistory];
    const currentIndex = currentState.historyIndex;
    if (currentIndex < history.length - 1) {
      history.splice(currentIndex + 1);
    }
    if (history[history.length - 1] !== path) {
      history.push(path);
    }
    setStore({
      navigationHistory: history,
      historyIndex: history.length - 1,
      currentPath: path,
    });
    storeActions.refreshDirectory();
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
};
