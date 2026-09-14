/**
 * GJS <-> React WebKitGTK Bridge
 * Handles asynchronous IPC with HyprCandyDock GJS host.
 *
 * Runtime mode detection:
 * - ELECTRON mode  : window.__hyprcandyElectronAgent === true (set by preload.cjs)
 *                    Full WebGPU via Chromium. WebLLM runs locally in this process.
 * - WEBKIT UI mode : window.__hyprcandyElectronAgent is not set (WebKitGTK context)
 *                    No real WebGPU. All WebLLM inference is delegated to the Electron
 *                    worker process via GJS bridge and comes back through
 *                    __hyprcandy_agent_dispatch as worker_progress / worker_token /
 *                    worker_done / worker_error messages.
 */

export interface HostMessage {
  id?: string;
  type: string;
  action?: string;
  payload?: any;
  error?: string;
}

type MessageCallback = (payload: any) => void;

// ── Electron / WebKit runtime detection ──────────────────────────────────────
// In the Electron renderer (preload.cjs) window.__hyprcandyElectronAgent = true.
// In the WebKitGTK UI renderer this flag is absent → delegate mode.
export function isElectronMode(): boolean {
  return typeof window !== 'undefined' && !!(window as any).__hyprcandyElectronAgent;
}

class AgentBridge {
  private pendingRequests = new Map<string, { resolve: (val: any) => void; reject: (err: any) => void }>();
  private themeListeners: Array<(cssVars: Record<string, string>) => void> = [];
  private hasWebKit = false;

  constructor() {
    this.hasWebKit = typeof window !== 'undefined' && 
      !!(window as any).webkit?.messageHandlers?.agent;

    if (typeof window !== 'undefined') {
      // Direct hook called by GJS run_javascript / evaluate_javascript
      (window as any).__hyprcandy_agent_dispatch = (msg: HostMessage) => {
        this.handleIncoming(msg);
      };

      // CustomEvent listener fallback
      window.addEventListener('agent_host_message', (e: any) => {
        if (e.detail) {
          this.handleIncoming(e.detail);
        }
      });
    }
  }

  private handleIncoming(msg: HostMessage) {
    if (msg.type === 'runtime_config' && msg.payload) {
      (window as any).__hyprcandyNativeProvider = msg.payload.inferenceProvider || '';
      (window as any).__hyprcandyLlamaEnabled = !!msg.payload.llamaEnabled;
      if (msg.payload.homeDir) (window as any).__hyprcandyHome = msg.payload.homeDir;
      // The frontend bundle has no way to know the real user's HOME at
      // build time, so projectPath starts unset until GJS reports the real
      // one here — including on a fresh install where nothing's been
      // opened yet. Once the user opens a real project via the folder
      // picker, that choice is persisted and this no longer applies.
      const store = (window as any).agent?.store?.();
      if (!store?.projectPath && msg.payload.defaultProjectRoot) {
        (window as any).agent?.setStore?.({ projectPath: msg.payload.defaultProjectRoot });
      }
      window.dispatchEvent(new CustomEvent('agent_runtime_config', { detail: msg.payload }));
      return;
    }
    if (msg.type === 'llama_state' && msg.payload) {
      (window as any).__hyprcandyLlamaEnabled = !!msg.payload.enabled;
      window.dispatchEvent(new CustomEvent('agent_llama_state', { detail: msg.payload }));
      return;
    }
    if (msg.type === 'theme_update' && msg.payload) {
      this.applyTheme(msg.payload);
      // Store raw vars for Monaco to read directly (avoids getComputedStyle timing race)
      (window as any).__hyprcandyThemeVars = msg.payload;
      // Signal Monaco to re-register the matugen theme with fresh injected colors
      window.dispatchEvent(new CustomEvent('matugen_theme_changed'));
      this.themeListeners.forEach(cb => cb(msg.payload));
      return;
    }

    if (msg.type === 'user_prompt' && msg.payload) {
      window.dispatchEvent(new CustomEvent('agent_user_prompt', { detail: msg.payload }));
      return;
    }

    if (msg.type === 'toggle_sidebar') {
      window.dispatchEvent(new CustomEvent('agent_toggle_sidebar'));
      return;
    }

    if (msg.type === 'toggle_model_manager') {
      window.dispatchEvent(new CustomEvent('agent_toggle_model_manager'));
      return;
    }

    if (msg.type === 'new_chat') {
      window.dispatchEvent(new CustomEvent('agent_new_chat'));
      return;
    }

    // ── Native llama-server progress (Electron → GJS → WebKit) ───────────────
    if (msg.type === 'llama_progress') {
      window.dispatchEvent(new CustomEvent('agent_llama_progress', { detail: msg.payload }));
      return;
    }

    // ── Worker inference relay messages (Electron → GJS → WebKit) ────────────
    if (msg.type === 'worker_progress') {
      // Forward model loading progress to the store (imported lazily to avoid
      // circular dependencies; store.ts does not import bridge.ts).
      window.dispatchEvent(new CustomEvent('agent_worker_progress', { detail: msg.payload }));
      return;
    }
    if (msg.type === 'worker_token') {
      window.dispatchEvent(new CustomEvent('agent_worker_token', { detail: msg.payload }));
      return;
    }
    if (msg.type === 'worker_done') {
      window.dispatchEvent(new CustomEvent('agent_worker_done', { detail: msg.payload }));
      return;
    }
    if (msg.type === 'worker_error') {
      window.dispatchEvent(new CustomEvent('agent_worker_error', { detail: msg.payload }));
      return;
    }
    if (msg.type === 'worker_model_ready') {
      window.dispatchEvent(new CustomEvent('agent_worker_model_ready', { detail: msg.payload }));
      return;
    }
    if (msg.type === 'worker_cache_status') {
      window.dispatchEvent(new CustomEvent('agent_worker_cache_status', { detail: msg.payload }));
      return;
    }
    if (msg.type === 'worker_cache_cleared') {
      window.dispatchEvent(new CustomEvent('agent_worker_cache_cleared', { detail: msg.payload }));
      return;
    }
    // ─────────────────────────────────────────────────────────────────────────

    if (msg.id && this.pendingRequests.has(msg.id)) {
      const { resolve, reject } = this.pendingRequests.get(msg.id)!;
      this.pendingRequests.delete(msg.id);
      if (msg.error) {
        reject(new Error(msg.error));
      } else {
        resolve(msg.payload);
      }
    }
  }

