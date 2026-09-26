import './monaco-env';
import React from 'react';
import ReactDOM from 'react-dom/client';
import { loader } from '@monaco-editor/react';
import * as monaco from 'monaco-editor';
import { App } from './App';
import { storeActions, getStore, setStore } from './store';
import { agentEngine } from './engine/agent-engine';
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

  // Debug handle only — nothing injects scripts into this renderer anymore.
  (window as any).__hyprcandyEngine  = agentEngine;
}

ReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
