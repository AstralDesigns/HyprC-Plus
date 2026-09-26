export interface MonacoThemeDefinition {
  id: string;
  name: string;
  base: 'vs-dark' | 'vs';
  bg: string;
  fg: string;
  accent: string;
  line: string;
}

// No preset themes — this app uses only the adaptive Matugen theme.
export const CANDYCODE_THEMES: { id: string; name: string }[] = [];

// ── Color reading helpers ────────────────────────────────────────────────────

/**
 * Read a matugen token directly from window.__hyprcandyThemeVars (the raw dict
 * that bridge.ts populates on every theme_update from GJS). This avoids the
 * getComputedStyle timing race where Monaco's beforeMount fires before GJS has
 * injected the CSS vars. Falls back to getComputedStyle and then to `fallback`.
 *
 * rawKey: the key as it appears in the GJS-sent dict, e.g. 'matugen_primary',
 *         'matugen_on_secondary', 'wallust_color3'.
 */
function readThemeVar(rawKey: string, cssVarName: string, fallback: string): string {
  // 1. Try the raw dict set by bridge.ts on theme_update (most reliable)
  if (typeof window !== 'undefined') {
    const vars = (window as any).__hyprcandyThemeVars as Record<string, string> | undefined;
    if (vars) {
      const val = vars[rawKey];
      if (val && typeof val === 'string') return normalizeHex(val, fallback);
    }
  }
  // 2. Fall back to getComputedStyle (works after CSS vars are set)
  if (typeof document !== 'undefined') {
    const val = getComputedStyle(document.documentElement).getPropertyValue(cssVarName).trim();
    if (val) return normalizeHex(val, fallback);
  }
  return fallback;
}

function normalizeHex(val: string, fallback: string): string {
  val = val.trim();
  if (!val) return fallback;
  if (val.startsWith('#')) {
    if (val.length === 7 || val.length === 9) return val.slice(0, 7);
    if (val.length === 4) return '#' + val[1] + val[1] + val[2] + val[2] + val[3] + val[3];
  }
  const clean = val.replace('#', '');
  if (/^[0-9a-fA-F]{6}$/.test(clean)) return '#' + clean;
  if (/^[0-9a-fA-F]{8}$/.test(clean)) return '#' + clean.slice(0, 6);
  if (/^[0-9a-fA-F]{3}$/.test(clean)) return '#' + clean[0] + clean[0] + clean[1] + clean[1] + clean[2] + clean[2];
  const m = val.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
  if (m) return '#' + [m[1], m[2], m[3]].map(n => parseInt(n).toString(16).padStart(2, '0')).join('');
  return fallback;
}

function hexToRgb(hex: string): { r: number; g: number; b: number } {
  const h = hex.replace('#', '');
  const full = h.length === 3 ? h.split('').map(c => c + c).join('') : h.slice(0, 6);
  return {
    r: parseInt(full.substring(0, 2), 16) || 0,
    g: parseInt(full.substring(2, 4), 16) || 0,
    b: parseInt(full.substring(4, 6), 16) || 0,
  };
}

/** Returns an 8-character hex RGBA string (e.g. '#a0c9dc26') for Monaco colors */
function withAlpha(hex: string, alphaPct: number): string {
  const { r, g, b } = hexToRgb(hex.startsWith('#') ? hex : '#000000');
  const a = Math.round(Math.max(0, Math.min(1, alphaPct / 100)) * 255);
  return '#' +
    r.toString(16).padStart(2, '0') +
    g.toString(16).padStart(2, '0') +
    b.toString(16).padStart(2, '0') +
    a.toString(16).padStart(2, '0');
}

const strip = (c: string) => c.replace('#', '').slice(0, 6);

/** Blends fg over bg at the given opacity into a plain opaque 6-hex color —
 * for use in tokenizer `rules[].foreground`, which (unlike the `colors` map)
 * does not support an alpha channel. */
function blendWithBackground(fgHex: string, alphaPct: number, bgHex: string): string {
  const fg = hexToRgb(fgHex);
  const bg = hexToRgb(bgHex);
  const a = Math.max(0, Math.min(1, alphaPct / 100));
  const mix = (f: number, b: number) => Math.round(f * a + b * (1 - a));
  return [mix(fg.r, bg.r), mix(fg.g, bg.g), mix(fg.b, bg.b)]
    .map(n => n.toString(16).padStart(2, '0')).join('');
}

// ── Theme registration ────────────────────────────────────────────────────────

