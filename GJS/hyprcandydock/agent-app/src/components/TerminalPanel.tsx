/**
 * TerminalPanel — embedded xterm.js PTY terminal with multi-tab support.
 *
 * Mounts at the bottom of the workspace-container.
 * Styled with Kitty / Wallust palette and CaskaydiaCove Nerd Font Mono so it
 * blends with the host terminal experience.
 *
 * Architecture:
 *   • Supports multiple concurrent terminal tabs, each running its own PTY session.
 *   • Left header starts directly with the tab chips (no redundant icon/title).
 *   • Tab chips show a close button only when >1 tab exists.
 *   • Right header includes '+' toggle to spawn a new tab with auto-focus,
 *     along with clear, restart, and panel toggle controls.
 *   • Output and processes persist across hiding/showing (display: none).
 */

import React, { useEffect, useRef, useState, useCallback } from 'react';
import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import { ImageAddon } from '@xterm/addon-image';
import '@xterm/xterm/css/xterm.css';
import { X, RotateCcw, Trash2, Plus, Terminal as TerminalIcon } from 'lucide-react';
import { useStore, storeActions } from '../store';
import { bridge } from '../bridge';

// ── Wallust → xterm theme helper ─────────────────────────────────────────────
function buildXtermTheme(cssVars: Record<string, string>) {
  const m = (k: string) => {
    const clean = k.replace(/-/g, '_');
    const hyphen = k.replace(/_/g, '-');
    return (
      cssVars[`matugen_${clean}`] ||
      cssVars[`matugen_${hyphen}`] ||
      cssVars[clean] ||
      cssVars[hyphen] ||
      (typeof document !== 'undefined'
        ? getComputedStyle(document.documentElement).getPropertyValue(`--matugen-${hyphen}`).trim()
        : '') ||
      undefined
    );
  };
  const w = (n: number) => {
    return (
      cssVars[`wallust_color${n}`] ||
      cssVars[`color${n}`] ||
      (typeof document !== 'undefined'
        ? getComputedStyle(document.documentElement).getPropertyValue(`--wallust-color${n}`).trim()
        : '') ||
      undefined
    );
  };

  const surface = m('surface');
  const surfaceTint = m('surface_tint');
  const primaryFixedDim = m('primary_fixed_dim');
  const background = m('background');

  return {
    background:   surface,
    foreground:   surfaceTint || m('on_surface') || w(7),
    cursor:       surfaceTint || primaryFixedDim || w(6),
    cursorAccent: surface,
    selectionBackground: primaryFixedDim ? `${primaryFixedDim}44` : (w(4) ? `${w(4)}44` : undefined),
    black:        background || w(0),
    red:          w(1),
    green:        w(2),
    yellow:       w(3),
    blue:         w(4),
    magenta:      w(5),
    cyan:         w(6),
    white:        surfaceTint || w(7),
    brightBlack:  surfaceTint || w(8),
    brightRed:    w(9),
    brightGreen:  w(10),
    brightYellow: w(11),
    brightBlue:   w(12),
    brightMagenta:w(13),
    brightCyan:   w(14),
    brightWhite:  w(15),
  };
}

function getThemeVars(): Record<string, string> {
  return (window as any).__hyprcandyThemeVars || {};
}

interface TerminalTab {
  id: string;
  name: string;
}

interface TerminalInstance {
  term: Terminal;
  fit: FitAddon;
  sessionRef: string | null;
  sseRef: EventSource | null;
}

