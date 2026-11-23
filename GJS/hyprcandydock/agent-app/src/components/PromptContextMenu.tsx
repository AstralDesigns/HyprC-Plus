import React, { useEffect } from 'react';
import { createPortal } from 'react-dom';
import {
  Undo2,
  Redo2,
  Scissors,
  Copy,
  Clipboard,
  CheckSquare,
} from 'lucide-react';
import { bridge } from '../bridge';

export interface PromptContextMenuProps {
  x: number;
  y: number;
  targetEl: HTMLElement | null;
  onClose: () => void;
}

export const PromptContextMenu: React.FC<PromptContextMenuProps> = ({
  x,
  y,
  targetEl,
  onClose,
}) => {
  useEffect(() => {
    const handleClose = () => onClose();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') handleClose();
    };
    window.addEventListener('pointerdown', handleClose);
    window.addEventListener('blur', handleClose);
    window.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('pointerdown', handleClose);
      window.removeEventListener('blur', handleClose);
      window.removeEventListener('keydown', onKey);
    };
  }, [onClose]);

  const handleUndo = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (targetEl) {
      targetEl.focus();
      document.execCommand('undo');
    }
    onClose();
  };

  const handleRedo = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (targetEl) {
      targetEl.focus();
      document.execCommand('redo');
    }
    onClose();
  };

  const handleCut = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (targetEl) {
      targetEl.focus();
      if ('selectionStart' in targetEl) {
        const ta = targetEl as HTMLTextAreaElement | HTMLInputElement;
        const start = ta.selectionStart ?? 0;
        const end = ta.selectionEnd ?? 0;
        if (start !== end) {
          const selected = ta.value.slice(start, end);
          await bridge.copyToClipboard(selected);
          const val = ta.value;
          ta.value = val.slice(0, start) + val.slice(end);
          ta.setSelectionRange(start, start);
          ta.dispatchEvent(new Event('input', { bubbles: true }));
        } else {
          document.execCommand('cut');
        }
      } else {
        const sel = window.getSelection();
        const selected = sel ? sel.toString() : '';
        if (selected) {
          await bridge.copyToClipboard(selected);
          document.execCommand('delete');
          targetEl.dispatchEvent(new Event('input', { bubbles: true }));
        } else {
          document.execCommand('cut');
        }
      }
    }
    onClose();
  };

  const handleCopy = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (targetEl) {
      if ('selectionStart' in targetEl) {
        const ta = targetEl as HTMLTextAreaElement | HTMLInputElement;
        const start = ta.selectionStart ?? 0;
        const end = ta.selectionEnd ?? 0;
        const selected = start !== end ? ta.value.slice(start, end) : ta.value;
        if (selected) {
          await bridge.copyToClipboard(selected);
        } else {
          document.execCommand('copy');
        }
      } else {
        const sel = window.getSelection();
        const selected = sel && sel.toString() ? sel.toString() : targetEl.innerText;
        if (selected) {
          await bridge.copyToClipboard(selected);
        } else {
          document.execCommand('copy');
        }
      }
    }
    onClose();
  };

  const handlePaste = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (targetEl) {
      targetEl.focus();
      const text = await bridge.readFromClipboard();
      if (text) {
        if ('selectionStart' in targetEl) {
          const ta = targetEl as HTMLTextAreaElement | HTMLInputElement;
          const start = ta.selectionStart ?? 0;
          const end = ta.selectionEnd ?? 0;
          const val = ta.value;
          ta.value = val.slice(0, start) + text + val.slice(end);
          ta.setSelectionRange(start + text.length, start + text.length);
          ta.dispatchEvent(new Event('input', { bubbles: true }));
        } else {
          document.execCommand('insertText', false, text);
          targetEl.dispatchEvent(new Event('input', { bubbles: true }));
        }
      } else {
        document.execCommand('paste');
      }
    }
    onClose();
  };

  const handleSelectAll = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (targetEl) {
      targetEl.focus();
      if ('select' in targetEl) {
        (targetEl as HTMLTextAreaElement).select();
      } else {
        const range = document.createRange();
        range.selectNodeContents(targetEl);
        const sel = window.getSelection();
        sel?.removeAllRanges();
        sel?.addRange(range);
      }
    }
    onClose();
  };

  const left = Math.max(10, Math.min(x, window.innerWidth - 210));
  const top = Math.max(10, Math.min(y, window.innerHeight - 260));

  return createPortal(
    <div
      className="agent-context-menu tab-context-menu"
      style={{ left, top }}
      onPointerDown={(e) => e.stopPropagation()}
      onContextMenu={(e) => e.preventDefault()}
    >
      <button type="button" onClick={handleUndo}>
        <Undo2 size={12} /> Undo<span className="menu-accel">Ctrl+Z</span>
      </button>
      <button type="button" onClick={handleRedo}>
        <Redo2 size={12} /> Redo<span className="menu-accel">Ctrl+Shift+Z</span>
      </button>
      <div className="menu-separator" />
      <button type="button" onClick={handleCut}>
        <Scissors size={12} /> Cut<span className="menu-accel">Ctrl+X</span>
      </button>
      <button type="button" onClick={handleCopy}>
        <Copy size={12} /> Copy<span className="menu-accel">Ctrl+C</span>
      </button>
      <button type="button" onClick={handlePaste}>
        <Clipboard size={12} /> Paste<span className="menu-accel">Ctrl+V</span>
      </button>
      <div className="menu-separator" />
      <button type="button" onClick={handleSelectAll}>
        <CheckSquare size={12} /> Select all<span className="menu-accel">Ctrl+A</span>
      </button>
    </div>,
    document.body,
  );
};
