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

// ── Foreground legibility guard ──────────────────────────────────────────────
// Some palette roles (matugen on_primary_container, wallust mid-tones) can
// land near-black on a given wallpaper — fine on a filled container, wrong for
// text on our dark editor. ensureReadable lifts any too-dark foreground above
// a minimum relative-luminance while keeping its hue.
function relLuminance(hex: string): number {
  const { r, g, b } = hexToRgb(hex);
  const chan = (c: number) => {
    c /= 255;
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  };
  return 0.2126 * chan(r) + 0.7152 * chan(g) + 0.0722 * chan(b);
}

// Minimum luminance an editor foreground must clear to stay readable over a
// dark (~near-black) surface.
const FG_MIN_LUMINANCE = 0.22;

/** Lift a foreground hex to a legible tone for the dark editor. Returns the
 *  input unchanged when it already clears FG_MIN_LUMINANCE; otherwise blends
 *  it toward `lightBase` (a guaranteed-light text token) until it does. */
function ensureReadable(hex: string, lightBase: string): string {
  const c = normalizeHex(hex, lightBase);
  if (relLuminance(c) >= FG_MIN_LUMINANCE) return c;
  const light = normalizeHex(lightBase, '#e6e6e6');
  for (let t = 15; t <= 100; t += 15) {
    const mixed = '#' + blendWithBackground(c, 100 - t, light);
    if (relLuminance(mixed) >= FG_MIN_LUMINANCE) return mixed;
  }
  return light;
}

// ── Theme registration ────────────────────────────────────────────────────────