  private postToHost(action: string, payload: any = {}): Promise<any> {
    const id = 'req_' + Math.random().toString(36).substring(2, 9) + '_' + Date.now();
    
    return new Promise((resolve, reject) => {
      this.pendingRequests.set(id, { resolve, reject });

      const envelope = { id, action, payload };

      if (this.hasWebKit) {
        try {
          (window as any).webkit.messageHandlers.agent.postMessage(JSON.stringify(envelope));
        } catch (e: any) {
          this.pendingRequests.delete(id);
          reject(new Error(`Failed to post to WebKit messageHandler: ${e.message}`));
        }
      } else {
        // Fallback / Mock mode when outside WebKitGTK
        this.handleDevFallback(action, payload, id);
      }
    });
  }

  public llamaRequest(action: string, payload: any = {}): Promise<any> {
    return this.postToHost(action, payload);
  }

  private handleDevFallback(action: string, payload: any, id: string) {
    setTimeout(async () => {
      try {
        if (action === 'web_search') {
          // Direct fetch to SearXNG if running locally
          try {
            const res = await fetch(`http://127.0.0.1:8080/search?q=${encodeURIComponent(payload.query)}&format=json`);
            if (res.ok) {
              const data = await res.json();
              this.handleIncoming({ id, type: 'response', payload: data.results?.slice(0, 5) || [] });
              return;
            }
          } catch {
            // fallback mock search
          }
          this.handleIncoming({
            id,
            type: 'response',
            payload: [
              { title: 'Search result for: ' + payload.query, url: 'https://github.com/searxng/searxng', content: 'SearXNG local metasearch response.' }
            ]
          });
        } else if (action === 'list_directory') {
          this.handleIncoming({
            id,
            type: 'response',
            payload: [
              { name: 'app-launcher.js', isDir: false, size: 1775115 },
              { name: 'config.js', isDir: false, size: 8986 },
              { name: 'searxng-settings', isDir: true, size: 0 },
              { name: 'style.css', isDir: false, size: 7385 }
            ]
          });
        } else if (action === 'read_file') {
          this.handleIncoming({ id, type: 'response', payload: `// Mock content for ${payload.path}` });
        } else if (action === 'write_file') {
          this.handleIncoming({ id, type: 'response', payload: { success: true } });
        } else if (action === 'exec_command') {
          this.handleIncoming({ id, type: 'response', payload: { exitCode: 0, stdout: `Executed: ${payload.command}`, stderr: '' } });
        } else if (action === 'file_dialog') {
          this.handleIncoming({ id, type: 'response', payload: null });
        } else {
          this.handleIncoming({ id, type: 'response', payload: { status: 'mock_ok' } });
        }
      } catch (err: any) {
        this.handleIncoming({ id, type: 'response', error: err.message });
      }
    }, 100);
  }

