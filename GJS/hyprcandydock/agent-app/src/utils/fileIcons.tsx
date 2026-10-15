import React from 'react';
import {
  Folder,
  File as FileGeneric,
  Code,
  Braces,
  Database,
  SquareTerminal,
  Palette,
  Globe,
  Settings2,
  Cog,
  Lock,
  ScrollText,
  Table,
  Image as ImageIcon,
  Clapperboard,
  AudioLines,
  Archive,
  Binary,
  FileType2,
  KeyRound,
  GitBranch,
  Container,
} from 'lucide-react';
import type { LucideIcon } from 'lucide-react';

// VSCode-style per-format file glyphs, shared by the explorer, canvas tabs and
// chat chips. Unlike the earlier "File*" lucide icons (which draw a document
// page silhouette around a tiny mark), these are the *direct* format symbols —
// a bare <> for source, { } for JSON, a terminal box for shell, a git branch
// for .gitignore, etc. — matching how VSCode/Qoder render file types. Colors
// still ride the live Material-You / wallust palette (see the file-type
// theming convention) so they re-tint with the wallpaper instead of using
// fixed brand colors.

// Themed color slots (fallbacks only apply before the first theme_update).
const C = {
  code: 'var(--matugen-primary, #a0c9dc)',
  text: 'var(--matugen-secondary, #b6c489)',
  image: 'var(--wallust-color2, #b3a40a)',
  video: 'var(--wallust-color3, #3589d0)',
  config: 'var(--wallust-color4, #a85b27)',
  folder: 'var(--wallust-color1, #c16f4c)',
  outline: 'var(--matugen-outline, #838673)',
} as const;

type Glyph = LucideIcon;
type Mapped = { Icon: Glyph; color: string };

// extension → direct glyph + color slot.
const BY_EXT: Record<string, Mapped> = {
  // Source code → bare angle brackets (SQL gets a database mark).
  ts: { Icon: Code, color: C.code }, tsx: { Icon: Code, color: C.code },
  js: { Icon: Code, color: C.code }, jsx: { Icon: Code, color: C.code },
  mjs: { Icon: Code, color: C.code }, cjs: { Icon: Code, color: C.code },
  py: { Icon: Code, color: C.code }, rb: { Icon: Code, color: C.code },
  go: { Icon: Code, color: C.code }, rs: { Icon: Code, color: C.code },
  c: { Icon: Code, color: C.code }, h: { Icon: Code, color: C.code },
  cpp: { Icon: Code, color: C.code }, cc: { Icon: Code, color: C.code },
  hpp: { Icon: Code, color: C.code }, java: { Icon: Code, color: C.code },
  kt: { Icon: Code, color: C.code }, swift: { Icon: Code, color: C.code },
  php: { Icon: Code, color: C.code }, cs: { Icon: Code, color: C.code },
  lua: { Icon: Code, color: C.code }, pl: { Icon: Code, color: C.code },
  scala: { Icon: Code, color: C.code }, dart: { Icon: Code, color: C.code },
  vue: { Icon: Code, color: C.code }, svelte: { Icon: Code, color: C.code },
  ex: { Icon: Code, color: C.code }, exs: { Icon: Code, color: C.code },
  clj: { Icon: Code, color: C.code }, zig: { Icon: Code, color: C.code },
  r: { Icon: Code, color: C.code },
  sql: { Icon: Database, color: C.code },
  // Shell / scripts → terminal box (the "$" prompt mark).
  sh: { Icon: SquareTerminal, color: C.code }, bash: { Icon: SquareTerminal, color: C.code },
  zsh: { Icon: SquareTerminal, color: C.code }, fish: { Icon: SquareTerminal, color: C.code },
  ps1: { Icon: SquareTerminal, color: C.code }, bat: { Icon: SquareTerminal, color: C.code },
  cmd: { Icon: SquareTerminal, color: C.code },
  // Styles / markup.
  css: { Icon: Palette, color: C.code }, scss: { Icon: Palette, color: C.code },
  sass: { Icon: Palette, color: C.code }, less: { Icon: Palette, color: C.code },
  html: { Icon: Globe, color: C.code }, htm: { Icon: Globe, color: C.code },
  // Data / config → braces for JSON, gear for the rest, lock for lockfiles.
  json: { Icon: Braces, color: C.config }, jsonc: { Icon: Braces, color: C.config },
  json5: { Icon: Braces, color: C.config },
  yaml: { Icon: Settings2, color: C.config }, yml: { Icon: Settings2, color: C.config },
  toml: { Icon: Settings2, color: C.config }, ini: { Icon: Settings2, color: C.config },
  cfg: { Icon: Settings2, color: C.config }, conf: { Icon: Settings2, color: C.config },
  properties: { Icon: Settings2, color: C.config },
  xml: { Icon: Code, color: C.config },
  lock: { Icon: Lock, color: C.config },
  // Docs / text → scroll mark (no page wrapper); tabular data → table.
  md: { Icon: ScrollText, color: C.text }, markdown: { Icon: ScrollText, color: C.text },
  mdx: { Icon: ScrollText, color: C.text }, txt: { Icon: ScrollText, color: C.text },
  log: { Icon: ScrollText, color: C.text }, rst: { Icon: ScrollText, color: C.text },
  pdf: { Icon: ScrollText, color: C.text },
  csv: { Icon: Table, color: C.text }, tsv: { Icon: Table, color: C.text },
  xlsx: { Icon: Table, color: C.text }, xls: { Icon: Table, color: C.text },
  // Media → bare image frame / clapper / audio waveform.
  png: { Icon: ImageIcon, color: C.image }, jpg: { Icon: ImageIcon, color: C.image },
  jpeg: { Icon: ImageIcon, color: C.image }, gif: { Icon: ImageIcon, color: C.image },
  webp: { Icon: ImageIcon, color: C.image }, bmp: { Icon: ImageIcon, color: C.image },
  ico: { Icon: ImageIcon, color: C.image }, tiff: { Icon: ImageIcon, color: C.image },
  svg: { Icon: ImageIcon, color: C.image },
  mp4: { Icon: Clapperboard, color: C.video }, webm: { Icon: Clapperboard, color: C.video },
  mov: { Icon: Clapperboard, color: C.video }, mkv: { Icon: Clapperboard, color: C.video },
  avi: { Icon: Clapperboard, color: C.video },
  mp3: { Icon: AudioLines, color: C.config }, wav: { Icon: AudioLines, color: C.config },
  ogg: { Icon: AudioLines, color: C.config }, flac: { Icon: AudioLines, color: C.config },
  aac: { Icon: AudioLines, color: C.config }, m4a: { Icon: AudioLines, color: C.config },
  // Archives / binary / fonts / keys.
  zip: { Icon: Archive, color: C.outline }, tar: { Icon: Archive, color: C.outline },
  gz: { Icon: Archive, color: C.outline }, rar: { Icon: Archive, color: C.outline },
  '7z': { Icon: Archive, color: C.outline }, bz2: { Icon: Archive, color: C.outline },
  xz: { Icon: Archive, color: C.outline },
  exe: { Icon: Binary, color: C.outline }, dll: { Icon: Binary, color: C.outline },
  so: { Icon: Binary, color: C.outline }, dylib: { Icon: Binary, color: C.outline },
  bin: { Icon: Binary, color: C.outline },
  ttf: { Icon: FileType2, color: C.outline }, otf: { Icon: FileType2, color: C.outline },
  woff: { Icon: FileType2, color: C.outline }, woff2: { Icon: FileType2, color: C.outline },
  pem: { Icon: KeyRound, color: C.config }, crt: { Icon: KeyRound, color: C.config },
  key: { Icon: KeyRound, color: C.config },
};

