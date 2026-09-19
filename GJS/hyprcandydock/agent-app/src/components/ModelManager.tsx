import { useCallback, useEffect, useRef, useState, type FC } from 'react';
import {
  AlertTriangle, Check, Cloud, Cpu,
  Eye, EyeOff, ExternalLink, HardDrive, Key, Loader, Play,
  RefreshCw, Trash2, Upload, X, Zap, Sparkles, TestTube, Search,
} from 'lucide-react';
import { useStore, setStore } from '../store';
import { bridge } from '../bridge';

// ── TESTING: set true to skip the BYOK Lemon Squeezy license gate ─────────────
// Set false before production shipping. In dev test mode, all providers are shown.
const DEV_BYPASS_BYOK_LICENSE = true;

// ── System Color Tokens (Matugen + Wallust) ───────────────────────────────────
// The user explicitly requested:
// - Buttons, active tabs, Candy Agent header icon: matugen primary bg + on-secondary fg
// - Active states, text, borders, provider indicators: matugen primary (no neon blue)
// - iOS toggle knob: wallust color5 when deactivated, matugen primary when activated
const PRIMARY       = 'var(--matugen-primary, #a0c9dc)';
const ON_PRIMARY    = 'var(--matugen-on-secondary, #1d343c)';
const INVERSE_PRI   = 'var(--matugen-inverse-primary, #a0c9dc)';
const COLOR5_AMBER  = 'var(--wallust-color5, #BA8C40)';
const ERROR_COLOR   = 'var(--matugen-error, #ffb4ab)';

const LS_BYOK_PRODUCT_ID   = ''; // Fill in after Lemon Squeezy approval
const LS_BYOK_CHECKOUT_URL = 'https://mirukai.gumroad.com/l/HyprCandy-Workspace';

