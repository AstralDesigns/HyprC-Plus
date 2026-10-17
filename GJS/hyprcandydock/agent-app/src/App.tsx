import React, { Component, useEffect, useRef, ReactNode } from 'react';
import { useStore, setStore, getStore, storeActions, PRESET_MODELS, persistStoreNow } from './store';
import { bridge } from './bridge';
import { Header } from './components/Header';
import { Sidebar } from './components/Sidebar';
import { Canvas } from './components/Canvas';
import { ChatPanel } from './components/ChatPanel';
import { ModelManager } from './components/ModelManager';
import { ProfileModal } from './components/ProfileModal';
import { MemoryPanel } from './components/MemoryPanel';
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
  const appRootRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    storeActions.refreshPendingFiles();
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

    // §3.1 (rev. Option A) — Ctrl/Cmd+N starts a new Quest from the keyboard,
    // mirroring the ChatPanel Quests dropdown and the agent_new_chat host event.
    const onKeyDown = (ev: KeyboardEvent) => {
      if ((ev.ctrlKey || ev.metaKey) && (ev.key === 'n' || ev.key === 'N')) {
        ev.preventDefault();
        storeActions.createSession();
        return;
      }
      // Ctrl+Tab / Ctrl+Shift+Tab cycles the active canvas tab. Handled at the
      // window level so it works regardless of whether focus is in the editor,
      // a tab, or the chat composer.
      if (ev.ctrlKey && ev.key === 'Tab') {
        ev.preventDefault();
        storeActions.cycleActivePane(ev.shiftKey ? -1 : 1);
        return;
      }
      // Ctrl+O opens a folder via the native picker.
      if ((ev.ctrlKey || ev.metaKey) && (ev.key === 'o' || ev.key === 'O')) {
        ev.preventDefault();
        storeActions.openFolderDialog();
        return;
      }
      // Ctrl+1 / Ctrl+2 toggle the floating side panels (same key shows/hides).
      if ((ev.ctrlKey || ev.metaKey) && ev.key === '1') {
        ev.preventDefault();
        storeActions.toggleSidebar();
        return;
      }
      if ((ev.ctrlKey || ev.metaKey) && ev.key === '2') {
        ev.preventDefault();
        storeActions.toggleChat();
      }
    };
    window.addEventListener('keydown', onKeyDown);

    // The host webview only receives key events once it holds keyboard focus,
    // which the compositor grants lazily. Give the page a focused element from
    // mount so the global keybinds above fire at workspace startup, before the
    // user clicks into a canvas (which is otherwise what pulls focus in).
    const focusRoot = () => { try { appRootRef.current?.focus({ preventScroll: true }); } catch { /* noop */ } };
    focusRoot();
    requestAnimationFrame(focusRoot);
    setTimeout(focusRoot, 150);

    // Auto-activate last active Cloud tab model/provider if saved from previous session.
    {
      const autoActivateCloudModel = async () => {
        const current = getStore();
        if (current.inferenceMode === 'byok' && current.byokProvider) {
          const providerId = current.byokProvider;
          const modelId = current.byokModel || current.activeModel || '';
          try {
            let key: string | null = current.byokKeys[providerId] || null;
            if (!key) {
              key = await bridge.lookupSecret(providerId);
            }
            if (key) {
              for (let attempt = 0; attempt < 8; attempt++) {
                try {
                  await bridge.runtimeRequest('/api/byok/set', {
                    provider: providerId,
                    api_key: key,
                    set_active: true,
                  });
                  await bridge.runtimeRequest(`/api/byok/activate/${providerId}`);
                  break;
                } catch {
                  await new Promise(r => setTimeout(r, 600));
                }
              }
              setStore({
                inferenceMode: 'byok',
                byokProvider: providerId,
                byokModel: modelId,
                activeModel: modelId,
                modelStatus: 'ready',
                byokKeys: { ...current.byokKeys, [providerId]: key },
              });
              bridge.notifyModelStatus(true, modelId);
              console.log(`[agent-app] Auto-activated last cloud provider ${providerId} (${modelId})`);
            }
          } catch (err: any) {
            console.warn('[agent-app] Could not auto-activate cloud model:', err?.message || err);
          }
        } else if (current.inferenceMode === 'cloud' && current.cloudModel) {
          setStore({
            inferenceMode: 'cloud',
            modelStatus: 'ready',
            activeModel: current.cloudModel,
          });
          bridge.notifyModelStatus(true, current.cloudModel);
        }
      };
      autoActivateCloudModel();
    }

    return () => {
      window.removeEventListener('agent_toggle_sidebar', onToggleSidebar);
      window.removeEventListener('agent_toggle_model_manager', onToggleModel);
      window.removeEventListener('agent_new_chat', onNewChat);
      window.removeEventListener('agent_open_file', onOpenFile);
      window.removeEventListener('unhandledrejection', onUnhandledRejection);
      window.removeEventListener('error', onUncaughtError);
      window.removeEventListener('beforeunload', onBeforeUnload);
      window.removeEventListener('keydown', onKeyDown);
      try { persistStoreNow(); } catch (_) { /* noop */ }
    };
  }, []);

  const workspaceRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = workspaceRef.current;
    if (!el) return;
    const enforceZeroScrollLeft = () => {
      if (el.scrollLeft !== 0) el.scrollLeft = 0;
    };
    el.addEventListener('scroll', enforceZeroScrollLeft);
    return () => el.removeEventListener('scroll', enforceZeroScrollLeft);
  }, []);

  // External-change detection. The inotify feed (fs_drain, separate effect
  // below) is the instant path; pollFilesystem is the mtime fallback that also
  // covers files outside the watched set. Neither is gated on
  // document.hasFocus() — in an embedded QtWebEngine view that flag is
  // unreliable and was why a background edit could go unnoticed. git status
  // churn stays focus-gated. refreshGitStatus/pollFilesystem coalesce.
  useEffect(() => {
    const tick = () => {
      storeActions.pollFilesystem();
      if (document.hasFocus() && getStore().projectPath) storeActions.refreshGitStatus();
    };
    tick();
    const id = setInterval(tick, 5000);
    const onFocus = () => { storeActions.pollFilesystem(); storeActions.refreshGitStatus(); };
    window.addEventListener('focus', onFocus);
    return () => { clearInterval(id); window.removeEventListener('focus', onFocus); };
  }, []);

  // Drain buffered inotify events from the host watcher and apply them. Cheap
  // (the server returns a small list), so a short tick + focus gives near-
  // real-time updates without per-file polling.
  useEffect(() => {
    let busy = false;
    const drain = async () => {
      if (busy) return;
      busy = true;
      try {
        const res = await bridge.fsDrain();
        const paths = res?.paths;
        if (paths && paths.length) await storeActions.handleFsEvents(paths);
      } catch { /* loopback offline / stale server: the mtime poll covers it */ }
      finally { busy = false; }
    };
    const id = setInterval(drain, 1200);
    window.addEventListener('focus', drain);
    return () => { clearInterval(id); window.removeEventListener('focus', drain); };
  }, []);

  // Gumroad Agents subscription re-validation. Hourly (and once at boot) verify
  // the stored key: an active signal refreshes the grace clock. A confirmed
  // inactive key keeps the UI unlocked for a 24h grace — long enough for Gumroad
  // auto-renewal or a re-entered key to flip it back — then clears the license,
  // which re-gates the Agents tab and chat panel (both gate on byokLicenseKey).
  // Transient network errors never re-gate; only a confirmed-inactive status
  // past the grace window does, so an offline blip can't lock out a payer.
  useEffect(() => {
    const GRACE_MS = 24 * 60 * 60 * 1000;
    const CHECK_MS = 60 * 60 * 1000;
    let busy = false;
    const recheck = async () => {
      const key = getStore().byokLicenseKey;
      if (!key || busy) return;
      busy = true;
      try {
        const res = await bridge.runtimeRequest('/api/license/verify', { license_key: key });
        if (res?.ok && res.active !== false) {
          setStore({ licenseLastActiveAt: Date.now() });
        } else if (res?.ok && res.active === false) {
          const last = getStore().licenseLastActiveAt || 0;
          if (Date.now() - last > GRACE_MS) {
            setStore({ byokLicenseKey: '', byokLicenseInstanceId: '', licenseLastActiveAt: 0 });
          }
        }
        // !res (unreachable / offline): leave state untouched, retry next tick.
      } catch { /* offline: grace clock untouched */ }
      finally { busy = false; }
    };
    recheck();
    const id = setInterval(recheck, CHECK_MS);
    return () => clearInterval(id);
  }, []);

  return (
    <AppErrorBoundary>
      <div className="app-container" ref={appRootRef} tabIndex={-1}>
        <Header />

        <div className="workspace-container" ref={workspaceRef}>
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
        <ProfileModal />
        <MemoryPanel />
      </div>
    </AppErrorBoundary>
  );
};