// Whole-filename overrides (dotfiles and extensionless build files).
const BY_NAME: Record<string, Mapped> = {
  dockerfile: { Icon: Container, color: C.code },
  makefile: { Icon: Cog, color: C.code },
  '.gitignore': { Icon: GitBranch, color: C.config },
  '.gitattributes': { Icon: GitBranch, color: C.config },
  '.gitmodules': { Icon: GitBranch, color: C.config },
  '.gitconfig': { Icon: GitBranch, color: C.config },
  '.env': { Icon: KeyRound, color: C.config },
  '.editorconfig': { Icon: Settings2, color: C.config },
  'package-lock.json': { Icon: Lock, color: C.config },
  'yarn.lock': { Icon: Lock, color: C.config },
  'pnpm-lock.yaml': { Icon: Lock, color: C.config },
  'cargo.lock': { Icon: Lock, color: C.config },
  'tsconfig.json': { Icon: Braces, color: C.config },
  'jsconfig.json': { Icon: Braces, color: C.config },
};

function resolve(name: string, isDir: boolean): Mapped {
  if (isDir) return { Icon: Folder, color: C.folder };
  const exact = BY_NAME[name] || BY_NAME[name.toLowerCase()];
  if (exact) return exact;
  const dot = name.lastIndexOf('.');
  if (dot > 0) {
    const ext = name.slice(dot + 1).toLowerCase();
    const hit = BY_EXT[ext];
    if (hit) return hit;
  }
  // Leading-dot files with no other match (.babelrc, .zshrc, …) read as config.
  if (name.startsWith('.')) return { Icon: Settings2, color: C.config };
  // Genuinely unknown type: a plain page is the honest fallback.
  return { Icon: FileGeneric, color: C.outline };
}

export function FileIcon({ name, isDir = false, size = 13 }: { name: string; isDir?: boolean; size?: number }) {
  const { Icon, color } = resolve(name || '', isDir);
  return <Icon size={size} color={color} />;
}
