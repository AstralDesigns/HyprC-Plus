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
      border: '1px solid var(--border-glass)',
      background: 'var(--bg-card)',
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
        background: 'rgba(255, 255, 255, 0.04)',
        borderBottom: collapsed ? 'none' : '1px solid var(--border-subtle)',
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
          {collapsed ? <ChevronRight size={15} color="var(--text-muted)" /> : <ChevronDown size={15} color="var(--text-muted)" />}
          <Terminal size={15} color="var(--accent-yellow)" />
          <span style={{ fontWeight: 600, fontSize: '12px', color: 'var(--text-primary)' }}>
            Terminal Command
          </span>
          {command.cwd && (
            <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
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
              color: command.exitCode === 0 ? 'var(--accent-green)' : 'var(--accent-red)',
              fontSize: '12px',
              fontWeight: 600,
            }}>
              {command.exitCode === 0 ? <CheckCircle size={15} /> : <AlertCircle size={15} />}
              <span>{command.exitCode === 0 ? 'Success' : `Exit ${command.exitCode}`}</span>
            </div>
          ) : command.status === 'rejected' ? (
            <span style={{ color: 'var(--accent-red)', fontSize: '12px', fontWeight: 600 }}>Rejected</span>
          ) : isRunning || command.status === 'running' ? (
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px', color: 'var(--accent-cyan)', fontSize: '12px' }}>
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
                  border: '1px solid rgba(255, 142, 142, 0.3)',
                  background: 'rgba(255, 142, 142, 0.1)',
                  color: 'var(--accent-red)',
                  cursor: 'pointer',
                  fontSize: '11px',
                  fontWeight: 600,
                }}
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
                  border: 'none',
                  background: 'var(--accent-yellow)',
                  color: '#1a1900',
                  cursor: 'pointer',
                  fontSize: '11px',
                  fontWeight: 600,
                }}
              >
                <Play size={12} fill="#1a1900" />
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
