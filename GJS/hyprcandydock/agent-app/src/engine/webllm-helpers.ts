export interface WebLLMModelOption {
  id: string;
  name: string;
  desc: string;
  limits: string;
  provider: 'webllm';
  recommended?: boolean;
  // Keep the exact prebuilt catalog URLs with the UI metadata.  WebLLM model
  // IDs do not map 1:1 to WASM library filenames (Hermes uses its base model's
  // library), so callers must not synthesize these URLs from `id`.
  model: string;
  model_lib: string;
  required_features?: string[];
}

export interface CustomWebLLMModel {
  id: string;
  name: string;
  model: string;
  model_lib: string;
  desc?: string;
  required_features?: string[];
}

export const WEBLLM_MODELS: WebLLMModelOption[] = [
  {
    id: 'Hermes-3-Llama-3.1-8B-q4f16_1-MLC',
    name: 'Hermes 3 Llama 3.1 8B',
    desc: 'Best agentic quality. Llama 3.1 base with robust native function-calling for full tool use.',
    limits: 'WebGPU + shader-f16 · ~5GB VRAM',
    provider: 'webllm',
    recommended: true,
    model: 'https://huggingface.co/mlc-ai/Hermes-3-Llama-3.1-8B-q4f16_1-MLC',
    model_lib: 'https://raw.githubusercontent.com/mlc-ai/binary-mlc-llm-libs/main/web-llm-models/v0_2_84/base/Llama-3_1-8B-Instruct-q4f16_1_cs1k-webgpu.wasm',
  },
  {
    id: 'Hermes-2-Pro-Llama-3-8B-q4f16_1-MLC',
    name: 'Hermes 2 Pro Llama 3 8B',
    desc: 'Proven agentic model with native function-calling and structured output. Solid choice.',
    limits: 'WebGPU + shader-f16 · ~5GB VRAM',
    provider: 'webllm',
    model: 'https://huggingface.co/mlc-ai/Hermes-2-Pro-Llama-3-8B-q4f16_1-MLC',
    model_lib: 'https://raw.githubusercontent.com/mlc-ai/binary-mlc-llm-libs/main/web-llm-models/v0_2_84/base/Llama-3-8B-Instruct-q4f16_1_cs1k-webgpu.wasm',
  },
  {
    id: 'Hermes-2-Pro-Mistral-7B-q4f16_1-MLC',
    name: 'Hermes 2 Pro Mistral 7B',
    desc: 'Mistral 7B base with Hermes Pro tool-calling. Slightly smaller footprint than Llama 3.',
    limits: 'WebGPU + shader-f16 · ~4.5GB VRAM',
    provider: 'webllm',
    model: 'https://huggingface.co/mlc-ai/Hermes-2-Pro-Mistral-7B-q4f16_1-MLC',
    model_lib: 'https://raw.githubusercontent.com/mlc-ai/binary-mlc-llm-libs/main/web-llm-models/v0_2_84/base/Mistral-7B-Instruct-v0.3-q4f16_1_cs1k-webgpu.wasm',
    required_features: ['shader-f16'],
  },
];

export const WEBLLM_MODELS_FP32: WebLLMModelOption[] = [
  {
    id: 'Hermes-3-Llama-3.1-8B-q4f32_1-MLC',
    name: 'Hermes 3 Llama 3.1 8B (FP32)',
    desc: 'Same robust native tool-calling as the FP16 variant. 32-bit for GPUs without shader-f16.',
    limits: 'WebGPU (FP32) · ~5.8GB VRAM',
    provider: 'webllm',
    recommended: true,
    model: 'https://huggingface.co/mlc-ai/Hermes-3-Llama-3.1-8B-q4f32_1-MLC',
    model_lib: 'https://raw.githubusercontent.com/mlc-ai/binary-mlc-llm-libs/main/web-llm-models/v0_2_84/base/Llama-3_1-8B-Instruct-q4f32_1_cs1k-webgpu.wasm',
  },
  {
    id: 'Hermes-2-Pro-Llama-3-8B-q4f32_1-MLC',
    name: 'Hermes 2 Pro Llama 3 8B (FP32)',
    desc: 'Full 8B agentic model with native tool calling in 32-bit precision.',
    limits: 'WebGPU (FP32) · ~6.0GB VRAM',
    provider: 'webllm',
    model: 'https://huggingface.co/mlc-ai/Hermes-2-Pro-Llama-3-8B-q4f32_1-MLC',
    model_lib: 'https://raw.githubusercontent.com/mlc-ai/binary-mlc-llm-libs/main/web-llm-models/v0_2_84/base/Llama-3-8B-Instruct-q4f32_1_cs1k-webgpu.wasm',
  },
];

export const DEFAULT_WEBLLM_MODEL = WEBLLM_MODELS[0].id;   // Hermes-3-Llama-3.1-8B-q4f16_1-MLC
export const DEFAULT_WEBLLM_MODEL_FP32 = WEBLLM_MODELS_FP32[0].id; // Hermes-3-Llama-3.1-8B-q4f32_1-MLC

export const GEMMA4_E2B_MLC_ID = 'gemma-4-E2B-it-q4f16_1-MLC';
export const GEMMA4_E2B_MLC_REPO = 'https://huggingface.co/welcoma/gemma-4-E2B-it-q4f16_1-MLC';
export const GEMMA4_E2B_MLC_WASM =
  `${GEMMA4_E2B_MLC_REPO}/resolve/main/libs/gemma-4-E2B-it-q4f16_1-MLC-webgpu.wasm`;