// ── Official Provider SVG Icons ───────────────────────────────────────────────
export const OpenRouterIcon: FC<{ size?: number }> = ({ size = 16 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="#6366F1" xmlns="http://www.w3.org/2000/svg">
    <path d="M16.778 1.844v1.919q-.569-.026-1.138-.032-.708-.008-1.415.037c-1.93.126-4.023.728-6.149 2.237-2.911 2.066-2.731 1.95-4.14 2.75-.396.223-1.342.574-2.185.798-.841.225-1.753.333-1.751.333v4.229s.768.108 1.61.333c.842.224 1.789.575 2.185.799 1.41.798 1.228.683 4.14 2.75 2.126 1.509 4.22 2.11 6.148 2.236.88.058 1.716.041 2.555.005v1.918l7.222-4.168-7.222-4.17v2.176c-.86.038-1.611.065-2.278.021-1.364-.09-2.417-.357-3.979-1.465-2.244-1.593-2.866-2.027-3.68-2.508.889-.518 1.449-.906 3.822-2.59 1.56-1.109 2.614-1.377 3.978-1.466.667-.044 1.418-.017 2.278.02v2.176L24 6.014Z" />
  </svg>
);

export const GroqIcon: FC<{ size?: number }> = ({ size = 16 }) => (
  <svg width={size} height={size} viewBox="0 34 36 54" fill="#F55036" xmlns="http://www.w3.org/2000/svg">
    <path d="M17.77,34.048C7.971,34.048,0,42.019,0,51.817s7.971,17.77,17.77,17.77h5.844v-6.664H17.77 c-6.124,0-11.106-4.982-11.106-11.106s4.982-11.106,11.106-11.106s11.132,4.982,11.132,11.106l0,0v16.365l0,0 c0,6.084-4.954,11.039-11.023,11.103c-2.904-0.024-5.681-1.191-7.729-3.25l-4.712,4.712c3.266,3.283,7.691,5.151,12.321,5.201 v0.003c0.04,0,0.08,0,0.119,0h0.125v-0.003c9.659-0.131,17.48-8.005,17.525-17.686l0.006-16.881 C35.302,41.785,27.422,34.048,17.77,34.048z" />
  </svg>
);

export const GoogleGeminiIcon: FC<{ size?: number }> = ({ size = 16 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
    <path
      d="M12 0C12 6.627 6.627 12 0 12C6.627 12 12 17.373 12 24C12 17.373 17.373 12 24 12C17.373 12 12 6.627 12 0Z"
      fill="url(#mm-gemini-gradient)"
    />
    <defs>
      <linearGradient id="mm-gemini-gradient" x1="0" y1="12" x2="24" y2="12" gradientUnits="userSpaceOnUse">
        <stop stopColor="#4285F4" />
        <stop offset="0.5" stopColor="#9B72CB" />
        <stop offset="1" stopColor="#D96570" />
      </linearGradient>
    </defs>
  </svg>
);

export const AnthropicIcon: FC<{ size?: number }> = ({ size = 16 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="#D97757" xmlns="http://www.w3.org/2000/svg">
    <path d="M17.3041 3.541h-3.6718l6.696 16.918H24Zm-10.6082 0L0 20.459h3.7442l1.3693-3.5527h7.0052l1.3693 3.5528h3.7442L10.5363 3.5409Zm-.3712 10.2232 2.2914-5.9456 2.2914 5.9456Z" />
  </svg>
);

export const OpenAIIcon: FC<{ size?: number }> = ({ size = 16 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="#10A37F" xmlns="http://www.w3.org/2000/svg">
    <path d="M22.282 9.821a5.985 5.985 0 0 0-.516-4.91 6.046 6.046 0 0 0-6.51-2.9A6.065 6.065 0 0 0 4.981 4.18a5.985 5.985 0 0 0-3.998 2.9 6.046 6.046 0 0 0 .743 7.097 5.98 5.98 0 0 0 .51 4.911 6.051 6.051 0 0 0 6.515 2.9A5.985 5.985 0 0 0 13.26 24a6.056 6.056 0 0 0 5.771-4.206 5.99 5.99 0 0 0 3.997-2.9 6.056 6.056 0 0 0-.746-7.073zM13.26 22.43a4.476 4.476 0 0 1-2.876-1.04l.141-.081 4.779-2.758a.795.795 0 0 0 .392-.681v-6.737l2.02 1.168a.071.071 0 0 1 .038.052v5.583a4.504 4.504 0 0 1-4.494 4.494zM3.6 18.304a4.47 4.47 0 0 1-.535-3.014l.142.085 4.783 2.759a.771.771 0 0 0 .78 0l5.843-3.369v2.332a.08.08 0 0 1-.033.062L9.74 19.95a4.5 4.5 0 0 1-6.14-1.646zM2.34 8.937a4.485 4.485 0 0 1 2.366-1.973V12.6a.766.766 0 0 0 .388.677l5.815 3.355-2.02 1.168a.076.076 0 0 1-.071 0l-4.83-2.786A4.504 4.504 0 0 1 2.34 8.937zm16.597 3.855l-5.833-3.387L15.119 8.24a.076.076 0 0 1 .071 0l4.83 2.791a4.494 4.494 0 0 1-.674 8.105v-5.659a.79.79 0 0 0-.409-.685zm2.013-3.023l-.14-.085-4.773-2.782a.776.776 0 0 0-.785 0L9.409 10.27V7.934a.08.08 0 0 1 .033-.061l4.833-2.79a4.5 4.5 0 0 1 6.68 4.677v.004zm-11.458-3.08a4.48 4.48 0 0 1 2.87-1.04 4.504 4.504 0 0 1 4.5 4.5v2.24l-2.02-1.168a.076.076 0 0 0-.071 0L6.05 9.77a4.47 4.47 0 0 1 1.433-3.091z" />
  </svg>
);

export const XAIIcon: FC<{ size?: number }> = ({ size = 16 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="#1DA1F2" xmlns="http://www.w3.org/2000/svg">
    <path d="M6.469 8.776L16.512 23h-4.464L2.005 8.776H6.47zm-.004 7.9l2.233 3.164L6.467 23H2l4.465-6.324zM22 2.582V23h-3.659V7.764L22 2.582zM22 1l-9.952 14.095-2.233-3.163L17.533 1H22z" />
  </svg>
);

// ── BYOK provider definitions ─────────────────────────────────────────────────
// Order: OpenRouter, Groq, Google, Anthropic, OpenAI, Grok
export const BYOK_PROVIDERS = [
  {
    id: 'openrouter',
    name: 'OpenRouter',
    IconComponent: OpenRouterIcon,
    keyHint: 'sk-or-v1-...',
    apiKeyUrl: 'https://openrouter.ai/keys',
    keyLabel: 'OpenRouter API key',
    hasSearch: true,
    defaultModel: 'openrouter/free',
    models: [
      { id: 'openrouter/free',                        name: 'OpenRouter Free (Auto)',   ctx: '128k tokens', desc: 'Auto-cycles best available free models. NVIDIA Nemotron, Gemma 4, and other current free-tier models.' },
      { id: 'anthropic/claude-fable-5-1',             name: 'Claude Fable 5.1',         ctx: '1M tokens',   desc: 'Anthropic flagship (Sep 2026). Best-in-class reasoning & long-horizon agentic work.' },
      { id: 'anthropic/claude-sonnet-5',              name: 'Claude Sonnet 5',          ctx: '1M tokens',   desc: 'Best balance of speed & intelligence for production agentic coding.' },
      { id: 'openai/gpt-6-astra',                     name: 'GPT-6 Astra',              ctx: '128k tokens', desc: 'OpenAI flagship (Sep 2026). Frontier reasoning, computer use & advanced agents.' },
      { id: 'openai/gpt-5.6-sol',                     name: 'GPT-5.6 Sol',              ctx: '128k tokens', desc: 'High-capability flagship for complex professional work & reasoning.' },
      { id: 'google/gemini-3.8-flash',                name: 'Gemini 3.8 Flash',         ctx: '1M tokens',   desc: 'Google best Flash model — long-horizon coding & agents, 65K output.' },
      { id: 'x-ai/grok-4.6',                          name: 'Grok 4.6',                 ctx: '500k tokens', desc: 'xAI flagship (Aug 2026). Real-time knowledge, 500K context, advanced reasoning.' },
      { id: 'deepseek/deepseek-r1',                   name: 'DeepSeek R1',              ctx: '128k tokens', desc: 'Top open reasoning model for complex code & math.' },
      { id: 'meta-llama/llama-3.3-70b-instruct',      name: 'Llama 3.3 70B',            ctx: '128k tokens', desc: 'Meta open-weights flagship. High-speed versatile model.' },
    ],
  },
  {
    id: 'groq',
    name: 'Groq',
    IconComponent: GroqIcon,
    keyHint: 'gsk_...',
    apiKeyUrl: 'https://console.groq.com/keys',
    keyLabel: 'Groq Cloud API key',
    hasSearch: true,
    defaultModel: 'llama-3.3-70b-versatile',
    models: [
      { id: 'openai/gpt-oss-120b',               name: 'GPT-OSS 120B',            ctx: '128k tokens', desc: 'OpenAI open-weights flagship on Groq LPU. Complex reasoning & agentic tasks. Recommended.' },
      { id: 'openai/gpt-oss-20b',                name: 'GPT-OSS 20B',             ctx: '128k tokens', desc: 'Compact open-weights model. Fast inference, cost-efficient agentic workflows.' },
      { id: 'llama-3.3-70b-versatile',           name: 'Llama 3.3 70B',           ctx: '128k tokens', desc: 'Ultra-fast LPU inference (~300 t/s). Meta open-weights flagship.' },
      { id: 'llama-3.1-8b-instant',              name: 'Llama 3.1 8B Instant',    ctx: '128k tokens', desc: 'Blazing speed (~800 t/s). Best for low-latency quick answers.' },
      { id: 'qwen/qwen3-32b',                    name: 'Qwen3 32B',               ctx: '128k tokens', desc: 'Alibaba open-weights high-speed coding & reasoning model on Groq.' },
      { id: 'groq/compound',                     name: 'Groq Compound',           ctx: '128k tokens', desc: 'Groq compound model with integrated tool use & web search.' },
      { id: 'groq/compound-mini',                name: 'Groq Compound Mini',      ctx: '128k tokens', desc: 'Fast, cost-efficient Groq compound model for everyday tasks.' },
    ],
  },
  {
    id: 'google',
    name: 'Google Gemini',
    IconComponent: GoogleGeminiIcon,
    keyHint: 'AIzaSy...',
    apiKeyUrl: 'https://aistudio.google.com/apikey',
    keyLabel: 'Google AI Studio API key',
    models: [
      { id: 'gemini-3.8-flash',                  name: 'Gemini 3.8 Flash',        ctx: '1M tokens',  desc: 'Best Flash — long-horizon coding & agents, 65K output. Recommended.' },
      { id: 'gemini-3.6-flash',                  name: 'Gemini 3.6 Flash',        ctx: '1M tokens',  desc: 'Previous Flash generation — fast & capable.' },
      { id: 'gemini-3.1-pro-preview',            name: 'Gemini 3.1 Pro',          ctx: '1M tokens',  desc: 'Most intelligent Gemini model. Paid tier only.' },
      { id: 'gemini-3.1-flash-lite',             name: 'Gemini 3.1 Flash-Lite',   ctx: '1M tokens',  desc: 'Ultra-fast lightweight model. Free tier friendly.' },
    ],
  },
  {
    id: 'anthropic',
    name: 'Anthropic',
    IconComponent: AnthropicIcon,
    keyHint: 'sk-ant-api03-...',
    apiKeyUrl: 'https://console.anthropic.com/settings/keys',
    keyLabel: 'Anthropic API key',
    models: [
      { id: 'claude-fable-5-1',                  name: 'Claude Fable 5.1',        ctx: '1M tokens',   desc: 'Anthropic flagship (Sep 2026). Best demanding reasoning & long-horizon agentic work.' },
      { id: 'claude-opus-5',                     name: 'Claude Opus 5',           ctx: '1M tokens',   desc: 'Frontier agentic coding & enterprise-grade complex reasoning.' },
      { id: 'claude-sonnet-5',                   name: 'Claude Sonnet 5',         ctx: '1M tokens',   desc: 'Recommended default. Best balance of speed & intelligence for production. Recommended.' },
      { id: 'claude-haiku-4-5-20251001',              name: 'Claude Haiku 4.5',        ctx: '200k tokens', desc: 'Ultra-fast & cost-effective. Best for high-volume latency-sensitive tasks.' },
    ],
  },
  {
    id: 'openai',
    name: 'OpenAI',
    IconComponent: OpenAIIcon,
    keyHint: 'sk-proj-...',
    apiKeyUrl: 'https://platform.openai.com/api-keys',
    keyLabel: 'OpenAI API key',
    models: [
      { id: 'gpt-6-astra',                       name: 'GPT-6 Astra',             ctx: '128k tokens', desc: 'OpenAI flagship (Sep 2026). Frontier reasoning, computer use & advanced agentic tasks.' },
      { id: 'gpt-5.6-sol',                       name: 'GPT-5.6 Sol',             ctx: '128k tokens', desc: 'High-capability flagship for complex professional work. Also accessible as gpt-5.6.' },
      { id: 'gpt-5.6-terra',                     name: 'GPT-5.6 Terra',           ctx: '128k tokens', desc: 'Balanced model for general production use. Performance vs. cost sweet spot.' },
      { id: 'gpt-5.6-luna',                      name: 'GPT-5.6 Luna',            ctx: '128k tokens', desc: 'Cost-efficient model for high-volume workloads. Recommended for cost-sensitive tasks.' },
      { id: 'o4-mini',                           name: 'o4-mini',                 ctx: '200k tokens', desc: 'Optimized reasoning model for fast math, coding & STEM.' },
      { id: 'o3',                                name: 'o3',                      ctx: '200k tokens', desc: 'Advanced reasoning for complex analytical & scientific tasks.' },
    ],
  },
  {
    id: 'xai',
    name: 'xAI (Grok)',
    IconComponent: XAIIcon,
    keyHint: 'xai-...',
    apiKeyUrl: 'https://console.x.ai/',
    keyLabel: 'xAI API key',
    models: [
      { id: 'grok-4.6',                          name: 'Grok 4.6',                ctx: '500k tokens', desc: 'xAI flagship (Aug 2026). Real-time knowledge, 500K context, advanced reasoning & tool use.' },
      { id: 'grok-4.6-latest',                   name: 'Grok 4.6 Latest',         ctx: '500k tokens', desc: 'Auto-updated alias to the very latest Grok 4.6 build. Best for cutting-edge tasks.' },
      { id: 'grok-3',                            name: 'Grok 3',                  ctx: '131k tokens', desc: 'Previous generation flagship. Stable, reliable general-purpose intelligence.' },
    ],
  },
] as const;

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED PRIMITIVES
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Material-You / System-token styled iOS pill toggle switch.
 * Track: matugen inverse-primary background
 * Knob circle: wallust color5 when deactivated, matugen primary when activated
 */
export const IosToggle: FC<{
  checked: boolean;
  onChange: (checked: boolean) => void;
  disabled?: boolean;
  label?: string;
  size?: 'sm' | 'md';
}> = ({
  checked,
  onChange,
  disabled = false,
  label,
  size = 'md',
}) => {
  const isSm = size === 'sm';
  const width = isSm ? 32 : 38;
  const height = isSm ? 18 : 22;
  const knobSize = isSm ? 14 : 18;
  const knobTravel = isSm ? 14 : 16;

  // Exact user requirements:
  // - Background: matugen inverse-primary
  // - Knob circle: wallust color5 when deactivated, matugen primary when activated
  const knobColor = checked ? PRIMARY : COLOR5_AMBER;
  const trackBg = checked
    ? INVERSE_PRI
    : `color-mix(in srgb, ${INVERSE_PRI} 32%, transparent)`;

  return (
    <div
      onClick={e => {
        e.stopPropagation();
        if (!disabled) onChange(!checked);
      }}
      role="switch"
      aria-checked={checked}
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: '8px',
        cursor: disabled ? 'not-allowed' : 'pointer',
        opacity: disabled ? 0.55 : 1,
        userSelect: 'none',
      }}
    >
      <div
        style={{
          width: `${width}px`,
          height: `${height}px`,
          borderRadius: `${height / 2}px`,
          background: trackBg,
          border: `1px solid ${checked ? PRIMARY : `color-mix(in srgb, ${INVERSE_PRI} 45%, transparent)`}`,
          position: 'relative',
          transition: 'all 0.22s cubic-bezier(0.4, 0, 0.2, 1)',
          flexShrink: 0,
        }}
      >
        <div
          style={{
            position: 'absolute',
            top: '1px',
            left: checked ? `${knobTravel + 1}px` : '1px',
            width: `${knobSize}px`,
            height: `${knobSize}px`,
            borderRadius: '50%',
            background: knobColor,
            boxShadow: '0 1px 4px rgba(0,0,0,0.4)',
            transition: 'left 0.22s cubic-bezier(0.4, 0, 0.2, 1), background 0.2s ease',
          }}
        />
      </div>
      {label && (
        <span
          style={{
            fontSize: isSm ? '11px' : '11.5px',
            fontWeight: 700,
            color: checked ? PRIMARY : COLOR5_AMBER,
            letterSpacing: '0.02em',
          }}
        >
          {label}
        </span>
      )}
    </div>
  );
};

const StatusPill: FC<{ running: boolean; loading?: boolean; label?: string }> = ({ running, loading, label }) => (
  <span style={{
    display: 'inline-flex', alignItems: 'center', gap: '5px',
    padding: '3px 10px', borderRadius: 'var(--radius-full)', fontSize: '11px', fontWeight: 600,
    background: loading
      ? `color-mix(in srgb, ${COLOR5_AMBER} 16%, transparent)`
      : running
      ? `color-mix(in srgb, ${PRIMARY} 16%, transparent)`
      : 'color-mix(in srgb, var(--matugen-surface-variant, #40484c) 20%, transparent)',
    color: loading ? COLOR5_AMBER : running ? PRIMARY : 'var(--text-muted)',
    border: `1px solid ${
      loading
        ? `color-mix(in srgb, ${COLOR5_AMBER} 40%, transparent)`
        : running
        ? `color-mix(in srgb, ${PRIMARY} 40%, transparent)`
        : 'var(--border-subtle)'
    }`,
  }}>
    {loading
      ? <Loader size={10} style={{ animation: 'spin 1.5s linear infinite' }} />
      : <span style={{ width: 7, height: 7, borderRadius: '50%', background: running ? PRIMARY : 'var(--text-muted)', display: 'inline-block' }} />}
    {label ?? (loading ? 'Starting…' : running ? 'Running' : 'Stopped')}
  </span>
);

// ── Outer tab bar (Local / Cloud) ─────────────────────────────────────────────
const TabBar: FC<{ active: 'local' | 'cloud'; onChange: (t: 'local' | 'cloud') => void }> = ({ active, onChange }) => (
  <div style={{
    display: 'flex', gap: '4px', padding: '4px',
    background: 'color-mix(in srgb, var(--matugen-surface, #0c1014) 40%, transparent)',
    borderRadius: 'var(--radius-full, 9999px)',
    border: '1px solid var(--border-subtle)',
  }}>
    {(['local', 'cloud'] as const).map(tab => {
      const isSelected = active === tab;
      return (
        <button
          key={tab}
          onClick={() => onChange(tab)}
          style={{
            flex: 1, padding: '7px 0', border: 'none',
            borderRadius: 'var(--radius-full, 9999px)',
            fontWeight: 700, fontSize: '12px', cursor: 'pointer', transition: 'all .18s ease',
            background: isSelected ? PRIMARY : 'transparent',
            color: isSelected ? ON_PRIMARY : 'var(--text-secondary)',
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px',
            boxShadow: isSelected ? '0 1px 4px rgba(0,0,0,0.3)' : 'none',
          }}
        >
          {tab === 'local' ? <><Cpu size={13} />Local</> : <><Cloud size={13} />Cloud</>}
        </button>
      );
    })}
  </div>
);

// ═══════════════════════════════════════════════════════════════════════════════
// LOCAL TAB
// ═══════════════════════════════════════════════════════════════════════════════
interface LocalModel { path: string; filename: string; size_label: string; quant: string; id: string; }

const LocalTab: FC = () => {
  const [store] = useStore();
  const [localModels, setLocalModels]       = useState<any[]>([]);
  const [serverStatus, setServerStatus]     = useState<{ running: boolean; model_name?: string }>({ running: false });
  const [loadingServer, setLoadingServer]   = useState(false);
  const [downloadUrl, setDownloadUrl]       = useState('');
  const [downloadTaskId, setDownloadTaskId] = useState<string | null>(null);
  const [downloadProgress, setDownloadProgress] = useState(0);
  const [downloadText, setDownloadText]     = useState('');
  const [searchQuery, setSearchQuery]       = useState('');
  const [searchResults, setSearchResults]   = useState<any[]>([]);
  const [searching, setSearching]           = useState(false);
  const [error, setError]                   = useState('');
  const fileInputRef = useRef<HTMLInputElement>(null);
  const pollRef      = useRef<ReturnType<typeof setInterval> | null>(null);

  const refreshModels = useCallback(async () => {
    try {
      const d = await bridge.runtimeRequest('/api/models', {}, 'GET');
      setLocalModels(d.models || []);
    } catch { /* not ready */ }
  }, []);

  const refreshStatus = useCallback(async () => {
    try {
      const d = await bridge.runtimeRequest('/api/server/status', {}, 'GET');
      setServerStatus(d);
      if (d.running) {
        setStore({
          runtimeServerReady: true,
          ...(store.inferenceMode === 'local' ? { modelStatus: 'ready' } : {}),
          ...(d.model_name ? { activeModel: d.model_name } : {}),
        });
      }
    } catch {
      setServerStatus({ running: false });
    }
  }, [store.inferenceMode]);

  useEffect(() => {
    refreshModels();
    refreshStatus();
    const t = setInterval(refreshStatus, 4000);
    return () => clearInterval(t);
  }, [refreshModels, refreshStatus]);

  useEffect(() => {
    if (!downloadTaskId) return;
    pollRef.current = setInterval(async () => {
      try {
        const s = await bridge.runtimeRequest(`/api/models/pull/status/${downloadTaskId}`, {}, 'GET');
        setDownloadProgress(s.percent ?? 0);
        setDownloadText(s.text ?? '');
        if (s.done || s.error) {
          clearInterval(pollRef.current!);
          pollRef.current = null;
          setDownloadTaskId(null);
          if (s.error) setError(`Download failed: ${s.error}`);
          else { await refreshModels(); setDownloadUrl(''); }
        }
      } catch (e: any) {
        clearInterval(pollRef.current!);
        pollRef.current = null;
        setDownloadTaskId(null);
        setError(`Poll error: ${e?.message}`);
      }
    }, 800);
    return () => { if (pollRef.current) clearInterval(pollRef.current); };
  }, [downloadTaskId, refreshModels]);

  const handleStartServer = async (path: string) => {
    setLoadingServer(true); setError('');
    try {
      const r = await bridge.runtimeRequest('/api/server/start', { model_path: path, ctx_size: 0, max_tokens: 2048 });
      setServerStatus(r || { running: true });
      await refreshModels();
      const name = r?.model_name || path.split('/').pop()?.replace('.gguf', '') || path;
      // Deactivate any active cloud provider
      try { await bridge.runtimeRequest('/api/byok/deactivate'); } catch {}
      setStore({
        inferenceMode: 'local',
        byokProvider: null,
        modelStatus: 'ready',
        activeModel: name,
      });
      bridge.notifyModelStatus(true, name);
    } catch (e: any) {
      setError(e?.message || 'Failed to start llama-server');
    } finally {
      setLoadingServer(false);
    }
  };

  const handleStopServer = async () => {
    setLoadingServer(true);
    try {
      await bridge.runtimeRequest('/api/server/stop');
      setServerStatus({ running: false });
      await refreshModels();
      setStore({ modelStatus: 'idle', activeModel: '' });
      bridge.notifyModelStatus(false);
    } catch (e: any) {
      setError(e?.message || 'Failed to stop llama-server');
    } finally {
      setLoadingServer(false);
    }
  };

  const handleToggleLocalActive = async (activate: boolean) => {
    if (activate) {
      if (serverStatus.running) {
        try { await bridge.runtimeRequest('/api/byok/deactivate'); } catch {}
        setStore({
          inferenceMode: 'local',
          byokProvider: null,
          modelStatus: 'ready',
          ...(serverStatus.model_name ? { activeModel: serverStatus.model_name } : {}),
        });
        bridge.notifyModelStatus(true, serverStatus.model_name || 'local');
        return;
      }
      const candidate = localModels[0]?.path;
      if (!candidate) {
        setError('No local models installed. Download a model below or import from disk first.');
        return;
      }
      await handleStartServer(candidate);
    } else {
      await handleStopServer();
    }
  };

  const handleDelete = async (m: LocalModel) => {
    if (!confirm(`Delete "${m.filename}" (${m.size_label})?`)) return;
    try {
      await bridge.runtimeRequest('/api/models/delete', { path: m.path });
      await refreshModels();
      await refreshStatus();
      const wasActive = serverStatus.running && (
        serverStatus.model_name === m.id ||
        serverStatus.model_name === m.filename ||
        serverStatus.model_name === m.filename?.replace('.gguf', '')
      );
      if (wasActive) bridge.notifyModelStatus(false);
    } catch (e: any) {
      setError(e?.message || 'Delete failed');
    }
  };

  const handleDownload = async () => {
    if (!downloadUrl.trim() || downloadTaskId) return;
    setDownloadProgress(0); setDownloadText('Queuing…'); setError('');
    try {
      const r = await bridge.runtimeRequest('/api/models/pull/start', { url: downloadUrl.trim() });
      if (r?.task_id) setDownloadTaskId(r.task_id);
      else setError('No task_id returned');
    } catch (e: any) {
      setError(e?.message || 'Download failed');
    }
  };

  const handleSearch = async () => {
    if (!searchQuery.trim()) return;
    setSearching(true); setError(''); setSearchResults([]);
    try {
      const result = await bridge.runtimeRequest(`/api/models/search?q=${encodeURIComponent(searchQuery.trim())}`, {}, 'GET');
      setSearchResults(Array.isArray(result?.models) ? result.models.slice(0, 16) : []);
    } catch (e: any) {
      setError('Search failed — check internet connection');
    } finally {
      setSearching(false);
    }
  };

  const handleAddSearchResult = async (repo: string) => {
    setError('');
    try {
      const r = await fetch(`https://huggingface.co/api/models/${repo}?full=true`);
      const meta = await r.json();
      const files = (meta?.siblings || []).map((f: any) => f.rfilename).filter((f: string) => /\.gguf$/i.test(f));
      const ranked = [...files].sort((a: string, b: string) => {
        const rank = (f: string) => /Q4_K_M/i.test(f) ? 0 : /Q5_K_M/i.test(f) ? 1 : /Q4_K_S/i.test(f) ? 2 : /Q6_K/i.test(f) ? 3 : 4;
        return rank(a) - rank(b);
      });
      if (!ranked[0]) throw new Error('No GGUF files found. Try a quantized fork (bartowski, unsloth, etc.)');
      setDownloadUrl(`https://huggingface.co/${repo}/resolve/main/${ranked[0]}`);
      setSearchResults([]); setSearchQuery('');
    } catch (e: any) {
      setError(e?.message || 'Could not resolve GGUF');
    }
  };

  const isDownloading = !!downloadTaskId;
  const isLocalActive = serverStatus.running && store.inferenceMode === 'local';

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
      {/* Activation Bar with iOS Pill Toggle */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '12px 14px',
        background: isLocalActive
          ? `color-mix(in srgb, ${PRIMARY} 10%, transparent)`
          : 'color-mix(in srgb, var(--matugen-surface, #0c1014) 30%, transparent)',
        borderRadius: 'var(--radius-md)',
        border: `1px solid ${isLocalActive ? `color-mix(in srgb, ${PRIMARY} 45%, transparent)` : 'var(--border-subtle)'}`,
        transition: 'all .2s ease',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <div style={{
            width: 32, height: 32, borderRadius: 'var(--radius-sm)',
            background: isLocalActive ? `color-mix(in srgb, ${PRIMARY} 20%, transparent)` : 'color-mix(in srgb, var(--matugen-surface-variant, #40484c) 25%, transparent)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Zap size={16} color={isLocalActive ? PRIMARY : 'var(--text-muted)'} />
          </div>
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <span style={{ fontSize: '13px', fontWeight: 700, color: 'var(--text-primary)' }}>Local Runtime</span>
              <StatusPill running={serverStatus.running} loading={loadingServer} />
            </div>
            <div style={{ fontSize: '10.5px', color: 'var(--text-muted)', marginTop: '2px' }}>
              {serverStatus.running
                ? `Running on :17843 · ${serverStatus.model_name || 'GGUF model active'}`
                : 'Offline — toggle on to launch llama-server'}
            </div>
          </div>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <IosToggle
            checked={isLocalActive}
            onChange={handleToggleLocalActive}
            disabled={loadingServer}
            label={isLocalActive ? 'Active' : 'Inactive'}
          />
          <button onClick={refreshStatus} title="Refresh status"
            style={{ background: 'transparent', border: 'none', color: 'var(--text-muted)', cursor: 'pointer', display: 'flex', padding: '4px' }}>
            <RefreshCw size={12} />
          </button>
        </div>
      </div>

      {error && (
        <div style={{ padding: '8px 12px', background: `color-mix(in srgb, ${ERROR_COLOR} 12%, transparent)`, border: `1px solid color-mix(in srgb, ${ERROR_COLOR} 35%, transparent)`, borderRadius: 'var(--radius-sm)', fontSize: '11.5px', color: ERROR_COLOR, display: 'flex', gap: '7px', alignItems: 'flex-start' }}>
          <AlertTriangle size={13} style={{ flexShrink: 0, marginTop: 1 }} /> {error}
        </div>
      )}

      {/* Installed models */}
      <div>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '6px' }}>
          <div style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '.05em' }}>
            Installed Models ({localModels.length})
          </div>
          {localModels.length > 0 && (
            <button
              onClick={async () => {
                if (!confirm('Delete ALL GGUF models?')) return;
                try {
                  await bridge.runtimeRequest('/api/models/clear');
                  setServerStatus({ running: false });
                  await refreshModels();
                  setStore({ modelStatus: 'idle', activeModel: '' });
                  bridge.notifyModelStatus(false);
                } catch (e: any) { setError(e?.message); }
              }}
              style={{ display: 'flex', alignItems: 'center', gap: '4px', background: 'transparent', border: 'none', color: ERROR_COLOR, fontSize: '11px', cursor: 'pointer' }}
            >
              <Trash2 size={11} /> Clear Cache
            </button>
          )}
        </div>

        {localModels.length === 0 ? (
          <div style={{ padding: '16px', textAlign: 'center', color: 'var(--text-muted)', fontSize: '11.5px', border: '1px dashed var(--border-subtle)', borderRadius: 'var(--radius-md)' }}>
            No GGUF models found. Download one below or import from disk.
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
            {localModels.map((m) => {
              const active = !!(serverStatus.running && serverStatus.model_name && (
                serverStatus.model_name === m.id || serverStatus.model_name === m.filename ||
                serverStatus.model_name === m.filename?.replace('.gguf', '')
              ));
              return (
                <div key={m.path} style={{
                  display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '10px',
                  padding: '10px 12px', borderRadius: 'var(--radius-sm)',
                  background: active ? `color-mix(in srgb, ${PRIMARY} 12%, transparent)` : 'color-mix(in srgb, var(--matugen-surface, #0c1014) 22%, transparent)',
                  border: `1px solid ${active ? PRIMARY : 'var(--border-subtle)'}`,
                }}>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '7px' }}>
                      <span style={{ fontWeight: 600, fontSize: '12px', color: 'var(--text-primary)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: '210px' }}>
                        {m.filename}
                      </span>
                      {m.quant && (
                        <span style={{
                          fontSize: '10px', padding: '1px 6px', borderRadius: 'var(--radius-full)',
                          background: `color-mix(in srgb, ${PRIMARY} 20%, transparent)`,
                          color: PRIMARY, fontWeight: 600,
                        }}>
                          {m.quant}
                        </span>
                      )}
                    </div>
                    <div style={{ fontSize: '10.5px', color: 'var(--text-muted)', marginTop: '3px' }}>
                      <HardDrive size={10} style={{ marginRight: 3 }} />{m.size_label}
                    </div>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                    {active ? (
                      <span style={{ display: 'flex', alignItems: 'center', gap: '5px', color: PRIMARY, fontSize: '11px', fontWeight: 700 }}>
                        <Check size={13} /> Active
                      </span>
                    ) : (
                      <button onClick={() => handleStartServer(m.path)} disabled={loadingServer}
                        style={{ display: 'flex', alignItems: 'center', gap: '5px', padding: '6px 12px', borderRadius: 'var(--radius-sm)', border: 'none', background: PRIMARY, color: ON_PRIMARY, fontSize: '11px', fontWeight: 700, cursor: 'pointer' }}>
                        <Play size={11} /> Load
                      </button>
                    )}
                    <button onClick={() => handleDelete(m)} style={{ display: 'flex', alignItems: 'center', padding: '6px', borderRadius: 'var(--radius-sm)', border: 'none', background: 'rgba(255,255,255,.05)', color: 'var(--text-muted)', cursor: 'pointer' }}>
                      <Trash2 size={12} />
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Download by URL */}
      <div style={{ padding: '12px', background: 'color-mix(in srgb, var(--matugen-surface, #0c1014) 25%, transparent)', borderRadius: 'var(--radius-md)', border: '1px solid var(--border-subtle)' }}>
        <div style={{ fontSize: '11px', fontWeight: 600, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '.05em', marginBottom: '8px' }}>Download GGUF by URL</div>
        <div style={{ display: 'flex', gap: '6px' }}>
          <input type="text" value={downloadUrl} onChange={e => setDownloadUrl(e.target.value)}
            placeholder="HuggingFace direct .gguf URL…" onKeyDown={e => e.key === 'Enter' && handleDownload()} disabled={isDownloading}
            style={{ flex: 1, padding: '7px 10px', background: 'var(--bg-input)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--radius-sm)', color: 'var(--text-primary)', fontSize: '11px', outline: 'none', opacity: isDownloading ? 0.6 : 1 }} />
          <button onClick={handleDownload} disabled={!downloadUrl.trim() || isDownloading}
            style={{ padding: '7px 12px', background: PRIMARY, border: 'none', borderRadius: 'var(--radius-sm)', color: ON_PRIMARY, fontSize: '11px', fontWeight: 700, cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '5px', opacity: (!downloadUrl.trim() || isDownloading) ? 0.5 : 1 }}>
            {isDownloading ? <Loader size={11} style={{ animation: 'spin 1.5s linear infinite' }} /> : null}
            {isDownloading ? 'Downloading…' : 'Pull'}
          </button>
        </div>
        {isDownloading && (
          <div style={{ marginTop: '8px' }}>
            <div style={{ fontSize: '10.5px', color: 'var(--text-secondary)', marginBottom: '4px' }}>{downloadText}</div>
            <div style={{ height: '5px', background: 'rgba(255,255,255,.1)', borderRadius: '3px', overflow: 'hidden' }}>
              <div style={{ height: '100%', width: `${downloadProgress}%`, background: PRIMARY, transition: 'width .4s ease' }} />
            </div>
            <div style={{ fontSize: '10px', color: 'var(--text-muted)', marginTop: '3px', textAlign: 'right' }}>{downloadProgress}%</div>
          </div>
        )}
      </div>

      {/* HF Search */}
      <div style={{ padding: '12px', background: 'color-mix(in srgb, var(--matugen-surface, #0c1014) 25%, transparent)', borderRadius: 'var(--radius-md)', border: '1px solid var(--border-subtle)' }}>
        <div style={{ fontSize: '11px', fontWeight: 600, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '.05em', marginBottom: '4px' }}>Search HuggingFace</div>
        <div style={{ fontSize: '10.5px', color: 'var(--text-muted)', marginBottom: '7px' }}>
          Try: <code style={{ fontFamily: 'var(--font-mono)', color: PRIMARY }}>bartowski Qwen2.5</code>, <code style={{ fontFamily: 'var(--font-mono)', color: PRIMARY }}>unsloth llama</code>
        </div>
        <div style={{ display: 'flex', gap: '6px', marginBottom: searchResults.length ? '8px' : 0 }}>
          <input type="text" value={searchQuery} onChange={e => setSearchQuery(e.target.value)}
            placeholder="Search author or model name…" onKeyDown={e => e.key === 'Enter' && handleSearch()}
            style={{ flex: 1, padding: '7px 10px', background: 'var(--bg-input)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--radius-sm)', color: 'var(--text-primary)', fontSize: '11px', outline: 'none' }} />
          <button onClick={handleSearch} disabled={searching || !searchQuery.trim()}
            style={{ padding: '7px 12px', background: 'color-mix(in srgb, var(--matugen-surface-variant, #40484c) 25%, transparent)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--radius-sm)', color: 'var(--text-primary)', fontSize: '11px', cursor: 'pointer', whiteSpace: 'nowrap' }}>
            {searching ? 'Searching…' : 'Search'}
          </button>
        </div>
        {searchResults.length > 0 && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '5px', maxHeight: '160px', overflowY: 'auto' }}>
            {searchResults.map(r => {
              const id = r.id || r.modelId || '';
              const author = id.split('/')[0] || '';
              const isGguf = !!(r.tags?.includes('gguf') || r.library_name === 'gguf');
              return (
                <button key={id} onClick={() => handleAddSearchResult(id)}
                  style={{ display: 'flex', flexDirection: 'column', gap: '2px', padding: '7px 10px', background: 'color-mix(in srgb, var(--matugen-surface, #0c1014) 20%, transparent)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--radius-sm)', color: 'var(--text-primary)', cursor: 'pointer', fontSize: '11px', textAlign: 'left' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '7px' }}>
                    <strong style={{ color: PRIMARY }}>{id}</strong>
                    {isGguf && <span style={{ fontSize: '9px', padding: '1px 5px', background: `color-mix(in srgb, ${PRIMARY} 18%, transparent)`, color: PRIMARY, borderRadius: 'var(--radius-full)', fontWeight: 700 }}>GGUF</span>}
                  </div>
                  <div style={{ display: 'flex', gap: '10px', color: 'var(--text-muted)', fontSize: '10px' }}>
                    <span>by {author}</span>
                    {r.downloads && <span>↓ {r.downloads.toLocaleString()}</span>}
                  </div>
                </button>
              );
            })}
          </div>
        )}
      </div>

      {/* Import from disk */}
      <div style={{ display: 'flex', gap: '8px' }}>
        <input ref={fileInputRef} type="file" accept=".gguf" style={{ display: 'none' }} onChange={async e => {
          const file = e.target.files?.[0]; if (!file) return;
          try { await bridge.runtimeRequest('/api/models/import', { path: (file as any).path || file.name }); await refreshModels(); }
          catch (e: any) { setError(e?.message || 'Import failed'); }
        }} />
        <button onClick={async () => {
          setError(''); try { const p = await bridge.openFileDialog({ directory: false }); if (!p) return; await bridge.runtimeRequest('/api/models/import', { path: p }); await refreshModels(); } catch (e: any) { setError(e?.message || 'Import failed'); }
        }} style={{ display: 'flex', alignItems: 'center', gap: '6px', padding: '7px 12px', background: 'color-mix(in srgb, var(--matugen-surface-variant, #40484c) 25%, transparent)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--radius-sm)', color: 'var(--text-secondary)', fontSize: '11px', cursor: 'pointer' }}>
          <Upload size={12} /> Import from disk
        </button>
        <button onClick={refreshModels} style={{ display: 'flex', alignItems: 'center', gap: '5px', padding: '7px 10px', background: 'transparent', border: '1px solid var(--border-subtle)', borderRadius: 'var(--radius-sm)', color: 'var(--text-muted)', fontSize: '11px', cursor: 'pointer' }}>
          <RefreshCw size={11} />
        </button>
      </div>
    </div>
  );
};

// ═══════════════════════════════════════════════════════════════════════════════
// CLOUD TAB — Pure BYOK with Material-You Rounded Pills & Robust Show/Hide
// ═══════════════════════════════════════════════════════════════════════════════
const CloudTab: FC = () => {
  const [store] = useStore();

  // License gate state
  const [licenseInput, setLicenseInput]     = useState('');
  const [validatingLicense, setValidating]  = useState(false);
  const [licenseError, setLicenseError]     = useState('');
  const hasBYOKLicense = !!store.byokLicenseKey;

  // Selected provider in the scrollable tab bar
  const [selectedProviderId, setSelectedProviderId] = useState<string>(
    store.byokProvider || 'google'
  );

  // Per-provider key input and control state
  const [keyInputs, setKeyInputs]       = useState<Record<string, string>>({});
  const [showKey, setShowKey]           = useState<Record<string, boolean>>({});
  const [saving, setSaving]             = useState<Record<string, boolean>>({});
  const [providerErrors, setProvErrors] = useState<Record<string, string>>({});

  // ── Dynamic models per provider ─────────────────────────────────────────────
  const [fetchedModels, setFetchedModels] = useState<Record<string, Array<{ id: string; name: string; desc: string; context?: string; ctx?: string; has_tools?: boolean }>>>({});
  const [loadingModels, setLoadingModels] = useState<Record<string, boolean>>({});
  const [searchQuery, setSearchQuery]     = useState<Record<string, string>>({});
  const [modelsLive, setModelsLive]       = useState<Record<string, boolean>>({});
  const cardRefs = useRef<Record<string, HTMLButtonElement | null>>({});

  const fetchModelsForProvider = useCallback(async (providerId: string, force = false) => {
    if (!force && fetchedModels[providerId] && fetchedModels[providerId].length > 0) return;
    setLoadingModels(p => ({ ...p, [providerId]: true }));
    try {
      const res = await bridge.runtimeRequest(`/api/byok/models/${providerId}`, {}, 'GET');
      if (res?.models && Array.isArray(res.models) && res.models.length > 0) {
        setFetchedModels(p => ({ ...p, [providerId]: res.models }));
        setModelsLive(p => ({ ...p, [providerId]: !!res.live }));
      }
    } catch (e) {
      console.warn('[ModelManager] Failed to fetch dynamic models for', providerId, e);
    } finally {
      setLoadingModels(p => ({ ...p, [providerId]: false }));
    }
  }, [fetchedModels]);

  // Fetch models whenever selectedProviderId changes
  useEffect(() => {
    fetchModelsForProvider(selectedProviderId);
  }, [selectedProviderId, fetchModelsForProvider]);

  // ── Restore saved keys from GNOME Secrets & local runtime on mount ──────────
  useEffect(() => {
    let isMounted = true;
    (async () => {
      const foundKeys: Record<string, string> = {};
      for (const provider of BYOK_PROVIDERS) {
        let secret = store.byokKeys[provider.id];
        if (!secret) {
          secret = await bridge.lookupSecret(provider.id);
        }
        if (!secret) {
          try {
            const res = await bridge.runtimeRequest(`/api/byok/key/${provider.id}`, {}, 'GET');
            if (res?.key) secret = res.key;
          } catch { /* best effort */ }
        }
        if (secret) {
          foundKeys[provider.id] = secret;
          try {
            await bridge.runtimeRequest('/api/byok/set', {
              provider: provider.id,
              api_key: secret,
              set_active: store.byokProvider === provider.id,
            });
          } catch { /* best effort */ }
        }
      }
      if (isMounted && Object.keys(foundKeys).length > 0) {
        setStore(prev => ({
          byokKeys: { ...prev.byokKeys, ...foundKeys }
        }));
      }
    })();
    return () => { isMounted = false; };
  }, []);

  // ── When selecting a provider, ensure its key is loaded ─────────────────────
  useEffect(() => {
    if (!store.byokKeys[selectedProviderId]) {
      (async () => {
        let key = await bridge.lookupSecret(selectedProviderId);
        if (!key) {
          try {
            const res = await bridge.runtimeRequest(`/api/byok/key/${selectedProviderId}`, {}, 'GET');
            if (res?.key) key = res.key;
          } catch {}
        }
        if (key) {
          setStore(prev => ({
            byokKeys: { ...prev.byokKeys, [selectedProviderId]: key }
          }));
        }
      })();
    }
  }, [selectedProviderId]);

  // ── Lemon Squeezy license validation ────────────────────────────────────────
  const handleValidateLicense = async () => {
    const key = licenseInput.trim();
    if (!key) return;
    setValidating(true); setLicenseError('');
    try {
      const stored = store.byokLicenseInstanceId;
      let endpoint = 'https://api.lemonsqueezy.com/v1/licenses/validate';
      const body: any = { license_key: key };
      if (!stored) {
        endpoint = 'https://api.lemonsqueezy.com/v1/licenses/activate';
        body.instance_name = 'HyprCandy-Desktop';
      } else {
        body.instance_id = stored;
      }
      const resp = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Accept': 'application/json', 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      const data = await resp.json();
      const valid = data?.activated || data?.valid || false;
      if (!valid) {
        const errMsg = data?.error || data?.meta?.status_formatted || 'License key invalid or expired';
        setLicenseError(errMsg);
        return;
      }
      const instanceId = data?.instance?.id || stored || '';
      setStore({ byokLicenseKey: key, byokLicenseInstanceId: instanceId });
      setLicenseInput('');
    } catch (e: any) {
      setLicenseError(e?.message || 'Validation failed — check internet connection');
    } finally {
      setValidating(false);
    }
  };

  // ── Provider key saving (synced to GNOME Secrets + Python runtime) ───────────
  const handleSetProviderKey = async (providerId: string, autoActivate = true) => {
    const inputVal = keyInputs[providerId];
    const key = (inputVal !== undefined ? inputVal : store.byokKeys[providerId])?.trim();
    if (!key) return;
    setSaving(p => ({ ...p, [providerId]: true }));
    setProvErrors(p => ({ ...p, [providerId]: '' }));
    try {
      // 1. Store securely in GNOME Secrets via GJS libsecret
      await bridge.storeSecret(providerId, key);

      // 2. Sync to Python runtime server
      await bridge.runtimeRequest('/api/byok/set', {
        provider: providerId,
        api_key: key,
        set_active: autoActivate,
      });

      const providerDef = BYOK_PROVIDERS.find(p => p.id === providerId);
      const chosenModel = store.byokModel || providerDef?.models[0]?.id || '';

      // If auto-activating, stop llama-server and deactivate local
      if (autoActivate) {
        try { await bridge.runtimeRequest('/api/server/stop'); } catch {}
        bridge.notifyModelStatus(false);
      }

      setStore({
        byokProvider: autoActivate ? providerId : store.byokProvider,
        byokKeys: { ...store.byokKeys, [providerId]: key },
        byokModel: chosenModel,
        inferenceMode: autoActivate ? 'byok' : store.inferenceMode,
        modelStatus: autoActivate ? 'ready' : store.modelStatus,
        activeModel: chosenModel,
      });
      // Clear manual edit state so the input cleanly reflects saved key
      setKeyInputs(p => {
        const next = { ...p };
        delete next[providerId];
        return next;
      });
      // Re-fetch dynamic models with new key
      fetchModelsForProvider(providerId, true);
    } catch (e: any) {
      setProvErrors(p => ({ ...p, [providerId]: e?.message || 'Failed to save key' }));
    } finally {
      setSaving(p => ({ ...p, [providerId]: false }));
    }
  };

  // ── Revoke provider key (clears GNOME Secrets + Python runtime) ──────────────
  const handleRevokeProvider = async (providerId: string) => {
    try {
      await bridge.clearSecret(providerId);
      await bridge.runtimeRequest(`/api/byok/revoke/${providerId}`, {}, 'DELETE');
      const newKeys = { ...store.byokKeys };
      delete newKeys[providerId];
      const isCurrentActive = store.byokProvider === providerId;
      setStore({
        byokProvider: isCurrentActive ? null : store.byokProvider,
        byokKeys: newKeys,
        byokModel: isCurrentActive ? '' : store.byokModel,
        inferenceMode: isCurrentActive ? 'local' : store.inferenceMode,
        modelStatus: isCurrentActive ? 'idle' : store.modelStatus,
      });
      setKeyInputs(p => {
        const next = { ...p };
        delete next[providerId];
        return next;
      });
    } catch (e: any) {
      setProvErrors(p => ({ ...p, [providerId]: e?.message || 'Revoke failed' }));
    }
  };

  // ── Toggle show/hide API key with active fetch fallback ─────────────────────
  const handleToggleShowKey = async (providerId: string) => {
    const nextState = !showKey[providerId];
    if (nextState && !store.byokKeys[providerId]) {
      let secret = await bridge.lookupSecret(providerId);
      if (!secret) {
        try {
          const res = await bridge.runtimeRequest(`/api/byok/key/${providerId}`, {}, 'GET');
          if (res?.key) secret = res.key;
        } catch {}
      }
      if (secret) {
        setStore(prev => ({
          byokKeys: { ...prev.byokKeys, [providerId]: secret }
        }));
      }
    }
    setShowKey(p => ({ ...p, [providerId]: nextState }));
  };

  // ── iOS pill toggle handler for activating/deactivating a provider ──────────
  const handleToggleProvider = async (providerId: string, shouldActivate: boolean, overrideModel?: string) => {
    setProvErrors(p => ({ ...p, [providerId]: '' }));
    if (shouldActivate) {
      const key = (keyInputs[providerId] !== undefined ? keyInputs[providerId] : store.byokKeys[providerId])?.trim();
      if (!key) {
        setProvErrors(p => ({ ...p, [providerId]: 'Please save an API key for this provider before activating.' }));
        return;
      }
      try {
        // Stop llama-server so local releases VRAM & deactivates
        try { await bridge.runtimeRequest('/api/server/stop'); } catch {}
        bridge.notifyModelStatus(false);

        // Activate provider in backend
        await bridge.runtimeRequest(`/api/byok/activate/${providerId}`);

        const providerDef = BYOK_PROVIDERS.find(p => p.id === providerId);
        const providerModelsList = fetchedModels[providerId] || (providerDef?.models as any[]) || [];
        const selectedModel = overrideModel
          || (store.byokProvider === providerId && store.byokModel)
          || providerModelsList[0]?.id
          || '';

        setStore({
          inferenceMode: 'byok',
          byokProvider: providerId,
          byokModel: selectedModel,
          activeModel: selectedModel,
          modelStatus: 'ready',
        });
      } catch (e: any) {
        setProvErrors(p => ({ ...p, [providerId]: e?.message || 'Activation failed' }));
      }
    } else {
      // Deactivate this provider, keep keys in GNOME Secrets
      try {
        await bridge.runtimeRequest('/api/byok/deactivate');
      } catch {}
      setStore({
        byokProvider: null,
        modelStatus: 'idle',
      });
    }
  };

  // ── Select and activate model from provider list ────────────────────────────
  const handleSelectModel = async (modelId: string) => {
    const isCurrentActive = store.inferenceMode === 'byok' && store.byokProvider === currentProvider.id;
    const isCurrentConfigured = !!store.byokKeys[currentProvider.id];
    const hasTypedKey = !!keyInputs[currentProvider.id]?.trim();

    if (!isCurrentActive) {
      if (isCurrentConfigured || hasTypedKey) {
        await handleToggleProvider(currentProvider.id, true, modelId);
      } else {
        setStore({ byokModel: modelId, activeModel: modelId });
      }
    } else {
      setStore({ byokModel: modelId, activeModel: modelId });
    }
  };

  // ── Locked state — no license key in non-dev mode ───────────────────────────
  if (!hasBYOKLicense && !DEV_BYPASS_BYOK_LICENSE) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
        <div style={{
          padding: '16px',
          background: `color-mix(in srgb, ${PRIMARY} 8%, transparent)`,
          border: '1px solid var(--border-glass)',
          borderRadius: 'var(--radius-md)',
          backdropFilter: 'blur(8px)',
        }}>
          <div style={{ fontWeight: 700, fontSize: '13px', color: 'var(--text-primary)', marginBottom: '6px' }}>
            BYOK — Bring Your Own Key
          </div>
          <div style={{ fontSize: '11.5px', color: 'var(--text-secondary)', lineHeight: 1.6 }}>
            A flat monthly fee for the agent UI &amp; orchestration. You supply your own API keys — model calls go <strong>straight from your machine to your provider</strong>, never through our servers.
          </div>
          <div style={{ marginTop: '10px', display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
            {BYOK_PROVIDERS.map(p => (
              <span key={p.id} style={{
                fontSize: '10px', padding: '3px 10px', borderRadius: 'var(--radius-full)',
                background: `color-mix(in srgb, ${PRIMARY} 14%, transparent)`, color: PRIMARY, fontWeight: 600,
              }}>
                {p.name}
              </span>
            ))}
          </div>
          <div style={{ marginTop: '12px', display: 'flex', gap: '8px', alignItems: 'center' }}>
            <span style={{ fontSize: '20px', fontWeight: 800, color: 'var(--text-primary)' }}>$5</span>
            <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>/month · 1-week free trial · cancel anytime</span>
          </div>
        </div>

        {/* License key input */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
          <label style={{ fontSize: '11.5px', fontWeight: 600, color: 'var(--text-secondary)', display: 'flex', alignItems: 'center', gap: '5px' }}>
            <Key size={12} /> License Key
          </label>
          <div style={{ display: 'flex', gap: '8px' }}>
            <input type="password" value={licenseInput} onChange={e => setLicenseInput(e.target.value)}
              placeholder="Paste key from your confirmation email…"
              onKeyDown={e => e.key === 'Enter' && handleValidateLicense()}
              style={{ flex: 1, padding: '8px 12px', background: 'var(--bg-input)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--radius-sm)', color: 'var(--text-primary)', fontSize: '12px', fontFamily: 'var(--font-mono)', outline: 'none' }} />
            <button onClick={handleValidateLicense} disabled={!licenseInput.trim() || validatingLicense}
              style={{ padding: '8px 14px', background: PRIMARY, border: 'none', borderRadius: 'var(--radius-sm)', color: ON_PRIMARY, fontSize: '12px', fontWeight: 700, cursor: 'pointer', opacity: (!licenseInput.trim() || validatingLicense) ? 0.5 : 1, whiteSpace: 'nowrap' }}>
              {validatingLicense ? 'Checking…' : 'Activate'}
            </button>
          </div>
          {licenseError && (
            <div style={{ fontSize: '11px', color: ERROR_COLOR, display: 'flex', alignItems: 'center', gap: '5px' }}>
              <AlertTriangle size={11} /> {licenseError}
            </div>
          )}
        </div>

        {/* CTA */}
        <button onClick={() => bridge.openExternalUrl(LS_BYOK_CHECKOUT_URL)}
          style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px', padding: '11px', borderRadius: 'var(--radius-md)', background: PRIMARY, border: 'none', color: ON_PRIMARY, fontSize: '12px', fontWeight: 700, cursor: 'pointer' }}>
          <Sparkles size={13} color={ON_PRIMARY} /> Start 1-week free trial <ExternalLink size={11} color={ON_PRIMARY} />
        </button>
      </div>
    );
  }

  // ── Unlocked view — Rounded Pill Provider Tab-Bar + Selected Provider Pane ──
  const currentProvider = BYOK_PROVIDERS.find(p => p.id === selectedProviderId) || BYOK_PROVIDERS[0];
  const isCurrentActive = store.inferenceMode === 'byok' && store.byokProvider === currentProvider.id;
  const isCurrentConfigured = !!store.byokKeys[currentProvider.id];

  const availableModels = fetchedModels[currentProvider.id] || (currentProvider.models as any[]) || [];
  const isModelsLive = !!modelsLive[currentProvider.id];
  const currentQuery = (searchQuery[currentProvider.id] || '').trim().toLowerCase();

  const filteredModels = currentQuery
    ? availableModels.filter(m =>
        m.id.toLowerCase().includes(currentQuery) ||
        m.name.toLowerCase().includes(currentQuery) ||
        (m.desc && m.desc.toLowerCase().includes(currentQuery))
      )
    : availableModels;

  // Auto-scroll to first match when searching
  useEffect(() => {
    if (currentQuery && filteredModels.length > 0) {
      const firstId = filteredModels[0].id;
      const el = cardRefs.current[firstId];
      if (el) {
        el.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
      }
    }
  }, [currentQuery, filteredModels]);

  // Robust show/hide logic: reflects saved key or typed key
  const savedKey = store.byokKeys[currentProvider.id] || '';
  const hasTyped = keyInputs[currentProvider.id] !== undefined;
  const rawKeyValue = hasTyped ? keyInputs[currentProvider.id] : savedKey;
  const isKeyRevealed = !!showKey[currentProvider.id];

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
      {/* Dev Testing Banner OR Subscription Status */}
      {DEV_BYPASS_BYOK_LICENSE ? (
        <div style={{
          display: 'flex', alignItems: 'center', gap: '8px', padding: '8px 12px',
          background: `color-mix(in srgb, ${COLOR5_AMBER} 14%, transparent)`,
          border: `1px solid color-mix(in srgb, ${COLOR5_AMBER} 40%, transparent)`,
          borderRadius: 'var(--radius-sm)',
        }}>
          <TestTube size={14} color={COLOR5_AMBER} style={{ flexShrink: 0 }} />
          <span style={{ fontSize: '11.5px', fontWeight: 700, color: COLOR5_AMBER }}>Dev Testing Mode</span>
          <span style={{ fontSize: '10.5px', color: 'var(--text-muted)' }}>— license gate bypassed · all providers enabled · remove before shipping</span>
        </div>
      ) : (
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 12px',
          background: `color-mix(in srgb, ${PRIMARY} 12%, transparent)`,
          border: `1px solid color-mix(in srgb, ${PRIMARY} 35%, transparent)`,
          borderRadius: 'var(--radius-sm)',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '7px' }}>
            <Check size={13} color={PRIMARY} />
            <span style={{ fontSize: '11.5px', fontWeight: 600, color: PRIMARY }}>BYOK Active</span>
            <span style={{ fontSize: '10px', color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' }}>{store.byokLicenseKey?.slice(0, 8)}…</span>
          </div>
          <button
            onClick={() => setStore({ byokLicenseKey: '', byokLicenseInstanceId: '', byokProvider: null, byokKeys: {}, byokModel: '', inferenceMode: 'local' })}
            style={{ background: 'transparent', border: 'none', color: 'var(--text-muted)', cursor: 'pointer', fontSize: '10px', display: 'flex', alignItems: 'center', gap: '3px' }}
          >
            <X size={11} /> Revoke License
          </button>
        </div>
      )}

      {/* ── Scrollable Material-You Rounded Pill Tab-Bar ───────────────────── */}
      <div>
        <div style={{ fontSize: '10.5px', fontWeight: 600, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '.05em', marginBottom: '8px' }}>
          Select Cloud Provider
        </div>
        <div style={{
          display: 'flex',
          gap: '5px',
          overflowX: 'auto',
          paddingBottom: '4px',
          scrollbarWidth: 'none',
        }}>
          {BYOK_PROVIDERS.map(provider => {
            const isTabSelected = selectedProviderId === provider.id;
            const isProvActive = store.inferenceMode === 'byok' && store.byokProvider === provider.id;
            const hasKeySaved = !!store.byokKeys[provider.id];
            const IconComp = provider.IconComponent;

            return (
              <button
                key={provider.id}
                onClick={() => setSelectedProviderId(provider.id)}
                style={{
                  padding: '6px 14px',
                  borderRadius: 'var(--radius-full, 9999px)',
                  border: isTabSelected
                    ? `1px solid ${PRIMARY}`
                    : '1px solid var(--border-subtle)',
                  background: isTabSelected
                    ? PRIMARY
                    : 'color-mix(in srgb, var(--matugen-surface-variant, #40484c) 20%, transparent)',
                  color: isTabSelected ? ON_PRIMARY : 'var(--text-secondary)',
                  fontWeight: isTabSelected ? 700 : 500,
                  fontSize: '11.5px',
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '7px',
                  whiteSpace: 'nowrap',
                  transition: 'all .18s cubic-bezier(0.16, 1, 0.3, 1)',
                  flexShrink: 0,
                  boxShadow: isTabSelected ? '0 1px 4px rgba(0,0,0,0.35)' : 'none',
                }}
              >
                <IconComp size={15} />
                <span>{provider.name}</span>
                {isProvActive ? (
                  <span style={{
                    width: '6px',
                    height: '6px',
                    borderRadius: '50%',
                    background: isTabSelected ? ON_PRIMARY : PRIMARY,
                    boxShadow: isTabSelected ? `0 0 6px ${ON_PRIMARY}` : `0 0 6px ${PRIMARY}`,
                    display: 'inline-block',
                    marginLeft: '2px',
                  }} />
                ) : hasKeySaved ? (
                  <span style={{
                    fontSize: '8px',
                    color: isTabSelected ? ON_PRIMARY : COLOR5_AMBER,
                    opacity: 0.9,
                    marginLeft: '1px',
                  }}>
                    ●
                  </span>
                ) : null}
              </button>
            );
          })}
        </div>
      </div>

      {/* ── Active Provider Dedicated Pane ─────────────────────────────────── */}
      <div style={{
        borderRadius: 'var(--radius-md)',
        border: `1px solid ${isCurrentActive ? `color-mix(in srgb, ${PRIMARY} 45%, transparent)` : 'var(--border-subtle)'}`,
        background: isCurrentActive
          ? `color-mix(in srgb, var(--matugen-surface, #0c1014) 28%, transparent)`
          : 'color-mix(in srgb, var(--matugen-surface, #0c1014) 22%, transparent)',
        padding: '14px',
        display: 'flex',
        flexDirection: 'column',
        gap: '12px',
        transition: 'all .2s ease',
      }}>
        {/* Provider Pane Header with iOS Pill Toggle */}
        <div style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          borderBottom: '1px solid var(--border-subtle)',
          paddingBottom: '12px',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <div style={{
              width: 34, height: 34, borderRadius: 'var(--radius-sm)',
              background: `color-mix(in srgb, ${PRIMARY} 15%, transparent)`,
              border: `1px solid color-mix(in srgb, ${PRIMARY} 30%, transparent)`,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              flexShrink: 0,
            }}>
              <currentProvider.IconComponent size={19} />
            </div>
            <div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '7px' }}>
                <span style={{ fontSize: '13px', fontWeight: 700, color: 'var(--text-primary)' }}>
                  {currentProvider.name}
                </span>
                {isCurrentActive && (
                  <span style={{
                    fontSize: '9px', padding: '1px 7px', borderRadius: 'var(--radius-full)',
                    background: `color-mix(in srgb, ${PRIMARY} 20%, transparent)`,
                    border: `1px solid color-mix(in srgb, ${PRIMARY} 40%, transparent)`,
                    color: PRIMARY, fontWeight: 700,
                  }}>
                    Active Provider
                  </span>
                )}
              </div>
              <div style={{ fontSize: '10.5px', color: 'var(--text-muted)', marginTop: '1px' }}>
                {isCurrentActive
                  ? `Active · streaming with ${store.byokModel || 'default model'}`
                  : isCurrentConfigured
                  ? 'Key saved in GNOME Secrets — toggle to activate'
                  : 'API key required to activate'}
              </div>
            </div>
          </div>

          {/* Provider Activation iOS Pill Toggle */}
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <IosToggle
              checked={isCurrentActive}
              onChange={val => handleToggleProvider(currentProvider.id, val)}
              disabled={!isCurrentConfigured && !keyInputs[currentProvider.id]?.trim()}
              label={isCurrentActive ? 'Active' : 'Inactive'}
            />
          </div>
        </div>

        {/* API Key management section */}
        <div>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '5px' }}>
            <label style={{ fontSize: '11px', fontWeight: 600, color: 'var(--text-secondary)', display: 'flex', alignItems: 'center', gap: '5px' }}>
              <Key size={10} /> {currentProvider.keyLabel}
            </label>
            <a
              href={currentProvider.apiKeyUrl}
              onClick={e => { e.preventDefault(); bridge.openExternalUrl(currentProvider.apiKeyUrl); }}
              style={{ fontSize: '10.5px', color: PRIMARY, display: 'flex', alignItems: 'center', gap: '3px', textDecoration: 'none' }}
            >
              Get key <ExternalLink size={10} />
            </a>
          </div>

          <div style={{ display: 'flex', gap: '6px' }}>
            <div style={{ flex: 1, position: 'relative' }}>
              <input
                type={isKeyRevealed ? 'text' : 'password'}
                value={rawKeyValue}
                onChange={e => setKeyInputs(p => ({ ...p, [currentProvider.id]: e.target.value }))}
                placeholder={currentProvider.keyHint}
                onKeyDown={e => e.key === 'Enter' && handleSetProviderKey(currentProvider.id, true)}
                style={{
                  width: '100%', padding: '7px 32px 7px 10px', boxSizing: 'border-box',
                  background: 'var(--bg-input)', border: '1px solid var(--border-subtle)',
                  borderRadius: 'var(--radius-sm)', color: 'var(--text-primary)',
                  fontSize: '11.5px', fontFamily: 'var(--font-mono)', outline: 'none',
                }}
              />
              <button
                type="button"
                onClick={() => handleToggleShowKey(currentProvider.id)}
                title={isKeyRevealed ? 'Hide API key' : 'Show API key'}
                style={{
                  position: 'absolute', right: '8px', top: '50%', transform: 'translateY(-50%)',
                  background: 'transparent', border: 'none',
                  color: isKeyRevealed ? PRIMARY : 'var(--text-muted)',
                  cursor: 'pointer', display: 'flex', padding: '2px',
                }}
              >
                {isKeyRevealed ? <EyeOff size={13} /> : <Eye size={13} />}
              </button>
            </div>

            <button
              onClick={() => handleSetProviderKey(currentProvider.id, true)}
              disabled={
                saving[currentProvider.id] ||
                (isCurrentConfigured && !hasTyped) ||
                (hasTyped && !keyInputs[currentProvider.id]?.trim())
              }
              style={{
                padding: '7px 14px', background: PRIMARY, border: 'none', borderRadius: 'var(--radius-sm)',
                color: ON_PRIMARY, fontSize: '11px', fontWeight: 700, cursor: 'pointer',
                opacity: (saving[currentProvider.id] || (isCurrentConfigured && !hasTyped) || (hasTyped && !keyInputs[currentProvider.id]?.trim())) ? 0.5 : 1,
                whiteSpace: 'nowrap', display: 'flex', alignItems: 'center', gap: '5px',
              }}
            >
              {saving[currentProvider.id] && <Loader size={10} style={{ animation: 'spin 1s linear infinite' }} />}
              {isCurrentConfigured ? 'Update Key' : 'Save & Activate'}
            </button>

            {isCurrentConfigured && (
              <button
                onClick={() => handleRevokeProvider(currentProvider.id)}
                title="Revoke key from GNOME Secrets and disk"
                style={{
                  display: 'flex', alignItems: 'center', gap: '4px', padding: '7px 10px',
                  background: `color-mix(in srgb, ${ERROR_COLOR} 12%, transparent)`,
                  border: `1px solid color-mix(in srgb, ${ERROR_COLOR} 30%, transparent)`,
                  borderRadius: 'var(--radius-sm)', color: ERROR_COLOR, fontSize: '11px', cursor: 'pointer',
                }}
              >
                <X size={11} /> Revoke
              </button>
            )}
          </div>

          {providerErrors[currentProvider.id] && (
            <div style={{ marginTop: '4px', fontSize: '11px', color: ERROR_COLOR, display: 'flex', alignItems: 'center', gap: '4px' }}>
              <AlertTriangle size={11} /> {providerErrors[currentProvider.id]}
            </div>
          )}
        </div>

        {/* Model Search input field between API key field and first listed model card */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
          <div style={{ position: 'relative', display: 'flex', alignItems: 'center' }}>
            <Search
              size={13}
              color="var(--text-muted)"
              style={{ position: 'absolute', left: '10px', pointerEvents: 'none', flexShrink: 0 }}
            />
            <input
              type="text"
              value={searchQuery[currentProvider.id] || ''}
              onChange={e => setSearchQuery(p => ({ ...p, [currentProvider.id]: e.target.value }))}
              onKeyDown={e => {
                if (e.key === 'Enter') {
                  if (filteredModels.length > 0) {
                    handleSelectModel(filteredModels[0].id);
                  }
                }
              }}
              placeholder={`Search ${currentProvider.name} models (e.g. claude, gpt, flash, llama)...`}
              style={{
                width: '100%',
                padding: '7px 30px 7px 30px',
                boxSizing: 'border-box',
                background: 'var(--bg-input)',
                border: '1px solid var(--border-subtle)',
                borderRadius: 'var(--radius-sm)',
                color: 'var(--text-primary)',
                fontSize: '11.5px',
                outline: 'none',
                transition: 'border-color .15s ease',
              }}
            />
            {searchQuery[currentProvider.id] && (
              <button
                type="button"
                onClick={() => setSearchQuery(p => ({ ...p, [currentProvider.id]: '' }))}
                title="Clear search"
                style={{
                  position: 'absolute', right: '8px',
                  background: 'transparent', border: 'none',
                  color: 'var(--text-muted)', cursor: 'pointer',
                  display: 'flex', padding: '2px',
                }}
              >
                <X size={12} />
              </button>
            )}
          </div>
        </div>

        {/* Scrollable Models section */}
        <div>
          <div style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            marginBottom: '6px',
          }}>
            <div style={{
              fontSize: '11px',
              fontWeight: 600,
              color: 'var(--text-muted)',
              textTransform: 'uppercase',
              letterSpacing: '.05em',
              display: 'flex',
              alignItems: 'center',
              gap: '6px',
            }}>
              <span>Models ({filteredModels.length}{filteredModels.length !== availableModels.length ? ` of ${availableModels.length}` : ''})</span>
              {isModelsLive && (
                <span style={{
                  fontSize: '9px',
                  padding: '1px 5px',
                  borderRadius: 'var(--radius-full)',
                  background: `color-mix(in srgb, ${PRIMARY} 16%, transparent)`,
                  color: PRIMARY,
                  fontWeight: 600,
                  textTransform: 'none',
                  letterSpacing: 'normal',
                }}>
                  Live API
                </span>
              )}
            </div>

            <button
              onClick={() => fetchModelsForProvider(currentProvider.id, true)}
              disabled={loadingModels[currentProvider.id]}
              title="Refresh models from provider"
              style={{
                background: 'transparent',
                border: 'none',
                color: loadingModels[currentProvider.id] ? PRIMARY : 'var(--text-muted)',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: '4px',
                fontSize: '10.5px',
                padding: '2px 4px',
              }}
            >
              <RefreshCw
                size={11}
                style={{ animation: loadingModels[currentProvider.id] ? 'spin 1s linear infinite' : 'none' }}
              />
              <span>{loadingModels[currentProvider.id] ? 'Fetching…' : 'Refresh'}</span>
            </button>
          </div>

          <div style={{
            display: 'flex',
            flexDirection: 'column',
            gap: '4px',
            maxHeight: '220px',
            overflowY: 'auto',
            paddingRight: '2px',
          }}>
            {filteredModels.length === 0 ? (
              <div style={{
                padding: '18px 12px',
                textAlign: 'center',
                color: 'var(--text-muted)',
                fontSize: '11px',
                background: 'color-mix(in srgb, var(--matugen-surface, #0c1014) 15%, transparent)',
                borderRadius: 'var(--radius-sm)',
                border: '1px dashed var(--border-subtle)',
              }}>
                <div>No models match "{searchQuery[currentProvider.id]}"</div>
                <button
                  onClick={() => setSearchQuery(p => ({ ...p, [currentProvider.id]: '' }))}
                  style={{
                    marginTop: '6px',
                    background: 'transparent',
                    border: 'none',
                    color: PRIMARY,
                    fontSize: '11px',
                    fontWeight: 600,
                    cursor: 'pointer',
                  }}
                >
                  Clear search
                </button>
              </div>
            ) : (
              filteredModels.map((model, idx) => {
                const selected = store.byokModel === model.id && isCurrentActive;
                const isFirstMatch = !!currentQuery && idx === 0;
                const ctxText = (model as any).ctx || (model as any).context || '';

                return (
                  <button
                    key={model.id}
                    ref={el => { cardRefs.current[model.id] = el; }}
                    onClick={() => handleSelectModel(model.id)}
                    style={{
                      display: 'flex', alignItems: 'center', gap: '10px', padding: '8px 10px',
                      background: selected
                        ? `color-mix(in srgb, ${PRIMARY} 14%, transparent)`
                        : isFirstMatch
                        ? `color-mix(in srgb, ${PRIMARY} 8%, transparent)`
                        : 'color-mix(in srgb, var(--matugen-surface, #0c1014) 20%, transparent)',
                      border: `1px solid ${selected ? PRIMARY : isFirstMatch ? `color-mix(in srgb, ${PRIMARY} 55%, transparent)` : 'var(--border-subtle)'}`,
                      borderRadius: 'var(--radius-sm)', cursor: 'pointer', textAlign: 'left',
                      transition: 'all .12s ease',
                      outline: isFirstMatch && !selected ? `1px dashed color-mix(in srgb, ${PRIMARY} 60%, transparent)` : 'none',
                    }}
                  >
                    <div style={{
                      width: 18, height: 18, borderRadius: '50%',
                      background: selected ? PRIMARY : 'color-mix(in srgb, var(--matugen-surface-variant, #40484c) 25%, transparent)',
                      display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
                    }}>
                      {selected ? <Check size={10} color={ON_PRIMARY} /> : <span style={{ width: 5, height: 5, borderRadius: '50%', background: 'var(--text-muted)', display: 'block' }} />}
                    </div>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '6px' }}>
                        <span style={{ fontSize: '11.5px', fontWeight: 600, color: 'var(--text-primary)' }}>{model.name}</span>
                        {ctxText && (
                          <span style={{ fontSize: '10px', color: PRIMARY, flexShrink: 0 }}>{ctxText}</span>
                        )}
                      </div>
                      <div style={{ fontSize: '10px', color: 'var(--text-muted)', marginTop: '1px' }}>
                        {model.desc}
                      </div>
                    </div>
                  </button>
                );
              })
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN MODEL MANAGER MODAL
// ═══════════════════════════════════════════════════════════════════════════════
export const ModelManager: FC = () => {
  const [store] = useStore();
  const activeTab = store.modelManagerTab ?? 'local';

  if (!store.modelManagerOpen) return null;

  const statusSubtitle =
    store.inferenceMode === 'byok' && store.byokProvider
      ? `BYOK · ${BYOK_PROVIDERS.find(p => p.id === store.byokProvider)?.name ?? store.byokProvider} active`
      : store.inferenceMode === 'local' && store.modelStatus === 'ready'
      ? `Local active · ${store.activeModel || 'llama-server'}`
      : 'Configure your inference backend';

  return (
    <div
      onClick={() => setStore({ modelManagerOpen: false })}
      style={{
        position: 'absolute', inset: 0, background: 'rgba(0,0,0,.65)',
        display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 100,
      }}
    >
      <div
        className="animate-fade-in"
        onClick={e => e.stopPropagation()}
        style={{
          width: '560px', maxHeight: '88vh', background: 'var(--matugen-on-secondary, #1d343c)',
          border: '1px solid var(--border-glass)', borderRadius: 'var(--radius-lg)',
          boxShadow: '0 20px 60px rgba(0,0,0,.7)', display: 'flex', flexDirection: 'column',
          overflow: 'hidden', backdropFilter: 'blur(20px)',
        }}
      >
        {/* Header */}
        <div style={{ padding: '16px 20px 12px', borderBottom: '1px solid var(--border-subtle)', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <div style={{ width: 34, height: 34, borderRadius: 'var(--radius-sm)', background: PRIMARY, color: ON_PRIMARY, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Cpu size={17} color={ON_PRIMARY} />
            </div>
            <div>
              <div style={{ fontWeight: 700, fontSize: '14px', color: 'var(--text-primary)' }}>Candy Agent</div>
              <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{statusSubtitle}</div>
            </div>
          </div>
          <button onClick={() => setStore({ modelManagerOpen: false })} style={{ background: 'transparent', border: 'none', color: 'var(--text-muted)', cursor: 'pointer', display: 'flex', padding: '4px' }}>
            <X size={16} />
          </button>
        </div>

        {/* Outer Tab bar (Local / Cloud) */}
        <div style={{ padding: '10px 20px', borderBottom: '1px solid var(--border-subtle)' }}>
          <TabBar active={activeTab} onChange={tab => setStore({ modelManagerTab: tab })} />
        </div>

        {/* Tab Content */}
        <div style={{ flex: 1, overflowY: 'auto', padding: '16px 20px', scrollbarWidth: 'thin' }}>
          {activeTab === 'local' ? <LocalTab /> : <CloudTab />}
        </div>
      </div>
    </div>
  );
};
