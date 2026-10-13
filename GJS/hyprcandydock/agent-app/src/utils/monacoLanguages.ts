/**
 * Monaco language + lint support for the workspace editor.
 *
 * The bundled `monaco-editor` already ships Monarch tokenizers for ~80
 * "basic" languages (lua, yaml, xml, ini, rust, go, …) and full worker-backed
 * validation for TypeScript/JavaScript, JSON, CSS and HTML. What it does *not*
 * provide out of the box is (a) a mapping from the many file extensions this
 * desktop actually edits to those language ids, (b) tokenizers for QML and
 * TOML, and (c) any diagnostics for languages without a Monaco worker.
 *
 * This module fills those gaps:
 *   • a broad extension → language-id table,
 *   • custom QML and TOML grammars,
 *   • best-effort live syntax markers for Lua (via the `luaparse` parser) and
 *     QML (a bracket-balance scanner), since neither has a Monaco worker.
 */
import { parse as luaParse } from 'luaparse';

/** File extension (lower-cased, no dot) → Monaco language id. Ids marked ✱
 * are registered by us in `registerCustomLanguages`; every other id is a
 * language Monaco already ships. */
export const EXTENSION_LANGUAGE_MAP: Record<string, string> = {
  // Web / styling
  ts: 'typescript', tsx: 'typescript', mts: 'typescript', cts: 'typescript',
  js: 'javascript', jsx: 'javascript', mjs: 'javascript', cjs: 'javascript',
  json: 'json', jsonc: 'json', json5: 'json',
  css: 'css', scss: 'scss', less: 'less',
  html: 'html', htm: 'html', vue: 'html', svelte: 'html', xml: 'xml',
  md: 'markdown', mdx: 'mdx', markdown: 'markdown',
  // Systems / general purpose
  py: 'python', pyc: 'python', pyi: 'python',
  c: 'cpp', h: 'cpp', cpp: 'cpp', cc: 'cpp', cxx: 'cpp', hpp: 'cpp', hh: 'cpp', hxx: 'cpp',
  cs: 'csharp', m: 'objective-c', mm: 'objective-c',
  go: 'go', rs: 'rust', java: 'java', kt: 'kotlin', kts: 'kotlin',
  swift: 'swift', scala: 'scala', dart: 'dart', php: 'php', rb: 'ruby',
  pl: 'perl', pm: 'perl', lua: 'lua', r: 'r', jl: 'julia',
  sh: 'shell', bash: 'shell', zsh: 'shell', fish: 'shell',
  ps1: 'powershell', psm1: 'powershell', bat: 'bat', cmd: 'bat',
  ex: 'elixir', exs: 'elixir',
  sql: 'sql', mysql: 'mysql', pgsql: 'pgsql', graphql: 'graphql', gql: 'graphql',
  proto: 'protobuf', clj: 'clojure', cljs: 'clojure',
  // Config / markup
  yml: 'yaml', yaml: 'yaml', toml: 'toml' /* ✱ */, ini: 'ini', conf: 'ini',
  properties: 'ini', env: 'ini', dockerfile: 'dockerfile',
  tf: 'hcl', tfvars: 'hcl', nomad: 'hcl',
  // HyprCandy / Qt / KDE desktop files
  qml: 'qml' /* ✱ */, qrc: 'xml', desktop: 'ini',
  // Misc
  svg: 'xml', diff: 'plaintext',
};

/** Resolve the Monaco language id for a file path (defaults to plaintext). */
export function languageForPath(path: string): string {
  const name = (path.split('/').pop() || '').toLowerCase();
  // A few files have no usable extension but a well-known syntax.
  if (name === 'dockerfile') return 'dockerfile';
  if (name === 'makefile' || name === 'gnumakefile') return 'plaintext';
  const ext = name.includes('.') ? name.split('.').pop()! : '';
  return EXTENSION_LANGUAGE_MAP[ext] || 'plaintext';
}

let customRegistered = false;

/** Register the QML and TOML grammars (idempotent; safe to call from every
 * editor's beforeMount). */
