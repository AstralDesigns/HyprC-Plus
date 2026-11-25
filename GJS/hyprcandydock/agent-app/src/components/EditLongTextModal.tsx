import React, { useState, useEffect, useRef } from 'react';
import { createPortal } from 'react-dom';
import { X } from 'lucide-react';

interface EditLongTextModalProps {
  initialText: string;
  onSave: (newText: string) => void;
  onClose: () => void;
}

export const EditLongTextModal: React.FC<EditLongTextModalProps> = ({
  initialText,
  onSave,
  onClose,
}) => {
  const [text, setText] = useState(initialText);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // Focus textarea on open and place cursor at end
  useEffect(() => {
    if (textareaRef.current) {
      textareaRef.current.focus();
      textareaRef.current.setSelectionRange(textareaRef.current.value.length, textareaRef.current.value.length);
    }
  }, []);

  // Global keydown: Escape to close, Ctrl+Enter / Cmd+Enter to save
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        e.stopPropagation();
        onClose();
      } else if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
        e.preventDefault();
        e.stopPropagation();
        onSave(text);
      }
    };
    window.addEventListener('keydown', handleKeyDown, { capture: true });
    return () => window.removeEventListener('keydown', handleKeyDown, { capture: true });
  }, [text, onSave, onClose]);

  const handleTextareaKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    // Support Tab indent inside the editor textarea
    if (e.key === 'Tab') {
      e.preventDefault();
      const target = e.currentTarget;
      const start = target.selectionStart;
      const end = target.selectionEnd;
      const val = target.value;
      const updated = val.substring(0, start) + '  ' + val.substring(end);
      setText(updated);
      requestAnimationFrame(() => {
        target.selectionStart = target.selectionEnd = start + 2;
      });
    }
  };

  return createPortal(
    <div
      className="edit-long-text-modal-backdrop"
      onClick={onClose}
      role="dialog"
      aria-modal="true"
      aria-labelledby="edit-long-text-title"
    >
      <div
        className="edit-long-text-modal-container"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="edit-long-text-modal-header">
          <div className="edit-long-text-modal-title" id="edit-long-text-title">
            Edit Long Text
          </div>
          <button
            type="button"
            className="edit-long-text-modal-close-btn"
            onClick={onClose}
            aria-label="Close dialog"
          >
            <X size={15} />
          </button>
        </div>

        {/* Text Body */}
        <div className="edit-long-text-modal-body">
          <textarea
            ref={textareaRef}
            className="edit-long-text-textarea"
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={handleTextareaKeyDown}
            spellCheck={false}
            placeholder="Paste or edit text here…"
          />
        </div>

        {/* Footer */}
        <div className="edit-long-text-modal-footer">
          <button
            type="button"
            className="edit-long-text-btn-cancel"
            onClick={onClose}
          >
            Cancel
          </button>
          <button
            type="button"
            className="edit-long-text-btn-continue"
            onClick={() => onSave(text)}
          >
            Continue
          </button>
        </div>
      </div>
    </div>,
    document.body
  );
};
