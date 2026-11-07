/**
 * TerminalPanel — embedded xterm.js PTY terminal.
 *
 * Mounts at the bottom of the workspace-container.
 * Styled with Kitty / Wallust palette and CaskaydiaCove Nerd Font Mono so it
 * blends with the host terminal experience.
 *
 * Architecture:
 *   • A PTY session is spawned via bridge.ptySpawn() on first reveal.
 *   • stdout is received over SSE (/pty/stream?id=…&token=…) as base64
 *     chunks, decoded and written directly to the xterm Terminal instance.
 *   • Keyboard input goes back through bridge.ptyWrite().
 *   • Kept mounted in DOM (display: none when hidden) so shell processes and
 *     output history persist across toggling with Ctrl + 3.
 *   • ResizeObserver keeps dimensions synced and notifies the kernel via SIGWINCH.
 *   • The top drag handle lets the user resize the panel height.
 */

import React, { useEffect, useRef, useCallback } from 'react';
import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import { ImageAddon } from '@xterm/addon-image';
import '@xterm/xterm/css/xterm.css';
import { X, RotateCcw, Trash2, TerminalSquare } from 'lucide-react';
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

// ── Component ─────────────────────────────────────────────────────────────────
export const TerminalPanel: React.FC = () => {
  const [store] = useStore();
  const containerRef = useRef<HTMLDivElement>(null);
  const termRef      = useRef<Terminal | null>(null);
  const fitRef       = useRef<FitAddon | null>(null);
  const sessionRef   = useRef<string | null>(null);
  const sseRef       = useRef<EventSource | null>(null);
  const startingRef  = useRef(false);
  const resizingRef  = useRef(false);
  const startYRef    = useRef(0);
  const startHRef    = useRef(0);

  // ── Spawn / attach PTY ────────────────────────────────────────────────────
  const spawnSession = useCallback(async () => {
    if (sessionRef.current || startingRef.current) return;
    startingRef.current = true;

    try {
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

      // Intercept Ctrl+3 (toggle terminal), Ctrl+1 (toggle sidebar), and Ctrl+2 (toggle chat)
      // inside xterm so keystrokes aren't swallowed by the PTY slave.
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

      if (containerRef.current) {
        containerRef.current.innerHTML = '';
        term.open(containerRef.current);
      }

      termRef.current = term;
      fitRef.current  = fit;

      // Allow DOM to settle before measuring
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
      sessionRef.current = sessionId;

      // SSE stdout stream
      const streamUrl = bridge.getPtyStreamUrl(sessionId);
      const sse = new EventSource(streamUrl);
      sseRef.current = sse;

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
        console.warn('[TerminalPanel] SSE stream error:', err);
      };

      sse.addEventListener('close', () => {
        term.writeln('\r\n\x1b[33m[session closed]\x1b[0m');
        if (sseRef.current) {
          sseRef.current.close();
          sseRef.current = null;
        }
        sessionRef.current = null;
      });

      // Keyboard → PTY write
      term.onData((data) => {
        if (sessionRef.current) {
          bridge.ptyWrite(sessionRef.current, data).catch(() => {});
        }
      });
    } finally {
      startingRef.current = false;
    }
  }, []);

  // ── Kill session ─────────────────────────────────────────────────────────
  const killSession = useCallback(() => {
    if (sseRef.current) {
      try { sseRef.current.close(); } catch (_) {}
      sseRef.current = null;
    }
    if (sessionRef.current) {
      bridge.ptyKill(sessionRef.current).catch(() => {});
      sessionRef.current = null;
    }
    if (termRef.current) {
      try { termRef.current.dispose(); } catch (_) {}
      termRef.current = null;
    }
    fitRef.current = null;
  }, []);

  // ── Open / hide lifecycle ────────────────────────────────────────────────
  useEffect(() => {
    if (store.terminalVisible) {
      if (!sessionRef.current) {
        spawnSession();
      } else {
        // Refit, refresh theme, and focus when unhidden
        requestAnimationFrame(() => {
          try {
            if (termRef.current) {
              const vars = getThemeVars();
              termRef.current.options.theme = buildXtermTheme(vars);
            }
            fitRef.current?.fit();
            termRef.current?.scrollToBottom();
            termRef.current?.focus();
          } catch (_) {}
        });
      }
    } else {
      try {
        termRef.current?.blur();
        const ae = document.activeElement as HTMLElement | null;
        if (ae && (containerRef.current?.contains(ae) || ae.tagName === 'TEXTAREA' || ae.tagName === 'INPUT')) {
          ae.blur();
        }
      } catch (_) {}
    }
  }, [store.terminalVisible, spawnSession]);

  // Live theme listener across component lifecycle
  useEffect(() => {
    const onTheme = (ev?: any) => {
      if (termRef.current) {
        const vars = (ev?.detail as Record<string, string>) || getThemeVars();
        termRef.current.options.theme = buildXtermTheme(vars);
      }
    };
    window.addEventListener('matugen_theme_changed', onTheme);
    return () => {
      window.removeEventListener('matugen_theme_changed', onTheme);
    };
  }, []);

  // Dispose on unmount
  useEffect(() => {
    return () => { killSession(); };
  }, [killSession]);

  // ── Resize observer ───────────────────────────────────────────────────────
  useEffect(() => {
    if (!containerRef.current) return;
    const ro = new ResizeObserver(() => {
      if (!store.terminalVisible) return;
      if (fitRef.current && termRef.current) {
        try {
          fitRef.current.fit();
          termRef.current.scrollToBottom();
          if (sessionRef.current) {
            bridge.ptyResize(sessionRef.current, termRef.current.cols, termRef.current.rows).catch(() => {});
          }
        } catch { /* noop */ }
      }
    });
    ro.observe(containerRef.current);
    return () => ro.disconnect();
  }, [store.terminalVisible]);

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

  // ── Restart ───────────────────────────────────────────────────────────────
  const handleRestart = useCallback(async () => {
    killSession();
    await new Promise(r => setTimeout(r, 100));
    await spawnSession();
  }, [killSession, spawnSession]);

  // ── Clear ─────────────────────────────────────────────────────────────────
  const handleClear = useCallback(() => {
    termRef.current?.clear();
  }, []);

  // ── Close ────────────────────────────────────────────────────────────────
  const handleClose = useCallback(() => {
    storeActions.toggleTerminal();
  }, []);

  return (
    <div
      className={`terminal-panel ${store.terminalVisible ? 'terminal-visible' : 'terminal-hidden'}`}
      style={{ height: `${store.terminalHeight}px` }}
    >
      {/* Resize handle */}
      <div
        className="terminal-resize-handle"
        onPointerDown={onHandlePointerDown}
        onPointerMove={onHandlePointerMove}
        onPointerUp={onHandlePointerUp}
      />

      {/* Header bar */}
      <div className="terminal-header">
        <TerminalSquare size={13} style={{ color: 'var(--matugen-surface-tint)', flexShrink: 0 }} />
        <span className="terminal-header-title">Terminal</span>
        <div className="terminal-header-actions">
          <button
            type="button"
            className="terminal-header-btn"
            onClick={handleClear}
            title="Clear terminal"
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

      {/* xterm.js mount point */}
      <div
        className="terminal-xterm-container"
        ref={containerRef}
        onClick={() => termRef.current?.focus()}
      />
    </div>
  );
};
