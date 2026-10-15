// Global, styled tooltip manager.
//
// Replaces the browser / Qt-WebEngine native `title` tooltip with one
// lightweight DOM node so every title-bearing element app-wide — header
// buttons, tabs, side panels, popups, AND Monaco's own find/replace action
// buttons (whose `title`s live in DOM we don't own) — renders the same
// matugen-styled hint.
//
// We move the text out of `title` (which suppresses the native tooltip) only
// while the tip is visible and restore it on leave, so author intent is never
// permanently mutated. Positioning prefers just below the element and flips
// above when there isn't room — which is what keeps the find widget's "Find"
// tooltip from rendering up behind the tab row.

let tipEl: HTMLDivElement | null = null;
let current: Element | null = null;
let showTimer: number | null = null;

const PADDING = 8;   // viewport keep-out margin
const GAP = 6;       // distance between element and tip
const DELAY = 120;   // hover dwell before showing (avoids flicker on sweep)

function ensureEl(): HTMLDivElement {
  if (!tipEl) {
    tipEl = document.createElement('div');
    tipEl.className = 'hc-tooltip';
    tipEl.setAttribute('role', 'tooltip');
    document.body.appendChild(tipEl);
  }
  return tipEl;
}

function clearPending() {
  if (showTimer !== null) { clearTimeout(showTimer); showTimer = null; }
}

// Arm the styled tip for `el` after the hover dwell. Assumes any native title
// has already been stashed/removed (or the element never had one, e.g. Monaco's
// aria-label buttons).
function scheduleShow(el: Element, text: string) {
  if (!text) return;
  current = el;
  clearPending();
  showTimer = window.setTimeout(() => {
    const tip = ensureEl();
    tip.textContent = text;
    place(el, tip);
    tip.classList.add('show');
  }, DELAY);
}

// Put the native `title` back and hide the tip.
function reset() {
  clearPending();
  if (current) {
    const orig = current.getAttribute('data-hc-tip');
    if (orig !== null) {
      current.setAttribute('title', orig);
      current.removeAttribute('data-hc-tip');
    }
    current = null;
  }
  if (tipEl) tipEl.classList.remove('show');
}

function place(el: Element, tip: HTMLDivElement) {
  const r = el.getBoundingClientRect();
  const t = tip.getBoundingClientRect();
  const vw = window.innerWidth;
  const vh = window.innerHeight;
  let left = r.left + r.width / 2 - t.width / 2;
  left = Math.max(PADDING, Math.min(left, vw - t.width - PADDING));
  let top = r.bottom + GAP;                       // prefer below
  if (top + t.height > vh - PADDING) top = r.top - t.height - GAP; // flip above
  top = Math.max(PADDING, top);
  tip.style.left = `${Math.round(left)}px`;
  tip.style.top = `${Math.round(top)}px`;
}

// Monaco's find/replace action buttons (previous / next / close / replace /
// replace-all), its option toggles (match-case / whole-word / regex /
// preserve-case), and its two text fields (the find `<input>` and replace
// `<textarea>`, both class `.input`) carry no native `title` — they expose
// `aria-label` and wire up Monaco's own hover service
// (hoverService.setupDelayedHover / setupDelayedHoverAtMouse bind MOUSE_OVER on
// the element), which renders ABOVE / at-cursor and gets clipped by the tab row.
// We take all of them over: suppress Monaco's hover (stop its MOUSE_OVER from
// reaching the element) and show our below-first tip from the aria-label instead.
const MONACO_FIND_HOVERABLE =
  '.monaco-editor .find-widget .button[aria-label], .monaco-editor .find-widget .monaco-custom-toggle[aria-label], .monaco-editor .find-widget .input[aria-label]';

function onOver(e: MouseEvent) {
  const target = e.target as Element | null;
  if (!target || typeof target.closest !== 'function') return;

  const mbtn = target.closest(MONACO_FIND_HOVERABLE);
  if (mbtn && !mbtn.hasAttribute('title')) {
    // Always swallow the event so Monaco's above-rendering hover never fires,
    // even while we're already showing our tip for this same button.
    e.stopPropagation();
    if (mbtn === current) return;
    reset();
    scheduleShow(mbtn, (mbtn.getAttribute('aria-label') || '').trim());
    return;
  }

  const el = target.closest('[title]');
  if (!el || el === current) return;
  reset();
  const text = (el.getAttribute('title') || '').trim();
  if (!text) return;
  // Stash then drop the native title so only the styled tip shows.
  el.setAttribute('data-hc-tip', el.getAttribute('title') || '');
  el.removeAttribute('title');
  scheduleShow(el, text);
}

function onOut(e: MouseEvent) {
  if (!current) return;
  const to = e.relatedTarget as Element | null;
  if (to && current.contains(to)) return; // still inside the same tip target
  reset();
}

export function initGlobalTooltips() {
  if (typeof document === 'undefined') return;
  // Capture phase so we run before any component handlers / React root.
  document.addEventListener('mouseover', onOver, true);
  document.addEventListener('mouseout', onOut, true);
  // Repositioning is stale on scroll/resize; just dismiss.
  window.addEventListener('scroll', reset, true);
  window.addEventListener('resize', reset);
  window.addEventListener('blur', reset);
}
