import React, { useState, useRef, useEffect, useCallback, useMemo } from 'react';
import { Send, Square, Paperclip, ListChecks, Plus, CheckCircle, Cpu } from 'lucide-react';
import { useStore, setStore, storeActions, type AttachmentData } from '../store';
import { getActiveModelLabel } from '../utils/modelLabels';
import { agentEngine } from '../engine/agent-engine';
import { bridge } from '../bridge';
import { PendingFilesBar } from './PendingFilesBar';
import { PromptContextMenu } from './PromptContextMenu';
import { EditLongTextModal } from './EditLongTextModal';
import {
  matchEditorCopy,
  serializeSelections,
  selectionRangeLabel,
  type SelectionRef,
} from '../utils/editorClipboard';

// Inline SVGs so imperatively-built chips (outside React) match the styled pill
// without pulling the lucide components into DOM-managed nodes.
const CODE_SVG = '<svg class="selection-chip-icon" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="16 18 22 12 16 6"></polyline><polyline points="8 6 2 12 8 18"></polyline></svg>';
const TEXT_SVG = '<svg class="selection-chip-icon" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="21" y1="10" x2="3" y2="10"></line><line x1="21" y1="6" x2="3" y2="6"></line><line x1="21" y1="14" x2="3" y2="14"></line><line x1="21" y1="18" x2="3" y2="18"></line></svg>';
const X_SVG = '<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>';

interface PastedTextRef {
  id: string;
  label: string;
  text: string;
}

const isLongText = (text: string): boolean => {
  const trimmed = text.trim();
  if (!trimmed) return false;
  const lines = trimmed.split('\n');
  return lines.length >= 4 || trimmed.length > 250;
};

function getPastedChipLabel(text: string): string {
  const firstNonEmpty = text.split('\n').map(l => l.trim()).find(l => l.length > 0) || 'Pasted text';
  const words = firstNonEmpty.split(/\s+/);
  let label = words[0];
  if (label.endsWith(':')) {
    return `${label}...`;
  }
  let candidate = words[0];
  for (let i = 1; i < Math.min(words.length, 3); i++) {
    if ((candidate + ' ' + words[i]).length <= 22) {
      candidate += ' ' + words[i];
    } else {
      break;
    }
  }
  return candidate.length > 22 ? `${candidate.slice(0, 22).trim()}...` : `${candidate}...`;
}

