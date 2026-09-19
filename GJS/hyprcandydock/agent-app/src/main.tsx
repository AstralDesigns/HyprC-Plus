import React from 'react';
import ReactDOM from 'react-dom/client';
import { loader } from '@monaco-editor/react';
import * as monaco from 'monaco-editor';
import { App } from './App';
import { configureMonacoWorkers } from './monacoWorkers';
import { storeActions, getStore, setStore } from './store';
import { agentEngine } from './engine/agent-engine';
import './theme.css';

// Configure Monaco to use locally bundled package and dedicated Vite workers.
// This prevents Monaco worker code from falling back to the UI thread.
loader.config({ monaco });
configureMonacoWorkers();

// Clear any stale theme selection — app is matugen-only now.
try { localStorage.removeItem('hyprcandy_monaco_theme'); } catch (_) {}

if (typeof window !== 'undefined') {
  (window as any).agent = {
    store: getStore,
    setStore,
    actions: storeActions,
  };
  (window as any).__hyprcandyEngine = agentEngine;
}

ReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
