/**
 * Helper utilities for formatting and resolving model labels and agent status.
 */

/**
 * Pure dynamic formatting and resolution for model labels and agent status.
 * Avoids stale hardcoded model tables so any current and future models
 * (OpenRouter, local Ollama, Groq, custom) format cleanly and automatically.
 */

export function formatModelName(raw: string): string {
  if (!raw) return '';
  if (raw === 'openrouter/free') return 'OpenRouter Free';

  // Take the segment after any provider/org namespace (e.g. "anthropic/claude-3.7-sonnet" -> "claude-3.7-sonnet")
  let seg = raw.split('/').pop() || raw;

  // Clean common noise like :latest, dates (-20250219), and preview/instruct flags
  seg = seg
    .replace(/:latest$/, '')
    .replace(/-20\d{6}$/, '')
    .replace(/-preview$/, '')
    .replace(/-instruct$/, '');

  // Keep colon-based parameter tags intact for Ollama (e.g. "gemma4:e4b", "qwen2.5-coder:7b")
  if (seg.includes(':')) {
    const [base, tag] = seg.split(':');
    const cleanBase = base.replace(/[-_]/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
    return `${cleanBase}:${tag}`.slice(0, 24);
  }

  // Capitalize word boundaries for clean presentation
  return seg
    .replace(/[-_]/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase())
    .slice(0, 24);
}

export function getActiveModelLabel(store: any): string {
  // Local (Ollama)
  if (store.activeBackendCategory === 'local' || store.byokProvider === 'ollama') {
    const raw = store.byokModel || store.ollamaModel;
    if (raw) return formatModelName(raw);
    return 'Select a model';
  }

  // BYOK (OpenRouter, Groq, etc.)
  if (store.inferenceMode === 'byok' && store.byokProvider) {
    const raw = store.byokModel || store.activeModel;
    if (raw) return formatModelName(raw);
    return 'Select a model';
  }

  // Cloud Gateway
  if (store.inferenceMode === 'cloud') {
    const raw = store.cloudModel || store.activeModel;
    if (raw) return formatModelName(raw);
    return 'Select a model';
  }

  if (store.activeModel) {
    return formatModelName(store.activeModel);
  }

  return 'Select a model';
}

export function hasActiveAgentConfig(store: any): boolean {
  if (store.activeBackendCategory === 'local' || store.byokProvider === 'ollama') {
    return !!(store.byokModel || store.ollamaModel);
  }
  if (store.inferenceMode === 'byok') {
    return !!(store.byokProvider && (store.byokModel || store.activeModel));
  }
  if (store.inferenceMode === 'cloud') {
    return !!(store.cloudModel || store.activeModel);
  }
  return !!store.activeModel;
}
