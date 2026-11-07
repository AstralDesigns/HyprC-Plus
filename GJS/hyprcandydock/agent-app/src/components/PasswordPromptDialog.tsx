import React, { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { Lock, Eye, EyeOff, Loader2, AlertCircle } from 'lucide-react';
import { useStoreSelector, storeActions } from '../store';

export const PasswordPromptDialog: React.FC = () => {
  const passwordPrompt = useStoreSelector(s => s.passwordPrompt);
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (passwordPrompt.open) {
      setPassword('');
      setShowPassword(false);
      const timer = setTimeout(() => {
        inputRef.current?.focus();
      }, 50);
      return () => clearTimeout(timer);
    }
  }, [passwordPrompt.open, passwordPrompt.filePath]);

  if (!passwordPrompt.open) return null;

  const handleClose = () => {
    if (passwordPrompt.loading) return;
    storeActions.closePasswordPrompt();
  };

  const handleSubmit = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    if (!password || passwordPrompt.loading) return;
    const success = await storeActions.submitPasswordPrompt(password);
    if (!success) {
      inputRef.current?.focus();
      inputRef.current?.select();
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Escape') {
      e.preventDefault();
      handleClose();
    }
  };

  return createPortal(
    <div className="agent-dialog-overlay" onPointerDown={handleClose}>
      <div
        className="agent-dialog password-dialog animate-fade-in"
        onPointerDown={(e) => e.stopPropagation()}
        onKeyDown={handleKeyDown}
      >
        <div className="password-dialog-header">
          <div className="password-dialog-icon">
            <Lock size={18} />
          </div>
          <div>
            <div className="password-dialog-title">Authentication Required</div>
            <div className="password-dialog-hint">
              {passwordPrompt.targetType === 'directory'
                ? 'Superuser privileges required to open directory'
                : 'Superuser privileges required to open file as editable'}
            </div>
          </div>
        </div>

        <div className="password-dialog-path" title={passwordPrompt.filePath}>
          {passwordPrompt.filePath}
        </div>

        <form onSubmit={handleSubmit} className="password-dialog-form">
          <div className="password-input-wrap">
            <input
              ref={inputRef}
              type={showPassword ? 'text' : 'password'}
              placeholder="Enter password"
              value={password}
              disabled={passwordPrompt.loading}
              onChange={(e) => setPassword(e.target.value)}
              className="password-dialog-input"
              autoComplete="current-password"
            />
            <button
              type="button"
              className="password-eye-btn"
              onClick={() => setShowPassword(prev => !prev)}
              tabIndex={-1}
              title={showPassword ? 'Hide password' : 'Show password'}
            >
              {showPassword ? <EyeOff size={15} /> : <Eye size={15} />}
            </button>
          </div>

          {passwordPrompt.error && (
            <div className="password-dialog-error">
              <AlertCircle size={14} className="flex-shrink-0" />
              <span>{passwordPrompt.error}</span>
            </div>
          )}

          <div className="agent-dialog-actions" style={{ marginTop: '14px' }}>
            <button
              type="button"
              className="agent-dialog-btn"
              disabled={passwordPrompt.loading}
              onClick={handleClose}
            >
              Cancel
            </button>
            <button
              type="submit"
              className="agent-dialog-btn password-dialog-btn-primary"
              disabled={passwordPrompt.loading || !password.trim()}
            >
              {passwordPrompt.loading ? (
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: '6px' }}>
                  <Loader2 size={13} className="animate-spin" /> Verifying…
                </span>
              ) : (
                'Unlock'
              )}
            </button>
          </div>
        </form>
      </div>
    </div>,
    document.body,
  );
};