export const COMMUNITY_WEBLLM_MODELS: CustomWebLLMModel[] = [
  {
    id: GEMMA4_E2B_MLC_ID,
    name: 'Gemma 4 E2B (community MLC)',
    desc: 'Community MLC packaging of google/gemma-4-E2B-it. Native OpenAI tool schemas are off in this artifact; use TOOL_CALL text syntax.',
    model: GEMMA4_E2B_MLC_REPO,
    model_lib: GEMMA4_E2B_MLC_WASM,
    required_features: ['shader-f16'],
  },
];

export function getAvailableWebLLMModels(hasShaderF16 = true): WebLLMModelOption[] {
  if (hasShaderF16) return WEBLLM_MODELS;
  return WEBLLM_MODELS_FP32;
}

export function isCustomWebLLMModelAllowed(model: { required_features?: string[] }, hasShaderF16 = true): boolean {
  // Now all custom models are always allowed; when GPU lacks shader-f16,
  // we automatically synthesize a q4f32 FP32-fallback record. So hiding isn't needed.
  if (!model?.required_features?.length) return true;
  for (const feat of model.required_features) {
    if (feat === 'shader-f16' && !hasShaderF16) {
      // Don't hide — label as FP32 fallback in UI instead.
      return true;
    }
  }
  return true;
}

export function mergeRuntimeModelRecords(
  userCustom: CustomWebLLMModel[] = []
): CustomWebLLMModel[] {
  const extras = userCustom.filter(isCustomWebLLMModel);
  const seen = new Set(extras.map((m) => m.id));
  return [...COMMUNITY_WEBLLM_MODELS.filter((m) => !seen.has(m.id)), ...extras];
}

export function getDefaultWebLLMModel(hasShaderF16 = true): string {
  return hasShaderF16 ? DEFAULT_WEBLLM_MODEL : DEFAULT_WEBLLM_MODEL_FP32;
}

export const WEBLLM_SYSTEM_PROMPT = `You are Candy, an autonomous local AI coding assistant running inside the HyprCandy launcher agent via WebGPU.

AGENTIC BEHAVIOR:
You can directly read project files, inspect directory trees, modify code, and execute shell commands using functions.
When asked to examine, read, or analyze files, do NOT guess, hallucinate URLs, or ask the user to paste them. Always use your tools!

AVAILABLE TOOLS:
- read_file(path, start_line?, end_line?): Read full file content.
- peek_file(path, preview_lines?): Quick preview of file start and end lines.
- write_file(path, content): Create or modify files. Creates a diff for user approval.
- list_directory(path): List directory entries and structure.
- search_code(pattern): Search for pattern across project files.
- execute_command(command, needs_elevation?): Run terminal commands. Safe commands execute passively; elevated commands (sudo, installs) request approval.
- create_plan(title, steps): Create or update dynamic task plans.
- task_complete(summary): Signal that all requested tasks are complete.

HOW TO CALL TOOLS:
You can call tools either via standard function calling or by writing on a single line:
TOOL_CALL: function_name({"arg1": "value1", "arg2": "value2"})
Or:
<tool_call>
{"name": "function_name", "arguments": {"arg1": "value1"}}
</tool_call>

EXAMPLES:
TOOL_CALL: list_directory({"path": "."})
TOOL_CALL: read_file({"path": "package.json"})
TOOL_CALL: execute_command({"command": "ls -la"})
TOOL_CALL: write_file({"path": "src/index.ts", "content": "export const ready = true;"})
TOOL_CALL: task_complete({"summary": "Analyzed project files and completed requested work."})

Always use tools when you need to inspect or act on files, directories, or system state.`;

export const WEBLLM_COMPACT_SYSTEM_PROMPT = `You are Candy, a local coding assistant. Use tools instead of guessing file contents. At the start of a project task, inspect the supplied project tree and use list_directory on the project root when the tree is incomplete.
Call tools as: TOOL_CALL: name({"arg":"value"})
Tools: read_file, peek_file, write_file, list_files, search_code, execute_command, create_plan, task_complete.`;

export interface ChatHistoryMessage {
  role: 'user' | 'assistant' | 'tool';
  content: string;
  name?: string;
  tool_call_id?: string;
}

export interface ChatContextFiles {
  files?: Array<{ path: string; content?: string; startLine?: number; endLine?: number }>;
  project?: string;
  projectOverview?: string;
}

export type WebLLMChatMessage = {
  role: 'system' | 'user' | 'assistant' | 'tool';
  content: string;
  name?: string;
  tool_call_id?: string;
  tool_calls?: any[];
};

export interface ParsedToolCall {
  name: string;
  args: Record<string, any>;
  raw: string;
}

