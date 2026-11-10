import React, { useState, useRef, useEffect, useCallback, useMemo } from 'react';
import { Send, Square, Paperclip, ListChecks } from 'lucide-react';
import { useStore, setStore, storeActions, type AttachmentData } from '../store';
import { agentEngine } from '../engine/agent-engine';
import { bridge } from '../bridge';
import { PendingFilesBar } from './PendingFilesBar';
import {
  matchEditorCopy,
  serializeSelections,
  selectionRangeLabel,
  type SelectionRef,
} from '../utils/editorClipboard';

// Inline SVGs so imperatively-built chips (outside React) match the styled pill
// without pulling the lucide components into DOM-managed nodes.
const CODE_SVG = '<svg class="selection-chip-icon" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="16 18 22 12 16 6"></polyline><polyline points="8 6 2 12 8 18"></polyline></svg>';
const X_SVG = '<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>';

export const Composer: React.FC = () => {
  const [store] = useStore();
  const [attachments, setAttachments] = useState<AttachmentData[]>([]);
  const [hasContent, setHasContent] = useState(false);
  const editorRef = useRef<HTMLDivElement>(null);
  // SelectionRefs live here (keyed by chip id); the contenteditable holds only
  // the chip DOM nodes, so large snippets never round-trip through React state.
  const selStore = useRef<Map<string, SelectionRef>>(new Map());

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

  const updateHasContent = useCallback(() => {
    const ed = editorRef.current;
    if (!ed) return;
    const text = (ed.textContent || '').replace(/\u200B/g, '').trim();
    const hasChip = !!ed.querySelector('[data-sel-id]');
    setHasContent(!!text || hasChip);
  }, []);

  const clearEditor = useCallback(() => {
    const ed = editorRef.current;
    if (ed) ed.innerHTML = '';
    selStore.current.clear();
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
  // replaced inline by its <selection> block, plus a compact display form
  // (⟦file Lx-Ly⟧) for the stored user bubble.
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
          if (selId) {
            const r = selStore.current.get(selId);
            if (r) {
              refs.push(r);
              prompt += `\n${serializeSelections([r])}\n`;
              display += `⟦${r.name} ${selectionRangeLabel(r)}⟧`;
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

  const handleSend = async () => {
    const { prompt, display, refs } = collectPrompt();
    const text = display.trim();
    if (!prompt.trim() && attachments.length === 0 && refs.length === 0) return;

    // While a turn is running, a non-empty message steers it instead of
    // starting a new turn. Attachments can't be steered, so ignore those here.
    if (store.agentRunning) {
      const steerText = prompt.trim();
      if (!steerText) return;
      const ok = await agentEngine.steer(steerText);
      if (ok) { clearEditor(); return; }
      // steer refused (task already finished) → fall through to a fresh send
    }

    clearEditor();

    const currentSession = store.sessions.find(s => s.id === store.activeSessionId);
    if (!currentSession) return;

    // Merge explicit attachments and context bar items
    const allAttachments: AttachmentData[] = [...attachments];
    store.contextFiles.forEach(cf => {
      if (!allAttachments.some(a => a.path === cf.path)) {
        allAttachments.push({ path: cf.path, name: cf.name, kind: 'text' });
      }
    });
    store.contextImages.forEach(ci => {
      if (!allAttachments.some(a => a.path === ci.path)) {
        allAttachments.push({ path: ci.path, name: ci.path.split('/').pop() || 'image', kind: 'image' });
      }
    });

    const userMsg = {
      id: 'msg_' + Date.now(), role: 'user' as const, content: text, timestamp: Date.now(),
      ...(allAttachments.length ? { attachments: allAttachments } : {}),
      ...(refs.length ? { selectionRefs: refs } : {}),
    };
    storeActions.addMessage(store.activeSessionId, userMsg);

    // Immediately clear staged attachments & context UI upon prompt send so next prompt starts fresh
    setAttachments([]);
    setStore({ contextFiles: [], contextImages: [] });

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
            return;
          }
          const nextMarker = /^\d+\./.test(marker) ? `${parseInt(marker, 10) + 1}. ` : `${marker} `;
          document.execCommand('insertLineBreak');
          document.execCommand('insertText', false, `${indent}${nextMarker}`);
          updateHasContent();
          return;
        }
      }
      // Force a plain <br> so WebKit doesn't wrap lines in block <div>s.
      e.preventDefault();
      const ed = editorRef.current;
      if (ed) { ed.focus(); try { document.execCommand('insertLineBreak'); } catch { /* noop */ } }
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
      setAttachments(prev => [...prev, { path: data, name, kind: 'image' }]);
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
    <div style={{ padding: '10px 12px 14px', background: 'transparent', flexShrink: 0 }}>
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
      <div className="composer-wrap">
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
          />
          {!hasContent && <div className="composer-placeholder">{placeholder}</div>}
        </div>
        <div className="composer-toolbar">
          {/* Left tools */}
          <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
            <button
              className="chat-attach-btn"
              onClick={handleAttachFile}
              data-tip="Attach File Context"
            >
              <Paperclip size={12} />
              <span>Attach</span>
            </button>
            <button
              type="button"
              className={`chat-attach-btn composer-spec-toggle ${store.specMode ? 'active' : ''}`}
              onClick={() => setStore({ specMode: !store.specMode })}
              disabled={store.agentRunning}
              data-tip="Spec-driven: draft a plan for your approval before executing"
            >
              <ListChecks size={12} />
              <span>Spec</span>
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
    </div>
  );
};
