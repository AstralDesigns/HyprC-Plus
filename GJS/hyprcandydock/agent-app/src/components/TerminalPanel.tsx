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
  const w = (n: number) => cssVars[`wallust_color${n}`] || undefined;
  const m = (k: string) => cssVars[`matugen_${k}`] || undefined;
  return {
    background:   m('background') || m('surface') || '#0d1117',
    foreground:   m('on_surface') || w(7) || '#e4eef3',
    cursor:       m('primary_fixed_dim') || w(6) || '#a9c5cf',
    cursorAccent: m('background') || '#0d1117',
    selectionBackground: (m('primary_fixed_dim') || w(4) || '#4fa3c0') + '44',
    black:        w(0)  || '#0d1117',
    red:          w(1)  || '#f28b82',
    green:        w(2)  || '#81c995',
    yellow:       w(3)  || '#fdd663',
    blue:         w(4)  || '#8ab4f8',
    magenta:      w(5)  || '#c58af9',
    cyan:         w(6)  || '#78dce8',
    white:        w(7)  || '#e4eef3',
    brightBlack:  w(8)  || '#444c56',
    brightRed:    w(9)  || '#ff9391',
    brightGreen:  w(10) || '#a8e6ba',
    brightYellow: w(11) || '#fee89f',
    brightBlue:   w(12) || '#b0c9ff',
    brightMagenta:w(13) || '#d9aaff',
    brightCyan:   w(14) || '#9fe9f7',
    brightWhite:  w(15) || '#ffffff',
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
          term.focus();
        } catch (_) {}
      });

      // Live-retheme when matugen changes
      const onTheme = () => {
        const vars = getThemeVars();
        term.options.theme = buildXtermTheme(vars);
      };
      window.addEventListener('matugen_theme_changed', onTheme);

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

      sse.onmessage = (ev) => {
        try {
          const bytes = atob(ev.data);
          const u8 = new Uint8Array(bytes.length);
          for (let i = 0; i < bytes.length; i++) u8[i] = bytes.charCodeAt(i);
          term.write(u8);
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
        // Refit and focus when unhidden
        requestAnimationFrame(() => {
          try {
            fitRef.current?.fit();
            termRef.current?.focus();
          } catch (_) {}
        });
      }
    }
  }, [store.terminalVisible, spawnSession]);

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
      className={`terminal-panel ${store.terminalVisible ? '' : 'terminal-hidden'}`}
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
        <TerminalSquare size={13} style={{ color: 'var(--accent-cyan)', flexShrink: 0 }} />
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
