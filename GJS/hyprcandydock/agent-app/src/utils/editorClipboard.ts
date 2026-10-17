// Correlates a Monaco text copy with a later paste into the chat composer so a
// pasted selection becomes an "edit this" reference chip instead of raw text.
// Canvas records the selection (path + line range + text) on the editor's copy
// event; the Composer checks a pasted string against the most recent record.

export interface SelectionRef {
  path: string;        // absolute file path the selection came from
  name: string;        // file name for the chip label
  startLine: number;   // 1-based, inclusive
  endLine: number;     // 1-based, inclusive
  text: string;        // the exact selected text
  at: number;          // Date.now() when it was copied
}

// A paste is only treated as an editor selection while the copy is still fresh;
// after this window a matching string is pasted as ordinary text.
const COPY_TTL_MS = 5 * 60 * 1000;

let lastCopy: SelectionRef | null = null;

export function setEditorCopy(ref: SelectionRef): void {
  lastCopy = ref;
}

export function getEditorCopy(): SelectionRef | null {
  return lastCopy;
}

// Returns the recorded selection when `pasted` matches it (ignoring trailing
// newlines and CRLF differences Monaco may introduce), else null.
export function matchEditorCopy(pasted: string): SelectionRef | null {
  if (!lastCopy) return null;
  if (Date.now() - lastCopy.at > COPY_TTL_MS) return null;
  const norm = (s: string) => s.replace(/\r\n/g, '\n').replace(/\r/g, '\n').replace(/\s+$/, '');
  const a = norm(pasted);
  return a && a === norm(lastCopy.text) ? lastCopy : null;
}

export function selectionRangeLabel(ref: SelectionRef): string {
  return ref.startLine === ref.endLine
    ? `L${ref.startLine}`
    : `L${ref.startLine}-L${ref.endLine}`;
}

// Serialise one or more selection refs into the structured block the agent is
// prompted to edit. Kept as a single helper so the composer and any resend path
// format it identically.
export function serializeSelections(refs: SelectionRef[]): string {
  return refs.map(ref => {
    const range = ref.startLine === ref.endLine ? `${ref.startLine}` : `${ref.startLine}-${ref.endLine}`;
    return `<selection path="${ref.path}" lines="${range}">\n${ref.text}\n</selection>`;
  }).join('\n\n');
}
