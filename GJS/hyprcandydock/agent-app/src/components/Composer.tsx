import React, { useState, useRef, useEffect } from 'react';
import { Send, Square, Paperclip } from 'lucide-react';
import { useStore, setStore, storeActions, type AttachmentData } from '../store';
import { agentEngine } from '../engine/agent-engine';
import { bridge } from '../bridge';
import { PendingFilesBar } from './PendingFilesBar';

export const Composer: React.FC = () => {
  const [store] = useStore();
  const [input, setInput] = useState('');
  const [attachments, setAttachments] = useState<AttachmentData[]>([]);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // Listen for prompts injected from the GJS host (search bar)
  useEffect(() => {
    const onUserPrompt = (e: any) => {
      const text = typeof e.detail === 'string' ? e.detail.trim() : '';
      if (!text) return;
      setInput(text);
      setTimeout(async () => {
        const curr = store.sessions.find(s => s.id === store.activeSessionId);
        if (curr && !store.agentRunning) {
          const userMsg = {
            id: 'msg_' + Date.now(),
            role: 'user' as const,
            content: text,
            timestamp: Date.now(),
          };
          storeActions.addMessage(store.activeSessionId, userMsg);
          setInput('');
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
  }, [store.activeSessionId, store.agentRunning, store.sessions]);

  const handleSend = async () => {
    const text = input.trim();
    if ((!text && attachments.length === 0) || store.agentRunning) return;
    setInput('');
    if (textareaRef.current) textareaRef.current.style.height = '38px';

    const currentSession = store.sessions.find(s => s.id === store.activeSessionId);
    if (!currentSession) return;

    const userMsg = { id: 'msg_' + Date.now(), role: 'user' as const, content: text, timestamp: Date.now() };
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
        text + attachmentContext,
        priorHistory
      );
    } catch (e: any) {
      console.error('Inference error:', e);
    } finally {
      setAttachments([]);
    }
  };

  const handleStop = () => agentEngine.cancel();

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleSend(); }
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

  const handleInput = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setInput(e.target.value);
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto';
      textareaRef.current.style.height = Math.min(textareaRef.current.scrollHeight, 160) + 'px';
    }
  };

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

  const handlePaste = (e: React.ClipboardEvent<HTMLTextAreaElement>) => {
    const imageFile = Array.from(e.clipboardData.files).find((file) => file.type.startsWith('image/'))
      || Array.from(e.clipboardData.items).find((item) => item.type.startsWith('image/'))?.getAsFile();
    if (imageFile) {
      e.preventDefault();
      addImageBlob(imageFile);
      return;
    }
    // Some WebKitGTK clipboard providers expose screenshots through the
    // asynchronous Clipboard API but omit them from ClipboardEvent.items.
    if (navigator.clipboard?.read) {
      void navigator.clipboard.read().then(async (items) => {
        for (const item of items) {
          const type = item.types.find((value) => value.startsWith('image/'));
          if (type) {
            addImageBlob(await item.getType(type));
            break;
          }
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

  const canSend = (!!input.trim() || attachments.length > 0) && !store.agentRunning;

  return (
    <div style={{ padding: '10px 12px 14px', background: 'transparent', flexShrink: 0 }}>
      <PendingFilesBar />
      <div className="composer-wrap">
        <div className="composer-input-row" style={{ display: 'flex', alignItems: 'flex-start', gap: '6px', padding: '6px 8px 0' }}>
          <textarea
            ref={textareaRef}
            className="composer-textarea"
            value={input}
            onChange={handleInput}
            onKeyDown={handleKeyDown}
            onPaste={handlePaste}
            placeholder={store.agentRunning ? "Agent is running… click Stop to interrupt." : "Ask the agent...(Enter to send) "}
            rows={1}
            style={{ height: '38px', minHeight: '38px', flex: 1 }}
            disabled={store.agentRunning}
          />
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
          </div>

          {store.agentRunning ? (
            <button className="composer-action-btn composer-stop-btn" onClick={handleStop} title="Stop agent (Esc)" aria-label="Stop agent">
              <Square size={13} fill="var(--matugen-on-secondary, #1d343c)" color="var(--matugen-on-secondary, #1d343c)" />
            </button>
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
          Enter to send · Shift+Enter for new line · Shift+F to attach file · Esc to stop
        </span>
      </div>
    </div>
  );
};