export const WEBLLM_TOOL_DEFINITIONS = [
  {
    type: 'function' as const,
    function: {
      name: 'read_file',
      description: 'Read file content from the project or filesystem. Returns file text with line count.',
      parameters: {
        type: 'object',
        properties: {
          path: { type: 'string', description: 'File path to read (relative to project or absolute)' },
          start_line: { type: 'integer', description: 'Optional start line (1-based)' },
          end_line: { type: 'integer', description: 'Optional end line (1-based)' },
        },
        required: ['path'],
      },
    },
  },
  {
    type: 'function' as const,
    function: {
      name: 'peek_file',
      description: 'Preview the first and last lines of a file.',
      parameters: {
        type: 'object',
        properties: {
          path: { type: 'string', description: 'File path to preview' },
          preview_lines: { type: 'integer', description: 'Number of lines to preview from top and bottom' },
        },
        required: ['path'],
      },
    },
  },
  {
    type: 'function' as const,
    function: {
      name: 'write_file',
      description: 'Create or modify a file. Presents a diff to the user in the DiffWidget for approval.',
      parameters: {
        type: 'object',
        properties: {
          path: { type: 'string', description: 'File path to write (relative to project or absolute)' },
          content: { type: 'string', description: 'Full content of the file' },
        },
        required: ['path', 'content'],
      },
    },
  },
  {
    type: 'function' as const,
    function: {
      name: 'list_files',
      description: 'List files and directories in a directory path.',
      parameters: {
        type: 'object',
        properties: {
          directory_path: { type: 'string', description: 'Directory path to list (use "." for project root)' },
        },
        required: ['directory_path'],
      },
    },
  },
  {
    type: 'function' as const,
    function: {
      name: 'search_code',
      description: 'Search for text or a pattern across project files.',
      parameters: {
        type: 'object',
        properties: {
          pattern: { type: 'string', description: 'Text or regex search pattern' },
        },
        required: ['pattern'],
      },
    },
  },
  {
    type: 'function' as const,
    function: {
      name: 'execute_command',
      description: 'Execute a shell command. Safe commands run passively; elevated commands (sudo, installs) require approval.',
      parameters: {
        type: 'object',
        properties: {
          command: { type: 'string', description: 'Shell command to execute' },
          needs_elevation: { type: 'boolean', description: 'Whether command requires elevated/root privileges' },
        },
        required: ['command'],
      },
    },
  },
  {
    type: 'function' as const,
    function: {
      name: 'create_plan',
      description: 'Create or update task plan steps shown in the TaskList widget.',
      parameters: {
        type: 'object',
        properties: {
          title: { type: 'string', description: 'Plan title' },
          steps: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                id: { type: 'string' },
                description: { type: 'string' },
                status: { type: 'string', enum: ['pending', 'in-progress', 'completed'] },
                order: { type: 'number' },
              },
              required: ['id', 'description', 'status', 'order'],
            },
          },
        },
        required: ['title', 'steps'],
      },
    },
  },
  {
    type: 'function' as const,
    function: {
      name: 'task_complete',
      description: 'Signal that all requested steps are completed.',
      parameters: {
        type: 'object',
        properties: {
          summary: { type: 'string', description: 'Summary of completed work' },
        },
        required: ['summary'],
      },
    },
  },
];

export function parseToolCallsFromText(text: string): ParsedToolCall[] {
  const calls: ParsedToolCall[] = [];
  if (!text) return calls;

  const toolCallRegex = /TOOL_CALL:\s*([a-zA-Z0-9_-]+)\s*\(([\s\S]*?)\)(?=\n|$)/g;
  let match: RegExpExecArray | null;
  while ((match = toolCallRegex.exec(text)) !== null) {
    const name = match[1].trim();
    const rawArgs = match[2].trim();
    try {
      const args = rawArgs ? JSON.parse(rawArgs) : {};
      calls.push({ name, args, raw: match[0] });
    } catch {
      // partial json ignored
    }
  }

  const tagRegex = /<tool_call>\s*([\s\S]*?)\s*<\/tool_call>/g;
  while ((match = tagRegex.exec(text)) !== null) {
    const rawBody = match[1].trim();
    try {
      const parsed = JSON.parse(rawBody);
      if (parsed && typeof parsed === 'object') {
        const name = parsed.name || parsed.function?.name;
        const args = parsed.arguments || parsed.args || parsed.parameters || parsed.function?.arguments || {};
        const parsedArgs = typeof args === 'string' ? JSON.parse(args) : args;
        if (name) {
          calls.push({ name, args: parsedArgs || {}, raw: match[0] });
        }
      }
    } catch {
      // ignore
    }
  }

  const codeBlockRegex = /```(?:tool_call|json:tool_call)\s*([\s\S]*?)\s*```/g;
  while ((match = codeBlockRegex.exec(text)) !== null) {
    const rawBody = match[1].trim();
    try {
      const parsed = JSON.parse(rawBody);
      if (parsed && typeof parsed === 'object') {
        const name = parsed.name || parsed.function?.name;
        const args = parsed.arguments || parsed.args || {};
        const parsedArgs = typeof args === 'string' ? JSON.parse(args) : args;
        if (name) {
          calls.push({ name, args: parsedArgs || {}, raw: match[0] });
        }
      }
    } catch {
      // ignore
    }
  }

  return calls;
}

export function cleanModelOutputText(text: string): string {
  return text
    .replace(/TOOL_CALL:\s*[a-zA-Z0-9_-]+\s*\([\s\S]*?\)(?=\n|$)/g, '')
    .replace(/<tool_call>[\s\S]*?<\/tool_call>/g, '')
    .replace(/```(?:tool_call|json:tool_call)[\s\S]*?```/g, '')
    .trim();
}

export function isWebLLMModelId(modelId: string | undefined): boolean {
  if (!modelId) return false;
  return WEBLLM_MODELS.some((m) => m.id === modelId) || modelId.endsWith('-MLC') || modelId.includes('-MLC-');
}

export function isNativeToolCallingModel(modelId?: string): boolean {
  if (!modelId) return false;
  if (/E2B|community|welcoma/i.test(modelId)) return false;
  if (COMMUNITY_WEBLLM_MODELS.some((m) => m.id === modelId)) return false;
  // Only the confirmed WebLLM ChatCompletionRequest.tools-compatible models:
  // Hermes-2-Pro-Llama-3, Hermes-2-Pro-Mistral-7B, Hermes-3-Llama-3.1
  // (Hermes-3-Llama-3.2-3B and Qwen2.5 do NOT appear in the confirmed list)
  return (
    /^Hermes-2-Pro-(Llama-3|Mistral-7B)-\dB-q4f(16|32)_1-MLC$/.test(modelId) ||
    /^Hermes-3-Llama-3\.1-8B-q4f(16|32)_1-MLC$/.test(modelId)
  );
}

export function isCompactWebLLMModel(modelId?: string): boolean {
  return /360M|0\.5B/i.test(modelId || '');
}

