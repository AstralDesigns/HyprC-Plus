import React from 'react';

/**
 * Standard diff coloring for ```diff / ```patch fences, shared by the chat
 * renderer and the canvas markdown preview. Semantic colors stay conventional
 * (GitHub-dark green/red/purple) rather than matugen/wallust: a diff's +/-
 * meaning must read identically under every wallpaper palette.
 */
export const isDiffLang = (lang?: string): boolean => lang === 'diff' || lang === 'patch';

export const diffLines = (code: string): React.ReactNode[] =>
  code.replace(/\n$/, '').split('\n').map((ln, i) => {
    let cls = 'md-diff-ctx';
    if (/^\+/.test(ln) && !/^\+\+\+/.test(ln)) cls = 'md-diff-add';
    else if (/^-/.test(ln) && !/^---/.test(ln)) cls = 'md-diff-del';
    else if (/^@@/.test(ln) || /^diff /.test(ln) || /^index /.test(ln)) cls = 'md-diff-hunk';
    return <span key={i} className={cls}>{ln || ' '}</span>;
  });