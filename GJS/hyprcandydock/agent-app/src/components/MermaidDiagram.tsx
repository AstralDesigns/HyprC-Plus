import React, { useEffect, useRef, useState } from 'react';
import mermaid from 'mermaid';
import { Network, Copy, Check, AlertCircle } from 'lucide-react';
import { bridge } from '../bridge';

let mermaidInitialized = false;

function ensureMermaidInit() {
  if (mermaidInitialized) return;
  mermaidInitialized = true;
  mermaid.initialize({
    startOnLoad: false,
    theme: 'dark',
    themeVariables: {
      darkMode: true,
      background: 'transparent',
      primaryColor: '#a0c9dc',
      primaryTextColor: '#e4eef3',
      primaryBorderColor: '#a0c9dc',
      lineColor: '#a0c9dc',
      secondaryColor: '#20343d',
      tertiaryColor: '#162329',
      edgeLabelBackground: '#1d343c',
      nodeBorder: '#a0c9dc',
      clusterBkg: 'rgba(29, 52, 60, 0.4)',
      clusterBorder: '#a0c9dc',
      fontFamily: 'inherit',
    },
    securityLevel: 'loose',
    flowchart: {
      htmlLabels: true,
      curve: 'basis',
      useMaxWidth: true,
    },
  });
}

export const MermaidDiagram: React.FC<{ code: string }> = ({ code }) => {
  const [svg, setSvg] = useState<string>('');
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);
  const idRef = useRef(`mermaid-${Math.random().toString(36).slice(2, 9)}`);

  useEffect(() => {
    ensureMermaidInit();
    let isMounted = true;
    const cleanCode = code.trim();

    if (!cleanCode) {
      setSvg('');
      setError(null);
      return;
    }

    const renderDiagram = async () => {
      try {
        const renderId = `${idRef.current}-${Date.now()}`;
        const { svg: renderedSvg } = await mermaid.render(renderId, cleanCode);
        if (isMounted) {
          setSvg(renderedSvg);
          setError(null);
        }
      } catch (err: any) {
        if (isMounted) {
          setError(err?.message || 'Mermaid syntax error');
          setSvg('');
        }
      }
    };

    renderDiagram();

    return () => {
      isMounted = false;
    };
  }, [code]);

  const handleCopy = async () => {
    if (await bridge.copyToClipboard(code)) {
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    }
  };

  return (
    <div className="mermaid-card animate-fade-in">
      <div className="mermaid-card-header">
        <div className="mermaid-card-title">
          <Network size={12} color="var(--matugen-primary, #a0c9dc)" />
          <span>Diagram</span>
        </div>
        <button
          type="button"
          className="mermaid-copy-btn"
          onClick={handleCopy}
          title="Copy diagram source"
        >
          {copied ? <Check size={11} color="var(--accent-green, #22c55e)" /> : <Copy size={11} />}
          <span>{copied ? 'Copied' : 'Copy'}</span>
        </button>
      </div>

      {svg ? (
        <div
          ref={containerRef}
          className="mermaid-svg-container"
          dangerouslySetInnerHTML={{ __html: svg }}
        />
      ) : error ? (
        <div className="mermaid-error-wrap">
          <div className="mermaid-error-msg">
            <AlertCircle size={12} color="var(--matugen-error, #ef4444)" />
            <span>{error}</span>
          </div>
          <pre className="mermaid-fallback-pre">
            <code>{code}</code>
          </pre>
        </div>
      ) : (
        <div className="mermaid-rendering-msg">Rendering flowchart…</div>
      )}
    </div>
  );
};
