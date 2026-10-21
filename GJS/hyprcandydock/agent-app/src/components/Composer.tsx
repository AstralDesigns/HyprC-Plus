import React, { useState, useRef, useEffect, useCallback } from 'react';
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

    const userMsg = {
      id: 'msg_' + Date.now(), role: 'user' as const, content: text, timestamp: Date.now(),
      ...(refs.length ? { selectionRefs: refs } : {}),
    };
    storeActions.addMessage(store.activeSessionId, userMsg);

    // Naming is left to the agent (storeActions.autoNameSession, called once
    // the first turn completes in agent-engine.ts) rather than truncating
    // the raw first prompt, which is often not a good topic summary on its
    // own. The session keeps its placeholder title until then.

    try {
      if (store.modelStatus !== 'ready') await agentEngine.loadModel(store.activeModel);
      const attachmentContext = (await Promise.all(attachments
        .filter((attachment) => attachment.kind === 'text')
        .map(async (attachment) => `\n\n[Attached file: ${attachment.name}]\n${await bridge.readFile(attachment.path)}\n[End attached file]`))).join('');
      const priorHistory = currentSession.messages.map(m => ({ role: m.role, content: m.content }));
      await agentEngine.runConversation(
        store.activeSessionId,
        prompt + attachmentContext,
        priorHistory
      );
    } catch (e: any) {
      console.error('Inference error:', e);
    } finally {
      setAttachments([]);
    }
  };

  const handleStop = () => agentEngine.cancel();

  const handleKeyDown = (e: React.KeyboardEvent<HTMLDivElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      void handleSend();
    } else if (e.key === 'Enter' && e.shiftKey) {
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
        const fileName = picked.split('/').pop();
        const extension = fileName?.split('.').pop()?.toLowerCase() || '';
        const kind = ['png', 'jpg', 'jpeg', 'gif', 'webp'].includes(extension)
          ? 'image' : ['mp4', 'webm', 'mov', 'mkv'].includes(extension)
            ? 'video' : ['txt', 'md', 'js', 'ts', 'tsx', 'jsx', 'json', 'css', 'html', 'py', 'sh'].includes(extension)
              ? 'text' : 'file';
        const attachment: AttachmentData = { path: picked, name: fileName || picked, kind };
        setAttachments(prev => [...prev, attachment]);
        if (kind === 'image') {
          storeActions.addContextImage({ path: picked, data: `file://${picked}` });
        } else if (kind === 'text') {
          storeActions.addContextFile({ path: picked, name: fileName || picked });
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

  const canSend = hasContent || attachments.length > 0;
  const placeholder = store.specApprovalPending
    ? 'Review the plan above — Approve or Revise…'
    : store.agentRunning
      ? 'Steer the agent… (Enter)'
      : 'Ask the agent… paste a copied selection to reference it (Enter to send)';

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
              title="Attach File Context"
            >
              <Paperclip size={12} />
              <span>Attach</span>
            </button>
            <button
              type="button"
              className={`chat-attach-btn composer-spec-toggle ${store.specMode ? 'active' : ''}`}
              onClick={() => setStore({ specMode: !store.specMode })}
              disabled={store.agentRunning}
              title="Spec-driven: draft a plan for your approval before executing"
            >
              <ListChecks size={12} />
              <span>Spec</span>
            </button>
          </div>

          {store.agentRunning ? (
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              <button className="composer-action-btn composer-stop-btn" onClick={handleStop} title="Stop agent (Esc)" aria-label="Stop agent">
                <Square size={13} fill="var(--matugen-on-secondary, #1d343c)" color="var(--matugen-on-secondary, #1d343c)" />
              </button>
              <button className="composer-action-btn" onClick={handleSend} disabled={!canSend} title="Steer the agent (Enter)" aria-label="Steer agent">
                <Send size={14} color="var(--matugen-on-secondary, #1d343c)" />
              </button>
            </div>
          ) : (
            <button className="composer-action-btn" onClick={handleSend} disabled={!canSend} title="Send (Enter)" aria-label="Send message">
              <Send size={14} color="var(--matugen-on-secondary, #1d343c)" />
            </button>
          )}
        </div>
      </div>

      {/* Hint row */}
      <div style={{ display: 'flex', justifyContent: 'center', marginTop: '6px' }}>
        <span style={{ fontSize: '10px', color: 'var(--text-muted)' }}>
          Enter to send · Shift+Enter for new line · Paste a copied selection to reference it · Esc to stop
        </span>
      </div>
    </div>
  );
};