  public applyTheme(cssVars: Record<string, string>) {
    const root = document.documentElement;

    // ── Apply all raw variables ─────────────────────────────────────────
    for (const [key, value] of Object.entries(cssVars)) {
      if (key.startsWith('matugen_')) {
        // matugen_primary → --matugen-primary
        const varName = '--matugen-' + key.slice(8).replace(/_/g, '-');
        root.style.setProperty(varName, value);
      } else if (key.startsWith('wallust_')) {
        // wallust_color3 → --wallust-color3
        const varName = '--wallust-' + key.slice(8).replace(/_/g, '-');
        root.style.setProperty(varName, value);
      } else {
        // Raw matugen token (legacy, no prefix) → --matugen-*
        const varName = '--matugen-' + key.replace(/_/g, '-');
        root.style.setProperty(varName, value);
      }
    }

    // ── Derive semantic accent variables from live tokens ───────────────
    // Primary accent (cyan) = matugen primary_fixed_dim (perceptually bright)
    const primaryFixedDim = cssVars['matugen_primary_fixed_dim'] || cssVars['primary_fixed_dim'];
    if (primaryFixedDim) {
      root.style.setProperty('--accent-cyan', primaryFixedDim);
      root.style.setProperty('--text-accent', primaryFixedDim);
    }

    // Yellow accent = wallust color3 (amber/orange from the terminal palette)
    const wallustColor3 = cssVars['wallust_color3'];
    if (wallustColor3) {
      root.style.setProperty('--accent-yellow', wallustColor3);
    }

    // Green = wallust color2 (teal-green in this palette)
    const wallustColor2 = cssVars['wallust_color2'];
    if (wallustColor2) {
      root.style.setProperty('--accent-green', wallustColor2);
    }

    // Cyan variant = wallust color4 (bright teal)
    const wallustColor4 = cssVars['wallust_color4'];
    if (wallustColor4 && !primaryFixedDim) {
      root.style.setProperty('--accent-cyan', wallustColor4);
    }

    // Purple/tertiary = matugen tertiary token
    const tertiary = cssVars['matugen_tertiary'] || cssVars['tertiary'];
    if (tertiary) {
      root.style.setProperty('--accent-purple', tertiary);
    }

    // Surface / bg tokens from matugen surface containers
    const surfaceContainerHigh = cssVars['matugen_surface_container_high'] || cssVars['surface_container_high'];
    if (surfaceContainerHigh) {
      root.style.setProperty('--bg-block', surfaceContainerHigh + 'b3'); // ~70% opacity
    }
    const surfaceBright = cssVars['matugen_surface_bright'] || cssVars['surface_bright'];
    if (surfaceBright) {
      root.style.setProperty('--bg-card', surfaceBright + '99');
    }

    // Text tokens from on_surface
    const onSurface = cssVars['matugen_on_surface'] || cssVars['on_surface'];
    if (onSurface) root.style.setProperty('--text-primary', onSurface);
    const onSurfaceVariant = cssVars['matugen_on_surface_variant'] || cssVars['on_surface_variant'];
    if (onSurfaceVariant) root.style.setProperty('--text-secondary', onSurfaceVariant);
  }

  public onThemeChange(cb: (cssVars: Record<string, string>) => void) {
    this.themeListeners.push(cb);
  }

  /* Native Host Tools */

  public execCommand(command: string, cwd?: string): Promise<{ exitCode: number; stdout: string; stderr: string }> {
    return this.postToHost('exec_command', { command, cwd });
  }

  public readFile(path: string, offset?: number, limit?: number): Promise<string> {
    return this.postToHost('read_file', { path, offset, limit });
  }

  public writeFile(path: string, content: string): Promise<{ success: boolean }> {
    return this.postToHost('write_file', { path, content });
  }

  public listDirectory(path: string): Promise<Array<{ name: string; isDir: boolean; size: number }>> {
    return this.postToHost('list_directory', { path });
  }

  public openFileDialog(options?: { title?: string; directory?: boolean; currentFolder?: string }): Promise<string | null> {
    return this.postToHost('file_dialog', options || {});
  }

  public webSearch(query: string): Promise<Array<{ title: string; url: string; content?: string }>> {
    return this.postToHost('web_search', { query });
  }

  public fetchUrl(url: string): Promise<{ url: string; text: string }> {
    return this.postToHost('fetch_url', { url });
  }

  public checkSearxStatus(): Promise<{ running: boolean }> {
    return this.postToHost('searxng_status');
  }

  public startSearx(): Promise<{ success: boolean }> {
    return this.postToHost('searxng_start');
  }

  public setWorkspaceStartupState(enabled: boolean): Promise<{ enabled: boolean }> {
    return this.postToHost('workspace_startup_state', { enabled });
  }

  /**
   * Take a screenshot using grim (Wayland) and return the saved file path.
   * @param region Optional region string "x,y,w,h"  (passed directly to grim -g)
   */
  public takeScreenshot(region?: string): Promise<{ path: string; filename: string }> {
    return this.postToHost('take_screenshot', region ? { region } : {});
  }
  /**
   * Fire-and-forget message to the GJS host WITHOUT waiting for a response.
   * Used for inference delegation: load_model / chat requests that produce
   * streaming responses delivered through separate worker_* dispatch events.
   */
  public fireWorkerRequest(action: string, payload: any = {}): void {
    const envelope = JSON.stringify({ action, payload });
    if (this.hasWebKit) {
      try {
        (window as any).webkit.messageHandlers.agent.postMessage(envelope);
      } catch (e: any) {
        console.warn('[bridge] fireWorkerRequest failed:', e.message);
      }
    }
  }
}

export const bridge = new AgentBridge();
