import { useEffect, useMemo, useState, type FormEvent, type FC } from 'react';
import { Cpu, Download, Check, Trash2, HardDrive, Zap, AlertTriangle, Database } from 'lucide-react';
import { useStore, setStore, storeActions, PRESET_MODELS, type ModelInfo } from '../store';
import { agentEngine } from '../engine/agent-engine';
import { llamaCppService } from '../engine/llama-cpp.service';
import { bridge } from '../bridge';

export const ModelManager: FC = () => {
  const [store] = useStore();
  const [gpuInfo, setGpuInfo] = useState<{
    supported: boolean;
    f16: boolean;
    adapterName?: string;
    error?: string;
  } | null>(null);
  const [cachedModelIds, setCachedModelIds] = useState<Set<string>>(new Set());
  const [customModelId, setCustomModelId] = useState('');
  const [searchResults, setSearchResults] = useState<Array<{ id: string; downloads?: number; likes?: number }>>([]);
  const [searching, setSearching] = useState(false);
  const [customModelError, setCustomModelError] = useState('');
  // Tracks which specific model card initiated the current fetch so only that
  // card's button shows the 'Fetching…' label (store.modelStatus is global).
  const [fetchingModelId, setFetchingModelId] = useState<string | null>(null);

  const workspaceStartupEnabled = store.workspaceStartupEnabled;

  const models = useMemo(() => {
    const presetIds = new Set(PRESET_MODELS.map((model) => model.id));
    return [
      ...PRESET_MODELS,
      ...(store.customModels || []).filter((model) => !presetIds.has(model.id) && model.llamaRepo && model.llamaFile),
    ].sort((a, b) => {
      const aLoaded = store.modelStatus === 'ready' && store.activeModel === a.id;
      const bLoaded = store.modelStatus === 'ready' && store.activeModel === b.id;
      const aCached = cachedModelIds.has(a.id);
      const bCached = cachedModelIds.has(b.id);
      if (aLoaded !== bLoaded) return aLoaded ? -1 : 1;
      if (aCached !== bCached) return aCached ? -1 : 1;
      return a.name.localeCompare(b.name);
    });
  }, [store.customModels, cachedModelIds, store.activeModel, store.modelStatus]);

  const refreshHardwareAndCache = async () => {
    console.log('[ModelManager] refreshHardwareAndCache:start', {
      modelCount: models.length,
      modelIds: models.map((model) => model.id),
      hasWebKit: Boolean((window as any).webkit?.messageHandlers?.agent),
      electronWorker: Boolean((window as any).__hyprcandyElectronAgent),
    });
    try {
      const info = llamaCppService.isEnabled()
        ? { supported: true, f16: true, adapterName: 'llama-server' }
        : await agentEngine.getWebGPUInfo();
      setGpuInfo(info);
      console.log('[ModelManager] WebGPU info', info);
    } catch (error: any) {
      setGpuInfo({ supported: false, f16: false, error: error?.message || String(error) });
      console.error('[ModelManager] WebGPU probe failed', error);
    }

    try {
      const ids = await agentEngine.getCachedModelIds(models.map((model) => model.id));
      setCachedModelIds(new Set(ids));
      console.log('[ModelManager] cache status', { cachedModelIds: ids });
    } catch (error) {
      console.warn('[ModelManager] Could not inspect model cache', error);
    }
  };

  useEffect(() => {
    console.log('[ModelManager] mounted/visibility update', {
      open: store.modelManagerOpen,
      activeModel: store.activeModel,
      modelStatus: store.modelStatus,
    });
    // Do one bounded refresh when the panel opens. Re-running this effect on
    // every custom-model mutation races an active llama-server pull/switch and
    // can keep the GJS/WebKit relay busy indefinitely. The cards themselves
    // update from the store without another cache scan.
    if (store.modelManagerOpen) void refreshHardwareAndCache();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [store.modelManagerOpen]);

  const handleWorkspaceStartupToggle = async () => {
    const nextEnabled = !workspaceStartupEnabled;
    try {
      const reply = await bridge.setWorkspaceStartupState(nextEnabled);
      const enabled = !!reply?.enabled;
      setStore({ workspaceStartupEnabled: enabled });
    } catch (error: any) {
      console.warn('[ModelManager] workspace startup state save failed', error);
    }
  };


  const handleSelectModel = async (model: ModelInfo) => {
    console.log('[ModelManager] load requested', { modelId: model.id, name: model.name });
    setFetchingModelId(model.id);
    try {
      await agentEngine.loadModel(model.id);
      setCachedModelIds((previous) => new Set(previous).add(model.id));
      console.log('[ModelManager] load completed', { modelId: model.id });
    } catch (error: any) {
      console.error('[ModelManager] load failed', { modelId: model.id, error });
    } finally {
      setFetchingModelId(null);
    }
  };

  const handleClearCache = async () => {
    if (!confirm('Clear all cached local model weights? You will need to redownload models.')) return;
    console.log('[ModelManager] clear cache requested');
    await agentEngine.clearCache();
    setCachedModelIds(new Set());
    console.log('[ModelManager] clear cache completed');
    alert('Local model cache cleared successfully.');
  };

  const handleSearchModels = async (event: FormEvent) => {
    event.preventDefault();
    setCustomModelError('');
    const id = customModelId.trim();
    if (!id) {
      setCustomModelError('Enter a model name, repository, or tool-supporting keyword to search.');
      return;
    }
    console.log('[ModelManager] Hugging Face search requested', { query: id });
    setSearching(true);
    try {
      const results = llamaCppService.isEnabled()
        ? await llamaCppService.searchModels(id)
        : await (async () => {
          const response = await fetch(`https://huggingface.co/api/models?search=${encodeURIComponent(`${id} tool calling GGUF`)}&sort=downloads&direction=-1&limit=8`);
          if (!response.ok) throw new Error(`Hugging Face search failed (${response.status})`);
          return response.json();
        })();
      setSearchResults(Array.isArray(results) ? results.filter((model) => typeof (model?.id || model?.modelId) === 'string').map((model) => ({
        id: model.id || model.modelId,
        downloads: model.downloads,
        likes: model.likes,
      })) : []);
      console.log('[ModelManager] Hugging Face search completed', {
        query: id,
        resultCount: Array.isArray(results) ? results.length : 0,
      });
    } catch (error: any) {
      setCustomModelError(error?.message || String(error));
      setSearchResults([]);
      console.error('[ModelManager] Hugging Face search failed', { query: id, error });
    } finally {
      setSearching(false);
    }
  };

  const handleAddCustomModel = async (repo: string) => {
    const modelId = repo.split('/').pop() || repo;
    console.log('[ModelManager] llama-server GGUF model requested', { repo, modelId });
    try {
      const files = llamaCppService.isEnabled()
        ? (await llamaCppService.inspectModel(repo)).files
        : await (async () => {
          const response = await fetch(`https://huggingface.co/api/models/${repo}?full=true`);
          if (!response.ok) throw new Error(`Could not inspect model files (${response.status})`);
          const metadata = await response.json();
          return (metadata?.siblings || []).map((file: any) => file?.rfilename).filter((file: any): file is string => typeof file === 'string');
        })();
      const gguf: string[] = files.filter((file: string) => /\.gguf$/i.test(file) && /Q[456](_K_[MS]|_0|_1)?/i.test(file));
      const selected = gguf.sort((a: string, b: string) => {
        const rank = (file: string) => /Q4_K_M/i.test(file) ? 0 : /Q5_K_M/i.test(file) ? 1 : /Q6_K/i.test(file) ? 2 : 3;
        return rank(a) - rank(b);
      })[0];
      if (!selected) throw new Error('No Q4, Q5, or Q6 GGUF file was found in that repository.');
      const selectedModel: ModelInfo = {
        id: repo,
        name: modelId,
        size: 'GGUF / local cache',
        vram: 'Depends on GPU layers',
        description: `llama-server GGUF model (${selected}); selected from a tool-supporting search result.`,
        llamaRepo: repo,
        llamaFile: selected,
        toolSupport: true,
      };
      storeActions.addCustomModel(selectedModel);
      console.log('[ModelManager] llama-server model registered', { repo, file: selected });
      // Collapse the search results as soon as the requested model is queued;
      // the model cards and download status remain visible while it loads.
      setSearchResults([]);
      setCustomModelId('');
      // A search result is an actionable model choice: register it and begin
      // the fetch immediately. Previously the click only added metadata, so
      // the user had to find the new card again before anything downloaded.
      await handleSelectModel(selectedModel);
      setCustomModelError('');
    } catch (error: any) {
      setCustomModelError(error?.message || String(error));
      console.error('[ModelManager] llama-server model registration failed', { repo, error });
    }
  };

  if (!store.modelManagerOpen) return null;

  return (
    <div
      onClick={() => setStore({ modelManagerOpen: false })}
      style={{
        position: 'absolute',
        inset: 0,
        background: 'rgba(0, 0, 0, 0.65)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        zIndex: 100,
      }}
    >
      <div style={{
        width: '580px',
        maxHeight: 'calc(88vh + 10px)',
        background: 'var(--matugen-on-secondary, #1d343c)',
        border: '1px solid var(--border-glass)',
        borderRadius: 'var(--radius-lg)',
        boxShadow: '0 16px 48px rgba(0, 0, 0, 0.6)',
        display: 'flex',
        flexDirection: 'column',
        overflow: 'hidden',
      }}
        className="animate-fade-in"
        onClick={(event) => event.stopPropagation()}
      >
        <div style={{
          padding: '16px 20px',
          borderBottom: '1px solid var(--border-subtle)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <Cpu size={20} color="var(--accent-cyan)" />
            <div>
              <h3 style={{ fontSize: '14px', fontWeight: 600, color: 'var(--text-primary)' }}>
                Local Model Manager
              </h3>
              <p style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                Fetch, cache, and load llama-server models.
              </p>
              <p style={{ fontSize: '11px', marginTop: '3px' }}>
                <a
                  href="https://huggingface.co/models?search=tool%20calling%20GGUF"
                  target="_blank"
                  rel="noopener noreferrer"
                  style={{ color: 'var(--accent-cyan)', textDecoration: 'none' }}
                  onMouseEnter={e => (e.currentTarget.style.textDecoration = 'underline')}
                  onMouseLeave={e => (e.currentTarget.style.textDecoration = 'none')}
                >
                  Find more tool supporting models
                </a>
              </p>
            </div>
          </div>
        </div>

        <div style={{
          padding: '10px 20px',
          background: 'rgba(160, 201, 220, 0.08)',
          borderBottom: '1px solid var(--border-subtle)',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between', fontSize: '11.5px',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', color: 'var(--text-primary)' }}>
            <span style={{ fontSize: '11.5px', color: 'var(--text-secondary)' }}>Workspace Startup Auto-Load</span>
            <button
              type="button"
              onClick={handleWorkspaceStartupToggle}
              title="Persist the workspace auto-load default for future launcher startups"
              style={{
                border: 'none',
                cursor: 'pointer',
                borderRadius: '999px',
                padding: '3px 10px',
                fontSize: '11px',
                fontWeight: 700,
                background: workspaceStartupEnabled ? 'var(--matugen-primary, #a0c9dc)' : 'var(--matugen-on-secondary, #1d343c)',
                color: workspaceStartupEnabled ? 'var(--matugen-on-secondary, #1d343c)' : 'var(--matugen-primary, #a0c9dc)',
                minWidth: '50px',
                boxShadow: '0 0 0 1px var(--border-subtle)',
              }}
            >
              {workspaceStartupEnabled ? 'ON' : 'OFF'}
            </button>
          </div>
        </div>

        <div style={{
          padding: '10px 20px',
          background: gpuInfo?.supported === false ? 'rgba(255, 142, 142, 0.12)' : 'rgba(160, 201, 220, 0.08)',
          borderBottom: '1px solid var(--border-subtle)',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between', fontSize: '11.5px',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', minWidth: 0 }}>
            {gpuInfo?.supported === false ? (
              <>
                <AlertTriangle size={15} color="var(--accent-red)" />
                <span style={{ color: 'var(--accent-red)' }}>
                  {gpuInfo.error || 'No usable WebGPU adapter detected.'}
                </span>
              </>
            ) : (
              <>
                <Zap size={15} color="var(--accent-cyan)" />
                <span style={{ color: 'var(--text-secondary)' }}>
                  {gpuInfo?.adapterName === 'llama-server' ? 'llama-server Backend: ' : 'WebGPU Acceleration: '}<strong style={{ color: 'var(--wallust-color3)' }}>
                    {gpuInfo ? 'Enabled' : 'Probing…'}
                  </strong>
                  {gpuInfo?.adapterName ? ` (${gpuInfo.adapterName})` : ''}
                  {gpuInfo && !gpuInfo.f16 && (
                    <span style={{ color: 'var(--accent-yellow)', marginLeft: '6px' }}>(FP32 fallback)</span>
                  )}
                </span>
              </>
            )}
          </div>
          <button
            onClick={handleClearCache}
            style={{
              background: 'transparent', border: 'none', color: 'var(--text-muted)', cursor: 'pointer',
              display: 'flex', alignItems: 'center', gap: '4px', fontSize: '11px', flexShrink: 0,
            }}
            title="Free storage space by clearing weights"
          >
            <Trash2 size={13} /> Clear Cache
          </button>
          {(store.modelStatus === 'downloading' || store.modelStatus === 'loading') && (
            <button
              onClick={() => agentEngine.cancelModelLoad()}
              style={{
                background: 'transparent', border: 'none', color: 'var(--accent-yellow)', cursor: 'pointer',
                display: 'flex', alignItems: 'center', gap: '4px', fontSize: '11px', flexShrink: 0,
              }}
              title="Cancel the current model load"
            >
              <X size={13} /> Cancel Load
            </button>
          )}
        </div>

        <div style={{ padding: '14px 20px', borderBottom: '1px solid var(--border-subtle)' }}>
        <form onSubmit={handleSearchModels} style={{ display: 'flex', flexDirection: 'column', gap: '7px' }}>
          <div style={{ display: 'flex', gap: '8px' }}>
            <input
              type="text"
              value={customModelId}
              onChange={(event) => setCustomModelId(event.target.value)}
              placeholder="Search for tool-supporting llama-server GGUF models…"
              aria-label="Search Hugging Face models"
              style={inputStyle}
            />
            <button
              type="submit"
              disabled={!customModelId.trim() || searching}
                style={{
                  padding: '7px 12px', background: 'var(--bg-glass)', border: '1px solid var(--border-subtle)',
                  borderRadius: 'var(--radius-sm)', color: 'var(--text-primary)', fontSize: '11px',
                  cursor: 'pointer', whiteSpace: 'nowrap',
                }}
              >
                {searching ? 'Searching models…' : 'Search models'}
              </button>
            </div>
            {customModelError && <span style={{ color: 'var(--accent-red)', fontSize: '11px' }}>{customModelError}</span>}
            {searchResults.length > 0 && (
              <div
                aria-label="Hugging Face search results"
                style={{
                  maxHeight: '120px',
                  overflowY: 'auto',
                  display: 'flex',
                  flexDirection: 'column',
                  gap: '6px',
                  padding: '2px 4px 2px 0',
                  overscrollBehavior: 'contain',
                  scrollbarWidth: 'thin',
                }}
              >
                {searchResults.map((result) => (
                  <button
                    key={result.id}
                    type="button"
                    onClick={() => handleAddCustomModel(result.id)}
                    style={{ ...searchResultStyle, textAlign: 'left', flexShrink: 0 }}
                  >
                    <strong>{result.id}</strong>
                    <span>{result.downloads ? `${result.downloads.toLocaleString()} downloads` : 'Hugging Face model'}</span>
                  </button>
                ))}
              </div>
            )}
          </form>
        </div>

        {(store.modelStatus === 'downloading' || store.modelStatus === 'loading') && (
          <div style={{ padding: '14px 20px', background: 'rgba(0, 0, 0, 0.25)', borderBottom: '1px solid var(--border-subtle)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '11.5px', marginBottom: '6px' }}>
              <span style={{ color: 'var(--text-primary)', fontWeight: 500 }}>{store.downloadProgress.text}</span>
              <span style={{ color: 'var(--accent-cyan)', fontWeight: 600 }}>{store.downloadProgress.progress}%</span>
            </div>
            <div style={{ height: '6px', background: 'rgba(255, 255, 255, 0.1)', borderRadius: '3px', overflow: 'hidden' }}>
              <div style={{ height: '100%', width: `${store.downloadProgress.progress}%`, background: 'linear-gradient(90deg, var(--accent-cyan), var(--wallust-color3))', transition: 'width 0.2s ease' }} />
            </div>
          </div>
        )}

        <div style={{ flex: 1, overflowY: 'auto', padding: '16px 20px', display: 'flex', flexDirection: 'column', gap: '10px' }}>
          {models.map((model) => {
            const isActive = store.activeModel === model.id;
            const isDownloading = store.modelStatus === 'downloading' || store.modelStatus === 'loading';
            const isReady = store.modelStatus === 'ready' && isActive;
            const isCustom = !PRESET_MODELS.some((preset) => preset.id === model.id);
            const isCached = cachedModelIds.has(model.id);

            return (
              <div key={model.id} style={{
                padding: '14px 16px', borderRadius: 'var(--radius-md)',
                background: isActive ? 'rgba(160, 201, 220, 0.08)' : 'rgba(255, 255, 255, 0.03)',
                border: `1px solid ${isActive ? 'var(--border-active)' : 'var(--border-subtle)'}`,
                display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '12px',
              }}>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '4px', flexWrap: 'wrap' }}>
                    <span style={{ fontWeight: 600, fontSize: '13px', color: 'var(--text-primary)' }}>{model.name}</span>
                    {model.isDefault && <span style={badgeStyle}>Recommended</span>}
                    {isCached && <span style={{ ...badgeStyle, color: 'var(--wallust-color3)' }}><Database size={10} /> Cached</span>}
                  </div>
                  <p style={{ fontSize: '11.5px', color: 'var(--text-secondary)', marginBottom: '6px' }}>{model.description}</p>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '12px', fontSize: '11px', color: 'var(--text-muted)', flexWrap: 'wrap' }}>
                    <span style={{ display: 'flex', alignItems: 'center', gap: '4px' }}><HardDrive size={12} /> {model.size}</span>
                    <span style={{ display: 'flex', alignItems: 'center', gap: '4px' }}><Cpu size={12} /> {model.vram} VRAM</span>
                    <span>{/q4f32/i.test(model.id) ? 'FP32' : 'FP16 / shader-f16'}</span>
                    {isCustom && model.required_features?.length ? <span>{model.required_features.join(', ')}</span> : null}
                  </div>
                </div>

                <div>
                  {isReady ? (
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                      <span style={{ display: 'flex', alignItems: 'center', gap: '5px', color: 'var(--wallust-color3)', fontSize: '12px', fontWeight: 600 }}>
                        <Check size={16} /> Active
                      </span>
                      {isCustom && <RemoveButton modelId={model.id} />}
                    </div>
                  ) : (
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <button
                        onClick={() => handleSelectModel(model)}
                        disabled={isDownloading}
                        style={{
                          display: 'flex', alignItems: 'center', gap: '6px', padding: '7px 14px', borderRadius: 'var(--radius-sm)',
                          border: 'none', background: isActive ? 'var(--accent-cyan)' : 'rgba(255, 255, 255, 0.08)',
                          color: isActive ? 'var(--matugen-on-primary, #003544)' : 'var(--text-primary)',
                          cursor: isDownloading ? 'not-allowed' : 'pointer', fontSize: '11.5px', fontWeight: 600,
                        }}
                      >
                        <Download size={14} /> {fetchingModelId === model.id
                          ? (store.modelStatus === 'downloading' ? 'Fetching…' : 'Loading cache…')
                          : isDownloading ? 'Busy…' : isCached ? 'Load Cached' : 'Fetch & Load'}
                      </button>
                      {isCustom && <RemoveButton modelId={model.id} />}
                    </div>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );

  function RemoveButton({ modelId }: { modelId: string }) {
    return (
      <button
        onClick={() => storeActions.removeCustomModel(modelId)}
        style={{ background: 'transparent', border: 'none', color: 'var(--text-muted)', cursor: 'pointer', padding: '5px' }}
        title="Remove custom model registration (cached weights are kept)"
      >
        <Trash2 size={14} />
      </button>
    );
  }
};

const inputStyle = {
  flex: 1,
  minWidth: 0,
  background: 'var(--bg-input)',
  border: '1px solid var(--border-subtle)',
  borderRadius: 'var(--radius-sm)',
  padding: '8px 10px',
  color: 'var(--text-primary)',
  fontSize: '11px',
  outline: 'none',
};

const searchResultStyle = {
  display: 'flex',
  flexDirection: 'column' as const,
  gap: '3px',
  width: '100%',
  padding: '8px 10px',
  background: 'rgba(255, 255, 255, 0.04)',
  border: '1px solid var(--border-subtle)',
  borderRadius: 'var(--radius-sm)',
  color: 'var(--text-primary)',
  cursor: 'pointer',
  fontSize: '11px',
};

const badgeStyle = {
  display: 'inline-flex',
  alignItems: 'center',
  gap: '3px',
  fontSize: '10px',
  padding: '1px 6px',
  borderRadius: 'var(--radius-full)',
  background: 'rgba(160, 201, 220, 0.2)',
  color: 'var(--accent-cyan)',
  fontWeight: 600,
};
