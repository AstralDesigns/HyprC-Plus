import { bridge } from '../bridge';

export type GitFileStatus =
  | 'untracked'
  | 'modified'
  | 'added'
  | 'deleted'
  | 'renamed'
  | 'conflict';

export interface GitStatusResult {
  map: Record<string, GitFileStatus>;
  isRepo: boolean;
}

// Run `git status --porcelain` in the project root and key the result by
// absolute path. Untracked directories stay collapsed (-unormal) so a repo
// without a node_modules ignore entry can't explode the output.
export async function fetchGitStatus(root: string): Promise<GitStatusResult> {
  const map: Record<string, GitFileStatus> = {};
  if (!root) return { map, isRepo: false };
  let res: { exitCode: number; stdout: string } | undefined;
  try {
    res = await bridge.execCommand('git status --porcelain=v1 -unormal', root);
  } catch {
    return { map, isRepo: false };
  }
  if (!res || res.exitCode !== 0) return { map, isRepo: false };
  const base = root.replace(/\/+$/, '');
  for (const line of (res.stdout || '').split('\n')) {
    if (line.length < 4) continue;
    const xy = line.slice(0, 2);
    let p = line.slice(3);
    if (p.includes(' -> ')) p = p.slice(p.lastIndexOf(' -> ') + 4);
    if (p.startsWith('"') && p.endsWith('"')) p = p.slice(1, -1);
    const status = classify(xy);
    if (status) map[`${base}/${p}`] = status;
  }
  return { map, isRepo: true };
}

function classify(xy: string): GitFileStatus | null {
  const x = xy[0];
  const y = xy[1];
  if (x === '?') return 'untracked';
  if (x === '!' || x === '#') return null;
  if (x === 'U' || y === 'U' || (x === 'A' && y === 'A') || (x === 'D' && y === 'D')) return 'conflict';
  if (x === 'A' || x === 'C') return 'added';
  if (x === 'R' || y === 'R') return 'renamed';
  if (x === 'D' || y === 'D') return 'deleted';
  if (x === 'M' || y === 'M' || x === 'T' || y === 'T') return 'modified';
  return null;
}

// A syntax error outranks git state; otherwise fall back to the working-tree
// status. Returns '' for a clean, untracked-free file so callers can skip.
export function fileStatusClass(
  path: string | undefined,
  gitStatus: Record<string, GitFileStatus>,
  errorFiles: Record<string, true>,
): string {
  if (!path) return '';
  if (errorFiles[path]) return 'status-error';
  const s = gitStatus[path];
  return s ? `status-${s}` : '';
}

export function fileStatusLetter(
  path: string | undefined,
  gitStatus: Record<string, GitFileStatus>,
  errorFiles: Record<string, true>,
): string {
  if (!path) return '';
  if (errorFiles[path]) return '!';
  switch (gitStatus[path]) {
    case 'untracked': return 'U';
    case 'modified': return 'M';
    case 'added': return 'A';
    case 'deleted': return 'D';
    case 'renamed': return 'R';
    case 'conflict': return 'C';
    default: return '';
  }
}

export type FileStatusKind = GitFileStatus | 'error';

// Higher rank wins when a folder aggregates several descendants; a syntax
// error outranks every git state, matching the per-file badge precedence.
const STATUS_RANK: Record<FileStatusKind, number> = {
  deleted: 1,
  renamed: 2,
  untracked: 3,
  added: 4,
  modified: 5,
  conflict: 6,
  error: 7,
};

function parentDir(p: string): string {
  const i = p.lastIndexOf('/');
  return i > 0 ? p.slice(0, i) : '';
}

// Roll every file's status up through its ancestor folders so a folder row can
// show one dot summarising "what changed inside". The project root itself is
// left unbadged. Keys are absolute folder paths under `root`.
export function buildFolderStatus(
  root: string,
  gitStatus: Record<string, GitFileStatus>,
  errorFiles: Record<string, true>,
): Record<string, FileStatusKind> {
  const base = (root || '').replace(/\/+$/, '');
  const out: Record<string, FileStatusKind> = {};
  if (!base) return out;
  const consider = (fileAbs: string, kind: FileStatusKind) => {
    let dir = parentDir(fileAbs);
    while (dir.length > base.length && dir.startsWith(base + '/')) {
      const cur = out[dir];
      if (!cur || STATUS_RANK[kind] > STATUS_RANK[cur]) out[dir] = kind;
      dir = parentDir(dir);
    }
  };
  for (const [p, s] of Object.entries(gitStatus)) consider(p, s);
  for (const p of Object.keys(errorFiles)) if (errorFiles[p]) consider(p, 'error');
  return out;
}
