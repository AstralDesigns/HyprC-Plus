import React from 'react';
import { X, Code } from 'lucide-react';
import { selectionRangeLabel, type SelectionRef } from '../utils/editorClipboard';

/**
 * A compact Material-You chip for an "edit this selection" reference: shows the
 * source file name + line range with an optional removal toggle. Rendered both
 * in the composer (pending send) and inside a sent user bubble. Font is kept a
 * hair under chat text so the chip height matches a single line of text.
 */
export const SelectionChip: React.FC<{ sel: SelectionRef; onRemove?: () => void }> = ({ sel, onRemove }) => (
  <span className="selection-chip" title={`${sel.path} · ${selectionRangeLabel(sel)}`}>
    <Code size={11} className="selection-chip-icon" />
    <span className="selection-chip-name">{sel.name}</span>
    <span className="selection-chip-range">{selectionRangeLabel(sel)}</span>
    {onRemove && (
      <button type="button" className="selection-chip-x" onClick={onRemove} aria-label="Remove selection reference">
        <X size={10} />
      </button>
    )}
  </span>
);