export function buildChatMessages(
  prompt: string,
  history: ChatHistoryMessage[] = [],
  context?: ChatContextFiles,
  options?: { compact?: boolean }
): WebLLMChatMessage[] {
  const compact = options?.compact === true;
  const messages: WebLLMChatMessage[] = [{
    role: 'system',
    content: compact ? WEBLLM_COMPACT_SYSTEM_PROMPT : WEBLLM_SYSTEM_PROMPT,
  }];

  // Keep history bounded to avoid overflowing compact 1k/2k WebGPU context windows
  const recent = history.slice(compact ? -2 : -6);
  for (const msg of recent) {
    if (!msg.content?.trim()) continue;
    messages.push({
      role: msg.role === 'assistant' ? 'assistant' : msg.role === 'tool' ? 'tool' : 'user',
      content: msg.content.slice(0, 800),
      name: msg.name,
      tool_call_id: msg.tool_call_id,
    });
  }

  let userContent = prompt;
  if (!compact) {
    const fileSnippets = (context?.files || [])
      .filter((f) => f.content)
      .slice(0, 2)
      .map((f) => {
        const range = f.startLine && f.endLine ? `:${f.startLine}-${f.endLine}` : '';
        const clipped = (f.content || '').slice(0, 600);
        return `File ${f.path}${range}:\n${clipped}`;
      });

    if (context?.projectOverview) {
      const compactOverview = context.projectOverview.slice(0, 600);
      userContent = `Project: ${context.project || ''}\nStructure:\n${compactOverview}\n\n${userContent}`;
    } else if (context?.project) {
      userContent = `Project: ${context.project}\n(Use list_files or read_file to inspect files in this project.)\n\n${userContent}`;
    }

    if (fileSnippets.length > 0) {
      userContent = `${userContent}\n\nContext:\n${fileSnippets.join('\n\n')}`;
    }
  }

  messages.push({ role: 'user', content: userContent });
  return messages;
}

export function extractDeltaContent(chunk: unknown): string {
  if (!chunk || typeof chunk !== 'object') return '';
  const choices = (chunk as { choices?: Array<{ delta?: { content?: string | null } }> }).choices;
  const content = choices?.[0]?.delta?.content;
  return typeof content === 'string' ? content : '';
}

export function buildCompletionPrompt(options: {
  prefix: string;
  suffix?: string;
  language?: string;
}): string {
  const prefix = options.prefix.slice(-2000);
  const suffix = (options.suffix || '').slice(0, 400);
  const language = options.language || 'plaintext';

  return [
    `You are a code completion engine. Continue the ${language} code at the cursor.`,
    'Return only the insertion text. No markdown, no quotes, no explanations.',
    'Prefix:',
    prefix,
    suffix ? `Suffix:\n${suffix}` : '',
    'Completion:',
  ]
    .filter(Boolean)
    .join('\n');
}

