import React, { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';

// ═══════════════════════════════════════════════════════════════════════════
//  RenameDialog.tsx — in-app "rename" prompt shared by the Explorer tree
//  (Sidebar) and the tab menu (Header). It reuses the existing agent-dialog
//  surface (theme.css) so it stays on the Material-You palette without any new
//  chrome. Submit is disabled until the name is non-empty, differs from the
//  initial value, and contains no path separator (a rename only edits the leaf
//  name; moving folders is done via the "Move to…" action).
// ═══════════════════════════════════════════════════════════════════════════

interface RenameDialogProps {
  open: boolean;
  initialName: string;
  title?: string;
  onCancel: () => void;
  onSubmit: (newName: string) => void;
}

export const RenameDialog: React.FC<RenameDialogProps> = ({
  open,
  initialName,
  title = 'Rename',
  onCancel,
  onSubmit,
}) => {
  const [value, setValue] = useState(initialName);
  const inputRef = useRef<HTMLInputElement>(null);

  // Re-seed + focus/select the basename each time the dialog opens so the user
  // can immediately type over the name (without the extension pre-selected).
  useEffect(() => {
    if (!open) return;
    setValue(initialName);
    const raf = requestAnimationFrame(() => {
      const el = inputRef.current;
      if (!el) return;
      el.focus();
      const dot = initialName.lastIndexOf('.');
      el.setSelectionRange(0, dot > 0 ? dot : initialName.length);
    });
    return () => cancelAnimationFrame(raf);
  }, [open, initialName]);

  if (!open) return null;

  const trimmed = value.trim();
  const valid = trimmed.length > 0 && trimmed !== initialName && !trimmed.includes('/');

  const submit = () => {
    if (!valid) return;
    onSubmit(trimmed);
  };

  const onKey = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') { e.preventDefault(); submit(); }
    else if (e.key === 'Escape') { e.preventDefault(); onCancel(); }
  };

  return createPortal(
    <div className="agent-dialog-overlay" onPointerDown={onCancel}>
      <div className="agent-dialog" onPointerDown={(e) => e.stopPropagation()}>
        <div className="agent-dialog-title">{title}</div>
        <div className="agent-dialog-body">
          <input
            ref={inputRef}
            className="agent-dialog-input"
            value={value}
            spellCheck={false}
            onChange={(e) => setValue(e.target.value)}
            onKeyDown={onKey}
          />
          {!valid && trimmed.length > 0 && trimmed !== initialName && trimmed.includes('/') && (
            <span className="agent-dialog-hint">Name can&apos;t contain &quot;/&quot;.</span>
          )}
        </div>
        <div className="agent-dialog-actions">
          <button type="button" className="agent-dialog-btn" onClick={onCancel}>Cancel</button>
          <button type="button" className="agent-dialog-btn" disabled={!valid} onClick={submit}>Rename</button>
        </div>
      </div>
    </div>,
    document.body,
  );
};
