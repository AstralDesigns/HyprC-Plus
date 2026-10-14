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
// Some Material-You roles are "text on a *container*" tokens (on_primary_
// container, on_secondary_container, …). On the mid-tone containers those
// tokens sit on, matugen is free to pick a near-BLACK foreground — which is
// perfect for a filled button chip but catastrophic for editor text, since
// our editor is always a dark surface (base 'vs-dark' + on-secondary fill).
// That is exactly what made Lua string literals render black: matugen set
// on_primary_container to #000000 for this wallpaper, and the very same
// value drove the `string` rule. It also explains the "theme colour flashes
// then gets overridden" symptom — before theme_update the rule used the
// light fallback, after it read the real #000000.
//
// ensureReadable keeps the hue but lifts any too-dark foreground back above a
// minimum relative-luminance so token text stays legible on the dark editor
// regardless of which palette the wallpaper produced.
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
  const tertiary       = readThemeVar('matugen_tertiary',            '--matugen-tertiary',            '#d0bcff');
  const outline        = readThemeVar('matugen_outline',             '--matugen-outline',             '#8a9296');

  // Semantic derived: text colors may have been overridden by bridge's accent logic
  const textPrimary   = readThemeVar('matugen_on_surface',          '--text-primary',    onSurface);
  const textSecondary = readThemeVar('matugen_secondary',           '--text-secondary',  secondary);

  // Guaranteed-light tone used by ensureReadable() to lift too-dark
  // foregrounds. Prefer on-surface (already light on this dark editor) but
  // fall back to neutral light if a wallpaper somehow made it dark.
  const lightBase = relLuminance(onSurface) >= FG_MIN_LUMINANCE ? onSurface : '#e8e8e8';

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

  // Sticky-scroll (pinned section headers) overlay live scrolling text, so the
  // fill must be opaque — a literal alpha would show doubled text through it.
  // Blend primary over the on-secondary surface to land the same primary tint
  // the focused line uses, but solid.
  const stickyScrollBg    = '#' + blendWithBackground(primary, 10, onSecondary);
  const stickyScrollHover = '#' + blendWithBackground(primary, 16, onSecondary);

  monaco.editor.defineTheme('matugen', {
    base: 'vs-dark',
    inherit: true,
    rules: [
      // Every palette-derived foreground is pushed through ensureReadable():
      // a role like on_primary_container / primary can legitimately land near
      // black on some wallpapers (matugen optimises them for filled
      // containers, not for text on our dark editor), which is what made Lua
      // strings render black after theme_update. The guard lifts any too-dark
      // tone back to a legible level while preserving its hue.
      // Catch-all default: any token scope not matched below (e.g. Lua's
      // `identifier`/`key`, which most languages never emit) falls back to the
      // readable on-surface text colour instead of the theme's black default.
      { token: '',          foreground: strip(ensureReadable(textPrimary, lightBase)) },
      { token: 'identifier',                        foreground: strip(ensureReadable(textPrimary, lightBase)) },
      { token: 'key',        foreground: strip(ensureReadable(secondary, lightBase)) },
      { token: 'comment',     fontStyle: 'italic', foreground: strip(ensureReadable(commentColor, lightBase)) },
      { token: 'keyword',     fontStyle: 'bold',   foreground: strip(ensureReadable(primary, lightBase)) },
      { token: 'string',                           foreground: strip(ensureReadable(tertiary, lightBase)) },
      { token: 'number',                           foreground: 'fab387' },
      { token: 'type',                             foreground: strip(ensureReadable(secondary, lightBase)) },
      { token: 'function',                         foreground: strip(ensureReadable(primary, lightBase)) },
      { token: 'variable',                         foreground: strip(ensureReadable(textPrimary, lightBase)) },
      { token: 'operator',                         foreground: strip(ensureReadable(textSecondary, lightBase)) },
      { token: 'punctuation',                      foreground: strip(ensureReadable(textSecondary, lightBase)) },
      { token: 'delimiter.bracket',                foreground: strip(ensureReadable(textSecondary, lightBase)) },
      // Shell-specific: Monaco's shell tokenizer emits these for flags
      // (-e, --needed, --noconfirm) and for redirect/operator characters
      // (>, &, ;, = in `2>&1`, `cmd1 && cmd2`, etc). Neither had a rule
      // before, so they fell through to vs-dark's generic defaults instead
      // of a matugen tone — visibly inconsistent next to everything else.
      { token: 'delimiter',                        foreground: strip(ensureReadable(textSecondary, lightBase)) },
      { token: 'attribute.name',                   foreground: strip(ensureReadable(secondary, lightBase)) },
      { token: 'metatag',    fontStyle: 'bold',     foreground: strip(ensureReadable(primary, lightBase)) },
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
      'editor.findMatchBackground':           '#' + strip(primary) + '44',
      'editor.findMatchHighlightBackground':  '#' + strip(primary) + '22',
      // Bracket pairs / matching — matugen tones so brace nesting stays
      // legible regardless of the underlying wallpaper-derived palette
      'editorBracketMatch.background':        withAlpha(primary, 20),
      'editorBracketMatch.border':            '#' + strip(primary),
      'editorBracketHighlight.foreground1':   '#' + strip(ensureReadable(primary, lightBase)),
      'editorBracketHighlight.foreground2':   '#' + strip(ensureReadable(secondary, lightBase)),
      'editorBracketHighlight.foreground3':   '#' + strip(ensureReadable(tertiary, lightBase)),
      'editorBracketHighlight.foreground4':   '#' + strip(ensureReadable(primary, lightBase)),
      'editorBracketHighlight.foreground5':   '#' + strip(ensureReadable(secondary, lightBase)),
      'editorBracketHighlight.foreground6':   '#' + strip(ensureReadable(tertiary, lightBase)),
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
