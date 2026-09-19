import React, { useState } from 'react';
import { DiffEditor } from '@monaco-editor/react';
import { Check, X, ChevronDown, ChevronRight, FileCode, CheckCircle2, XCircle } from 'lucide-react';
import { DiffData, storeActions } from '../store';
import { bridge } from '../bridge';

interface DiffWidgetProps {
  sessionId: string;
  messageId: string;
  diff: DiffData;
}

export const DiffWidget: React.FC<DiffWidgetProps> = ({ sessionId, messageId, diff }) => {
  const [collapsed, setCollapsed] = useState(false);
  const [isApplying, setIsApplying] = useState(false);

  const handleAccept = async () => {
    setIsApplying(true);
    try {
      await bridge.writeFile(diff.filePath, diff.modifiedCode);
      storeActions.updateDiffStatus(sessionId, messageId, 'accepted');
    } catch (e: any) {
      alert(`Failed to write file: ${e.message}`);
    } finally {
      setIsApplying(false);
    }
  };

  const handleReject = () => {
    storeActions.updateDiffStatus(sessionId, messageId, 'rejected');
  };

  const filename = diff.filePath.split('/').pop() || diff.filePath;

  return (
    <div style={{
      margin: '12px 0',
      borderRadius: 'var(--radius-md)',
      border: '1px solid color-mix(in srgb, var(--matugen-primary, #a0c9dc) 24%, transparent)',
      background: 'color-mix(in srgb, var(--matugen-surface, #0c1014) 75%, transparent)',
      overflow: 'hidden',
      boxShadow: '0 4px 20px rgba(0, 0, 0, 0.25)',
      transition: 'all 0.2s ease',
    }}>
      {/* Header */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        padding: '8px 14px',
        background: 'color-mix(in srgb, var(--matugen-surface-variant, #40484c) 15%, transparent)',
        borderBottom: collapsed ? 'none' : '1px solid color-mix(in srgb, var(--matugen-primary, #a0c9dc) 16%, transparent)',
      }}>
        <div 
          onClick={() => setCollapsed(!collapsed)}
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            cursor: 'pointer',
            userSelect: 'none',
          }}
        >
          {collapsed ? <ChevronRight size={15} color="var(--matugen-secondary, #b2cbd6)" /> : <ChevronDown size={15} color="var(--matugen-secondary, #b2cbd6)" />}
          <FileCode size={16} color="var(--matugen-primary, #a0c9dc)" />
          <span style={{ fontWeight: 600, fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text-primary)' }}>
            {filename}
          </span>
          <span style={{ fontSize: '11px', color: 'var(--matugen-secondary, #b2cbd6)' }}>
            {diff.filePath}
          </span>
        </div>

        {/* Action badges / buttons */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          {diff.status === 'accepted' ? (
            <div style={{ display: 'flex', alignItems: 'center', gap: '5px', color: '#4ade80', fontSize: '12px', fontWeight: 600 }}>
              <CheckCircle2 size={15} color="#4ade80" />
              <span>Accepted</span>
            </div>
          ) : diff.status === 'rejected' ? (
            <div style={{ display: 'flex', alignItems: 'center', gap: '5px', color: '#f87171', fontSize: '12px', fontWeight: 600 }}>
              <XCircle size={15} color="#f87171" />
              <span>Rejected</span>
            </div>
          ) : (
            <>
              <button
                onClick={handleReject}
                disabled={isApplying}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: '5px',
                  padding: '4px 10px',
                  borderRadius: 'var(--radius-sm)',
                  border: '1px solid rgba(239, 68, 68, 0.45)',
                  background: 'rgba(239, 68, 68, 0.15)',
                  color: '#f87171',
                  cursor: 'pointer',
                  fontSize: '11px',
                  fontWeight: 600,
                  transition: 'all 0.15s ease',
                }}
                onMouseEnter={e => e.currentTarget.style.background = 'rgba(239, 68, 68, 0.25)'}
                onMouseLeave={e => e.currentTarget.style.background = 'rgba(239, 68, 68, 0.15)'}
              >
                <X size={13} />
                Reject
              </button>

              <button
                onClick={handleAccept}
                disabled={isApplying}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: '5px',
                  padding: '4px 12px',
                  borderRadius: 'var(--radius-sm)',
                  border: '1px solid rgba(34, 197, 94, 0.55)',
                  background: 'rgba(34, 197, 94, 0.22)',
                  color: '#4ade80',
                  cursor: 'pointer',
                  fontSize: '11px',
                  fontWeight: 600,
                  transition: 'all 0.15s ease',
                }}
                onMouseEnter={e => e.currentTarget.style.background = 'rgba(34, 197, 94, 0.35)'}
                onMouseLeave={e => e.currentTarget.style.background = 'rgba(34, 197, 94, 0.22)'}
              >
                <Check size={13} />
                {isApplying ? 'Applying...' : 'Accept & Save'}
              </button>
            </>
          )}
        </div>
      </div>

      {/* Monaco Diff Viewer */}
      {!collapsed && (
        <div style={{ height: '260px', width: '100%', position: 'relative' }}>
          <DiffEditor
            height="100%"
            language={getLanguageFromPath(diff.filePath)}
            original={diff.originalCode}
            modified={diff.modifiedCode}
            theme="vs-dark"
            options={{
              readOnly: true,
              renderSideBySide: true,
              minimap: { enabled: false },
              scrollBeyondLastLine: false,
              fontSize: 12,
              fontFamily: 'var(--font-mono)',
              lineNumbersMinChars: 3,
              automaticLayout: true,
              smoothScrolling: true,
              padding: { top: 8, bottom: 8 },
            }}
          />
        </div>
      )}
    </div>
  );
};

function getLanguageFromPath(filePath: string): string {
  const ext = filePath.split('.').pop()?.toLowerCase() || '';
  const map: Record<string, string> = {
    js: 'javascript',
    jsx: 'javascript',
    ts: 'typescript',
    tsx: 'typescript',
    py: 'python',
    sh: 'shell',
    bash: 'shell',
    json: 'json',
    css: 'css',
    html: 'html',
    md: 'markdown',
    yml: 'yaml',
    yaml: 'yaml',
    rs: 'rust',
    go: 'go',
    c: 'c',
    cpp: 'cpp',
  };
  return map[ext] || 'plaintext';
}
