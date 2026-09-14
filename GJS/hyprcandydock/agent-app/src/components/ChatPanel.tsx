import React, { useState, useRef, useEffect } from 'react';
import { createPortal } from 'react-dom';
import {
  MessageSquare,
  ChevronDown,
  Plus,
  Trash2,
  X,
  FileCode,
} from 'lucide-react';
import { useStore, storeActions, setStore } from '../store';
import { ChatStream } from './ChatStream';
import { Composer } from './Composer';
import { getMediaUrl } from '../utils/media';

function relativeTime(ts: number) {
  const diff = Date.now() - ts;
  if (diff < 60_000) return 'just now';
  if (diff < 3600_000) return Math.floor(diff / 60_000) + 'm ago';
  if (diff < 86400_000) return Math.floor(diff / 3600_000) + 'h ago';
  return Math.floor(diff / 86400_000) + 'd ago';
}

export const ChatPanel: React.FC = () => {
  const [store] = useStore();
  const [showSessionsDropdown, setShowSessionsDropdown] = useState(false);
  const [hoveredImage, setHoveredImage] = useState<string | null>(null);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Resize handling
  const isResizing = useRef(false);
  const startX = useRef(0);
  const startWidth = useRef(0);

  const startResize = (e: React.MouseEvent) => {
    e.preventDefault();
    isResizing.current = true;
    startX.current = e.clientX;
    startWidth.current = store.chatWidth;

    const onMouseMove = (moveEvent: MouseEvent) => {
      if (!isResizing.current) return;
      // Dragging left handle: moving left increases width
      const delta = startX.current - moveEvent.clientX;
      const newWidth = Math.max(260, Math.min(window.innerWidth * 0.7, startWidth.current + delta));
      storeActions.setChatWidth(newWidth);
    };

    const onMouseUp = () => {
      isResizing.current = false;
      window.removeEventListener('mousemove', onMouseMove);
      window.removeEventListener('mouseup', onMouseUp);
    };

    window.addEventListener('mousemove', onMouseMove);
    window.addEventListener('mouseup', onMouseUp);
  };

  // Close session dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setShowSessionsDropdown(false);
      }
    };
    if (showSessionsDropdown) {
      document.addEventListener('mousedown', handleClickOutside);
    }
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [showSessionsDropdown]);

  const activeSession = store.sessions.find(s => s.id === store.activeSessionId);
  const imageSource = (image: { path: string; data: string }) => {
    if (image.data?.startsWith('data:') || image.data?.startsWith('http:') || image.data?.startsWith('https:')) return image.data;
    if (image.data?.startsWith('file://')) return getMediaUrl(image.data.slice('file://'.length));
    return getMediaUrl(image.path);
  };

  return (
    <div className="chat-panel-inner">
      {/* Left resize handle */}
      <div className="resize-handle resize-handle-left" onMouseDown={startResize} />

      {/* Header with status and sessions dropdown popup */}
      <div className="chat-panel-header">
        <div className="chat-header-title-wrap">
          <div className="chat-status-pulse" />
          <span className="chat-header-title">Candy Agent</span>
          {store.modelStatus === 'ready' && (
            <span className="chat-ready-badge">Ready</span>
          )}
        </div>

        <div className="chat-header-actions">
          {/* Sessions Dropdown Popup (CandyCode style) */}
          <div className="relative-wrap" ref={dropdownRef}>
            <button
              type="button"
              className={`chat-header-btn ${showSessionsDropdown ? 'active' : ''}`}
              onClick={() => setShowSessionsDropdown(!showSessionsDropdown)}
              title="Switch or create chat session"
            >
              <span className="chat-session-btn-title">
                {activeSession?.title || 'Chats'}
              </span>
              <ChevronDown size={12} className={showSessionsDropdown ? 'rotate-180' : ''} />
            </button>

            {showSessionsDropdown && (
              <div className="chat-sessions-dropdown-popup animate-fade-in">
                <button
                  type="button"
                  className="dropdown-new-chat-btn"
                  onClick={() => {
                    storeActions.createSession();
                    setShowSessionsDropdown(false);
                  }}
                >
                  <Plus size={13} color="var(--accent-cyan)" />
                  <span>+ New Chat</span>
                </button>

                <div className="dropdown-sessions-list">
                  {store.sessions.map(s => (
                    <div
                      key={s.id}
                      className={`dropdown-session-item ${s.id === store.activeSessionId ? 'active' : ''}`}
                      onClick={() => {
                        storeActions.switchSession(s.id);
                        setShowSessionsDropdown(false);
                      }}
                    >
                      <MessageSquare size={12} className="session-icon" />
                      <div className="session-item-text">
                        <div className="session-item-name">{s.title}</div>
                        <div className="session-item-time">{relativeTime(s.updatedAt)}</div>
                      </div>
                      <button
                        type="button"
                        className="session-delete-btn"
                        onClick={(e) => {
                          e.stopPropagation();
                          storeActions.deleteSession(s.id);
                        }}
                        title="Delete chat"
                      >
                        <X size={12} />
                      </button>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>

          <button
            type="button"
            className="chat-header-btn"
            onClick={() => storeActions.clearCurrentMessages()}
            title="Clear conversation"
          >
            <Trash2 size={13} />
          </button>

        </div>
      </div>

      {/* Chat Messages Stream */}
      <div className="chat-panel-stream-wrap">
        <ChatStream />
      </div>

      {/* The project tree is implicit context; these are explicit additions. */}
      {(store.contextFiles.length > 0 || store.contextImages.length > 0) && <div className="chat-context-chips-bar">
          <span className="context-chips-label">CONTEXT</span>
          {store.contextFiles.map(cf => (
            <span key={cf.path} className="context-chip">
              <FileCode size={11} color="var(--accent-cyan)" />
              <span className="context-chip-name">{cf.name}</span>
              <button
                type="button"
                className="context-chip-remove"
                onClick={() => storeActions.removeContextFile(cf.path)}
                title="Remove from context"
              >
                <X size={10} />
              </button>
            </span>
          ))}
          {store.contextImages.map(ci => (
            <span key={ci.path} className="context-chip context-image-chip">
              <span className="context-image-hover-target" onMouseEnter={() => setHoveredImage(imageSource(ci))} onMouseLeave={() => setHoveredImage(null)}>
                <img src={imageSource(ci)} alt={ci.path.split('/').pop() || 'Context image'} className="context-image-thumb" />
                <span className="context-chip-name">{ci.path.split('/').pop()}</span>
              </span>
              <button
                type="button"
                className="context-chip-remove"
                onMouseEnter={() => setHoveredImage(null)}
                onClick={() => { setHoveredImage(null); storeActions.removeContextImage(ci.path); }}
                title="Remove from context"
              >
                <X size={10} />
              </button>
            </span>
          ))}
      </div>}
      {hoveredImage && createPortal(
        <div className="context-image-lightbox" aria-hidden="true"><img src={hoveredImage} alt="Context image preview" /></div>,
        document.body,
      )}

      {/* Composer at bottom */}
      <Composer />
    </div>
  );
};
