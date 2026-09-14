/**
 * Resolves any filesystem path into a browser-loadable media URL.
 * Works across:
 * - GJS WebKitGTK / Loopback HTTP (http://127.0.0.1:17842/_media_file/...)
 * - Electron file:// protocol
 * - Vite Dev server
 */
export function getMediaUrl(path: string | null | undefined): string {
  if (!path) return '';
  if (
    path.startsWith('http://') ||
    path.startsWith('https://') ||
    path.startsWith('data:') ||
    path.startsWith('blob:')
  ) {
    return path;
  }

  // Running directly under file:// in Electron (native desktop)
  if (typeof window !== 'undefined' && window.location.protocol === 'file:') {
    return `file://${path}`;
  }

  // Running under loopback server (WebKitGTK or Electron on loopback)
  const origin =
    typeof window !== 'undefined' && window.location.origin && window.location.origin !== 'null'
      ? window.location.origin
      : 'http://127.0.0.1:17842';

  const cleanPath = path.startsWith('/') ? path : '/' + path;
  return `${origin}/_media_file${cleanPath}`;
}
