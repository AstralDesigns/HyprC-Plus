import React from 'react';
import { Sliders, RotateCcw, Check, Globe } from 'lucide-react';
import { useStore, setStore } from '../store';
import { bridge } from '../bridge';
import { DottedIntervalSlider, SliderTick } from './DottedIntervalSlider';

export const AISettingsPanel: React.FC<{ tab: 'ollama' | 'openrouter' }> = ({ tab }) => {
  const [store] = useStore();
  const [hostStatus, setHostStatus] = React.useState<string | null>(null);
  const [testingHost, setTestingHost] = React.useState(false);

  const aiSettings = store.aiSettings;

  const updateOpenRouter = (partial: Partial<typeof aiSettings.openrouter>) => {
    const next = {
      ...aiSettings,
      openrouter: {
        ...aiSettings.openrouter,
        ...partial,
      },
    };
    setStore({ aiSettings: next });
    bridge.updateAISettings(next).catch(() => {});
  };

  const updateOllama = (partial: Partial<typeof aiSettings.ollama>) => {
    const next = {
      ...aiSettings,
      ollama: {
        ...aiSettings.ollama,
        ...partial,
      },
    };
    setStore({ aiSettings: next });
    bridge.updateAISettings(next).catch(() => {});
  };

  const resetDefaults = () => {
    if (tab === 'openrouter') {
      updateOpenRouter({
        temperature: 0.2,
        reasoningEffort: 'high',
        reasoningTokens: 16384,
        maxOutputTokens: 16384,
        topP: 1.0,
      });
    } else {
      updateOllama({
        host: 'http://localhost:11434',
        temperature: 0.2,
        numCtx: 32768,
        maxOutputTokens: 8192,
        topP: 0.9,
      });
    }
  };

  const testOllamaHost = async () => {
    setTestingHost(true);
    setHostStatus(null);
    try {
      const res = await bridge.getOllamaStatus();
      if (res.online) {
        setHostStatus(`Online (v${res.version || 'unknown'})`);
      } else {
        setHostStatus(res.error || 'Offline / unreachable');
      }
    } catch (e: any) {
      setHostStatus(e?.message || 'Error connecting to host');
    } finally {
      setTestingHost(false);
    }
  };

  // OpenRouter Ticks
  const reasoningTicks: SliderTick[] = [
    { value: 8192, label: '8k' },
    { value: 16384, label: '16k', isRecommended: true },
    { value: 32768, label: '32k' },
    { value: 65536, label: '64k' },
    { value: 131072, label: '128k' },
    { value: 262144, label: '256k' },
    { value: -1, label: 'Uncapped' },
  ];

  const orTempTicks: SliderTick[] = [
    { value: 0.0, label: '0.0' },
    { value: 0.2, label: '0.2', isRecommended: true },
    { value: 0.4, label: '0.4' },
    { value: 0.7, label: '0.7' },
    { value: 1.0, label: '1.0' },
  ];

  const orMaxTokensTicks: SliderTick[] = [
    { value: 4096, label: '4k' },
    { value: 8192, label: '8k' },
    { value: 16384, label: '16k', isRecommended: true },
    { value: 32768, label: '32k' },
    { value: 65536, label: '64k' },
    { value: -1, label: 'Uncapped' },
  ];

  const orTopPTicks: SliderTick[] = [
    { value: 0.1, label: '0.1' },
    { value: 0.5, label: '0.5' },
    { value: 0.8, label: '0.8' },
    { value: 0.9, label: '0.9' },
    { value: 1.0, label: '1.0', isRecommended: true },
  ];

  // Ollama Ticks
  const olCtxTicks: SliderTick[] = [
    { value: 4096, label: '4k' },
    { value: 8192, label: '8k' },
    { value: 16384, label: '16k' },
    { value: 32768, label: '32k', isRecommended: true },
    { value: 65536, label: '64k' },
    { value: 131072, label: '128k' },
  ];

  const olTempTicks: SliderTick[] = [
    { value: 0.0, label: '0.0' },
    { value: 0.2, label: '0.2', isRecommended: true },
    { value: 0.4, label: '0.4' },
    { value: 0.7, label: '0.7' },
    { value: 1.0, label: '1.0' },
  ];

  const olMaxTokensTicks: SliderTick[] = [
    { value: 2048, label: '2k' },
    { value: 4096, label: '4k' },
    { value: 8192, label: '8k', isRecommended: true },
    { value: 16384, label: '16k' },
    { value: 32768, label: '32k' },
    { value: -1, label: 'Uncapped' },
  ];

  const olTopPTicks: SliderTick[] = [
    { value: 0.1, label: '0.1' },
    { value: 0.5, label: '0.5' },
    { value: 0.8, label: '0.8' },
    { value: 0.9, label: '0.9', isRecommended: true },
    { value: 1.0, label: '1.0' },
  ];

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '6px' }}>
        <div style={{ fontSize: '13px', fontWeight: 700, color: 'var(--text-primary)', display: 'flex', alignItems: 'center', gap: '6px' }}>
          <Sliders size={14} color="var(--matugen-primary, #a0c9dc)" />
          <span>{tab === 'openrouter' ? 'OpenRouter Cloud Parameters' : 'Ollama Local Engine Parameters'}</span>
        </div>
        <button
          type="button"
          onClick={resetDefaults}
          style={{
            background: 'none', border: '1px solid var(--border-subtle)', borderRadius: '4px',
            color: 'var(--text-muted)', fontSize: '11px', padding: '3px 8px', cursor: 'pointer',
            display: 'inline-flex', alignItems: 'center', gap: '4px',
          }}
          title="Restore recommended defaults"
        >
          <RotateCcw size={10} /> Reset Defaults
        </button>
      </div>

      {tab === 'openrouter' ? (
        <>
          {/* Reasoning tokens slider */}
          <DottedIntervalSlider
            label="Reasoning Token Budget (Chain-of-Thought)"
            description="Controls how deeply frontier models (Claude 3.7, DeepSeek-R1, GPT-5) think before output. Uncapped allows uninhibited maximum reasoning."
            value={aiSettings.openrouter.reasoningTokens}
            onChange={(val) => updateOpenRouter({ reasoningTokens: val })}
            ticks={reasoningTicks}
            formatDisplay={(v) => (v === -1 ? 'Uncapped / Max' : `${v.toLocaleString()} tokens`)}
          />

          {/* Reasoning effort */}
          <div className="dotted-slider-card">
            <div className="dotted-slider-header">
              <div>
                <div className="dotted-slider-label">Reasoning Effort Level</div>
                <div className="dotted-slider-desc">Effort tier sent to OpenRouter API (low, medium, high)</div>
              </div>
              <div style={{ display: 'flex', gap: '4px' }}>
                {(['low', 'medium', 'high'] as const).map((effort) => (
                  <button
                    key={effort}
                    type="button"
                    onClick={() => updateOpenRouter({ reasoningEffort: effort })}
                    style={{
                      background: aiSettings.openrouter.reasoningEffort === effort ? 'var(--matugen-primary, #a0c9dc)' : 'transparent',
                      color: aiSettings.openrouter.reasoningEffort === effort ? 'var(--matugen-on-secondary, #1d343c)' : 'var(--text-muted)',
                      border: '1px solid var(--border-subtle)',
                      borderRadius: '4px',
                      padding: '2px 8px',
                      fontSize: '11px',
                      fontWeight: 600,
                      cursor: 'pointer',
                      textTransform: 'capitalize',
                    }}
                  >
                    {effort}{effort === 'high' ? ' ★' : ''}
                  </button>
                ))}
              </div>
            </div>
          </div>

          {/* Temperature */}
          <DottedIntervalSlider
            label="Sampling Temperature"
            description="Randomness of output tokens. 0.2 is strictly recommended for coding to avoid syntax defects."
            value={aiSettings.openrouter.temperature}
            onChange={(val) => updateOpenRouter({ temperature: val })}
            ticks={orTempTicks}
            formatDisplay={(v) => `${v.toFixed(2)}`}
          />

          {/* Max Output Tokens */}
          <DottedIntervalSlider
            label="Maximum Completion Output Tokens"
            description="Overall limit on output text per turn. Uncapped uses model context ceiling."
            value={aiSettings.openrouter.maxOutputTokens}
            onChange={(val) => updateOpenRouter({ maxOutputTokens: val })}
            ticks={orMaxTokensTicks}
            formatDisplay={(v) => (v === -1 ? 'Max / Uncapped' : `${v.toLocaleString()} tokens`)}
          />

          {/* Top P */}
          <DottedIntervalSlider
            label="Nucleus Sampling (Top P)"
            description="Cumulative probability threshold for nucleus sampling."
            value={aiSettings.openrouter.topP}
            onChange={(val) => updateOpenRouter({ topP: val })}
            ticks={orTopPTicks}
            formatDisplay={(v) => `${v.toFixed(2)}`}
          />
        </>
      ) : (
        <>
          {/* Ollama Host URL */}
          <div className="dotted-slider-card">
            <div className="dotted-slider-header" style={{ marginBottom: '8px' }}>
              <div>
                <div className="dotted-slider-label">Ollama Daemon Host</div>
                <div className="dotted-slider-desc">HTTP address of your local Ollama server</div>
              </div>
              {hostStatus && (
                <div style={{
                  fontSize: '11px', fontWeight: 600,
                  color: hostStatus.includes('Online') ? 'var(--accent-green, #22c55e)' : 'var(--matugen-error, #ef4444)',
                }}>
                  {hostStatus}
                </div>
              )}
            </div>
            <div style={{ display: 'flex', gap: '8px' }}>
              <input
                type="text"
                value={aiSettings.ollama.host}
                onChange={(e) => updateOllama({ host: e.target.value })}
                style={{
                  flex: 1, padding: '6px 10px', background: 'rgba(0,0,0,0.22)',
                  border: '1px solid var(--border-subtle)', borderRadius: '6px',
                  color: 'var(--text-primary)', fontSize: '12px', outline: 'none',
                }}
                placeholder="http://localhost:11434"
              />
              <button
                type="button"
                onClick={testOllamaHost}
                disabled={testingHost}
                style={{
                  background: 'var(--matugen-primary, #a0c9dc)', color: 'var(--matugen-on-secondary, #1d343c)',
                  border: 'none', borderRadius: '6px', padding: '0 12px', fontSize: '11px', fontWeight: 600,
                  cursor: 'pointer',
                }}
              >
                {testingHost ? 'Checking…' : 'Ping Host'}
              </button>
            </div>
          </div>

          {/* Context Window (num_ctx) */}
          <DottedIntervalSlider
            label="Context Window Size (num_ctx)"
            description="Allocated token window in VRAM/RAM for conversation history and code context."
            value={aiSettings.ollama.numCtx}
            onChange={(val) => updateOllama({ numCtx: val })}
            ticks={olCtxTicks}
            formatDisplay={(v) => `${(v / 1024).toFixed(0)}k tokens (${v.toLocaleString()})`}
          />

          {/* Temperature */}
          <DottedIntervalSlider
            label="Sampling Temperature"
            description="Randomness of local output tokens. 0.2 is recommended for local coder models."
            value={aiSettings.ollama.temperature}
            onChange={(val) => updateOllama({ temperature: val })}
            ticks={olTempTicks}
            formatDisplay={(v) => `${v.toFixed(2)}`}
          />

          {/* Max Output Tokens */}
          <DottedIntervalSlider
            label="Maximum Output Tokens"
            description="Maximum continuation tokens per local completion/response."
            value={aiSettings.ollama.maxOutputTokens}
            onChange={(val) => updateOllama({ maxOutputTokens: val })}
            ticks={olMaxTokensTicks}
            formatDisplay={(v) => (v === -1 ? 'Uncapped' : `${v.toLocaleString()} tokens`)}
          />

          {/* Top P */}
          <DottedIntervalSlider
            label="Nucleus Sampling (Top P)"
            description="Probability cutoff for local generation (0.9 default for Ollama)."
            value={aiSettings.ollama.topP}
            onChange={(val) => updateOllama({ topP: val })}
            ticks={olTopPTicks}
            formatDisplay={(v) => `${v.toFixed(2)}`}
          />
        </>
      )}
    </div>
  );
};