export const TerminalPanel: React.FC = () => {
  const [store] = useStore();
  const [tabs, setTabs] = useState<TerminalTab[]>([
    { id: 'term_1', name: 'Terminal 1' }
  ]);
  const [activeTabId, setActiveTabId] = useState<string>('term_1');
  const nextNumRef = useRef(2);

  const panelRef        = useRef<HTMLDivElement>(null);
  const instancesRef    = useRef<Record<string, TerminalInstance>>({});
  const startingTabsRef = useRef<Record<string, boolean>>({});
  const resizingRef     = useRef(false);
  const startYRef       = useRef(0);
  const startHRef       = useRef(0);

  // ── Hover-to-focus listener ───────────────────────────────────────────────
  // Moving the mouse back into the terminal area transfers cursor focus into
  // the active terminal session, matching the Monaco editor's hover-to-focus behavior.
  const handleHoverFocus = useCallback(() => {
    if (!store.terminalVisible) return;
    try {
      const ae = document.activeElement as HTMLElement | null;
      const panel = panelRef.current;
      if (panel && ae && panel.contains(ae)) return;

      // If focus is in Monaco editor or non-input elements, transfer focus to terminal
      if (ae?.closest('.monaco-editor')) {
        ae.blur();
      } else if (ae && (ae.tagName === 'INPUT' || ae.tagName === 'TEXTAREA' || ae.isContentEditable)) {
        // If user is actively typing in chat composer or sidebar, do not yank focus
        const isHidden = ae.closest('.sidebar-panel:not(.sidebar-visible)') ||
                         ae.closest('.chat-panel:not(.chat-visible)') ||
                         (ae.offsetWidth === 0 && ae.offsetHeight === 0);
        if (!isHidden) return;
        ae.blur();
      }

      const inst = instancesRef.current[activeTabId];
      if (inst) {
        inst.term.focus();
        const ta = panel?.querySelector('.xterm-helper-textarea') as HTMLTextAreaElement | null;
        if (ta) ta.focus({ preventScroll: true });
      }
    } catch { /* noop */ }
  }, [store.terminalVisible, activeTabId]);

  useEffect(() => {
    const panel = panelRef.current;
    if (!panel) return;
    panel.addEventListener('mouseenter', handleHoverFocus);
    return () => panel.removeEventListener('mouseenter', handleHoverFocus);
  }, [handleHoverFocus]);

  // ── Spawn a tab session ───────────────────────────────────────────────────
  const spawnTabSession = useCallback(async (tabId: string) => {
    if (instancesRef.current[tabId] || startingTabsRef.current[tabId]) return;
    startingTabsRef.current[tabId] = true;

    try {
      const mountEl = document.getElementById(`terminal-mount-${tabId}`) as HTMLDivElement | null;
      if (!mountEl) return;

      const themeVars = getThemeVars();
      const term = new Terminal({
        fontFamily: 'CaskaydiaCove Nerd Font Mono, JetBrains Mono, Fira Code, monospace',
        fontSize: 13,
        lineHeight: 1.2,
        cursorStyle: 'bar',
        cursorBlink: true,
        allowTransparency: true,
        theme: buildXtermTheme(themeVars),
        scrollback: 2000,
        convertEol: true,
      });

      // Intercept Ctrl+3, Ctrl+1, Ctrl+2 inside xterm so keystrokes aren't swallowed
      term.attachCustomKeyEventHandler((ev: KeyboardEvent) => {
        if (ev.type === 'keydown' && (ev.ctrlKey || ev.metaKey)) {
          if (ev.key === '3' || ev.code === 'Digit3') {
            storeActions.toggleTerminal();
            return false;
          }
          if (ev.key === '1' || ev.code === 'Digit1') {
            storeActions.toggleSidebar();
            return false;
          }
          if (ev.key === '2' || ev.code === 'Digit2') {
            storeActions.toggleChat();
            return false;
          }
        }
        return true;
      });

      const fit = new FitAddon();
      term.loadAddon(fit);

      const imageAddon = new ImageAddon({
        sixelSupport: true,
        sixelScrolling: true,
        iipSupport: true,
        enableSizeReports: true,
        storageLimit: 128,
        showPlaceholder: true,
      });
      term.loadAddon(imageAddon);

      mountEl.innerHTML = '';
      term.open(mountEl);

      const inst: TerminalInstance = {
        term,
        fit,
        sessionRef: null,
        sseRef: null,
      };
      instancesRef.current[tabId] = inst;

      // Allow DOM to settle before measuring & focus
      requestAnimationFrame(() => {
        try {
          fit.fit();
          term.scrollToBottom();
          term.focus();
        } catch (_) {}
      });

      // Spawn server-side PTY
      let sessionId: string;
      try {
        const cols = term.cols || 80;
        const rows = term.rows || 24;
        const res = await bridge.ptySpawn({ cols, rows });
        sessionId = res?.sessionId;
        if (!sessionId) {
          term.writeln('\x1b[31mFailed to start terminal: host did not return a session ID.\x1b[0m');
          return;
        }
      } catch (e: any) {
        term.writeln(`\x1b[31mFailed to start terminal: ${e?.message || e}\x1b[0m`);
        return;
      }
      inst.sessionRef = sessionId;

      // SSE stdout stream
      const streamUrl = bridge.getPtyStreamUrl(sessionId);
      const sse = new EventSource(streamUrl);
      inst.sseRef = sse;

      let initialBurst = true;
      const initialBurstTimer = setTimeout(() => { initialBurst = false; }, 3500);

      sse.onmessage = (ev) => {
        try {
          const bytes = atob(ev.data);
          const u8 = new Uint8Array(bytes.length);
          for (let i = 0; i < bytes.length; i++) u8[i] = bytes.charCodeAt(i);
          term.write(u8, () => {
            if (initialBurst) {
              term.scrollToBottom();
            }
          });
        } catch { /* malformed chunk — ignore */ }
      };

      sse.onerror = (err) => {
        console.warn(`[TerminalPanel] SSE stream error for ${tabId}:`, err);
      };

      sse.addEventListener('close', () => {
        clearTimeout(initialBurstTimer);
        term.writeln('\r\n\x1b[33m[session closed]\x1b[0m');
        if (inst.sseRef) {
          inst.sseRef.close();
          inst.sseRef = null;
        }
        inst.sessionRef = null;
      });

      // Keyboard → PTY write
      term.onData((data) => {
        if (inst.sessionRef) {
          bridge.ptyWrite(inst.sessionRef, data).catch(() => {});
        }
      });
    } finally {
      startingTabsRef.current[tabId] = false;
    }
  }, []);

  // ── Kill single tab instance ──────────────────────────────────────────────
  const killTabInstance = useCallback((tabId: string) => {
    const inst = instancesRef.current[tabId];
    if (inst) {
      if (inst.sseRef) {
        try { inst.sseRef.close(); } catch (_) {}
        inst.sseRef = null;
      }
      if (inst.sessionRef) {
        bridge.ptyKill(inst.sessionRef).catch(() => {});
        inst.sessionRef = null;
      }
      try { inst.term.dispose(); } catch (_) {}
      delete instancesRef.current[tabId];
    }
    delete startingTabsRef.current[tabId];
  }, []);

  // ── Kill all instances ────────────────────────────────────────────────────
  const killAllSessions = useCallback(() => {
    Object.keys(instancesRef.current).forEach(killTabInstance);
  }, [killTabInstance]);

  // ── Active tab lifecycle & focus ──────────────────────────────────────────
  useEffect(() => {
    if (!store.terminalVisible) {
      try {
        const activeInst = instancesRef.current[activeTabId];
        activeInst?.term.blur();
      } catch (_) {}
      return;
    }

    // If active tab session doesn't exist yet, spawn it
    if (!instancesRef.current[activeTabId]) {
      requestAnimationFrame(() => {
        spawnTabSession(activeTabId);
      });
    } else {
      requestAnimationFrame(() => {
        try {
          const inst = instancesRef.current[activeTabId];
          if (inst) {
            const vars = getThemeVars();
            inst.term.options.theme = buildXtermTheme(vars);
            inst.fit.fit();
            inst.term.scrollToBottom();
            inst.term.focus();
          }
        } catch (_) {}
      });
    }
  }, [store.terminalVisible, activeTabId, spawnTabSession]);

  // ── Live theme listener across all open terminals ────────────────────────
  useEffect(() => {
    const onTheme = (ev?: any) => {
      const vars = (ev?.detail as Record<string, string>) || getThemeVars();
      const theme = buildXtermTheme(vars);
      Object.values(instancesRef.current).forEach(inst => {
        inst.term.options.theme = theme;
      });
    };
    window.addEventListener('matugen_theme_changed', onTheme);
    return () => {
      window.removeEventListener('matugen_theme_changed', onTheme);
    };
  }, []);

  // Dispose all terminals on unmount
  useEffect(() => {
    return () => { killAllSessions(); };
  }, [killAllSessions]);

  // ── Resize observer on container ──────────────────────────────────────────
  useEffect(() => {
    const activeMount = document.getElementById(`terminal-mount-${activeTabId}`);
    if (!activeMount) return;

    const ro = new ResizeObserver(() => {
      if (!store.terminalVisible) return;
      const inst = instancesRef.current[activeTabId];
      if (inst) {
        try {
          inst.fit.fit();
          inst.term.scrollToBottom();
          if (inst.sessionRef) {
            bridge.ptyResize(inst.sessionRef, inst.term.cols, inst.term.rows).catch(() => {});
          }
        } catch { /* noop */ }
      }
    });
    ro.observe(activeMount);
    return () => ro.disconnect();
  }, [store.terminalVisible, activeTabId]);

  // ── Drag-to-resize handle ─────────────────────────────────────────────────
  const onHandlePointerDown = useCallback((e: React.PointerEvent) => {
    e.preventDefault();
    resizingRef.current = true;
    startYRef.current = e.clientY;
    startHRef.current = store.terminalHeight;
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
  }, [store.terminalHeight]);

  const onHandlePointerMove = useCallback((e: React.PointerEvent) => {
    if (!resizingRef.current) return;
    const delta = startYRef.current - e.clientY; // drag up = taller
    storeActions.setTerminalHeight(startHRef.current + delta);
  }, []);

  const onHandlePointerUp = useCallback(() => {
    resizingRef.current = false;
  }, []);

  // ── Tab Management Actions ────────────────────────────────────────────────
  const handleNewTab = useCallback(() => {
    const num = nextNumRef.current++;
    const newId = `term_${Date.now()}_${num}`;
    const newName = `Terminal ${num}`;
    setTabs(prev => [...prev, { id: newId, name: newName }]);
    setActiveTabId(newId);
  }, []);

  const handleCloseTab = useCallback((e: React.MouseEvent, tabId: string) => {
    e.stopPropagation();
    if (tabs.length <= 1) return;

    killTabInstance(tabId);
    const remaining = tabs.filter(t => t.id !== tabId);
    setTabs(remaining);

    if (activeTabId === tabId) {
      const idx = tabs.findIndex(t => t.id === tabId);
      const nextTab = remaining[Math.max(0, idx - 1)] || remaining[0];
      if (nextTab) {
        setActiveTabId(nextTab.id);
      }
    }
  }, [tabs, activeTabId, killTabInstance]);

  const handleRestart = useCallback(async () => {
    killTabInstance(activeTabId);
    await new Promise(r => setTimeout(r, 80));
    await spawnTabSession(activeTabId);
  }, [activeTabId, killTabInstance, spawnTabSession]);

  const handleClear = useCallback(() => {
    instancesRef.current[activeTabId]?.term.clear();
  }, [activeTabId]);

  const handleClose = useCallback(() => {
    storeActions.toggleTerminal();
  }, []);

  return (
    <div
      ref={panelRef}
      className={`terminal-panel ${store.terminalVisible ? 'terminal-visible' : 'terminal-hidden'}`}
      style={{ height: `${store.terminalHeight}px` }}
      onMouseEnter={handleHoverFocus}
    >
      {/* Top drag handle to resize */}
      <div
        className="terminal-resize-handle"
        onPointerDown={onHandlePointerDown}
        onPointerMove={onHandlePointerMove}
        onPointerUp={onHandlePointerUp}
      />

      {/* Header bar: tabs start at the left, '+' toggle & controls on the right */}
      <div className="terminal-header">
        <div className="terminal-tabs-row">
          {tabs.map((tab) => {
            const isActive = tab.id === activeTabId;
            return (
              <div
                key={tab.id}
                className={`terminal-tab-chip ${isActive ? 'active' : ''}`}
                onClick={() => setActiveTabId(tab.id)}
                title={tab.name}
              >
                <TerminalIcon size={11} className="terminal-tab-icon" />
                <span className="terminal-tab-title">{tab.name}</span>
                {tabs.length > 1 && (
                  <button
                    type="button"
                    className="terminal-tab-close"
                    onClick={(e) => handleCloseTab(e, tab.id)}
                    title={`Close ${tab.name}`}
                  >
                    <X size={10} />
                  </button>
                )}
              </div>
            );
          })}
        </div>

        <div className="terminal-header-actions">
          <button
            type="button"
            className="terminal-header-btn terminal-header-btn-new"
            onClick={handleNewTab}
            title="New terminal tab"
          >
            <Plus size={13} />
          </button>
          <button
            type="button"
            className="terminal-header-btn"
            onClick={handleClear}
            title="Clear active terminal"
          >
            <Trash2 size={12} />
          </button>
          <button
            type="button"
            className="terminal-header-btn"
            onClick={handleRestart}
            title="Restart shell"
          >
            <RotateCcw size={12} />
          </button>
          <button
            type="button"
            className="terminal-header-btn terminal-header-btn-close"
            onClick={handleClose}
            title="Close terminal (Ctrl+3)"
          >
            <X size={12} />
          </button>
        </div>
      </div>

      {/* xterm.js mount points for all tabs */}
      <div className="terminal-xterm-wrapper" style={{ flex: 1, position: 'relative', overflow: 'hidden' }}>
        {tabs.map((tab) => (
          <div
            key={tab.id}
            id={`terminal-mount-${tab.id}`}
            className="terminal-xterm-container"
            style={{
              display: tab.id === activeTabId ? 'block' : 'none',
              width: '100%',
              height: '100%',
            }}
            onClick={() => instancesRef.current[tab.id]?.term.focus()}
          />
        ))}
      </div>
    </div>
  );
};