export function registerMatugenTheme(monaco: any): void {
  if (!monaco?.editor) return;

  // Matugen palette (roles kept for text/keywords/containers).
  const primary        = readThemeVar('matugen_primary',             '--matugen-primary',             '#a0c9dc');
  // surface-tint is used for keyword/function text in the code body instead of
  // primary; primary still drives the surrounding chrome (cursor, gutter, etc).
  const surfaceTint    = readThemeVar('matugen_surface_tint',        '--matugen-surface-tint',        primary);
  const onSecondary    = readThemeVar('matugen_on_secondary',        '--matugen-on-secondary',        '#1d343c');
  const onSurface      = readThemeVar('matugen_on_surface',          '--matugen-on-surface',          '#dfe3e6');
  const surface        = readThemeVar('matugen_surface',             '--matugen-surface',             '#0c1014');
  const surfaceVariant = readThemeVar('matugen_surface_variant',     '--matugen-surface-variant',     '#40484c');
  const primaryCont    = readThemeVar('matugen_primary_container',   '--matugen-primary-container',   '#1b4d5d');
  const secondary      = readThemeVar('matugen_secondary',           '--matugen-secondary',           '#b2cbd6');
  const outline        = readThemeVar('matugen_outline',             '--matugen-outline',             '#8a9296');
  const textPrimary   = readThemeVar('matugen_on_surface',           '--text-primary',    onSurface);
  const textSecondary = readThemeVar('matugen_secondary',            '--text-secondary',  secondary);

  // Wallust palette (color1..color6) drives the structural/special tokens:
  // digits, strings, braces, commas, operators, and indentation guides.
  const wc1 = readThemeVar('wallust_color1', '--wallust-color1', '#C16F4C');
  const wc2 = readThemeVar('wallust_color2', '--wallust-color2', '#B3A40A');
  const wc3 = readThemeVar('wallust_color3', '--wallust-color3', '#3589D0');
  const wc4 = readThemeVar('wallust_color4', '--wallust-color4', '#A85B27');
  const wc5 = readThemeVar('wallust_color5', '--wallust-color5', '#69852D');
  const wc6 = readThemeVar('wallust_color6', '--wallust-color6', '#386689');

  const lightBase = relLuminance(onSurface) >= FG_MIN_LUMINANCE ? onSurface : '#e8e8e8';

  const editorBg      = withAlpha(onSecondary, 20);
  const lineNumberDim = withAlpha(primary, 75);
  // Comments keep the on-surface-derived tone (blend of textSecondary/surface).
  const commentColor  = blendWithBackground(textSecondary, 70, surface);

  const cursorColor       = '#' + strip(primary);
  const lineHighlight     = withAlpha(primary, 12);
  const selectionBg       = withAlpha(primaryCont, 40);
  const selHighlight      = withAlpha(primary, 15);
  const wordHighlight     = withAlpha(primaryCont, 20);
  const wordHighlightStrg = withAlpha(primary, 20);
  const scrollbarIdle     = withAlpha(primary, 10);
  const scrollbarHover    = withAlpha(primary, 15);

  // Sticky-scroll headers overlay live scrolling text, so the fill is opaque:
  // primary blended over the on-secondary surface rather than a literal alpha.
  const stickyScrollBg    = '#' + blendWithBackground(primary, 10, onSecondary);
  const stickyScrollHover = '#' + blendWithBackground(primary, 16, onSecondary);

  // Readable foreground for a tokenizer rule (guard + strip leading '#').
  const rfg = (c: string) => strip(ensureReadable(c, lightBase));

  monaco.editor.defineTheme('matugen', {
    base: 'vs-dark',
    inherit: true,
    rules: [
      // Text/keyword roles stay on matugen; structural/special tokens use
      // wallust color1..color6. All go through ensureReadable (rfg).
      { token: '',            foreground: rfg(textPrimary) },
      { token: 'identifier',  foreground: rfg(textPrimary) },
      { token: 'key',         foreground: rfg(secondary) },
      { token: 'comment',     fontStyle: 'italic', foreground: rfg(commentColor) },
      { token: 'keyword',     fontStyle: 'bold',   foreground: rfg(surfaceTint) },
      { token: 'string',      foreground: rfg(wc2) },
      { token: 'number',      foreground: rfg(wc1) },
      { token: 'type',        foreground: rfg(secondary) },
      { token: 'function',    foreground: rfg(surfaceTint) },
      { token: 'variable',    foreground: rfg(textPrimary) },
      { token: 'operator',    foreground: rfg(wc5) },
      { token: 'punctuation', foreground: rfg(wc4) },
      { token: 'delimiter.bracket', foreground: rfg(wc3) },
      { token: 'delimiter.array',   foreground: rfg(wc3) },
      { token: 'delimiter.parenthesis', foreground: rfg(wc3) },
      { token: 'delimiter',   foreground: rfg(wc4) },
      { token: 'attribute.name', foreground: rfg(secondary) },
      { token: 'metatag',     fontStyle: 'bold', foreground: rfg(surfaceTint) },
    ],
    colors: {
      // Editor core
      'editor.background':                    editorBg,
      'editor.foreground':                    ensureReadable(textPrimary, lightBase),
      'editorGutter.background':              editorBg,
      'editorLineNumber.foreground':          lineNumberDim,
      'editorLineNumber.activeForeground':    '#' + strip(primary),
      'editorLineNumber.dimmedForeground':    lineNumberDim,
      'editor.lineHighlightBackground':       lineHighlight,
      'editor.lineHighlightBorder':           '#00000000',
      // Sticky scroll headers — themed to match the focused-line primary tint
      // instead of Monaco's default grey (kept opaque, see derivation above).
      // NOTE: hover and gutter are *separate* color ids in Monaco, not nested
      // under editorStickyScroll — using the wrong name is silently ignored.
      'editorStickyScroll.background':         stickyScrollBg,
      'editorStickyScrollHover.background':    stickyScrollHover,
      'editorStickyScrollGutter.background':   stickyScrollBg,
      'editorStickyScroll.border':             withAlpha(primary, 20),
      'editorStickyScroll.shadow':             '#00000000',
      'editorCursor.foreground':              cursorColor,
      'editorCursor.background':              '#' + strip(onSecondary),
      // Selections
      'editor.selectionBackground':           selectionBg,
      'editor.selectionHighlightBackground':  selHighlight,
      'editor.wordHighlightBackground':       wordHighlight,
      'editor.wordHighlightStrongBackground': wordHighlightStrg,
      // Find/replace widget (Ctrl+F / Ctrl+H): every find-related key set to a
      // primary tint so none fall through to Monaco's default blue highlight.
      'editor.findMatchBackground':           '#' + strip(primary) + '33', // current match, ~0.2
      'editor.findMatchBorder':               '#00000000',
      'editor.findMatchHighlightBackground':  '#' + strip(primary) + '33', // all matches, ~0.2
      'editor.findMatchHighlightBorder':      '#00000000',
      'editor.findRangeHighlightBackground':  '#' + strip(primary) + '1a',
      // Bracket pairs / matching — wallust tones so brace nesting stays
      // legible and distinct regardless of the wallpaper-derived palette.
      'editorBracketMatch.background':        withAlpha(primary, 20),
      'editorBracketMatch.border':            '#' + strip(primary),
      'editorBracketHighlight.foreground1':   '#' + rfg(wc3),
      'editorBracketHighlight.foreground2':   '#' + rfg(wc4),
      'editorBracketHighlight.foreground3':   '#' + rfg(wc1),
      'editorBracketHighlight.foreground4':   '#' + rfg(wc5),
      'editorBracketHighlight.foreground5':   '#' + rfg(wc2),
      'editorBracketHighlight.foreground6':   '#' + rfg(wc6),
      'editorBracketHighlight.unexpectedBracket.foreground': '#' + strip(outline),
      // Indent guides use wallust color6; whitespace stays a dim surface tone.
      'editorWhitespace.foreground':          '#' + strip(surfaceVariant) + '44',
      'editorIndentGuide.background1':        withAlpha(ensureReadable(wc6, lightBase), 38),
      'editorIndentGuide.activeBackground1':  withAlpha(ensureReadable(wc6, lightBase), 75),
      // Widgets & popups — all use matugen on-secondary as bg
      'quickInput.background':                '#' + strip(onSecondary),
      'quickInput.foreground':                '#' + strip(primary),
      'quickInput.border':                    '#' + strip(primary),
      'quickInputList.focusBackground':       scrollbarIdle,
      'quickInputList.focusForeground':       '#' + strip(primary),
      'editorSuggestWidget.background':       '#' + strip(onSecondary),
      'editorSuggestWidget.border':           '#' + strip(surfaceVariant),
      'editorSuggestWidget.foreground':       ensureReadable(textPrimary, lightBase),
      'editorSuggestWidget.selectedForeground': '#' + strip(primary),
      'editorSuggestWidget.selectedBackground': scrollbarIdle,
      'editorHoverWidget.background':         '#' + strip(onSecondary),
      'editorHoverWidget.border':             '#' + strip(surfaceVariant),
      'editorHoverWidget.foreground':         ensureReadable(textPrimary, lightBase),
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
