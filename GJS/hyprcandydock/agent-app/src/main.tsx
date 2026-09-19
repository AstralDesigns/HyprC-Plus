import React from 'react';
import ReactDOM from 'react-dom/client';
import { loader } from '@monaco-editor/react';
import * as monaco from 'monaco-editor';
import editorWorker from 'monaco-editor/esm/vs/editor/editor.worker?worker';
import jsonWorker from 'monaco-editor/esm/vs/language/json/json.worker?worker';
import cssWorker from 'monaco-editor/esm/vs/language/css/css.worker?worker';
import htmlWorker from 'monaco-editor/esm/vs/language/html/html.worker?worker';
import tsWorker from 'monaco-editor/esm/vs/language/typescript/ts.worker?worker';
import { App } from './App';
import { storeActions, getStore, setStore } from './store';
import { agentEngine } from './engine/agent-engine';
import './theme.css';

// Without this, Monaco can't spin up its language-service workers (Vite
// serves this app from a loopback origin, not from monaco-editor's own
// package layout) and silently falls back to running tokenization/diagnostics
// on the main thread — which can freeze the whole UI during heavy editing.
(self as any).MonacoEnvironment = {
  getWorker(_workerId: string, label: string) {
    switch (label) {
      case 'json':
        return new jsonWorker();
      case 'css':
      case 'scss':
      case 'less':
        return new cssWorker();
      case 'html':
      case 'handlebars':
      case 'razor':
        return new htmlWorker();
      case 'typescript':
      case 'javascript':
        return new tsWorker();
      default:
        return new editorWorker();
    }
  },
};

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
