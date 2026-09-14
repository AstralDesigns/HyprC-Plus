import React, { Component, useEffect, useRef, ReactNode } from 'react';
import { useStore, setStore, storeActions, PRESET_MODELS, persistStoreNow } from './store';
import { bridge } from './bridge';
import { Header } from './components/Header';
import { Sidebar } from './components/Sidebar';
import { Canvas } from './components/Canvas';
import { ChatPanel } from './components/ChatPanel';
import { ModelManager } from './components/ModelManager';
import { agentEngine } from './engine/agent-engine';

interface ErrorBoundaryProps { children: ReactNode; }
interface ErrorBoundaryState { hasError: boolean; error: Error | null; }

class AppErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, error: null };
  }
  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }
  componentDidCatch(error: Error, info: any) {
    console.error('[AppErrorBoundary] Render error caught:', error, info?.componentStack || '');
    try {
      if ((agentEngine as any)?.cancel) (agentEngine as any).cancel();
    } catch (_) { /* noop */ }
    try {
      persistStoreNow();
    } catch (_) { /* noop */ }
  }
  private handleReset = () => {
    this.setState({ hasError: false, error: null });
    try { setStore({ modelStatus: 'ready', agentRunning: false }); } catch (_) { /* noop */ }
  };
  render() {
    if (this.state.hasError) {
      return (
        <div style={{
          width: '100%', height: '100%',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          padding: 24,
        }}>
          <div style={{
            maxWidth: 520,
            padding: 20,
            borderRadius: 12,
            background: 'rgba(20,28,34,0.85)',
            border: '1px solid rgba(240,128,128,0.3)',
            color: 'var(--text, #e4eef3)',
            fontFamily: 'system-ui, sans-serif',
          }}>
            <h3 style={{ margin: '0 0 10px', color: 'var(--accent-red, #f8afa6)' }}>
              ⚠ Render Error Caught
            </h3>
            <pre style={{
              margin: 0, padding: 10,
              whiteSpace: 'pre-wrap', wordBreak: 'break-word',
              fontSize: 11, lineHeight: 1.5,
              background: 'rgba(0,0,0,0.25)',
              borderRadius: 6,
            }}>
              {this.state.error?.stack || this.state.error?.message || String(this.state.error)}
            </pre>
            <div style={{ marginTop: 14, display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
              <button
                onClick={this.handleReset}
                style={{
                  padding: '6px 14px',
                  borderRadius: 6,
                  border: '1px solid rgba(169,197,207,0.3)',
                  background: 'rgba(169,197,207,0.15)',
                  color: 'var(--accent-cyan, #a9c5cf)',
                  fontSize: 12, fontWeight: 600,
                  cursor: 'pointer',
                }}
              >
                Recover UI
              </button>
            </div>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}

export const App: React.FC = () => {
  const [store] = useStore();

  useEffect(() => {
    // The visible WebKitGTK surface owns model selection in embedded mode.
    // Electron still mounts the same React tree so it can expose AgentEngine
    // and WebLLM to main.cjs, but it must not run the normal UI warm-up: that
    // would start loading the persisted/default model before the GJS request
    // arrives and serialize every subsequent selection behind the wrong load.
    const isElectronWorker = Boolean((window as any).__hyprcandyElectronAgent);

    bridge.onThemeChange((cssVars) => {
      console.log('Applied live theme variables from GTK4:', Object.keys(cssVars).length);
      window.dispatchEvent(new CustomEvent('matugen_theme_changed', { detail: cssVars }));
    });

    const onToggleSidebar = () => storeActions.toggleSidebar();
    const onToggleModel = () => setStore(prev => ({ modelManagerOpen: !prev.modelManagerOpen }));
    const onNewChat = () => storeActions.createSession();
    const onOpenFile = (e: any) => {
      if (e.detail?.path) {
        try {
          storeActions.openFileByPath(e.detail.path);
        } catch (err) {
          console.warn('agent_open_file handler error:', err);
        }
      }
    };

    const onUnhandledRejection = (ev: PromiseRejectionEvent) => {
      console.warn('[App] unhandledrejection:', ev.reason);
      const msg = ev?.reason?.message || String(ev?.reason || 'unknown');
      if (msg.includes('AbortError') || msg.includes('The user aborted a request')) {
        ev.preventDefault();
        return;
      }
      try {
        setStore(prev => prev.agentRunning
          ? { agentRunning: false, modelStatus: 'error', downloadProgress: { progress: 0, text: `Generation error: ${msg.slice(0, 120)}` } }
          : {});
      } catch (_) { /* noop */ }
    };

    const onUncaughtError = (ev: ErrorEvent) => {
      console.error('[App] error:', ev.error || ev.message);
    };

    const onBeforeUnload = () => {
      try {
        persistStoreNow();
        agentEngine.cancel();
      } catch (_) { /* noop */ }
    };

    window.addEventListener('agent_toggle_sidebar', onToggleSidebar);
    window.addEventListener('agent_toggle_model_manager', onToggleModel);
    window.addEventListener('agent_new_chat', onNewChat);
    window.addEventListener('agent_open_file', onOpenFile);
    window.addEventListener('unhandledrejection', onUnhandledRejection);
    window.addEventListener('error', onUncaughtError);
    window.addEventListener('beforeunload', onBeforeUnload);

    // Do not preload the persisted/default model here. This effect runs again
    // when the launcher agent surface is recreated or reactivated, and native
    // llama-server must remain OFF until the explicit header toggle is used.

    return () => {
      window.removeEventListener('agent_toggle_sidebar', onToggleSidebar);
      window.removeEventListener('agent_toggle_model_manager', onToggleModel);
      window.removeEventListener('agent_new_chat', onNewChat);
      window.removeEventListener('agent_open_file', onOpenFile);
      window.removeEventListener('unhandledrejection', onUnhandledRejection);
      window.removeEventListener('error', onUncaughtError);
      window.removeEventListener('beforeunload', onBeforeUnload);
      try { persistStoreNow(); } catch (_) { /* noop */ }
    };
  }, []);

  return (
    <AppErrorBoundary>
      <div className="app-container">
        <Header />

        <div className="workspace-container">
          <main className="canvas-main-area">
            <Canvas />
          </main>

          <aside
            className={`sidebar-panel ${store.sidebarVisible ? 'sidebar-visible' : ''}`}
            style={{ width: `${store.sidebarWidth}px` }}
          >
            <Sidebar />
          </aside>

          <aside
            className={`chat-panel ${store.chatVisible ? 'chat-visible' : ''}`}
            style={{ width: `${store.chatWidth}px` }}
          >
            <ChatPanel />
          </aside>
        </div>

        <ModelManager />
      </div>
    </AppErrorBoundary>
  );
};
