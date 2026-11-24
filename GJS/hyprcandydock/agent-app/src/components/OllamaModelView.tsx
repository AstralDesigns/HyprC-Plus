import React, { useState, useEffect, useCallback, useMemo } from 'react';
import {
  Download, Trash2, Search, RefreshCw, Check,
  HardDrive, Cpu, AlertCircle, Server, Power, Sparkles,
} from 'lucide-react';
import { useStore, setStore } from '../store';
import { bridge } from '../bridge';

const PRIMARY = 'var(--matugen-primary, #a0c9dc)';
const ON_PRIMARY = 'var(--matugen-on-secondary, #1d343c)';
const ERROR_COLOR = 'var(--matugen-error, #ffb4ab)';

interface OllamaDownloadedItem {
  name: string;
  modified_at?: string;
  size?: number;
  digest?: string;
  details?: {
    format?: string;
    family?: string;
    parameter_size?: string;
    quantization_level?: string;
  };
}

interface LibraryModel {
  id: string;
  name: string;
  desc: string;
  context: string;
  size: string;
  param: string;
  category: 'coder' | 'reasoning' | 'general';
  isRecommended?: boolean;
}

const OLLAMA_LIBRARY_MODELS: LibraryModel[] = [
  {
    id: 'qwen2.5-coder:7b',
    name: 'Qwen 2.5 Coder 7B',
    desc: 'Alibaba flagship open coder. Deep tool use, surgical file edits, and high benchmark score.',
    context: '32k',
    size: '4.7 GB',
    param: '7B',
    category: 'coder',
    isRecommended: true,
  },
  {
    id: 'qwen2.5-coder:1.5b',
    name: 'Qwen 2.5 Coder 1.5B',
    desc: 'Ultra-fast lightweight model for instant ghost-text completions and cursor continuation.',
    context: '32k',
    size: '986 MB',
    param: '1.5B',
    category: 'coder',
  },
  {
    id: 'qwen2.5-coder:14b',
    name: 'Qwen 2.5 Coder 14B',
    desc: 'High-capability coder for complex architecture, refactoring, and multi-file debugging.',
    context: '32k',
    size: '9.0 GB',
    param: '14B',
    category: 'coder',
  },
  {
    id: 'deepseek-r1:8b',
    name: 'DeepSeek R1 8B',
    desc: 'Distilled open reasoning model. Extended chain-of-thought for algorithms, math, and logic.',
    context: '128k',
    size: '4.9 GB',
    param: '8B',
    category: 'reasoning',
    isRecommended: true,
  },
  {
    id: 'deepseek-r1:14b',
    name: 'DeepSeek R1 14B',
    desc: 'Enhanced reasoning model with superior mathematical synthesis and deep coding proofs.',
    context: '128k',
    size: '9.0 GB',
    param: '14B',
    category: 'reasoning',
  },
  {
    id: 'llama3.2:3b',
    name: 'Llama 3.2 3B',
    desc: 'Meta compact multilingual instruction model. Fast responses, summaries, and agentic tasks.',
    context: '128k',
    size: '2.0 GB',
    param: '3B',
    category: 'general',
    isRecommended: true,
  },
  {
    id: 'llama3.2:1b',
    name: 'Llama 3.2 1B',
    desc: 'Meta lightweight on-device instruction model for minimal memory environments.',
    context: '128k',
    size: '1.3 GB',
    param: '1B',
    category: 'general',
  },
  {
    id: 'llama3.1:8b',
    name: 'Llama 3.1 8B',
    desc: 'Meta 8B flagship open weights model with massive 128k context and robust instruction adherence.',
    context: '128k',
    size: '4.7 GB',
    param: '8B',
    category: 'general',
  },
  {
    id: 'codellama:7b',
    name: 'Code Llama 7B',
    desc: 'Meta code-specialized model fine-tuned on code datasets and Fill-In-The-Middle infilling.',
    context: '16k',
    size: '3.8 GB',
    param: '7B',
    category: 'coder',
  },
  {
    id: 'mistral:7b',
    name: 'Mistral 7B',
    desc: 'High-performing balanced model for general agentic tasks, formatting, and markdown reasoning.',
    context: '32k',
    size: '4.1 GB',
    param: '7B',
    category: 'general',
  },
  {
    id: 'phi4:14b',
    name: 'Phi-4 14B',
    desc: 'Microsoft synthetic reasoning flagship with deep STEM, logic, and coding performance.',
    context: '16k',
    size: '9.1 GB',
    param: '14B',
    category: 'reasoning',
  },
];

