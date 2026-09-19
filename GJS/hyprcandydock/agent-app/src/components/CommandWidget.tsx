import React, { useState } from 'react';
import { Terminal, Play, X, CheckCircle, AlertCircle, ChevronDown, ChevronRight, Loader2 } from 'lucide-react';
import { CommandData, storeActions } from '../store';
import { bridge } from '../bridge';

interface CommandWidgetProps {
  sessionId: string;
  messageId: string;
  command: CommandData;
}

export const CommandWidget: React.FC<CommandWidgetProps> = ({ sessionId, messageId, command }) => {
  const [collapsed, setCollapsed] = useState(false);
  const [isRunning, setIsRunning] = useState(false);

  const handleRun = async () => {
    setIsRunning(true);
    storeActions.updateCommandStatus(sessionId, messageId, { status: 'running' });

    try {
      const res = await bridge.execCommand(command.command, command.cwd);
      storeActions.updateCommandStatus(sessionId, messageId, {
        status: 'completed',
        exitCode: res.exitCode,
        stdout: res.stdout,
        stderr: res.stderr,
      });
    } catch (e: any) {
      storeActions.updateCommandStatus(sessionId, messageId, {
        status: 'completed',
        exitCode: 1,
        stderr: e.message,
      });
    } finally {
      setIsRunning(false);
    }
  };

  const handleReject = () => {
    storeActions.updateCommandStatus(sessionId, messageId, { status: 'rejected' });
  };

  return (
    <div style={{
      margin: '12px 0',
      borderRadius: 'var(--radius-md)',
      border: '1px solid color-mix(in srgb, var(--matugen-primary, #a0c9dc) 24%, transparent)',
      background: 'color-mix(in srgb, var(--matugen-surface, #0c1014) 75%, transparent)',
      overflow: 'hidden',
      boxShadow: '0 4px 18px rgba(0, 0, 0, 0.3)',
      transition: 'all 0.2s ease',
    }}>
      {/* Header bar */}
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
          <Terminal size={15} color="var(--matugen-primary, #a0c9dc)" />
          <span style={{ fontWeight: 600, fontSize: '12px', color: 'var(--text-primary)' }}>
            Terminal Command
          </span>
          {command.cwd && (
            <span style={{ fontSize: '11px', color: 'var(--matugen-secondary, #b2cbd6)' }}>
              in {command.cwd}
            </span>
          )}
        </div>

        {/* Action / Status */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          {command.status === 'completed' ? (
            <div style={{
              display: 'flex',
              alignItems: 'center',
              gap: '5px',
              color: command.exitCode === 0 ? '#4ade80' : '#f87171',
              fontSize: '12px',
              fontWeight: 600,
            }}>
              {command.exitCode === 0 ? <CheckCircle size={15} color="#4ade80" /> : <AlertCircle size={15} color="#f87171" />}
              <span>{command.exitCode === 0 ? 'Success' : `Exit ${command.exitCode}`}</span>
            </div>
          ) : command.status === 'rejected' ? (
            <span style={{ color: '#f87171', fontSize: '12px', fontWeight: 600 }}>Rejected</span>
          ) : isRunning || command.status === 'running' ? (
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px', color: 'var(--matugen-primary, #a0c9dc)', fontSize: '12px' }}>
              <Loader2 size={14} className="pulse-glow" style={{ animation: 'spin 1s linear infinite' }} />
              <span>Running...</span>
            </div>
          ) : (
            <>
              <button
                onClick={handleReject}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: '4px',
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
                Cancel
              </button>

              <button
                onClick={handleRun}
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
                <Play size={12} fill="#4ade80" />
                Run Command
              </button>
            </>
          )}
        </div>
      </div>

      {/* Code / Command preview */}
      {!collapsed && (
        <div style={{
          background: 'var(--bg-code)',
          padding: '12px 14px',
          fontFamily: 'var(--font-mono)',
          fontSize: '12px',
        }}>
          <div style={{ display: 'flex', alignItems: 'flex-start', gap: '8px', color: 'var(--accent-cyan)' }}>
            <span style={{ userSelect: 'none', color: 'var(--text-muted)' }}>$</span>
            <span style={{ color: 'var(--text-primary)', wordBreak: 'break-all' }}>{command.command}</span>
          </div>

          {/* Terminal output if completed or running */}
          {(command.stdout || command.stderr) && (
            <div style={{
              marginTop: '10px',
              paddingTop: '10px',
              borderTop: '1px solid rgba(255, 255, 255, 0.08)',
              fontSize: '11.5px',
              lineHeight: 1.45,
            }}>
              {command.stdout && (
                <pre style={{ color: 'var(--text-secondary)', whiteSpace: 'pre-wrap', margin: 0 }}>
                  {command.stdout}
                </pre>
              )}
              {command.stderr && (
                <pre style={{ color: 'var(--accent-red)', whiteSpace: 'pre-wrap', margin: 0, marginTop: '4px' }}>
                  {command.stderr}
                </pre>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
};