export function registerMatugenTheme(monaco: any): void {
  if (!monaco?.editor) return;

  // Read all colors directly from the injected matugen/wallust palette.
  // Keys match exactly what bridge.ts stores into window.__hyprcandyThemeVars
  // and also into document.documentElement.style CSS vars.
  const primary        = readThemeVar('matugen_primary',             '--matugen-primary',             '#a0c9dc');
  const onSecondary    = readThemeVar('matugen_on_secondary',        '--matugen-on-secondary',        '#1d343c');
  const onSurface      = readThemeVar('matugen_on_surface',          '--matugen-on-surface',          '#dfe3e6');
  const surface        = readThemeVar('matugen_surface',             '--matugen-surface',             '#0c1014');
  const surfaceVariant = readThemeVar('matugen_surface_variant',     '--matugen-surface-variant',     '#40484c');
  const primaryCont    = readThemeVar('matugen_primary_container',   '--matugen-primary-container',   '#1b4d5d');
  const onPrimaryCont  = readThemeVar('matugen_on_primary_container','--matugen-on-primary-container','#bde9fa');
  const secondary      = readThemeVar('matugen_secondary',           '--matugen-secondary',           '#b2cbd6');
  const outline        = readThemeVar('matugen_outline',             '--matugen-outline',             '#8a9296');

  // Semantic derived: text colors may have been overridden by bridge's accent logic
  const textPrimary   = readThemeVar('matugen_on_surface',          '--text-primary',    onSurface);
  const textSecondary = readThemeVar('matugen_secondary',           '--text-secondary',  secondary);

  // Editor background: on-secondary at ~20% opacity
  const editorBg   = withAlpha(onSecondary,    20);
  const subtleLine  = withAlpha(outline,        35);

  // Inactive line numbers and comments use a proper text-safe role
  // (textSecondary/primary) at reduced alpha, rather than a background-
  // adjacent tone like surfaceVariant — surfaceVariant is only guaranteed to
  // contrast against `surface`, not to be readable as foreground text, which
  // is exactly what made these low-contrast on matugen's lighter (system
  // light-mode) palettes.
  const lineNumberDim = withAlpha(primary, 75);
  const commentColor  = blendWithBackground(textSecondary, 70, surface);

  // Cursor and line-highlight use the primary accent directly
  const cursorColor       = '#' + strip(primary);
  const lineHighlight     = withAlpha(primary, 12); // 12% opacity
  const selectionBg       = withAlpha(primaryCont, 40); // ~40% opacity
  const selHighlight      = withAlpha(primary, 15);     // subtle word highlight
  const wordHighlight     = withAlpha(primaryCont, 20);
  const wordHighlightStrg = withAlpha(primary, 20);
  const scrollbarIdle     = withAlpha(primary, 10); // 10% opacity (0.1 alpha)
  const scrollbarHover    = withAlpha(primary, 15); // 15% opacity (0.15 alpha)

  monaco.editor.defineTheme('matugen', {
    base: 'vs-dark',
    inherit: true,
    rules: [
      { token: 'comment',     fontStyle: 'italic', foreground: strip(commentColor) },
      { token: 'keyword',     fontStyle: 'bold',   foreground: strip(primary) },
      { token: 'string',                           foreground: strip(onPrimaryCont) },
      { token: 'number',                           foreground: 'fab387' },
      { token: 'type',                             foreground: strip(secondary) },
      { token: 'function',                         foreground: strip(primary) },
      { token: 'variable',                         foreground: strip(textPrimary) },
      { token: 'operator',                         foreground: strip(textSecondary) },
      { token: 'punctuation',                      foreground: strip(textSecondary) },
      { token: 'delimiter.bracket',                foreground: strip(textSecondary) },
      // Shell-specific: Monaco's shell tokenizer emits these for flags
      // (-e, --needed, --noconfirm) and for redirect/operator characters
      // (>, &, ;, = in `2>&1`, `cmd1 && cmd2`, etc). Neither had a rule
      // before, so they fell through to vs-dark's generic defaults instead
      // of a matugen tone — visibly inconsistent next to everything else.
      { token: 'delimiter',                        foreground: strip(textSecondary) },
      { token: 'attribute.name',                   foreground: strip(secondary) },
      { token: 'metatag',    fontStyle: 'bold',     foreground: strip(primary) },
    ],
    colors: {
      // Editor core
      'editor.background':                    editorBg,
      'editor.foreground':                    textPrimary,
      'editorGutter.background':              editorBg,
      'editorLineNumber.foreground':          lineNumberDim,
      'editorLineNumber.activeForeground':    '#' + strip(primary),
      'editorLineNumber.dimmedForeground':    lineNumberDim,
      'editor.lineHighlightBackground':       lineHighlight,
      'editor.lineHighlightBorder':           '#00000000',
      'editorCursor.foreground':              cursorColor,
      'editorCursor.background':              '#' + strip(onSecondary),
      // Selections
      'editor.selectionBackground':           selectionBg,
      'editor.selectionHighlightBackground':  selHighlight,
      'editor.wordHighlightBackground':       wordHighlight,
      'editor.wordHighlightStrongBackground': wordHighlightStrg,
      'editor.findMatchBackground':           '#' + strip(primary) + '44',
      'editor.findMatchHighlightBackground':  '#' + strip(primary) + '22',
      // Bracket pairs / matching — matugen tones so brace nesting stays
      // legible regardless of the underlying wallpaper-derived palette
      'editorBracketMatch.background':        withAlpha(primary, 20),
      'editorBracketMatch.border':            '#' + strip(primary),
      'editorBracketHighlight.foreground1':   '#' + strip(primary),
      'editorBracketHighlight.foreground2':   '#' + strip(secondary),
      'editorBracketHighlight.foreground3':   '#' + strip(onPrimaryCont),
      'editorBracketHighlight.foreground4':   '#' + strip(primary),
      'editorBracketHighlight.foreground5':   '#' + strip(secondary),
      'editorBracketHighlight.foreground6':   '#' + strip(onPrimaryCont),
      'editorBracketHighlight.unexpectedBracket.foreground': '#' + strip(outline),
      // Indent / whitespace
      'editorWhitespace.foreground':          '#' + strip(surfaceVariant) + '44',
      'editorIndentGuide.background1':        subtleLine,
      'editorIndentGuide.activeBackground1':  '#' + strip(primary) + '55',
      // Widgets & popups — all use matugen on-secondary as bg
      'quickInput.background':                '#' + strip(onSecondary),
      'quickInput.foreground':                '#' + strip(primary),
      'quickInput.border':                    '#' + strip(primary),
      'quickInputList.focusBackground':       scrollbarIdle,
      'quickInputList.focusForeground':       '#' + strip(primary),
      'editorSuggestWidget.background':       '#' + strip(onSecondary),
      'editorSuggestWidget.border':           '#' + strip(surfaceVariant),
      'editorSuggestWidget.foreground':       textPrimary,
      'editorSuggestWidget.selectedForeground': '#' + strip(primary),
      'editorSuggestWidget.selectedBackground': scrollbarIdle,
      'editorHoverWidget.background':         '#' + strip(onSecondary),
      'editorHoverWidget.border':             '#' + strip(surfaceVariant),
      'editorHoverWidget.foreground':         textPrimary,
      // Input boxes inside widgets
      'input.background':                     '#' + strip(onSecondary),
      'input.foreground':                     '#' + strip(primary),
      'input.border':                         '#' + strip(surfaceVariant),
      'input.placeholderForeground':          '#' + strip(outline),
      'focusBorder':                          '#' + strip(primary),
      // Scrollbars (Monaco's own scrollbars — matugen primary at 10% idle, 15% hover)
      'scrollbarSlider.background':           scrollbarIdle,
      'scrollbarSlider.hoverBackground':      scrollbarHover,
      'scrollbarSlider.activeBackground':     scrollbarHover,
      // Minimap
      'minimap.background':                   editorBg,
      'minimapSlider.background':             scrollbarIdle,
      'minimapSlider.hoverBackground':        scrollbarHover,
      'minimapSlider.activeBackground':       scrollbarHover,
      // Right-click context menu & Action list
      'menu.background':                      '#' + strip(onSecondary),
      'menu.foreground':                      '#' + strip(primary),
      'menu.selectionBackground':             scrollbarIdle,
      'menu.selectionForeground':             '#' + strip(primary),
      'menu.selectionBorder':                 '#00000000',
      'menu.separatorBackground':             '#' + strip(primary),
      'menu.border':                          '#' + strip(surfaceVariant),
      'editorActionList.background':          '#' + strip(onSecondary),
      'editorActionList.foreground':          '#' + strip(primary),
      'editorActionList.focusForeground':     '#' + strip(primary),
      'editorActionList.focusBackground':     scrollbarIdle,
      // Rulers & overview
      'editorRuler.foreground':               '#' + strip(surfaceVariant),
      'editorWidget.background':              '#' + strip(onSecondary),
      'editorWidget.border':                  '#' + strip(surfaceVariant),
      'editorOverviewRuler.border':           '#' + strip(surfaceVariant),
      'editorOverviewRuler.findMatchForeground': '#' + strip(primary),
      // Peek view
      'peekView.border':                      '#' + strip(primary),
      'peekViewEditor.background':            '#' + strip(onSecondary),
      'peekViewResult.background':            '#' + strip(onSecondary),
      'peekViewEditor.matchHighlightBackground': '#' + strip(primary) + '26',
      // Title bar (used in diff editor headers etc.)
      'editorGroupHeader.tabsBackground':     '#' + strip(surface),
      'tab.activeBackground':                 '#' + strip(primaryCont),
      'tab.activeForeground':                 '#' + strip(primary),
      'tab.inactiveBackground':               '#' + strip(surface),
      'tab.inactiveForeground':               '#' + strip(outline),
      'tab.border':                           '#' + strip(surfaceVariant),
    },
  });

  // Always activate immediately after redefining.
  try { monaco.editor.setTheme('matugen'); } catch (_) {}
}

export function applyMatugenThemeNow(monaco: any): void {
  if (!monaco?.editor) return;
  registerMatugenTheme(monaco);
}

export function registerMonacoThemes(monaco: any) {
  if (!monaco?.editor) return;
  registerMatugenTheme(monaco);
}