export function registerCustomLanguages(monaco: any): void {
  if (customRegistered || !monaco?.languages) return;
  customRegistered = true;
  registerQml(monaco);
  registerToml(monaco);
}

function registerQml(monaco: any): void {
  monaco.languages.register({ id: 'qml' });
  monaco.languages.setMonarchTokensProvider('qml', {
    defaultToken: '',
    tokenPostfix: '.qml',
    keywords: [
      'import', 'property', 'default', 'readonly', 'required', 'signal',
      'function', 'on', 'as', 'if', 'else', 'for', 'while', 'do', 'return',
      'break', 'continue', 'switch', 'case', 'try', 'catch', 'finally',
      'throw', 'new', 'delete', 'typeof', 'instanceof', 'in', 'of', 'void',
      'var', 'let', 'const', 'class', 'extends', 'super', 'this',
      'true', 'false', 'null', 'undefined', 'async', 'await', 'yield',
      'component', 'pragma', 'singleton', 'weak', 'alias',
    ],
    // Common QtQuick / QtQml types and inline property types.
    types: [
      'Item', 'Rectangle', 'Text', 'TextInput', 'TextEdit', 'Image', 'BorderImage',
      'MouseArea', 'TapHandler', 'HoverHandler', 'DragHandler', 'KeysHandler',
      'Column', 'Row', 'Grid', 'Flow', 'ColumnLayout', 'RowLayout', 'GridLayout',
      'ListView', 'GridView', 'Repeater', ' Flickable', 'ScrollView', 'SwipeView',
      'StackView', 'Page', 'Pane', 'GroupItem', 'Loader', 'Layout',
      'ApplicationWindow', 'Window', 'Popup', 'Dialog', 'Menu', 'MenuItem',
      'MenuBar', 'ToolButton', 'Button', 'RadioButton', 'CheckBox', 'Slider',
      'SpinBox', 'ComboBox', 'Dial', 'DelayButton', 'Frame', 'GroupBox',
      'Action', 'Shortcut', 'Timer', 'Transition', 'Animation', 'PropertyAnimation',
      'NumberAnimation', 'Behavior', 'Binding', 'Component', 'Connections',
      'State', 'StateChangeTransition', 'PropertyAction', 'SequentialAnimation',
      'ParallelAnimation', 'AnchorAnimation', 'ShaderEffect', 'Canvas',
      'Color', 'Point', 'Size', 'Rect', 'vector2d', 'vector3d', 'vector4d',
      'quaternion', 'matrix4x4', 'int', 'real', 'double', 'string', 'bool',
      'color', 'url', 'font', 'date', 'datetime', 'variant', 'any',
    ],
    operators: [
      '=', '>', '<', '!', '~', '?', ':', '==', '<=', '>=', '!=', '&&', '||',
      '++', '--', '+', '-', '*', '/', '&', '|', '^', '%', '<<', '>>', '>>>',
    ],
    symbols: /[=><!~?:&|+\-*/^%]+/,
    escapes: /\\(?:[abfnrtv\\"']|x[0-9A-Fa-f]{1,4}|u[0-9A-Fa-f]{4}|U[0-9A-Fa-f]{8})/,
    tokenizer: {
      root: [
        { include: '@whitespace' },
        [/@[a-zA-Z_]\w*/, 'annotation'],
        [/[a-zA-Z_$][\w$]*/, {
          cases: {
            '@keywords': 'keyword',
            '@types': 'type',
            '@default': 'identifier',
          },
        }],
        [/[A-Z][\w$]*/, 'type.identifier'],
        { include: '@numbers' },
        [/[{}[\]()]/, '@brackets'],
        [/[;,.]/, 'delimiter'],
        [/@symbols/, { cases: { '@operators': 'operator', '@default': '' } }],
      ],
      whitespace: [
        [/[ \t\r\n]+/, ''],
        [/\/\/.*$/, 'comment'],
        [/\/\*/, 'comment', '@comment'],
      ],
      comment: [
        [/[^\/*]+/, 'comment'],
        [/\*\//, 'comment', '@pop'],
        [/[\/*]/, 'comment'],
      ],
      numbers: [
        [/0[xX][0-9a-fA-F]+/, 'number.hex'],
        [/\d+\.\d+([eE][\-+]?\d+)?/, 'number.float'],
        [/\d+/, 'number'],
      ],
    },
  } as any);
  monaco.languages.setLanguageConfiguration('qml', {
    comments: { lineComment: '//', blockComment: ['/*', '*/'] },
    brackets: [['{', '}'], ['[', ']'], ['(', ')']],
    autoClosingPairs: [
      { open: '{', close: '}' }, { open: '[', close: ']' }, { open: '(', close: ')' },
      { open: '"', close: '"' }, { open: "'", close: "'" },
    ],
    surroundingPairs: [
      { open: '{', close: '}' }, { open: '[', close: ']' }, { open: '(', close: ')' },
      { open: '"', close: '"' }, { open: "'", close: "'" },
    ],
  });
}

function registerToml(monaco: any): void {
  monaco.languages.register({ id: 'toml' });
  monaco.languages.setMonarchTokensProvider('toml', {
    defaultToken: '',
    tokenPostfix: '.toml',
    tokenizer: {
      root: [
        { include: '@whitespace' },
        [/^\s*\[\[?[^\]]*\]\]?/, 'keyword'],
        [/^\s*[A-Za-z0-9_.\-"']+(?=\s*=)/, 'variable.name'],
        [/=/, 'delimiter'],
        [/\b(true|false)\b/, 'boolean'],
        [/-?\d[\d_]*(\.\d+)?([eE][+-]?\d+)?/, 'number'],
        [/"""/, 'string', '@multilineBasic'],
        [/'''/, 'string', '@multilineLiteral'],
        [/"/, 'string', '@basicString'],
        [/'/, 'string', '@literalString'],
        [/[,[\]]/, 'delimiter'],
      ],
      whitespace: [
        [/[ \t\r\n]+/, ''],
        [/#.*$/, 'comment'],
      ],
      basicString: [
        [/@escapes/, 'string.escape'],
        [/\\./, 'string.escape.invalid'],
        [/"/, 'string', '@pop'],
        [/[^"\\]+/, 'string'],
      ],
      literalString: [[/'/, 'string', '@pop'], [/[^']+/, 'string']],
      multilineBasic: [[/"""/, 'string', '@pop'], [/[^"]+/, 'string'], [/"/, 'string']],
      multilineLiteral: [[/'''/, 'string', '@pop'], [/[^']+/, 'string'], [/'/, 'string']],
    },
    escapes: /\\(?:[btnfr\\"']|[0-7]{1,3}|[0-9]{1,3}|x[0-9A-Fa-f]{2}|u[0-9A-Fa-f]{4}|U[0-9A-Fa-f]{8})/,
  } as any);
  monaco.languages.setLanguageConfiguration('toml', {
    comments: { lineComment: '#' },
    brackets: [['[', ']'], ['{', '}']],
  });
}

const LINT_OWNER = 'hyprcandy-lint';

/**
 * Attach live syntax markers to an editor for languages that have no Monaco
 * worker (Lua, QML). JSON/CSS/HTML/TS are validated automatically by their
 * language workers, so we deliberately leave those alone.
 */
export function attachDiagnostics(monaco: any, editor: any): void {
  if (!monaco?.editor || !editor?.getModel) return;

  let timer: ReturnType<typeof setTimeout> | null = null;
  const run = () => {
    const model = editor.getModel?.();
    if (model) lintModel(monaco, model);
  };
  const schedule = () => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(run, 250);
  };

  editor.onDidChangeModel?.(schedule);
  editor.onDidChangeModelContent?.(schedule);
  run();
}

function lintModel(monaco: any, model: any): void {
  const lang = model.getLanguageId?.();
  if (lang === 'lua') return lintLua(monaco, model);
  if (lang === 'qml') return lintQml(monaco, model);
  // No custom provider for this language: clear any stale hyprcandy markers so
  // switching files doesn't leave old squiggles behind.
  monaco.editor.setModelMarkers(model, LINT_OWNER, []);
}

function clampCol(line: number, col: number, model: any): number {
  const max = model.getLineMaxColumn?.(line) ?? (col + 1);
  return Math.min(Math.max(1, col), max);
}

function lintLua(monaco: any, model: any): void {
  const text = model.getValue?.() || '';
  try {
    luaParse(text, { comments: false, scope: false, locations: false, ranges: false });
    monaco.editor.setModelMarkers(model, LINT_OWNER, []);
  } catch (e: any) {
    const line = Math.max(1, e?.line || 1);
    const col = Math.max(1, e?.column || 1);
    monaco.editor.setModelMarkers(model, LINT_OWNER, [{
      severity: monaco.MarkerSeverity?.Error ?? 8,
      message: e?.message ? String(e.message).replace(/^\[\d+:\d+\]\s*/, '') : 'Lua syntax error',
      startLineNumber: line,
      startColumn: clampCol(line, col, model),
      endLineNumber: line,
      endColumn: clampCol(line, col + 1, model),
    }]);
  }
}

/**
 * QML has no browser parser, so this is a conservative structural check: it
 * walks the source (skipping line comments, block comments and string
 * literals) and flags mismatched or never-closed braces, brackets and parens.
 * It intentionally reports only clear-cut errors to avoid noisy false
 * positives.
 */
function lintQml(monaco: any, model: any): void {
  const text = model.getValue?.() || '';
  const markers: any[] = [];
  const stack: Array<{ ch: string; line: number; col: number }> = [];
  const closing: Record<string, string> = { '}': '{', ']': '[', ')': '(' };
  const opening = new Set(['{', '[', '(']);

  let line = 1;
  let col = 1;
  let i = 0;
  const n = text.length;
  const advance = () => {
    if (text[i] === '\n') { line++; col = 1; } else { col++; }
    i++;
  };

  while (i < n && markers.length < 30) {
    const ch = text[i];
    const next = text[i + 1];

    if (ch === '/' && next === '/') { // line comment
      while (i < n && text[i] !== '\n') i++;
      continue;
    }
    if (ch === '/' && next === '*') { // block comment
      advance(); advance();
      while (i < n && !(text[i] === '*' && text[i + 1] === '/')) advance();
      advance(); advance();
      continue;
    }
    if (ch === '"' || ch === "'") { // string literal
      const quote = ch;
      const startLine = line, startCol = col;
      advance();
      while (i < n && text[i] !== quote) {
        if (text[i] === '\\') { advance(); advance(); continue; }
        if (text[i] === '\n') break; // unterminated on this line
        advance();
      }
      if (i >= n || text[i] !== quote) {
        markers.push(mkError(monaco, model, 'Unterminated string literal', startLine, startCol, line, col));
      } else {
        advance(); // closing quote
      }
      continue;
    }
    if (opening.has(ch)) {
      stack.push({ ch, line, col });
      advance();
      continue;
    }
    if (ch in closing) {
      const top = stack.pop();
      if (!top || top.ch !== closing[ch]) {
        markers.push(mkError(monaco, model, `Unmatched '${ch}'`, line, col, line, col + 1));
      }
      advance();
      continue;
    }
    advance();
  }

  for (const s of stack) {
    if (markers.length >= 30) break;
    markers.push({
      severity: monaco.MarkerSeverity?.Warning ?? 4,
      message: `'${s.ch}' is never closed`,
      startLineNumber: s.line,
      startColumn: clampCol(s.line, s.col, model),
      endLineNumber: s.line,
      endColumn: clampCol(s.line, s.col + 1, model),
    });
  }

  monaco.editor.setModelMarkers(model, LINT_OWNER, markers);
}

function mkError(monaco: any, model: any, message: string, sl: number, sc: number, el: number, ec: number) {
  return {
    severity: monaco.MarkerSeverity?.Error ?? 8,
    message,
    startLineNumber: sl,
    startColumn: clampCol(sl, sc, model),
    endLineNumber: el,
    endColumn: clampCol(el, ec, model),
  };
}