export const OllamaModelView: React.FC<{ mode: 'completions' | 'agents' }> = ({ mode }) => {
  const [store] = useStore();
  const [status, setStatus] = useState<{ online: boolean; version?: string; host?: string; error?: string } | null>(null);
  const [checkingStatus, setCheckingStatus] = useState(false);
  const [serviceActionLoading, setServiceActionLoading] = useState(false);
  const [downloadedModels, setDownloadedModels] = useState<OllamaDownloadedItem[]>([]);
  const [loadingModels, setLoadingModels] = useState(false);
  const [search, setSearch] = useState('');
  const [customPullInput, setCustomPullInput] = useState('');
  const [pullingTags, setPullingTags] = useState<Record<string, { percent: number; status: string; error?: string }>>({});
  const [deletingModel, setDeletingModel] = useState<string | null>(null);

  const fetchStatus = useCallback(async () => {
    setCheckingStatus(true);
    try {
      const res = await bridge.getOllamaStatus();
      setStatus(res);
    } catch (e: any) {
      setStatus({ online: false, error: e?.message || 'Failed to connect to local runtime' });
    } finally {
      setCheckingStatus(false);
    }
  }, []);

  const fetchModels = useCallback(async () => {
    setLoadingModels(true);
    try {
      const res = await bridge.getOllamaModels();
      setDownloadedModels(res?.models || []);
    } catch (e) {
      console.warn('Failed to fetch Ollama models:', e);
      setDownloadedModels([]);
    } finally {
      setLoadingModels(false);
    }
  }, []);

  useEffect(() => {
    fetchStatus();
    fetchModels();
  }, [fetchStatus, fetchModels]);

  const handleToggleService = async () => {
    setServiceActionLoading(true);
    const action = status?.online ? 'stop' : 'start';
    try {
      await bridge.setOllamaService(action);
      // Brief delay for systemd/process to settle
      setTimeout(async () => {
        await fetchStatus();
        await fetchModels();
        setServiceActionLoading(false);
      }, 900);
    } catch (e) {
      setServiceActionLoading(false);
      fetchStatus();
    }
  };

  const handlePull = async (modelTag: string) => {
    const target = modelTag.trim();
    if (!target) return;

    setPullingTags(p => ({
      ...p,
      [target]: { percent: 0, status: 'Starting pull…' },
    }));

    try {
      const res = await bridge.pullOllamaModel(target);
      if (!res?.task_id) throw new Error('No task ID returned for download');

      const taskId = res.task_id;
      const poll = setInterval(async () => {
        try {
          const pollRes = await bridge.getOllamaPullStatus(taskId);
          setPullingTags(p => ({
            ...p,
            [target]: {
              percent: pollRes.percent || 0,
              status: pollRes.status || 'Downloading…',
              error: pollRes.error,
            },
          }));

          if (pollRes.done) {
            clearInterval(poll);
            if (!pollRes.error) {
              setCustomPullInput('');
              fetchModels();
              setTimeout(() => {
                setPullingTags(p => {
                  const next = { ...p };
                  delete next[target];
                  return next;
                });
              }, 2000);
            }
          }
        } catch (err: any) {
          clearInterval(poll);
          setPullingTags(p => ({
            ...p,
            [target]: { percent: 0, status: 'Failed', error: err?.message || 'Error checking pull' },
          }));
        }
      }, 1000);
    } catch (e: any) {
      setPullingTags(p => ({
        ...p,
        [target]: { percent: 0, status: 'Failed', error: e?.message || 'Failed to start pull' },
      }));
    }
  };

  const handleDelete = async (modelName: string) => {
    if (!window.confirm(`Remove local model weights for "${modelName}"?`)) return;
    setDeletingModel(modelName);
    try {
      const res = await bridge.deleteOllamaModel(modelName);
      if (res?.status === 'ok') {
        fetchModels();
      } else {
        alert(`Failed to delete model: ${res?.error || 'Unknown error'}`);
      }
    } catch (e: any) {
      alert(`Error deleting model: ${e?.message || String(e)}`);
    } finally {
      setDeletingModel(null);
    }
  };

  const activeModelName = useMemo(() => {
    if (mode === 'agents') {
      return store.byokProvider === 'ollama' ? (store.byokModel || store.ollamaModel) : '';
    }
    return store.completionsProvider === 'ollama' ? (store.completionsModel || store.ollamaCompletionsModel) : '';
  }, [mode, store.byokProvider, store.byokModel, store.ollamaModel, store.completionsProvider, store.completionsModel, store.ollamaCompletionsModel]);

  const selectModel = (name: string) => {
    if (mode === 'agents') {
      setStore({
        inferenceMode: 'byok',
        byokProvider: 'ollama',
        byokModel: name,
        ollamaModel: name,
      });
    } else {
      setStore({
        completionsProvider: 'ollama',
        completionsModel: name,
        ollamaCompletionsModel: name,
        inlineCompletionsEnabled: true,
      });
    }
  };

  const formatSize = (bytes?: number) => {
    if (!bytes) return '';
    const gb = bytes / (1024 * 1024 * 1024);
    return `${gb.toFixed(1)} GB`;
  };

  const downloadedTagMap = useMemo(() => {
    const map = new Set<string>();
    for (const m of downloadedModels) {
      map.add(m.name);
      if (m.name.includes(':')) {
        map.add(m.name.split(':')[0]);
      }
    }
    return map;
  }, [downloadedModels]);

  const q = search.trim().toLowerCase();

  // Top Section: Downloaded models and Actively Pulling models
  const topModels = useMemo(() => {
    const list: Array<{
      type: 'downloaded' | 'pulling';
      tag: string;
      item?: OllamaDownloadedItem;
      pullInfo?: { percent: number; status: string; error?: string };
    }> = [];

    // Add actively pulling tags
    for (const [tag, pullInfo] of Object.entries(pullingTags)) {
      list.push({ type: 'pulling', tag, pullInfo });
    }

    // Add downloaded models
    for (const m of downloadedModels) {
      if (!pullingTags[m.name]) {
        list.push({ type: 'downloaded', tag: m.name, item: m });
      }
    }

    if (!q) return list;
    return list.filter(m => m.tag.toLowerCase().includes(q) || m.item?.details?.family?.toLowerCase().includes(q));
  }, [downloadedModels, pullingTags, q]);

  // Catalog Section: Library models that are not yet downloaded or pulling
  const catalogModels = useMemo(() => {
    const list = OLLAMA_LIBRARY_MODELS.filter(m => !downloadedTagMap.has(m.id) && !pullingTags[m.id]);
    if (!q) return list;
    return list.filter(m =>
      m.id.toLowerCase().includes(q) ||
      m.name.toLowerCase().includes(q) ||
      m.desc.toLowerCase().includes(q) ||
      m.param.toLowerCase().includes(q) ||
      m.category.toLowerCase().includes(q)
    );
  }, [downloadedTagMap, pullingTags, q]);

  const isOnline = !!status?.online;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
      {/* ── 1. Ollama Daemon Status & Interactive Service Switch ─────────── */}
      <div style={{
        padding: '12px 14px', borderRadius: 'var(--radius-sm, 8px)',
        border: '1px solid var(--border-subtle)',
        background: 'color-mix(in srgb, var(--matugen-surface-container, #16252c) 60%, transparent)',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <div style={{
            width: 32, height: 32, borderRadius: '6px',
            background: isOnline ? 'rgba(34, 197, 94, 0.15)' : 'rgba(239, 68, 68, 0.15)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Server size={17} color={isOnline ? '#22c55e' : ERROR_COLOR} />
          </div>
          <div>
            <div style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-primary)', display: 'flex', alignItems: 'center', gap: '6px' }}>
              <span>Ollama Local Daemon</span>
              <span style={{
                fontSize: '10px', padding: '1px 6px', borderRadius: '4px',
                background: isOnline ? 'rgba(34, 197, 94, 0.2)' : 'rgba(239, 68, 68, 0.2)',
                color: isOnline ? '#22c55e' : ERROR_COLOR,
              }}>
                {isOnline ? `Online (v${status?.version || '0.40'})` : 'Offline'}
              </span>
            </div>
            <div style={{ fontSize: '10.5px', color: 'var(--text-muted)' }}>
              {isOnline
                ? `Ready on ${status?.host || 'http://localhost:11434'}`
                : 'Turn on to run local completions and agent models without cloud APIs.'}
            </div>
          </div>
        </div>

        {/* Interactive Service Toggle Button */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
          <button
            type="button"
            onClick={handleToggleService}
            disabled={serviceActionLoading}
            style={{
              background: isOnline ? PRIMARY : 'rgba(255,255,255,0.08)',
              color: isOnline ? ON_PRIMARY : 'var(--text-primary)',
              border: 'none', borderRadius: '9999px', padding: '5px 14px', fontSize: '11px', fontWeight: 700,
              cursor: serviceActionLoading ? 'wait' : 'pointer', transition: 'all 0.18s ease',
              display: 'inline-flex', alignItems: 'center', gap: '5px',
            }}
          >
            <Power size={11} />
            <span>
              {serviceActionLoading
                ? (isOnline ? 'Stopping…' : 'Starting…')
                : (isOnline ? 'Stop Service' : 'Start Service')}
            </span>
          </button>
        </div>
      </div>

      {/* Auto-start preference option */}
      <div style={{
        padding: '8px 12px', borderRadius: '6px',
        background: 'rgba(0,0,0,0.14)', border: '1px solid var(--border-subtle)',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      }}>
        <div style={{ fontSize: '11px', color: 'var(--text-secondary)' }}>
          Auto-start Ollama when workspace opens
        </div>
        <button
          type="button"
          onClick={() => setStore({ ollamaAutoStart: !store.ollamaAutoStart })}
          style={{
            background: store.ollamaAutoStart ? PRIMARY : 'rgba(255,255,255,0.08)',
            color: store.ollamaAutoStart ? ON_PRIMARY : 'var(--text-muted)',
            border: 'none', borderRadius: '9999px', padding: '2px 10px', fontSize: '10.5px', fontWeight: 700,
            cursor: 'pointer', transition: 'all 0.15s ease',
          }}
        >
          {store.ollamaAutoStart ? 'Enabled' : 'Disabled'}
        </button>
      </div>

      {/* ── 2. Inline completions master switches (Completions mode only) ── */}
      {mode === 'completions' && (
        <div style={{
          padding: '12px 14px', borderRadius: 'var(--radius-sm, 8px)',
          border: '1px solid var(--border-subtle)',
          background: 'color-mix(in srgb, var(--matugen-surface-container, #16252c) 60%, transparent)',
          display: 'flex', flexDirection: 'column', gap: '10px',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <div>
              <div style={{ fontSize: '12px', fontWeight: 600, color: 'var(--text-primary)' }}>Inline Completions (Ghost text)</div>
              <div style={{ fontSize: '10.5px', color: 'var(--text-muted)' }}>
                Suggest continuations in the editor from your chosen local Ollama model.
              </div>
            </div>
            <button
              type="button"
              disabled={!isOnline}
              onClick={() => {
                const next = !store.inlineCompletionsEnabled;
                setStore({
                  inlineCompletionsEnabled: next,
                  completionsProvider: next ? 'ollama' : store.completionsProvider,
                });
              }}
              style={{
                background: store.inlineCompletionsEnabled && store.completionsProvider === 'ollama' ? PRIMARY : 'rgba(255,255,255,0.08)',
                color: store.inlineCompletionsEnabled && store.completionsProvider === 'ollama' ? ON_PRIMARY : 'var(--text-muted)',
                border: 'none', borderRadius: '9999px', padding: '4px 14px', fontSize: '11px', fontWeight: 700,
                cursor: isOnline ? 'pointer' : 'not-allowed', transition: 'all 0.15s ease',
                opacity: isOnline ? 1 : 0.5,
              }}
            >
              {store.inlineCompletionsEnabled && store.completionsProvider === 'ollama' ? 'Active' : 'Off'}
            </button>
          </div>

          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <div>
              <div style={{ fontSize: '12px', fontWeight: 600, color: 'var(--text-primary)' }}>Next-edit jump hints</div>
              <div style={{ fontSize: '10.5px', color: 'var(--text-muted)' }}>
                Surface predictive Tab-to-jump line hints in Monaco.
              </div>
            </div>
            <button
              type="button"
              disabled={!isOnline || !(store.inlineCompletionsEnabled && store.completionsProvider === 'ollama')}
              onClick={() => setStore({ jumpSuggestionsEnabled: !store.jumpSuggestionsEnabled })}
              style={{
                background: store.jumpSuggestionsEnabled ? PRIMARY : 'rgba(255,255,255,0.08)',
                color: store.jumpSuggestionsEnabled ? ON_PRIMARY : 'var(--text-muted)',
                border: 'none', borderRadius: '9999px', padding: '4px 14px', fontSize: '11px', fontWeight: 700,
                cursor: isOnline ? 'pointer' : 'not-allowed', transition: 'all 0.15s ease',
                opacity: isOnline ? 1 : 0.5,
              }}
            >
              {store.jumpSuggestionsEnabled ? 'Active' : 'Off'}
            </button>
          </div>
        </div>
      )}

      {/* ── 3. Search & Pull Custom Tag Bar ─────────────────────────────── */}
      <div style={{
        display: 'flex', gap: '8px', alignItems: 'center',
        background: 'color-mix(in srgb, var(--matugen-surface-container, #16252c) 60%, transparent)',
        padding: '10px 12px', borderRadius: 'var(--radius-sm, 8px)',
        border: '1px solid var(--border-subtle)',
      }}>
        <div style={{ position: 'relative', flex: 1 }}>
          <Search size={12} style={{ position: 'absolute', left: 8, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
          <input
            type="text"
            value={search}
            onChange={e => setSearch(e.target.value)}
            placeholder="Search Ollama library & local models (e.g. coder, llama, 7b)…"
            style={{
              width: '100%', padding: '6px 8px 6px 26px', background: 'rgba(0,0,0,0.22)',
              border: '1px solid var(--border-subtle)', borderRadius: '6px',
              color: 'var(--text-primary)', fontSize: '11.5px', outline: 'none',
              boxSizing: 'border-box',
            }}
          />
        </div>

        <div style={{ display: 'flex', gap: '4px', alignItems: 'center' }}>
          <input
            type="text"
            value={customPullInput}
            onChange={e => setCustomPullInput(e.target.value)}
            onKeyDown={e => { if (e.key === 'Enter') handlePull(customPullInput); }}
            placeholder="Pull tag (e.g. gemma2:2b)"
            style={{
              width: '160px', padding: '6px 8px', background: 'rgba(0,0,0,0.22)',
              border: '1px solid var(--border-subtle)', borderRadius: '6px',
              color: 'var(--text-primary)', fontSize: '11.5px', outline: 'none',
            }}
          />
          <button
            type="button"
            onClick={() => handlePull(customPullInput)}
            disabled={!customPullInput.trim() || !isOnline}
            style={{
              background: PRIMARY, color: ON_PRIMARY, border: 'none',
              borderRadius: '6px', padding: '6px 10px', fontSize: '11px', fontWeight: 700,
              cursor: customPullInput.trim() && isOnline ? 'pointer' : 'not-allowed',
              opacity: customPullInput.trim() && isOnline ? 1 : 0.5,
              whiteSpace: 'nowrap',
            }}
          >
            Pull
          </button>
        </div>
      </div>

      {/* ── 4. Top Section: Downloaded & Actively Pulling Models ─────────── */}
      <div>
        <div style={{
          fontSize: '11px', fontWeight: 700, color: 'var(--matugen-primary, #a0c9dc)',
          textTransform: 'uppercase', letterSpacing: '.05em', marginBottom: '8px',
          display: 'flex', alignItems: 'center', gap: '6px',
        }}>
          <HardDrive size={12} />
          <span>Downloaded & Active Models ({downloadedModels.length})</span>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
          {topModels.length === 0 ? (
            <div style={{
              padding: '16px', textAlign: 'center', borderRadius: '8px',
              border: '1px dashed var(--border-subtle)', color: 'var(--text-muted)', fontSize: '11px',
            }}>
              {isOnline
                ? 'No downloaded models yet. Click "Pull" on any model below to download into your local storage.'
                : 'Ollama is offline. Start the service above to list and run local models.'}
            </div>
          ) : (
            topModels.map(m => {
              const isSelected = activeModelName === m.tag;
              const isPulling = m.type === 'pulling';

              return (
                <div
                  key={m.tag}
                  style={{
                    padding: '10px 14px', borderRadius: 'var(--radius-sm, 8px)',
                    border: isSelected ? `1px solid ${PRIMARY}` : '1px solid var(--border-subtle)',
                    background: isSelected
                      ? 'color-mix(in srgb, var(--matugen-primary, #a0c9dc) 12%, transparent)'
                      : 'color-mix(in srgb, var(--matugen-surface-container, #16252c) 50%, transparent)',
                    display: 'flex', flexDirection: 'column', gap: '6px',
                    transition: 'all 0.15s ease',
                  }}
                >
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '6px', marginBottom: '3px' }}>
                        <span style={{ fontSize: '12px', fontWeight: 600, color: 'var(--text-primary)' }}>{m.tag}</span>
                        {isPulling ? (
                          <span style={{
                            background: 'rgba(234, 179, 8, 0.2)', color: '#eab308',
                            fontSize: '9px', fontWeight: 700, padding: '1px 6px', borderRadius: '4px',
                          }}>
                            PULLING ({m.pullInfo?.percent}%)
                          </span>
                        ) : isSelected ? (
                          <span style={{
                            background: PRIMARY, color: ON_PRIMARY,
                            fontSize: '9px', fontWeight: 700, padding: '1px 5px', borderRadius: '4px',
                          }}>
                            ACTIVE
                          </span>
                        ) : (
                          <span style={{
                            background: 'rgba(34, 197, 94, 0.18)', color: '#22c55e',
                            fontSize: '9px', fontWeight: 700, padding: '1px 5px', borderRadius: '4px',
                          }}>
                            INSTALLED
                          </span>
                        )}
                      </div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '10px', color: 'var(--text-muted)' }}>
                        {m.item?.details?.parameter_size && (
                          <span style={{ background: 'rgba(255,255,255,0.06)', padding: '1px 5px', borderRadius: '3px' }}>
                            {m.item.details.parameter_size}
                          </span>
                        )}
                        {m.item?.details?.quantization_level && (
                          <span style={{ background: 'rgba(255,255,255,0.06)', padding: '1px 5px', borderRadius: '3px' }}>
                            {m.item.details.quantization_level}
                          </span>
                        )}
                        {m.item?.size && <span>{formatSize(m.item.size)}</span>}
                      </div>
                    </div>

                    <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                      {!isPulling && (
                        <>
                          <button
                            type="button"
                            onClick={() => selectModel(m.tag)}
                            disabled={isSelected}
                            style={{
                              background: isSelected ? 'transparent' : PRIMARY,
                              color: isSelected ? PRIMARY : ON_PRIMARY,
                              border: isSelected ? `1px solid ${PRIMARY}` : 'none',
                              borderRadius: '5px', padding: '4px 10px', fontSize: '11px', fontWeight: 600,
                              cursor: isSelected ? 'default' : 'pointer',
                              display: 'inline-flex', alignItems: 'center', gap: '4px',
                            }}
                          >
                            {isSelected ? <Check size={11} /> : null}
                            <span>{isSelected ? 'Selected' : 'Use Model'}</span>
                          </button>

                          <button
                            type="button"
                            onClick={() => handleDelete(m.tag)}
                            disabled={deletingModel === m.tag}
                            style={{
                              background: 'none', border: '1px solid var(--border-subtle)',
                              borderRadius: '5px', padding: '4px 7px', color: 'var(--text-muted)',
                              cursor: deletingModel === m.tag ? 'wait' : 'pointer',
                            }}
                            title="Delete model weights from disk"
                          >
                            <Trash2 size={12} color={deletingModel === m.tag ? 'var(--text-muted)' : ERROR_COLOR} />
                          </button>
                        </>
                      )}
                    </div>
                  </div>

                  {/* Pull progress bar if currently downloading */}
                  {isPulling && m.pullInfo && (
                    <div style={{ marginTop: '2px' }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '10px', color: 'var(--text-muted)', marginBottom: '3px' }}>
                        <span>{m.pullInfo.status}</span>
                        <span>{m.pullInfo.percent}%</span>
                      </div>
                      <div style={{ height: '4px', background: 'rgba(255,255,255,0.1)', borderRadius: '9999px', overflow: 'hidden' }}>
                        <div style={{ width: `${m.pullInfo.percent}%`, height: '100%', background: PRIMARY, transition: 'width 0.3s ease' }} />
                      </div>
                      {m.pullInfo.error && (
                        <div style={{ color: ERROR_COLOR, fontSize: '10px', marginTop: '3px' }}>
                          {m.pullInfo.error}
                        </div>
                      )}
                    </div>
                  )}
                </div>
              );
            })
          )}
        </div>
      </div>

      {/* ── 5. Catalog Section: Available in Ollama Library ──────────────── */}
      <div>
        <div style={{
          fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)',
          textTransform: 'uppercase', letterSpacing: '.05em', marginBottom: '8px',
          display: 'flex', alignItems: 'center', gap: '6px',
        }}>
          <Sparkles size={12} />
          <span>Available in Ollama Library ({catalogModels.length})</span>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
          {catalogModels.length === 0 ? (
            <div style={{ padding: '16px', textAlign: 'center', color: 'var(--text-muted)', fontSize: '11px' }}>
              No catalog models matched your search.
            </div>
          ) : (
            catalogModels.map(m => (
              <div
                key={m.id}
                style={{
                  padding: '10px 14px', borderRadius: 'var(--radius-sm, 8px)',
                  border: '1px solid var(--border-subtle)',
                  background: 'color-mix(in srgb, var(--matugen-surface-container, #16252c) 40%, transparent)',
                  display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '10px',
                }}
              >
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '6px', marginBottom: '2px' }}>
                    <span style={{ fontSize: '12px', fontWeight: 600, color: 'var(--text-primary)' }}>{m.name}</span>
                    <span style={{ fontSize: '10.5px', color: 'var(--matugen-primary, #a0c9dc)' }}>({m.id})</span>
                    {m.isRecommended && (
                      <span style={{
                        background: 'rgba(160, 201, 220, 0.18)', color: PRIMARY,
                        fontSize: '9px', fontWeight: 700, padding: '1px 5px', borderRadius: '4px',
                      }}>
                        RECOMMENDED
                      </span>
                    )}
                  </div>
                  <div style={{ fontSize: '10.5px', color: 'var(--text-muted)', marginBottom: '4px' }}>
                    {m.desc}
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '10px', color: 'var(--text-secondary)' }}>
                    <span style={{ background: 'rgba(255,255,255,0.06)', padding: '1px 5px', borderRadius: '3px' }}>
                      {m.param}
                    </span>
                    <span style={{ background: 'rgba(255,255,255,0.06)', padding: '1px 5px', borderRadius: '3px' }}>
                      {m.context} ctx
                    </span>
                    <span>Est. {m.size}</span>
                  </div>
                </div>

                <button
                  type="button"
                  onClick={() => handlePull(m.id)}
                  disabled={!isOnline}
                  style={{
                    background: PRIMARY, color: ON_PRIMARY, border: 'none',
                    borderRadius: '5px', padding: '5px 12px', fontSize: '11px', fontWeight: 700,
                    cursor: isOnline ? 'pointer' : 'not-allowed',
                    opacity: isOnline ? 1 : 0.5,
                    display: 'inline-flex', alignItems: 'center', gap: '4px',
                    whiteSpace: 'nowrap',
                  }}
                  title={isOnline ? `Pull ${m.id} to local disk` : 'Start Ollama service to pull'}
                >
                  <Download size={11} />
                  <span>Pull</span>
                </button>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
};
