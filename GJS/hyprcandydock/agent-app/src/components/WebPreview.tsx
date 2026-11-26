import React, { useEffect, useRef, useState } from 'react';
import { Globe, RotateCw, ExternalLink } from 'lucide-react';
import { bridge } from '../bridge';
import { storeActions, FilePane } from '../store';

/**
 * Live web-app / website preview pane. The iframe is `credentialless` so it
 * survives the loopback origin's COEP require-corp (a plain cross-origin
 * iframe is blocked there); the agent drives this very same page over CDP
 * (web_preview_* tools), so what the user sees is what the agent tests.
 * The page itself stays unthemed (true-to-life); only our chrome is themed.
 */
export const WebPreview: React.FC<{ pane: FilePane }> = ({ pane }) => {
  const [addr, setAddr] = useState(pane.path || '');
  const [loaded, setLoaded] = useState(false);
  const [nonce, setNonce] = useState(0);
  const frameRef = useRef<HTMLIFrameElement>(null);
  const src = pane.path || 'about:blank';

  // Agent-side navigation (web_preview_open) swaps pane.path under us.
  useEffect(() => {
    setAddr(pane.path || '');
    setLoaded(false);
  }, [pane.path]);

  const go = (raw: string) => {
    let url = raw.trim();
    if (!url) return;
    if (!/^https?:\/\//i.test(url)) url = 'http://' + url;
    storeActions.navigatePreview(pane.id, url);
  };

  return (
    <div className="canvas-preview-pane web-preview-pane">
      <div className="canvas-preview-bar web-preview-bar">
        <Globe size={13} className="web-preview-globe" />
        <input
          className="web-preview-addr"
          value={addr}
          spellCheck={false}
          placeholder="http://127.0.0.1:5173/"
          onChange={e => setAddr(e.target.value)}
          onFocus={e => e.target.select()}
          onKeyDown={e => { if (e.key === 'Enter') go(addr); }}
          aria-label="Preview address"
        />
        <span
          className={`web-preview-dot ${loaded ? 'web-preview-dot-live' : ''}`}
          title={loaded ? 'Page loaded' : 'Loading…'}
        />
        <button
          type="button"
          className="web-preview-btn"
          title="Reload preview"
          onClick={() => { setLoaded(false); setNonce(n => n + 1); }}
        >
          <RotateCw size={13} />
        </button>
        <button
          type="button"
          className="web-preview-btn"
          title="Open in system browser"
          onClick={() => bridge.openExternalUrl(src)}
        >
          <ExternalLink size={13} />
        </button>
      </div>
      <iframe
        key={nonce}
        ref={frameRef}
        src={src}
        className="canvas-preview-frame web-preview-frame"
        title={pane.name || 'Web preview'}
        onLoad={() => setLoaded(true)}
        {...({ credentialless: '' } as any)}
      />
    </div>
  );
};