export const Composer: React.FC = () => {
  const [store] = useStore();
  const [attachments, setAttachments] = useState<AttachmentData[]>([]);
  const [hasContent, setHasContent] = useState(false);
  const [contextMenuPos, setContextMenuPos] = useState<{ x: number; y: number } | null>(null);
  const [actionMenuOpen, setActionMenuOpen] = useState(false);
  const actionMenuRef = useRef<HTMLDivElement>(null);
  const editorRef = useRef<HTMLDivElement>(null);
  // SelectionRefs live here (keyed by chip id); the contenteditable holds only
  // the chip DOM nodes, so large snippets never round-trip through React state.
  const selStore = useRef<Map<string, SelectionRef>>(new Map());
  // External non-file long pasted texts live here (keyed by chip id)
  const pastedStore = useRef<Map<string, PastedTextRef>>(new Map());
  const [editingPastedItem, setEditingPastedItem] = useState<{ id: string; text: string } | null>(null);

  // Prompt history navigation state (Up/Down arrow traversal)
  const historyIndexRef = useRef<number>(-1);
  const draftRef = useRef<string>('');

  const userPrompts = useMemo(() => {
    const currentSession = store.sessions.find(s => s.id === store.activeSessionId);
    if (!currentSession) return [];
    return currentSession.messages
      .filter(m => m.role === 'user' && m.content && m.content.trim())
      .map(m => m.content);
  }, [store.sessions, store.activeSessionId]);

  // Reset history index when switching sessions
  useEffect(() => {
    historyIndexRef.current = -1;
    draftRef.current = '';
  }, [store.activeSessionId]);

  // Click outside & Escape dismiss for the (+) actions menu
  useEffect(() => {
    if (!actionMenuOpen) return;
    const handleClickOutside = (e: MouseEvent) => {
      if (actionMenuRef.current && !actionMenuRef.current.contains(e.target as Node)) {
        setActionMenuOpen(false);
      }
    };
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setActionMenuOpen(false);
    };
    window.addEventListener('click', handleClickOutside);
    window.addEventListener('keydown', handleKeyDown);
    return () => {
      window.removeEventListener('click', handleClickOutside);
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, [actionMenuOpen]);

  const updateHasContent = useCallback(() => {
    const ed = editorRef.current;
    if (!ed) return;
    const text = (ed.textContent || '').replace(/\u200B/g, '').trim();
    const hasChip = !!ed.querySelector('[data-sel-id]') || !!ed.querySelector('[data-pasted-id]');
    setHasContent(!!text || hasChip);
  }, []);

  const clearEditor = useCallback(() => {
    const ed = editorRef.current;
    if (ed) ed.innerHTML = '';
    selStore.current.clear();
    pastedStore.current.clear();
    setHasContent(false);
  }, []);

  const setEditorText = useCallback((text: string) => {
    const ed = editorRef.current;
    if (!ed) return;
    ed.innerHTML = '';
    if (text) ed.appendChild(document.createTextNode(text));
    updateHasContent();
  }, [updateHasContent]);

  const isCaretAtStart = useCallback((): boolean => {
    const ed = editorRef.current;
    if (!ed || !ed.textContent?.trim()) return true;
    const sel = window.getSelection();
    if (!sel || sel.rangeCount === 0) return true;
    const range = sel.getRangeAt(0);
    if (!range.collapsed) return false;
    const preRange = range.cloneRange();
    preRange.selectNodeContents(ed);
    preRange.setEnd(range.startContainer, range.startOffset);
    return preRange.toString().length === 0;
  }, []);

  const moveCaretToEnd = useCallback(() => {
    const ed = editorRef.current;
    if (!ed) return;
    ed.focus();
    const range = document.createRange();
    const sel = window.getSelection();
    range.selectNodeContents(ed);
    range.collapse(false);
    sel?.removeAllRanges();
    sel?.addRange(range);
  }, []);

  // Walk the editor in document order, rebuilding the prompt with each chip
  // replaced inline by its <selection> block or full pasted text, plus a compact display form
  // for the stored user bubble.
  const collectPrompt = useCallback((): { prompt: string; display: string; refs: SelectionRef[] } => {
    const ed = editorRef.current;
    const refs: SelectionRef[] = [];
    let prompt = '';
    let display = '';
    const walk = (node: Node) => {
      node.childNodes.forEach(n => {
        if (n.nodeType === Node.TEXT_NODE) {
          const t = (n.textContent || '').replace(/\u200B/g, '');
          prompt += t; display += t;
        } else if (n instanceof HTMLElement) {
          const selId = n.dataset.selId;
          const pastedId = n.dataset.pastedId;
          if (selId) {
            const r = selStore.current.get(selId);
            if (r) {
              refs.push(r);
              prompt += `\n${serializeSelections([r])}\n`;
              display += `⟦${r.name} ${selectionRangeLabel(r)}⟧`;
            }
          } else if (pastedId) {
            const p = pastedStore.current.get(pastedId);
            if (p) {
              prompt += `\n${p.text}\n`;
              display += `\n${p.text}\n`;
            }
          } else if (n.tagName === 'BR') {
            prompt += '\n'; display += '\n';
          } else {
            if (n.tagName === 'DIV' || n.tagName === 'P') { prompt += '\n'; display += '\n'; }
            walk(n);
          }
        }
      });
    };
    if (ed) walk(ed);
    return { prompt, display, refs };
  }, []);

  const insertTextAtCaret = (text: string) => {
    const ed = editorRef.current;
    if (!ed) return;
    ed.focus();
    // execCommand preserves the undo stack + caret; fall back to a manual
    // range insert where it's unavailable.
    let ok = false;
    try { ok = document.execCommand('insertText', false, text); } catch { ok = false; }
    if (!ok) {
      const sel = window.getSelection();
      if (sel && sel.rangeCount && ed.contains(sel.getRangeAt(0).commonAncestorContainer)) {
        const range = sel.getRangeAt(0);
        range.deleteContents();
        range.insertNode(document.createTextNode(text));
        range.setStartAfter(range.endContainer);
      }
    }
    updateHasContent();
  };

  // Build an atomic, non-editable chip and drop it at the caret so it flows
  // inline with the surrounding prompt text.
  const insertChip = useCallback((ref: SelectionRef) => {
    const ed = editorRef.current;
    if (!ed) return;
    const id = 'sel_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 7);
    selStore.current.set(id, ref);

    const chip = document.createElement('span');
    chip.className = 'selection-chip selection-chip-inline';
    chip.setAttribute('contenteditable', 'false');
    chip.dataset.selId = id;
    chip.title = `${ref.path} · ${selectionRangeLabel(ref)}`;
    chip.innerHTML = `${CODE_SVG}<span class="selection-chip-name"></span><span class="selection-chip-range"></span><button type="button" class="selection-chip-x" aria-label="Remove selection reference">${X_SVG}</button>`;
    chip.querySelector('.selection-chip-name')!.textContent = ref.name;
    chip.querySelector('.selection-chip-range')!.textContent = selectionRangeLabel(ref);
    chip.querySelector('.selection-chip-x')!.addEventListener('click', (e) => {
      e.preventDefault(); e.stopPropagation();
      selStore.current.delete(id);
      chip.remove();
      updateHasContent();
    });

    ed.focus();
    const sel = window.getSelection();
    let placed = false;
    if (sel && sel.rangeCount) {
      const range = sel.getRangeAt(0);
      if (ed.contains(range.commonAncestorContainer)) {
        range.deleteContents();
        range.insertNode(chip);
        const sp = document.createTextNode(' ');
        chip.after(sp);
        const r2 = document.createRange();
        r2.setStartAfter(sp); r2.collapse(true);
        sel.removeAllRanges(); sel.addRange(r2);
        placed = true;
      }
    }
    if (!placed) {
      ed.appendChild(chip);
      ed.appendChild(document.createTextNode(' '));
    }
    updateHasContent();
  }, [updateHasContent]);

  // Build a minimal atomic chip for long pasted text that can be clicked to edit in a floating modal
  const insertPastedChip = useCallback((rawText: string) => {
    const ed = editorRef.current;
    if (!ed) return;
    const id = 'pasted_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 7);
    const label = getPastedChipLabel(rawText);
    pastedStore.current.set(id, { id, label, text: rawText });

    const chip = document.createElement('span');
    chip.className = 'selection-chip selection-chip-inline pasted-text-chip';
    chip.setAttribute('contenteditable', 'false');
    chip.dataset.pastedId = id;
    chip.title = `Click to view/edit pasted text (${rawText.length} chars) · ${label}`;
    chip.innerHTML = `${TEXT_SVG}<span class="selection-chip-name pasted-chip-label"></span><button type="button" class="selection-chip-x" aria-label="Remove pasted text">${X_SVG}</button>`;
    chip.querySelector('.pasted-chip-label')!.textContent = label;

    // Clicking the chip body opens the floating "Edit Long Text" container
    chip.addEventListener('click', (e) => {
      if ((e.target as HTMLElement).closest('.selection-chip-x')) return;
      e.preventDefault();
      e.stopPropagation();
      const entry = pastedStore.current.get(id);
      if (entry) {
        setEditingPastedItem({ id: entry.id, text: entry.text });
      }
    });

    // Remove button removes chip and entry
    chip.querySelector('.selection-chip-x')!.addEventListener('click', (e) => {
      e.preventDefault();
      e.stopPropagation();
      pastedStore.current.delete(id);
      chip.remove();
      updateHasContent();
    });

    ed.focus();
    const sel = window.getSelection();
    let placed = false;
    if (sel && sel.rangeCount) {
      const range = sel.getRangeAt(0);
      if (ed.contains(range.commonAncestorContainer)) {
        range.deleteContents();
        range.insertNode(chip);
        const sp = document.createTextNode(' ');
        chip.after(sp);
        const r2 = document.createRange();
        r2.setStartAfter(sp);
        r2.collapse(true);
        sel.removeAllRanges();
        sel.addRange(r2);
        placed = true;
      }
    }
    if (!placed) {
      ed.appendChild(chip);
      ed.appendChild(document.createTextNode(' '));
    }
    updateHasContent();
  }, [updateHasContent]);

  const handleSavePastedText = useCallback((newText: string) => {
    if (!editingPastedItem) return;
    const { id } = editingPastedItem;
    const trimmed = newText.trim();
    if (!trimmed) {
      pastedStore.current.delete(id);
      const chipEl = editorRef.current?.querySelector(`[data-pasted-id="${id}"]`);
      chipEl?.remove();
      updateHasContent();
      setEditingPastedItem(null);
      return;
    }

    const newLabel = getPastedChipLabel(trimmed);
    pastedStore.current.set(id, { id, label: newLabel, text: newText });

    const chipEl = editorRef.current?.querySelector(`[data-pasted-id="${id}"]`) as HTMLElement | null;
    if (chipEl) {
      const labelSpan = chipEl.querySelector('.pasted-chip-label');
      if (labelSpan) labelSpan.textContent = newLabel;
      chipEl.title = `Click to view/edit pasted text (${newText.length} chars) · ${newLabel}`;
    }
    setEditingPastedItem(null);
    updateHasContent();
  }, [editingPastedItem, updateHasContent]);

  const handleSend = async () => {
    const { prompt, display, refs } = collectPrompt();
    const text = display.trim();
    if (!prompt.trim() && attachments.length === 0 && refs.length === 0) return;

    // While a turn is running, a non-empty message steers it instead of
    // starting a new turn. Attachments/context files/images are preserved and folded into the steer.
    if (store.agentRunning) {
      let steerText = prompt.trim();
      const steerAttachments: AttachmentData[] = [];
      const seenSteerPaths = new Set<string>();

      for (const a of attachments) {
        if (a.path && !seenSteerPaths.has(a.path)) {
          seenSteerPaths.add(a.path);
          steerAttachments.push(a);
        }
      }
      for (const cf of store.contextFiles) {
        if (cf.path && !seenSteerPaths.has(cf.path)) {
          seenSteerPaths.add(cf.path);
          steerAttachments.push({ path: cf.path, name: cf.name, kind: 'text' });
        }
      }
      for (const ci of store.contextImages) {
        if (!ci.path) continue;
        const isBlobName = !ci.path.startsWith('/') && !ci.path.startsWith('data:') && !ci.path.startsWith('http');
        if (isBlobName && ci.data && seenSteerPaths.has(ci.data)) continue;
        const dedupeKey = isBlobName ? (ci.data || ci.path) : ci.path;
        if (seenSteerPaths.has(dedupeKey)) continue;
        seenSteerPaths.add(dedupeKey);
        const attPath = isBlobName ? (ci.data || ci.path) : ci.path;
        const attName = isBlobName ? ci.path : (ci.path.split('/').pop() || 'image');
        steerAttachments.push({ path: attPath, name: attName, kind: 'image' });
      }

      // Read any attached text files to format inline context into the steer
      if (steerAttachments.length > 0) {
        const textContext = (await Promise.all(steerAttachments
          .filter((att) => att.kind === 'text')
          .map(async (att) => {
            try {
              const raw = await bridge.readFile(att.path);
              const isTruncated = raw.length > 20000;
              const content = isTruncated
                ? raw.slice(0, 20000) + `\n\n[... Note: Attached file "${att.name}" is truncated at 20,000 characters ...]`
                : raw;
              return `\n\n[Attached file: ${att.name} (${att.path})]\n${content}\n[End attached file]`;
            } catch (err: any) {
              return `\n\n[Attached file: ${att.name} (${att.path}) - could not read: ${err?.message || err}]`;
            }
          }))).join('');

        const imageList = steerAttachments
          .filter((att) => att.kind === 'image')
          .map((att) => att.path)
          .join(', ');
        const imageContext = imageList ? `\n\n[Attached images: ${imageList}]` : '';

        steerText = (steerText ? steerText : 'Here is additional context:') + textContext + imageContext;
      }

      if (!steerText.trim()) return;

      const ok = await agentEngine.steer(steerText.trim());
      if (ok) {
        clearEditor();
        setAttachments([]);
        setStore({ contextFiles: [], contextImages: [] });
        return;
      }
      // steer refused (task already finished) → fall through to a fresh send
    }

    clearEditor();

    const currentSession = store.sessions.find(s => s.id === store.activeSessionId);
    if (!currentSession) return;

    // Merge explicit attachments and context bar items (deduplicated by path)
    const allAttachments: AttachmentData[] = [];
    const seenPaths = new Set<string>();

    for (const a of attachments) {
      if (a.path && !seenPaths.has(a.path)) {
        seenPaths.add(a.path);
        allAttachments.push(a);
      }
    }
    for (const cf of store.contextFiles) {
      if (cf.path && !seenPaths.has(cf.path)) {
        seenPaths.add(cf.path);
        allAttachments.push({ path: cf.path, name: cf.name, kind: 'text' });
      }
    }
    for (const ci of store.contextImages) {
      if (!ci.path) continue;
      // Pasted-blob chips have path = plain filename (e.g. "pasted-image-123.png") and
      // data = the base64 URL. The local `attachments` list already carries the same image
      // with path = base64 URL. Skip the chip here to avoid double-sending.
      const isBlobName = !ci.path.startsWith('/') && !ci.path.startsWith('data:') && !ci.path.startsWith('http');
      if (isBlobName && ci.data && seenPaths.has(ci.data)) continue;
      // For file-based images, use path as the dedup key (same as attachments list).
      const dedupeKey = isBlobName ? (ci.data || ci.path) : ci.path;
      if (seenPaths.has(dedupeKey)) continue;
      seenPaths.add(dedupeKey);
      // Use the data URL as the attachment path for blob images so the user bubble renders correctly.
      const attPath = isBlobName ? (ci.data || ci.path) : ci.path;
      const attName = isBlobName ? ci.path : (ci.path.split('/').pop() || 'image');
      allAttachments.push({ path: attPath, name: attName, kind: 'image' });
    }

    const userMsg = {
      id: 'msg_' + Date.now(), role: 'user' as const, content: text, timestamp: Date.now(),
      ...(allAttachments.length ? { attachments: allAttachments } : {}),
      ...(refs.length ? { selectionRefs: refs } : {}),
    };
    storeActions.addMessage(store.activeSessionId, userMsg);

    // Immediately clear staged attachments & context UI upon prompt send so next prompt starts fresh
    setAttachments([]);
    setStore({ contextFiles: [], contextImages: [] });

    // Scroll chat so new user prompt bubble is immediately fully in view above composer
    setTimeout(() => window.dispatchEvent(new CustomEvent('chat_scroll_to_bottom')), 60);
    setTimeout(() => window.dispatchEvent(new CustomEvent('chat_scroll_to_bottom')), 200);

    // Naming is left to the agent (storeActions.autoNameSession, called once
    // the first turn completes in agent-engine.ts) rather than truncating
    // the raw first prompt, which is often not a good topic summary on its
    // own. The session keeps its placeholder title until then.

    try {
      if (store.modelStatus !== 'ready') await agentEngine.loadModel(store.activeModel);
      const attachmentContext = (await Promise.all(allAttachments
        .filter((attachment) => attachment.kind === 'text')
        .map(async (attachment) => {
          const raw = await bridge.readFile(attachment.path);
          const isTruncated = raw.length > 20000;
          const content = isTruncated
            ? raw.slice(0, 20000) + `\n\n[... Note: Attached file "${attachment.name}" is truncated at 20,000 characters to conserve context budget. If you need the rest or full content, use tool: read_file("${attachment.path}", offset, limit) ...]`
            : raw;
          return `\n\n[Attached file: ${attachment.name} (full path: ${attachment.path})]\n${content}\n[End attached file]`;
        }))).join('');
      const priorHistory = currentSession.messages.map(m => ({ role: m.role, content: m.content }));
      await agentEngine.runConversation(
        store.activeSessionId,
        prompt + attachmentContext,
        priorHistory
      );
    } catch (e: any) {
      console.error('Inference error:', e);
    } finally {
      historyIndexRef.current = -1;
      draftRef.current = '';
    }
  };

  const handleStop = () => agentEngine.cancel();

  const handleKeyDown = (e: React.KeyboardEvent<HTMLDivElement>) => {
    // Ctrl+Shift+Up / Ctrl+Shift+Down (Cmd+Shift on macOS) traverses user prompt history
    // Standard Ctrl+Up / Ctrl+Down remains native for text paragraph navigation
    const isCtrlUp = (e.ctrlKey || e.metaKey) && e.shiftKey && e.key === 'ArrowUp';
    const isCtrlDown = (e.ctrlKey || e.metaKey) && e.shiftKey && e.key === 'ArrowDown';

    if (isCtrlUp) {
      if (userPrompts.length > 0) {
        e.preventDefault();
        if (historyIndexRef.current === -1) {
          draftRef.current = collectPrompt().display || editorRef.current?.textContent || '';
          const nextIndex = userPrompts.length - 1;
          historyIndexRef.current = nextIndex;
          setEditorText(userPrompts[nextIndex]);
          setTimeout(moveCaretToEnd, 0);
        } else if (historyIndexRef.current > 0) {
          const nextIndex = historyIndexRef.current - 1;
          historyIndexRef.current = nextIndex;
          setEditorText(userPrompts[nextIndex]);
          setTimeout(moveCaretToEnd, 0);
        }
        return;
      }
    } else if (isCtrlDown) {
      if (historyIndexRef.current >= 0) {
        e.preventDefault();
        const nextIndex = historyIndexRef.current + 1;
        if (nextIndex < userPrompts.length) {
          historyIndexRef.current = nextIndex;
          setEditorText(userPrompts[nextIndex]);
          setTimeout(moveCaretToEnd, 0);
        } else {
          historyIndexRef.current = -1;
          setEditorText(draftRef.current);
          setTimeout(moveCaretToEnd, 0);
        }
        return;
      }
    }
    if (e.key === 'Tab') {
      e.preventDefault();
      document.execCommand('insertText', false, '  ');
      updateHasContent();
      return;
    }
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      void handleSend();
    } else if (e.key === 'Enter' && e.shiftKey) {
      // Auto-markdown list continuation on Shift+Enter or new line
      const sel = window.getSelection();
      const ed = editorRef.current;

      // Scroll the composer's caret into view after inserting a line break.
      // We use double-rAF so the browser has fully re-laid-out the new content
      // before we try to scroll — a single rAF fires before WebKit reflows.
      // We insert a zero-width span at the caret, scroll it into view, then remove it.
      const scrollCaretIntoView = () => {
        requestAnimationFrame(() => {
          requestAnimationFrame(() => {
            if (!ed) return;
            const s = window.getSelection();
            if (s && s.rangeCount > 0) {
              const r = s.getRangeAt(0).cloneRange();
              r.collapse(true);
              const marker = document.createElement('span');
              marker.setAttribute('aria-hidden', 'true');
              r.insertNode(marker);
              marker.scrollIntoView({ block: 'nearest', behavior: 'instant' } as ScrollIntoViewOptions);
              marker.parentNode?.removeChild(marker);
              // Restore selection after the temporary node removal
              const sel2 = window.getSelection();
              if (sel2 && sel2.rangeCount > 0) {
                // selection usually survives; if not, place at end
              }
            } else {
              // Fallback: scroll textarea to bottom
              ed.scrollTop = ed.scrollHeight;
            }
          });
        });
      };

      if (sel && sel.rangeCount > 0) {
        const range = sel.getRangeAt(0);
        const node = range.startContainer;
        const textBefore = (node.textContent || '').slice(0, range.startOffset);
        const bulletMatch = textBefore.match(/^(\s*)([-*]|\d+\.)\s+(.*)$/);
        if (bulletMatch) {
          e.preventDefault();
          const [ , indent, marker, content] = bulletMatch;
          if (!content.trim()) {
            // Empty bullet -> delete list marker and wrap
            document.execCommand('delete', false);
            updateHasContent();
            scrollCaretIntoView();
            return;
          }
          const nextMarker = /^\d+\./.test(marker) ? `${parseInt(marker, 10) + 1}. ` : `${marker} `;
          document.execCommand('insertLineBreak');
          document.execCommand('insertText', false, `${indent}${nextMarker}`);
          updateHasContent();
          scrollCaretIntoView();
          return;
        }
      }
      // Force a plain <br> so WebKit doesn't wrap lines in block <div>s.
      e.preventDefault();
      if (ed) {
        ed.focus();
        try { document.execCommand('insertLineBreak'); } catch { /* noop */ }
        scrollCaretIntoView();
      }
      updateHasContent();
    }
  };

  useEffect(() => {
    const onGlobalStop = (ev: KeyboardEvent) => {
      if (ev.key === 'Escape' && store.agentRunning) {
        ev.preventDefault();
        handleStop();
      }
    };
    window.addEventListener('keydown', onGlobalStop);
    return () => window.removeEventListener('keydown', onGlobalStop);
  }, [store.agentRunning]);

  const addImageBlob = (blob: Blob) => {
    const reader = new FileReader();
    reader.onload = () => {
      const data = typeof reader.result === 'string' ? reader.result : '';
      if (!data) return;
      const name = `pasted-image-${Date.now()}.${blob.type.split('/')[1] || 'png'}`;
      // Add to local attachments using the data URL as path so dedup in handleSend works.
      setAttachments(prev => [...prev, { path: data, name, kind: 'image' }]);
      // Also show a chip in the context bar above the composer.
      // We use 'name' as the path here (plain filename) for display; the dedup in
      // handleSend uses ci.data to avoid double-sending the image.
      setStore(prev => ({
        contextImages: prev.contextImages.some(image => image.path === name)
          ? prev.contextImages
          : [...prev.contextImages, { path: name, data }],
      }));
    };
    reader.readAsDataURL(blob);
  };

  const handlePaste = (e: React.ClipboardEvent<HTMLDivElement>) => {
    e.preventDefault();
    const cd = e.clipboardData;
    const imageFile = Array.from(cd.files).find((file) => file.type.startsWith('image/'))
      || Array.from(cd.items).find((item) => item.type.startsWith('image/'))?.getAsFile();
    if (imageFile) { addImageBlob(imageFile); return; }
    const pasted = cd.getData('text/plain');
    if (pasted) {
      // A paste matching the most recent Monaco copy becomes an inline "edit
      // this" chip at the caret; anything else is inserted as plain text.
      const ref = matchEditorCopy(pasted);
      if (ref) { insertChip(ref); return; }
      if (isLongText(pasted)) {
        insertPastedChip(pasted);
        return;
      }
      insertTextAtCaret(pasted);
      return;
    }
    // Some WebKitGTK clipboard providers expose screenshots through the
    // asynchronous Clipboard API but omit them from ClipboardEvent.items.
    if (navigator.clipboard?.read) {
      void navigator.clipboard.read().then(async (items) => {
        for (const item of items) {
          const type = item.types.find((value) => value.startsWith('image/'));
          if (type) { addImageBlob(await item.getType(type)); break; }
        }
      }).catch(() => undefined);
    }
  };

  const handleAttachFile = async () => {
    try {
      const picked = await bridge.openFileDialog({ directory: false, currentFolder: store.projectPath });
      if (picked) {
        const paths = picked.split(/[|\n]/).map(s => s.trim()).filter(Boolean);
        for (const p of paths) {
          const fileName = p.split('/').pop() || p;
          const extension = fileName.split('.').pop()?.toLowerCase() || '';
          const isImg = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'bmp', 'ico'].includes(extension);
          const isVid = ['mp4', 'webm', 'mov', 'mkv'].includes(extension);
          const kind = isImg ? 'image' : isVid ? 'video' : 'text';
          const attachment: AttachmentData = { path: p, name: fileName, kind };
          setAttachments(prev => prev.some(a => a.path === p) ? prev : [...prev, attachment]);
          if (isImg) {
            storeActions.addContextImage({ path: p, data: `file://${p}` });
          } else {
            storeActions.addContextFile({ path: p, name: fileName });
          }
        }
      }
    } catch (e) { console.warn('File attach cancelled:', e); }
  };

  const tapComposerChip = (opt: { label: string; promptText: string; sendAs?: 'send' | 'steer' }) => {
    const text = (opt.promptText || opt.label || '').trim();
    if (!text) return;
    setStore({ activeSuggestions: null });
    // The agent_user_prompt listener routes this to steer (running) or a fresh send.
    window.dispatchEvent(new CustomEvent('agent_user_prompt', { detail: text }));
  };

  // Listen for prompts injected from the GJS host (search bar) and from
  // suggestion chips. When a turn is already running, treat the text as a
  // steering instruction; otherwise start a fresh turn.
  useEffect(() => {
    const onUserPrompt = async (e: any) => {
      const text = typeof e.detail === 'string' ? e.detail.trim() : '';
      if (!text) return;
      if (store.agentRunning) {
        const ok = await agentEngine.steer(text);
        if (ok) { clearEditor(); return; }
        // steer refused (task already finished) → fall through to a normal send
      }
      setEditorText(text);
      setTimeout(async () => {
        const curr = store.sessions.find(s => s.id === store.activeSessionId);
        if (curr && !store.agentRunning) {
          const userMsg = { id: 'msg_' + Date.now(), role: 'user' as const, content: text, timestamp: Date.now() };
          storeActions.addMessage(store.activeSessionId, userMsg);
          clearEditor();
          try {
            if (store.modelStatus !== 'ready') await agentEngine.loadModel(store.activeModel);
            await agentEngine.runConversation(
              store.activeSessionId, text,
              curr.messages.map(m => ({ role: m.role, content: m.content }))
            );
          } catch (err) {
            console.error('Inference error on user prompt:', err);
          }
        }
      }, 50);
    };
    window.addEventListener('agent_user_prompt', onUserPrompt);
    return () => window.removeEventListener('agent_user_prompt', onUserPrompt);
  }, [store.activeSessionId, store.agentRunning, store.sessions, clearEditor, setEditorText]);

  // Listen for text insertion from suggestions to populate the chat input field for review/editing
  useEffect(() => {
    const onSetText = (e: any) => {
      const text = typeof e.detail === 'string' ? e.detail : (e.detail?.text ?? '');
      if (text) {
        setEditorText(text);
        if (editorRef.current) {
          editorRef.current.focus();
        }
      }
    };
    window.addEventListener('composer_set_text', onSetText);
    return () => window.removeEventListener('composer_set_text', onSetText);
  }, [setEditorText]);

  const canSend = hasContent || attachments.length > 0;
  const placeholder = store.specApprovalPending
    ? 'Review the plan above — Approve or Revise…'
    : store.agentRunning
      ? 'Steer the agent…'
      : 'Ask anything… (you can also paste screenshots from the clipboard)';

  return (
    <div style={{ padding: '10px 12px 14px', background: 'transparent', flexShrink: 0 }} onContextMenu={(e) => e.preventDefault()}>
      <PendingFilesBar />
      {store.activeSuggestions && !store.activeSuggestions.questions?.length && store.activeSuggestions.options.length > 0 && (
        <div className="suggestion-block composer-suggestions">
          {store.activeSuggestions.question ? (
            <div className="suggestion-question">{store.activeSuggestions.question}</div>
          ) : null}
          <div className="suggestion-chips">
            {store.activeSuggestions.options.map((opt, idx) => (
              <button
                key={`${opt.label}-${idx}`}
                type="button"
                className="suggestion-chip"
                onClick={() => tapComposerChip(opt)}
              >
                {opt.label}
              </button>
            ))}
          </div>
        </div>
      )}
      <div className="composer-wrap" onContextMenu={(e) => e.preventDefault()}>
        <div className="composer-input-row composer-editable-row">
          <div
            ref={editorRef}
            className="composer-textarea composer-editable"
            contentEditable
            suppressContentEditableWarning
            role="textbox"
            aria-multiline="true"
            onInput={updateHasContent}
            onKeyDown={handleKeyDown}
            onPaste={handlePaste}
            onBlur={updateHasContent}
            onContextMenu={(e) => {
              e.preventDefault();
              e.stopPropagation();
              setContextMenuPos({ x: e.clientX, y: e.clientY });
            }}
          />
          {!hasContent && <div className="composer-placeholder">{placeholder}</div>}
        </div>
        <div className="composer-toolbar">
          {/* Left tools: (+) Action Menu & Minimal Active Model Chip */}
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', position: 'relative' }}>
            <button
              type="button"
              className={`composer-plus-btn ${actionMenuOpen ? 'active' : ''}`}
              onClick={(e) => {
                e.stopPropagation();
                setActionMenuOpen(prev => !prev);
              }}
              data-tip="Actions & Options"
              aria-label="Add options"
            >
              <Plus size={14} />
            </button>

            {actionMenuOpen && (
              <div
                ref={actionMenuRef}
                className="composer-plus-menu animate-fade-in"
                onClick={(e) => e.stopPropagation()}
              >
                <button
                  type="button"
                  className="composer-plus-item"
                  onClick={() => {
                    setActionMenuOpen(false);
                    handleAttachFile();
                  }}
                >
                  <div className="composer-plus-item-left">
                    <Paperclip size={13} />
                    <span>Attach</span>
                  </div>
                </button>

                <button
                  type="button"
                  className={`composer-plus-item ${store.specMode ? 'enabled' : ''}`}
                  onClick={() => {
                    setStore({ specMode: !store.specMode });
                  }}
                  disabled={store.agentRunning}
                >
                  <div className="composer-plus-item-left">
                    <ListChecks
                      size={13}
                      style={store.specMode ? { color: '#22c55e' } : undefined}
                    />
                    <span style={store.specMode ? { color: '#22c55e', fontWeight: 600 } : undefined}>
                      Create Plan
                    </span>
                  </div>
                  {store.specMode && (
                    <CheckCircle size={13} color="#22c55e" className="composer-plus-check" />
                  )}
                </button>
              </div>
            )}

            <button
              type="button"
              className="composer-model-chip"
              onClick={() => setStore({ modelManagerOpen: true })}
              data-tip="Configure inference backend"
              aria-label="Active Model"
            >
              <Cpu size={11} className="composer-model-chip-icon" />
              <span className="composer-model-chip-name">{getActiveModelLabel(store)}</span>
            </button>
          </div>

          {store.agentRunning ? (
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              <button className="composer-action-btn composer-stop-btn" onClick={handleStop} data-tip="Stop agent (Esc)" aria-label="Stop agent">
                <Square size={13} fill="var(--matugen-on-secondary, #1d343c)" color="var(--matugen-on-secondary, #1d343c)" />
              </button>
              <button className="composer-action-btn" onClick={handleSend} disabled={!canSend} data-tip="Steer the agent (Enter)" aria-label="Steer agent">
                <Send size={14} color="var(--matugen-on-secondary, #1d343c)" />
              </button>
            </div>
          ) : (
            <button className="composer-action-btn" onClick={handleSend} disabled={!canSend} data-tip="Send (Enter)" aria-label="Send message">
              <Send size={14} color="var(--matugen-on-secondary, #1d343c)" />
            </button>
          )}
        </div>
      </div>

      {/* Hint row */}
      <div style={{ display: 'flex', justifyContent: 'center', marginTop: '6px' }}>
        <span style={{ fontSize: '10px', color: 'var(--text-muted)' }}>
          Enter to send · Shift+Enter for new line · Ctrl+↑/↓ prompt history · Esc to stop
        </span>
      </div>

      {contextMenuPos && (
        <PromptContextMenu
          x={contextMenuPos.x}
          y={contextMenuPos.y}
          targetEl={editorRef.current}
          onClose={() => setContextMenuPos(null)}
        />
      )}

      {editingPastedItem && (
        <EditLongTextModal
          initialText={editingPastedItem.text}
          onSave={handleSavePastedText}
          onClose={() => setEditingPastedItem(null)}
        />
      )}
    </div>
  );
};
