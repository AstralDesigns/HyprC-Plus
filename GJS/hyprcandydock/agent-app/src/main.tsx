import React from 'react';
import ReactDOM from 'react-dom/client';
import { loader } from '@monaco-editor/react';
import * as monaco from 'monaco-editor';
import { App } from './App';
import { storeActions, getStore, setStore } from './store';
import { agentEngine } from './engine/agent-engine';
import { webllmService } from './engine/webllm.service';
import './theme.css';

// Configure Monaco to use locally bundled package rather than CDN
loader.config({ monaco });

// Clear any stale theme selection — app is matugen-only now.
try { localStorage.removeItem('hyprcandy_monaco_theme'); } catch (_) {}

if (typeof window !== 'undefined') {
  (window as any).agent = {
    store: getStore,
    setStore,
    actions: storeActions,
  };

  // Expose the engine singletons for executeJavaScript-injected worker scripts.
  // Do this unconditionally: contextBridge/preload feature detection can be
  // observed a few milliseconds late on startup, while the hidden Electron
  // worker already accepts its first model-load request. In WebKitGTK this is
  // harmless; AgentEngine still delegates inference through the bridge.
  (window as any).__hyprcandyEngine  = agentEngine;
  (window as any).__webllmService    = webllmService;
}

ReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