export function sanitizeCompletion(raw: string): string {
  let text = raw.trim();
  if (!text) return '';

  const fenced = text.match(/^```(?:\w+)?\n([\s\S]*?)```$/);
  if (fenced) {
    text = fenced[1].trim();
  }

  text = text.replace(/^```(?:\w+)?\n?/, '').replace(/\n?```$/, '');
  const firstLine = text.split('\n')[0] || '';
  if (/^(here('s| is)|the completion|sure[,.]?)/i.test(firstLine) && text.includes('\n')) {
    text = text.split('\n').slice(1).join('\n').trim();
  }

  return text.slice(0, 400);
}

export function detectWebGPU(): boolean {
  if (typeof navigator === 'undefined') return false;
  return typeof (navigator as Navigator & { gpu?: unknown }).gpu !== 'undefined';
}

export interface GPUProbeResult {
  available: boolean;
  error?: string;
  isFallback?: boolean;
  hasShaderF16?: boolean;
  adapterName?: string;
  preferenceUsed?: string;
  adapterInfo?: {
    vendor?: string;
    architecture?: string;
    device?: string;
    description?: string;
  };
  maxStorageBufferBindingSize?: number;
  maxBufferSize?: number;
  optimalMaxTokens?: number;
}

export function calculateOptimalMaxTokens(adapter?: any): number {
  if (!adapter || !adapter.limits) {
    return 2048;
  }
  const maxStorageBinding = adapter.limits.maxStorageBufferBindingSize || (128 * 1024 * 1024);
  const maxBuffer = adapter.limits.maxBufferSize || (256 * 1024 * 1024);

  // High-performance GPU (>= 8GB VRAM / Modern desktop / Apple Silicon)
  // Max storage buffer >= 2GB
  if (maxStorageBinding >= (2 * 1024 * 1024 * 1024) || maxBuffer >= (2 * 1024 * 1024 * 1024)) {
    return 8192;
  }

  // Mid-range GPU (4GB - 8GB VRAM)
  // Max storage buffer >= 1GB
  if (maxStorageBinding >= (1024 * 1024 * 1024) || maxBuffer >= (1024 * 1024 * 1024)) {
    return 4096;
  }

  // Moderate GPU (2GB - 4GB VRAM)
  // Max storage buffer >= 512MB
  if (maxStorageBinding >= (512 * 1024 * 1024)) {
    return 2560;
  }

  // Entry-level / legacy GPU (<2GB VRAM e.g. GCN 1.0 1GB VRAM)
  return 1536;
}

export function getPreferredContextWindow(modelId: string, optimalMaxTokens = 2048): number {
  const compact = isCompactWebLLMModel(modelId);
  const medium = /1B|1\.5B|E2B|2b-it|2B/i.test(modelId);
  const large = /3B|4B|7B|8B|12B|14B|34B|70B/i.test(modelId);
  if (compact) return 1024;
  if (/gemma-2|gemma-4/i.test(modelId) || medium) return Math.min(1024, Math.max(768, Math.min(1024, optimalMaxTokens)));
  if (large) return Math.min(2048, Math.max(1024, Math.min(2048, optimalMaxTokens)));
  // Unknown / future models: be conservative to avoid WebGPU VRAM OOM
  return Math.min(2048, Math.max(1024, Math.min(optimalMaxTokens, 2048)));
}

export function getWebLLMRuntimeLimits(
  modelId: string,
  modelRecord?: { model_lib?: string; overrides?: { context_window_size?: number; prefill_chunk_size?: number } },
  optimalMaxTokens = 2048
): { contextWindow: number; prefillChunkSize: number } {
  const preferred = getPreferredContextWindow(modelId, optimalMaxTokens);
  const lib = String(modelRecord?.model_lib || '');
  const csMatch = lib.match(/_cs(\d+)k/i);
  const compiledChunk = csMatch ? parseInt(csMatch[1], 10) * 1024 : undefined;
  const recordContext = modelRecord?.overrides?.context_window_size;
  const recordPrefill = modelRecord?.overrides?.prefill_chunk_size;

  let contextWindow = preferred;
  if (typeof compiledChunk === 'number') {
    contextWindow = Math.min(contextWindow, compiledChunk);
  }
  if (isCompactWebLLMModel(modelId)) {
    contextWindow = Math.min(contextWindow, 1024);
  }
  if (typeof recordContext === 'number') {
    contextWindow = Math.min(contextWindow, recordContext);
  }

  const isSmallOrMedium = /360M|0\.5B|1B|1\.5B|E2B|2b-it|2B|Smol/i.test(modelId);
  const isGemmaFamily = /gemma-2|gemma-4|Gemma/i.test(modelId);

  let prefillChunkSize = recordPrefill || compiledChunk || Math.min(1024, contextWindow);
  prefillChunkSize = Math.min(prefillChunkSize, contextWindow);
  if (isCompactWebLLMModel(modelId)) {
    prefillChunkSize = Math.min(prefillChunkSize, 256);
  }
  if (isGemmaFamily || isSmallOrMedium) {
    contextWindow = Math.min(contextWindow, 1024);
    prefillChunkSize = Math.min(prefillChunkSize, 256);
  }
  return { contextWindow: Math.max(256, contextWindow), prefillChunkSize: Math.max(64, prefillChunkSize) };
}

export function capGenerationTokens(
  modelId: string,
  requested: number,
  contextWindow: number,
  promptChars = 0
): number {
  const promptTokens = Math.ceil(Math.max(0, promptChars) / 4);
  const remaining = Math.max(64, contextWindow - promptTokens - 32);
  const isSmallOrMedium = /360M|0\.5B|1B|1\.5B|E2B|2b-it|2B|Smol|Gemma/i.test(modelId);
  const isLarge = /3B|4B|7B|8B|12B|14B/i.test(modelId);
  let modelCap = 1024;
  if (isCompactWebLLMModel(modelId)) modelCap = 256;
  else if (isSmallOrMedium) modelCap = 384;
  else if (isLarge) modelCap = 1024;
  else {
    modelCap = Math.min(768, Math.floor(contextWindow * 0.35));
  }
  return Math.max(64, Math.min(requested, remaining, modelCap));
}

export function isCommunityModel(modelId?: string): boolean {
  if (!modelId) return false;
  return /E2B|community|welcoma/i.test(modelId) || COMMUNITY_WEBLLM_MODELS.some((m) => m.id === modelId);
}

export function isFatalWebGpuError(message: string): boolean {
  return /disposed|mapAsync|unmapped|Device is lost|Device lost|Invalid ShaderModule|destroyed/i.test(message);
}

export function shouldUseNativeWebLLMTools(modelId?: string): boolean {
  if (!isNativeToolCallingModel(modelId)) return false;
  // Tiny models blow the KV cache if the full OpenAI tool schema is injected.
  return !isCompactWebLLMModel(modelId);
}

const MAP_GUARD_MARK = '__candyWebGPUMapGuard';
let globalMapChain: Promise<unknown> = Promise.resolve();

async function waitBriefly(promise: Promise<unknown> | undefined, ms = 20000): Promise<void> {
  if (!promise) return;
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    await Promise.race([
      promise.catch(() => undefined),
      new Promise<void>((resolve) => {
        timer = setTimeout(resolve, ms);
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

export async function drainWebGPUMapChain(extraMs = 150): Promise<void> {
  const marker = globalMapChain.then(() => new Promise<void>((r) => setTimeout(r, extraMs)));
  globalMapChain = marker.catch(() => undefined);
  await marker.catch(() => undefined);
}

export function installWebGPUMapGuard(): void {
  if (typeof globalThis === 'undefined') return;
  const GT = globalThis as any;
  const GPUBufferCtor = GT.GPUBuffer;
  if (!GPUBufferCtor?.prototype?.mapAsync) return;
  const proto = GPUBufferCtor.prototype as any;
  if (proto[MAP_GUARD_MARK]) return;
  proto[MAP_GUARD_MARK] = true;

  const origMapAsync = proto.mapAsync;
  const origUnmap = proto.unmap;
  const origDestroy = proto.destroy;
  const pendingMaps = new WeakMap<object, Promise<unknown>>();
  const pendingUnmaps = new WeakMap<object, Promise<unknown>>();
  const destroyedBuffers = new WeakSet<object>();
  const bufferDevices = new WeakMap<object, any>();

  proto.mapAsync = function mapAsyncGuarded(this: any, ...args: any[]) {
    if (destroyedBuffers.has(this)) {
      return Promise.resolve(undefined);
    }
    const self = this;
    const run = async () => {
      if (destroyedBuffers.has(self)) return undefined;
      const pendingUnmap = pendingUnmaps.get(self);
      if (pendingUnmap) await pendingUnmap.catch(() => undefined);
      const device = bufferDevices.get(self);
      await waitBriefly(device?.queue?.onSubmittedWorkDone?.());
      const inflight = pendingMaps.get(self);
      if (self.mapState === 'pending' && inflight) {
        await inflight.catch(() => undefined);
      }
      if (destroyedBuffers.has(self)) return undefined;
      if (self.mapState === 'mapped') {
        return undefined;
      }
      const request: Promise<undefined> = origMapAsync.apply(self, args);
      pendingMaps.set(self, request);
      try {
        return await request;
      } finally {
        if (pendingMaps.get(self) === request) pendingMaps.delete(self);
      }
    };
    const queued = globalMapChain.then(run, run);
    globalMapChain = queued.catch(() => undefined);
    return queued;
  };

  proto.unmap = function unmapGuarded(this: any) {
    const self = this;
    if (destroyedBuffers.has(self)) return;
    if (self.mapState === 'unmapped') return;
    if (self.mapState !== 'pending' && !pendingUnmaps.has(self)) {
      try { origUnmap.call(self); } catch {}
      return;
    }
    const doUnmap = async () => {
      if (destroyedBuffers.has(self)) return;
      const pending = pendingMaps.get(self);
      if (pending) {
        try { await pending.catch(() => undefined); } catch {}
      }
      if (destroyedBuffers.has(self)) return;
      if (self.mapState === 'mapped') {
        try { origUnmap.call(self); } catch {}
      } else if (self.mapState !== 'unmapped') {
        try { origUnmap.call(self); } catch {}
      }
    };
    const queued = globalMapChain.then(doUnmap, doUnmap);
    pendingUnmaps.set(self, queued);
    globalMapChain = queued.catch(() => undefined);
    void queued.finally(() => {
      if (pendingUnmaps.get(self) === queued) pendingUnmaps.delete(self);
    });
  };

  proto.destroy = function destroyGuarded(this: any) {
    const self = this;
    if (destroyedBuffers.has(self)) return;
    destroyedBuffers.add(self);
    const doDestroy = async () => {
      const device = bufferDevices.get(self);
      if (device?.queue?.onSubmittedWorkDone) {
        await waitBriefly(device.queue.onSubmittedWorkDone()).catch(() => undefined);
      }
      const pending = pendingMaps.get(self);
      if (pending) {
        try { await pending.catch(() => undefined); } catch {}
      }
      const pendingUnmap = pendingUnmaps.get(self);
      if (pendingUnmap) {
        try { await pendingUnmap.catch(() => undefined); } catch {}
      }
      try {
        if (self.mapState === 'mapped') {
          try { origUnmap.call(self); } catch {}
        } else if (self.mapState === 'pending') {
          try {
            await new Promise<void>((r) => setTimeout(r, 30));
            if (self.mapState === 'mapped') { try { origUnmap.call(self); } catch {} }
          } catch {}
        }
      } catch {}
      try { origDestroy.call(self); } catch {}
    };
    const queued = globalMapChain.then(doDestroy, doDestroy);
    globalMapChain = queued.catch(() => undefined);
  };

  const GPUDeviceCtor = GT.GPUDevice;
  if (GPUDeviceCtor?.prototype) {
    const deviceProto = GPUDeviceCtor.prototype as any;
    if (!deviceProto[MAP_GUARD_MARK]) {
      deviceProto[MAP_GUARD_MARK] = true;
      if (typeof deviceProto.createBuffer === 'function') {
        const origCreateBuffer = deviceProto.createBuffer;
        deviceProto.createBuffer = function createBufferGuarded(this: any, descriptor: any) {
          const buffer = origCreateBuffer.call(this, descriptor);
          bufferDevices.set(buffer, this);
          return buffer;
        };
      }
      if (typeof deviceProto.destroy === 'function') {
        const origDeviceDestroy = deviceProto.destroy;
        deviceProto.destroy = function destroyGuarded(this: any) {
          const self = this;
          const doDestroy = async () => {
            try {
              await waitBriefly(self.queue?.onSubmittedWorkDone?.()).catch(() => undefined);
            } catch {}
            try { return origDeviceDestroy.call(self); } catch {}
          };
          const queued = globalMapChain.then(doDestroy, doDestroy);
          globalMapChain = queued.catch(() => undefined);
        };
      }
    }
  }
}

type CachedGpuProbe = { result: GPUProbeResult; at: number };
let cachedGpuProbe: CachedGpuProbe | null = null;
let inFlightGpuProbe: Promise<GPUProbeResult> | null = null;
const GPU_PROBE_TTL_MS = 10 * 60 * 1000;

export function clearWebGPUProbeCache(): void {
  cachedGpuProbe = null;
  inFlightGpuProbe = null;
}

export interface ProbeWebGPUOptions {
  force?: boolean;
  verifyDevice?: boolean;
}

let adapterFallbackInstalled = false;

export function ensureWebGPUAdapterResilience(): void {
  if (adapterFallbackInstalled || typeof navigator === 'undefined') return;
  const navGpu = (navigator as any)?.gpu;
  if (!navGpu || typeof navGpu.requestAdapter !== 'function') return;

  const originalRequestAdapter = navGpu.requestAdapter.bind(navGpu);
  navGpu.requestAdapter = async function (options?: any) {
    try {
      const adapter = await originalRequestAdapter(options);
      if (adapter) return adapter;
    } catch {
      // Fall through to candidates
    }

    const fallbackOptions = [
      { powerPreference: 'high-performance' },
      { powerPreference: 'low-power' },
      undefined,
      { forceFallbackAdapter: true },
    ];

    for (const opt of fallbackOptions) {
      try {
        const adapter = await originalRequestAdapter(opt);
        if (adapter) return adapter;
      } catch {
        continue;
      }
    }
    return null;
  };
  adapterFallbackInstalled = true;
}

export async function probeWebGPU(options: ProbeWebGPUOptions = {}): Promise<GPUProbeResult> {
  if (typeof navigator === 'undefined') {
    return { available: false, error: 'WebGPU can only run inside the HyprCandy agent WebView.' };
  }
  const gpu = (navigator as Navigator & {
    gpu?: {
      requestAdapter?: (options?: { powerPreference?: string; forceFallbackAdapter?: boolean }) => Promise<any>;
    };
  }).gpu;

  if (!gpu?.requestAdapter) {
    let origin = 'unknown';
    let secure = 'unknown';
    let userAgent = 'unknown';
    try { origin = globalThis.location?.origin || origin; } catch { }
    try { secure = String(globalThis.isSecureContext); } catch { }
    try { userAgent = globalThis.navigator?.userAgent || userAgent; } catch { }
    let gpuMethods = 'unknown';
    try {
      gpuMethods = Object.getOwnPropertyNames(Object.getPrototypeOf(gpu || {})).sort().join(',') || 'none';
    } catch { }
    const detail = `origin=${origin}; secure=${secure}; navigator.gpu=${typeof gpu}; gpuMethods=${gpuMethods}; userAgent=${userAgent}`;
    const reason = gpu
      ? 'This WebKitGTK build exposes navigator.gpu but not GPU.requestAdapter; the browser runtime lacks usable WebGPU support.'
      : 'The browser runtime does not expose navigator.gpu.';
    console.warn('[WebLLM] WebGPU capability incomplete:', reason, detail);
    return {
      available: false,
      error: `${reason} ${detail}. WebLLM requires a WebGPU-capable runtime; this is not a model-download or cache error.`,
    };
  }

  if (
    !options.force &&
    cachedGpuProbe?.result.available &&
    Date.now() - cachedGpuProbe.at < GPU_PROBE_TTL_MS
  ) {
    return cachedGpuProbe.result;
  }

  if (!options.force && inFlightGpuProbe) {
    return inFlightGpuProbe;
  }

  ensureWebGPUAdapterResilience();
  installWebGPUMapGuard();
  // Default off: requestDevice()+destroy() races WebLLM GPUBuffer.mapAsync on Vulkan.
  const verifyDevice = options.verifyDevice === true;

  inFlightGpuProbe = (async () => {

  // Try GPU candidates in order:
  // 1. high-performance (discrete GPU on hybrid laptops)
  // 2. low-power (integrated GPU fallback)
  // 3. default (browser/system default adapter)
  // 4. fallback adapter (CPU/software fallback if available)
  const candidateOptions: Array<{ label: string; opt?: { powerPreference?: string; forceFallbackAdapter?: boolean } }> = [
    { label: 'high-performance', opt: { powerPreference: 'high-performance' } },
    { label: 'low-power', opt: { powerPreference: 'low-power' } },
    { label: 'default', opt: undefined },
    { label: 'fallback', opt: { forceFallbackAdapter: true } },
  ];

  let lastError = '';

  for (const candidate of candidateOptions) {
    try {
      let adapter: any = null;
      try {
        const gpuAny = gpu as any;
        adapter = candidate.opt ? await gpuAny.requestAdapter(candidate.opt) : await gpuAny.requestAdapter();
      } catch (reqErr: any) {
        lastError = `Candidate ${candidate.label} adapter request failed: ${reqErr?.message || reqErr}`;
        continue;
      }

      if (!adapter) {
        continue;
      }

      const isFallback = Boolean(adapter.isFallbackAdapter);
      const hasShaderF16 = Boolean(adapter.features?.has('shader-f16'));

      let info: { vendor?: string; architecture?: string; device?: string; description?: string } | undefined;
      try {
        if (adapter.info) {
          info = {
            vendor: adapter.info.vendor,
            architecture: adapter.info.architecture,
            device: adapter.info.device,
            description: adapter.info.description,
          };
        } else if (typeof adapter.requestAdapterInfo === 'function') {
          const reqInfo = await adapter.requestAdapterInfo();
          info = {
            vendor: reqInfo?.vendor,
            architecture: reqInfo?.architecture,
            device: reqInfo?.device,
            description: reqInfo?.description,
          };
        }
      } catch {
        // adapter info is optional
      }

      let adapterName = [info?.vendor, info?.architecture, info?.device || info?.description]
        .filter(Boolean)
        .join(' ')
        .trim();

      if (!adapterName && isFallback) {
        adapterName = 'CPU Fallback Adapter';
      }



      // Creating a second GPUDevice while WebLLM is inferencing races mapAsync.
      // Only allocate a throwaway device during the first adapter selection.
      if (verifyDevice) {
        try {
          const testDevice = await adapter.requestDevice();
          if (testDevice) {
            try {
              await testDevice.queue?.onSubmittedWorkDone?.();
            } catch {
              // queue flush is best-effort
            }
            if (typeof testDevice.destroy === 'function') {
              try {
                testDevice.destroy();
              } catch {
                // cleanup
              }
            }
          }
        } catch (devError: any) {
          lastError = `Candidate ${candidate.label} (${adapterName || 'GPU'}) device creation failed: ${devError?.message || devError}`;
          console.warn(`[WebLLM] Candidate ${candidate.label} failed device creation, trying alternative candidate...`, devError);
          continue;
        }
      }

      const optimalMaxTokens = calculateOptimalMaxTokens(adapter);
      const successResult: GPUProbeResult = {
        available: true,
        isFallback,
        hasShaderF16,
        adapterName: adapterName || undefined,
        adapterInfo: info,
        preferenceUsed: candidate.label,
        maxStorageBufferBindingSize: adapter.limits?.maxStorageBufferBindingSize,
        maxBufferSize: adapter.limits?.maxBufferSize,
        optimalMaxTokens,
      };
      console.log('[WebLLM] Probed GPU adapter successfully: ' + JSON.stringify(successResult));
      cachedGpuProbe = { result: successResult, at: Date.now() };
      return successResult;
    } catch (err: any) {
      lastError = err?.message || String(err);
    }
  }

  const errorResult: GPUProbeResult = {
    available: false,
    error: lastError
      ? `Unable to find a compatible GPU adapter (${lastError}). Restart hyprcandy-launcher.service and reopen the agent.`
      : 'Unable to find a compatible GPU adapter. Restart hyprcandy-launcher.service and reopen the agent.',
  };
  console.warn('[WebLLM] WebGPU probe failed on all candidates:', errorResult);
  return errorResult;
  })();

  try {
    return await inFlightGpuProbe;
  } finally {
    inFlightGpuProbe = null;
  }
}

export interface CustomWebLLMModel {
  id: string;
  name: string;
  model: string;
  model_lib: string;
  desc?: string;
  required_features?: string[];
}

export function parseProgressFromText(text: string): number | null {
  if (!text) return null;
  const match = text.match(/(\d+(?:\.\d+)?)\s*%/);
  if (!match) return null;
  const value = Number(match[1]) / 100;
  if (Number.isNaN(value)) return null;
  return Math.min(1, Math.max(0, value));
}

export function normalizeInitProgress(report: {
  text?: string;
  progress?: number;
}): { text: string; progress: number } {
  const text = report.text || 'Loading WebLLM model…';
  const fromReport = typeof report.progress === 'number' ? report.progress : 0;
  const fromText = parseProgressFromText(text);
  const progress = fromReport > 0 ? fromReport : (fromText ?? fromReport);
  return { text, progress };
}

export function isCustomWebLLMModel(model: Partial<CustomWebLLMModel>): model is CustomWebLLMModel {
  return Boolean(
    model.id?.trim() &&
    model.model?.trim() &&
    model.model_lib?.trim()
  );
}

export function mergeWebLLMModelLists(
  builtin: Array<{ model_id?: string }>,
  custom: CustomWebLLMModel[]
): Array<Record<string, unknown>> {
  const extra = custom.filter(isCustomWebLLMModel).map((m) => ({
    model: m.model.trim(),
    model_id: m.id.trim(),
    model_lib: m.model_lib.trim(),
    ...(m.required_features?.length ? { required_features: m.required_features } : {}),
  }));
  const seen = new Set(extra.map((m) => m.model_id));
  const base = builtin.filter((m) => m.model_id && !seen.has(m.model_id));
  return [...(base as Array<Record<string, unknown>>), ...extra];
}

export function rewriteF16ModelIdToFp32(modelId: string): string {
  let target = modelId;
  if (target.includes('-q4f16_1-')) {
    target = target.replace('-q4f16_1-', '-q4f32_1-');
  } else if (target.endsWith('-q4f16_1-MLC')) {
    target = target.replace('-q4f16_1-MLC', '-q4f32_1-MLC');
  } else if (target.includes('-q0f16-')) {
    target = target.replace('-q0f16-', '-q4f32_1-');
  } else if (target.endsWith('-q0f16-MLC')) {
    target = target.replace('-q0f16-MLC', '-q4f32_1-MLC');
  }
  return target;
}

function rewriteCustomModelF16ToFp32(model: CustomWebLLMModel): CustomWebLLMModel | null {
  const newId = rewriteF16ModelIdToFp32(model.id);
  if (newId === model.id) return null;
  const rewrite = (s: string): string => {
    let out = s;
    out = out.replace(/q4f16_1/g, 'q4f32_1').replace(/q0f16/g, 'q4f32_1');
    out = out.replace(/q4f16%5F1/g, 'q4f32_1').replace(/q0f16/g, 'q4f32_1');
    return out;
  };
  const required_features = model.required_features?.filter((f) => f !== 'shader-f16');
  return {
    ...model,
    id: newId,
    model: rewrite(model.model),
    model_lib: rewrite(model.model_lib),
    required_features,
    desc: model.desc ? `${model.desc} (FP32 auto-fallback: GPU lacks shader-f16)` : undefined,
  };
}

export function synthesizeFp32FallbackCustomModels(
  customModels: CustomWebLLMModel[],
  hasShaderF16: boolean
): CustomWebLLMModel[] {
  if (hasShaderF16) return customModels;
  const extras: CustomWebLLMModel[] = [];
  for (const m of customModels) {
    const fallback = rewriteCustomModelF16ToFp32(m);
    if (fallback) extras.push(fallback);
  }
  const seen = new Set(customModels.map((m) => m.id));
  const dedupedExtras = extras.filter((m) => !seen.has(m.id));
  return [...customModels, ...dedupedExtras];
}

export function resolveWebLLMModel(
  modelId?: string,
  extraIds: string[] = [],
  hasShaderF16 = true
): string {
  let target = modelId;
  if (!target || (!isWebLLMModelId(target) && !extraIds.includes(target))) {
    target = getDefaultWebLLMModel(hasShaderF16);
  }

  // If the GPU does not support float16 shaders (shader-f16), map to 32-bit (FP32) variant.
  // Applies to BOTH builtin WebLLM model IDs AND custom/community extra IDs.
  if (!hasShaderF16) {
    target = rewriteF16ModelIdToFp32(target);
  }

  return target;
}
