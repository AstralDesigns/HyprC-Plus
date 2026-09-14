#!/usr/bin/env gjs
// HyprCandy App Launcher — GTK4 Layer Shell
// Replaces rofi -show drun for the hyprcandydock start button.
//
// Features:
//   • Reads dock.pos (0=bottom 1=right 2=top 3=left) and positions itself
//     2–3 px from the dock edge, centered on the perpendicular axis.
//   • Search bar + icon grid (same categories / sort as the GTK app list).
//   • Left-click launches the app; Enter on search launches the first match.
//   • Right-click → context menu:
//       – Focus / switch to running instance (one entry per window)
//       – New Window  (always shown)
//       – ─────────────────────────
//       – Pin to Dock / Unpin from Dock
//   • Styling: uses the same matugen GTK CSS variables as the dock
//     (@blur_background, @primary, @on_secondary, @inverse_primary …)
//     so it matches your theme automatically.
//   • ESC or app-launch closes the window.
//
// Toggle:  toggle-app-launcher.sh  (kills if running, spawns if not)
// Signal:  the launcher sends pkill -12 -f "gjs dock-main.js" after any
//          pin-state change so the dock hot-reloads pinned apps immediately.

'use strict';

imports.gi.versions.Gtk = '4.0';
imports.gi.versions.Gdk = '4.0';

const { Gtk, Gdk, Gio, GLib, GObject } = imports.gi;
const GioUnix = imports.gi.GioUnix;
GLib.set_prgname('HC-launcher');
GLib.set_application_name('HC-launcher');

const GLibUnix = imports.gi.GLibUnix;   // import before Gtk.Application so GJS
// routes signal_add to the new namespace
// instead of the deprecated GLib one
const Gtk4LayerShell = imports.gi.Gtk4LayerShell;

// Force the launcher process onto a warning/error-only GJS/WebKit logging mode.
// This suppresses the noisy ALL/DEBUG trace stream without removing reportable errors.
try {
    GLib.setenv('G_MESSAGES_DEBUG', 'none', true);
} catch (_) { }

// ── Paths ──────────────────────────────────────────────────────────────────
const HOME = GLib.get_home_dir();
const _rawDir = GLib.path_get_dirname(imports.system.programInvocationName);
const SCRIPT_DIR = GLib.canonicalize_filename(_rawDir, GLib.get_current_dir());

// Import the dock's config and launcher's own config
imports.searchPath.unshift(SCRIPT_DIR);
const DockConfig = imports.config.DockConfig;
const LauncherConfig = imports.launcherConfig.LauncherConfig;
const GlyphData = imports.glyphData.GlyphData;

// Soup 3 — used for native SearXNG JSON API calls in the web search tab.
imports.gi.versions.Soup = '3.0';
const Soup = imports.gi.Soup;

// The agent must use a secure/loopback HTTP origin for WebGPU. Loading the
// React bundle from file:// makes navigator.gpu unavailable in WebKitGTK even
// when the WebGPU feature and hardware acceleration are enabled. Keep this
// port stable so the agent's IndexedDB origin and WebLLM model cache survive
// daemon restarts.
const AGENT_LOOPBACK_HOST = '127.0.0.1';
const AGENT_LOOPBACK_PORT = 17842;
const LLAMA_SERVER_PORT = Number(GLib.getenv('HYPRCANDY_LLAMA_PORT') || 17843);
const LLAMA_MODELS_DIR = GLib.getenv('HYPRCANDY_LLAMA_MODELS_DIR') || GLib.build_filenamev([HOME, '.local', 'share', 'hyprcandy', 'llama-models']);
const LLAMA_STATE_PATH = GLib.getenv('HYPRCANDY_LLAMA_STATE') || GLib.build_filenamev([HOME, '.local', 'share', 'hyprcandy', 'llama-server-state.json']);
const LLAMA_CATALOG = [
    { id: 'Qwen2.5-Coder-1.5B-Instruct', repo: 'bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF', file: 'Qwen2.5-Coder-1.5B-Instruct-Q4_K_M.gguf' },
    { id: 'Qwen2.5-Coder-0.5B-Instruct', repo: 'bartowski/Qwen2.5-Coder-0.5B-Instruct-GGUF', file: 'Qwen2.5-Coder-0.5B-Instruct-Q4_K_M.gguf' },
];

const WORKSPACE_STARTUP_STATE_PATH = GLib.getenv('HYPRCANDY_WORKSPACE_STARTUP_STATE')
    || GLib.build_filenamev([HOME, '.local', 'share', 'hyprcandy', 'workspace-startup-state.json']);

function readWorkspaceStartupState() {
    try {
        const [ok, bytes] = GLib.file_get_contents(WORKSPACE_STARTUP_STATE_PATH);
        if (ok) {
            const parsed = JSON.parse(new TextDecoder().decode(bytes));
            return parsed && typeof parsed.enabled === 'boolean' ? parsed.enabled : true;
        }
    } catch (_) { }
    return true;
}

function writeWorkspaceStartupState(enabled) {
    try {
        const dir = GLib.path_get_dirname(WORKSPACE_STARTUP_STATE_PATH);
        GLib.mkdir_with_parents(dir, 0o755);
        const payload = JSON.stringify({ enabled: !!enabled }) + '\n';
        GLib.file_set_contents(WORKSPACE_STARTUP_STATE_PATH, new TextEncoder().encode(payload));
    } catch (_) { }
}

function readCachedLlamaModel() {
    let preferred = null;
    try {
        const [ok, bytes] = GLib.file_get_contents(LLAMA_STATE_PATH);
        if (ok) preferred = JSON.parse(new TextDecoder().decode(bytes));
    } catch (_) { }
    const candidates = preferred?.repo && preferred?.file ? [preferred, ...LLAMA_CATALOG] : LLAMA_CATALOG;
    for (const model of candidates) {
        if (!model?.file) continue;
        const path = GLib.build_filenamev([LLAMA_MODELS_DIR, model.file]);
        if (GLib.file_test(path, GLib.FileTest.IS_REGULAR)) {
            try {
                const file = Gio.File.new_for_path(path);
                const info = file.query_info('standard::size', Gio.FileQueryInfoFlags.NONE, null);
                if (info && info.get_size() > 1024 * 1024) return { id: model.id, repo: model.repo, file: model.file };
            } catch (_) { }
        }
    }
    return null;
}

function agentMimeType(filePath) {
    const lower = filePath.toLowerCase();
    if (lower.endsWith('.html')) return 'text/html; charset=utf-8';
    if (lower.endsWith('.js') || lower.endsWith('.mjs')) return 'text/javascript; charset=utf-8';
    if (lower.endsWith('.css')) return 'text/css; charset=utf-8';
    if (lower.endsWith('.json')) return 'application/json; charset=utf-8';
    if (lower.endsWith('.wasm')) return 'application/wasm';
    if (lower.endsWith('.map')) return 'application/json; charset=utf-8';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.avif')) return 'image/avif';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    if (lower.endsWith('.ico')) return 'image/x-icon';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.avi')) return 'video/x-msvideo';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.flac')) return 'audio/flac';
    if (lower.endsWith('.woff')) return 'font/woff';
    if (lower.endsWith('.woff2')) return 'font/woff2';
    return 'application/octet-stream';
}

// WebKit's file:// security rules are intentionally bypassed only for this
// private loopback server. It serves the already-built agent dist directory
// and never accepts non-loopback connections.
function createAgentLoopbackServer(distRoot) {
    const server = new Soup.Server();
    server.add_handler(null, (_server, message, requestPath) => {
        // Required for SharedArrayBuffer/pthread-enabled Wllama builds.
        // Apply these to every private-origin response, including assets.
        const responseHeaders = message.get_response_headers();
        responseHeaders.append('Cross-Origin-Opener-Policy', 'same-origin');
        responseHeaders.append('Cross-Origin-Embedder-Policy', 'require-corp');
        responseHeaders.append('Cross-Origin-Resource-Policy', 'same-origin');
        let path = requestPath || '/';
        try { path = decodeURIComponent(path); } catch (_) { }
        if (!path.startsWith('/')) path = '/' + path;

        // ── Stream local filesystem media files (images, audio, video) ────
        if (path.startsWith('/_media_file/')) {
            let targetPath = path.substring('/_media_file/'.length);
            if (!targetPath.startsWith('/')) targetPath = '/' + targetPath;
            if (!GLib.file_test(targetPath, GLib.FileTest.IS_REGULAR)) {
                message.set_status(Soup.Status.NOT_FOUND, null);
                return;
            }
            try {
                const file = Gio.File.new_for_path(targetPath);
                const info = file.query_info('standard::size', Gio.FileQueryInfoFlags.NONE, null);
                const totalSize = info ? info.get_size() : 0;
                const mime = agentMimeType(targetPath);

                const reqHeaders = message.get_request_headers();
                const rangeHeader = reqHeaders && reqHeaders.get_one ? reqHeaders.get_one('Range') : null;

                if (rangeHeader && rangeHeader.startsWith('bytes=') && totalSize > 0) {
                    const rangeSpec = rangeHeader.substring(6).trim();
                    const parts = rangeSpec.split('-');
                    let start = parseInt(parts[0], 10);
                    if (isNaN(start) || start < 0) start = 0;
                    let end = parts[1] ? parseInt(parts[1], 10) : (totalSize - 1);
                    if (isNaN(end) || end >= totalSize) end = totalSize - 1;

                    if (start > end) {
                        message.set_status(Soup.Status.REQUESTED_RANGE_NOT_SATISFIABLE, null);
                        return;
                    }

                    const length = end - start + 1;
                    const stream = file.read(null);
                    stream.seek(start, GLib.SeekType.SET, null);
                    const bytes = stream.read_bytes(length, null);
                    stream.close(null);

                    message.set_response(mime, Soup.MemoryUse.COPY, bytes.get_data());
                    const respHeaders = message.get_response_headers();
                    respHeaders.append('Accept-Ranges', 'bytes');
                    respHeaders.append('Content-Range', `bytes ${start}-${end}/${totalSize}`);
                    respHeaders.append('Content-Length', String(length));
                    respHeaders.append('Cache-Control', 'public, max-age=3600');
                    message.set_status(Soup.Status.PARTIAL_CONTENT, null);
                    return;
                }

                const [ok, contents] = GLib.file_get_contents(targetPath);
                if (!ok) throw new Error(`Unable to read ${targetPath}`);
                message.set_response(mime, Soup.MemoryUse.COPY, contents);
                const respHeaders = message.get_response_headers();
                respHeaders.append('Accept-Ranges', 'bytes');
                respHeaders.append('Content-Length', String(contents.length));
                respHeaders.append('Cache-Control', 'public, max-age=3600');
                message.set_status(Soup.Status.OK, null);
                return;
            } catch (err) {
                console.warn('[launcher] Failed to serve media file:', targetPath, err.message);
                message.set_status(Soup.Status.INTERNAL_SERVER_ERROR, null);
                return;
            }
        }

        // Reject traversal before joining paths. The server is local, but the
        // request still comes from a browser and must not escape distRoot.
        const parts = path.split('/');
        if (parts.some((part) => part === '..')) {
            message.set_status(Soup.Status.NOT_FOUND, null);
            return;
        }

        let relative = path.replace(/^\/+/, '');
        if (!relative || relative.endsWith('/')) relative += 'index.html';
        let filePath = GLib.build_filenamev([distRoot, ...relative.split('/')]);
        if (!GLib.file_test(filePath, GLib.FileTest.IS_REGULAR)) {
            // Vite's SPA fallback is useful for future client-side routes, but
            // missing assets remain 404s so diagnostics are not misleading.
            if (!relative.includes('.') || relative === 'index.html') {
                filePath = GLib.build_filenamev([distRoot, 'index.html']);
            } else {
                message.set_status(Soup.Status.NOT_FOUND, null);
                return;
            }
        }

        try {
            const [ok, contents] = GLib.file_get_contents(filePath);
            if (!ok) throw new Error(`Unable to read ${filePath}`);
            message.set_response(agentMimeType(filePath), Soup.MemoryUse.COPY, contents);
            message.get_response_headers().append('Cache-Control', 'no-cache');
            message.set_status(Soup.Status.OK, null);
        } catch (error) {
            console.warn('[launcher] Agent loopback file error:', error.message);
            message.set_status(Soup.Status.INTERNAL_SERVER_ERROR, null);
        }
    });

    // Keep a strong reference on the returned object owner. GJS can garbage
    // collect an otherwise unreferenced Soup.Server after a short delay.
    server.listen_local(AGENT_LOOPBACK_PORT, Soup.ServerListenOptions.IPV4_ONLY);
    return server;
}

// ── Hybrid-graphics detection ────────────────────────────────────────────
// On a laptop/desktop with more than one GPU (an integrated GPU plus a
// working discrete GPU), the software-fallback workaround below is
// unnecessarily conservative — it exists specifically because certain
// *old* Intel iGPU generations (Sandy Bridge/Ivy Bridge and similar, seen
// in this launcher's own logs: "Ivy Bridge Vulkan support is incomplete",
// "iHD_drv_video.so init failed") produce broken/black WebKit surfaces or
// crash the WebProcess outright when accelerated. Everything else —
// including plenty of perfectly capable *single*-GPU machines (recent
// Intel Iris Xe/Arc, AMD APUs, etc.) — should get full acceleration by
// default. This function inspects every DRM render node's PCI vendor,
// device ID, and bound kernel driver so the fallback can be scoped
// narrowly instead of guessing from GPU *count* alone.
//
// Environment variables set here are inherited by every WebProcess/GPU
// process WebKit spawns, since those are forked from this process.
function _detectGpuTopology() {
    const gpus = [];
    try {
        const drmDir = '/sys/class/drm';
        if (!GLib.file_test(drmDir, GLib.FileTest.IS_DIR)) return gpus;
        let dirEnum;
        try {
            dirEnum = Gio.File.new_for_path(drmDir).enumerate_children(
                'standard::name', Gio.FileQueryInfoFlags.NONE, null);
        } catch (_) { return gpus; }

        let info;
        while ((info = dirEnum.next_file(null)) !== null) {
            const name = info.get_name();
            if (!/^renderD\d+$/.test(name)) continue;
            const devDir = GLib.build_filenamev([drmDir, name, 'device']);
            let pciAddr = null;
            try {
                pciAddr = GLib.file_read_link(devDir);
                pciAddr = pciAddr ? pciAddr.split('/').pop() : null;
            } catch (_) { continue; }
            if (!pciAddr) continue;

            let vendor = null, device = null, bootVga = false, driver = null;
            try {
                const [, vBytes] = GLib.file_get_contents(GLib.build_filenamev([devDir, 'vendor']));
                vendor = new TextDecoder().decode(vBytes).trim().toLowerCase();
            } catch (_) { }
            try {
                const [, dBytes] = GLib.file_get_contents(GLib.build_filenamev([devDir, 'device']));
                device = new TextDecoder().decode(dBytes).trim().toLowerCase();
            } catch (_) { }
            try {
                const [, bBytes] = GLib.file_get_contents(GLib.build_filenamev([devDir, 'boot_vga']));
                bootVga = new TextDecoder().decode(bBytes).trim() === '1';
            } catch (_) { }
            try {
                // The "driver" symlink's target basename is the actual bound
                // kernel module — "nvidia" (proprietary) vs "nouveau" (Mesa)
                // matters a great deal for which env vars apply below.
                const driverLink = GLib.file_read_link(GLib.build_filenamev([devDir, 'driver']));
                driver = driverLink ? driverLink.split('/').pop() : null;
            } catch (_) { }
            gpus.push({ pciAddr, vendor, device, bootVga, driver });
        }
    } catch (e) {
        console.warn('[launcher] GPU detection failed:', e.message);
    }
    return gpus;
}

// Intel Gen6 (Sandy Bridge) and Gen7 (Ivy Bridge) device IDs — Mesa has no
// Vulkan driver at all for Gen6, and explicitly logs Gen7's anv Vulkan
// support as "incomplete" (exactly what this launcher's own log shows).
// This is intentionally a narrow, specific list rather than a blanket
// "assume broken" default for every single-GPU machine.
const _KNOWN_PROBLEMATIC_INTEL_DEVICE_IDS = new Set([
    '0x0102', '0x0106', '0x010a', '0x0112', '0x0116', '0x0122', '0x0126', // Sandy Bridge
    '0x0152', '0x0156', '0x015a', '0x0162', '0x0166', '0x016a'            // Ivy Bridge
]);

const _gpus = _detectGpuTopology();
const _bootGpu = _gpus.find(g => g.bootVga) || _gpus[0] || null;
const _discreteGpu = _gpus.length > 1
    ? (_gpus.find(g => !g.bootVga) || _gpus.find(g => g.vendor !== '0x8086'))
    : null;

if (_discreteGpu) {
    if (_discreteGpu.driver === 'nvidia') {
        // Mesa's DRI_PRIME has no effect on the proprietary NVIDIA driver —
        // it only understands render-node offload for Mesa-based drivers
        // (i965/iris/anv, radeonsi/RADV, nouveau). NVIDIA's own PRIME
        // render-offload mechanism is a different set of variables.
        // https://wiki.archlinux.org/title/PRIME#NVIDIA_Optimus
        GLib.setenv('__NV_PRIME_RENDER_OFFLOAD', '1', true);
        GLib.setenv('__GLX_VENDOR_LIBRARY_NAME', 'nvidia', true);
        try { GLib.setenv('__VK_LAYER_NV_optimus', 'NVIDIA_only', true); } catch (_) { }
        console.log(`[launcher] Hybrid graphics detected — discrete NVIDIA GPU ${_discreteGpu.pciAddr} using proprietary driver; routing via __NV_PRIME_RENDER_OFFLOAD instead of DRI_PRIME. Leaving hardware acceleration enabled.`);
    } else {
        // Mesa-based discrete GPU (AMD/nouveau/another Intel part) — DRI_PRIME
        // accepts a "pci-<domain>_<bus>_<dev>_<func>" selector built from the
        // sysfs PCI address (e.g. "0000:01:00.0" -> "pci-0000_01_00_0").
        const driPrimeId = 'pci-' + _discreteGpu.pciAddr.replace(/[:.]/g, '_');
        GLib.setenv('DRI_PRIME', driPrimeId, true);
        console.log(`[launcher] Hybrid graphics detected — routing WebKit/GL rendering to discrete GPU ${_discreteGpu.pciAddr} (DRI_PRIME=${driPrimeId}); leaving hardware acceleration enabled.`);
    }
}

// Only fall back to disabling GPU acceleration when the GPU that will
// actually be used (the discrete one if we just routed to it, otherwise
// the sole/boot GPU) is a *specifically known* problem generation — not
// merely because the machine happens to have only one GPU.
const _activeGpu = _discreteGpu || _bootGpu;
const _activeGpuIsKnownProblematic = !!(_activeGpu &&
    _activeGpu.vendor === '0x8086' &&
    _KNOWN_PROBLEMATIC_INTEL_DEVICE_IDS.has(_activeGpu.device));

// WebKit 6.0 — used for embedded web content preview in the web search tab.
// IMPORTANT: Disable DMA-BUF renderer before WebKit initialises — but only
// for the specific old-Intel-iGPU case above. On Sandy/Ivy Bridge (and
// similar GPUs without full Vulkan/VA-API support), WebKitGTK's DMA-BUF/
// GPU-buffer sharing with the Wayland compositor produces a completely
// black (transparent) surface, or in some driver combinations crashes the
// WebProcess outright, even though the DOM is fully rendered. Setting this
// env var forces WebKit to fall back to the shm/pixmap path which always
// composites correctly — at the cost of GPU acceleration, which is why
// this now only applies to the narrow set of GPUs actually known to need
// it, instead of every single-GPU machine.
if (_activeGpuIsKnownProblematic) {
    console.log(`[launcher] Known-problematic Intel GPU detected (${_activeGpu.device}) — disabling DMA-BUF/GPU compositing as a stability workaround.`);
    GLib.setenv('WEBKIT_DISABLE_DMABUF_RENDERER', '1', true);
    GLib.setenv('WEBKIT_FORCE_COMPOSITING_MODE', '0', true);
    try { GLib.setenv('WEBKIT_ENABLE_WEBGPU', '0', true); } catch (_) { }
    GLib.setenv('WEBKIT_GL_DISABLE_DMABUF', '1', true);
}
imports.gi.versions.WebKit = '6.0';
const WebKit = imports.gi.WebKit;

// libsecret 1 — GNOME Secrets credentials store for secure local storage.
try {
    imports.gi.versions.Secret = '1';
} catch (_) { }
const Secret = imports.gi.Secret;

// ── GNOME Secrets / Credentials Store ──────────────────────────────────────
let _secretSchema = null;

function getSecretSchema() {
    if (!_secretSchema) {
        try {
            _secretSchema = new Secret.Schema(
                'org.hyprcandy.LauncherCredentials',
                Secret.SchemaFlags.NONE,
                {
                    'service': Secret.SchemaAttributeType.STRING,
                    'account': Secret.SchemaAttributeType.STRING,
                }
            );
        } catch (_) { }
    }
    return _secretSchema;
}

var CredentialsManager = {
    store(service, account, secret) {
        try {
            const schema = getSecretSchema();
            if (schema && Secret) {
                Secret.password_store_sync(
                    schema,
                    { service: String(service), account: String(account) },
                    Secret.COLLECTION_DEFAULT,
                    `HyprCandy: ${service} (${account})`,
                    String(secret),
                    null
                );
                return true;
            }
        } catch (e) {
            console.warn('[launcher] CredentialsManager.store failed:', e.message);
        }
        return false;
    },

    lookup(service, account) {
        try {
            const schema = getSecretSchema();
            if (schema && Secret) {
                return Secret.password_lookup_sync(
                    schema,
                    { service: String(service), account: String(account) },
                    null
                );
            }
        } catch (e) {
            console.warn('[launcher] CredentialsManager.lookup failed:', e.message);
        }
        return null;
    },

    clear(service, account) {
        try {
            const schema = getSecretSchema();
            if (schema && Secret) {
                return Secret.password_clear_sync(
                    schema,
                    { service: String(service), account: String(account) },
                    null
                );
            }
        } catch (e) {
            console.warn('[launcher] CredentialsManager.clear failed:', e.message);
        }
        return false;
    }
};

// ── Persistent Web State across reloads ─────────────────────────────────────
const LAUNCHER_SAVED_STATE_PATH = GLib.build_filenamev([HOME, '.cache', 'hyprcandy', 'launcher_web_state.json']);

function readLauncherWebState() {
    try {
        const [ok, raw] = GLib.file_get_contents(LAUNCHER_SAVED_STATE_PATH);
        if (ok) return JSON.parse(new TextDecoder().decode(raw));
    } catch (_) { }
    return {};
}

function saveLauncherWebState(state) {
    try {
        const stateDir = GLib.path_get_dirname(LAUNCHER_SAVED_STATE_PATH);
        GLib.mkdir_with_parents(stateDir, 0o755);
        const file = Gio.File.new_for_path(LAUNCHER_SAVED_STATE_PATH);
        const json = JSON.stringify(state, null, 2);
        file.replace_contents(
            new TextEncoder().encode(json + '\n'),
            null, false, Gio.FileCreateFlags.REPLACE_DESTINATION, null
        );
    } catch (e) {
        console.error('[launcher] saveLauncherWebState error:', e.message);
    }
}

// ── Layout constants (read from LauncherConfig) ────────────────────────────

const APP_ICON_SIZE = LauncherConfig.iconSize || 48;
const TEXT_FONT_SIZE = LauncherConfig.textFontSize || 11;
const TILE_WIDTH = LauncherConfig.fixedTileWidth || 90;
const TILE_HEIGHT = LauncherConfig.fixedTileHeight || 90;
const GAP_FROM_DOCK = 3;    // px gap between dock surface edge and launcher

// ── CSS file paths (for hot-reload watcher) ────────────────────────────────
const GTK4_COLORS_PATH = GLib.build_filenamev([HOME, '.config', 'gtk-4.0', 'colors.css']);

// Horizontal dock (top / bottom) — wide landscape launcher
const W_HORIZ = LauncherConfig.frameWidth || 500;
const H_HORIZ = LauncherConfig.frameHeight || 480;
// Columns = how many tiles fit in the inner content width.
// Subtract 52px for the sidebar, 2x12 px side padding; tiles separated by 2 px gaps.
const SIDEBAR_W = 52;
const COLS_HORIZ = Math.max(2, Math.floor((W_HORIZ - SIDEBAR_W - 24 + 2) / (TILE_WIDTH + 2)));

// Vertical dock (left / right) — narrower portrait launcher
const W_VERT = LauncherConfig.frameWidthVert || 380;
const H_VERT = LauncherConfig.frameHeightVert || 560;
const COLS_VERT = Math.max(2, Math.floor((W_VERT - SIDEBAR_W - 24 + 2) / (TILE_WIDTH + 2)));

// ── Small helpers ──────────────────────────────────────────────────────────

const _dec = new TextDecoder();
const _enc = new TextEncoder();

/** Read dock.pos → 'bottom' | 'right' | 'top' | 'left' */
function readDockPos() {
    try {
        const [ok, raw] = GLib.file_get_contents(`${SCRIPT_DIR}/dock.pos`);
        if (ok) {
            const idx = parseInt(_dec.decode(raw).trim(), 10);
            return ['bottom', 'right', 'top', 'left'][idx] ?? 'bottom';
        }
    } catch (_) { }
    return 'bottom';
}

/** Read ~/.config/pinned → Set<className> */
function readPinnedApps() {
    const set = new Set();
    try {
        const [ok, raw] = GLib.file_get_contents(`${HOME}/.config/pinned`);
        if (ok)
            _dec.decode(raw).trim().split('\n')
                .forEach(l => { if (l.trim()) set.add(l.trim()); });
    } catch (_) { }
    return set;
}

/** Write updated Set back to ~/.config/pinned */
function savePinnedApps(set) {
    const file = Gio.File.new_for_path(`${HOME}/.config/pinned`);
    try {
        file.replace_contents(
            _enc.encode([...set].join('\n') + '\n'),
            null, false, Gio.FileCreateFlags.REPLACE_DESTINATION, null
        );
    } catch (e) { console.error('[launcher] savePinnedApps:', e.message); }
}

/** Read ~/.config/desktop-pinned → Set<className> */
function readDesktopPinnedApps() {
    const set = new Set();
    try {
        const [ok, raw] = GLib.file_get_contents(`${HOME}/.config/desktop-pinned`);
        if (ok)
            _dec.decode(raw).trim().split('\n')
                .forEach(l => { if (l.trim()) set.add(l.trim()); });
    } catch (_) { }
    return set;
}

/** Write updated Set back to ~/.config/desktop-pinned */
function saveDesktopPinnedApps(set) {
    const file = Gio.File.new_for_path(`${HOME}/.config/desktop-pinned`);
    try {
        file.replace_contents(
            _enc.encode([...set].join('\n') + '\n'),
            null, false, Gio.FileCreateFlags.REPLACE_DESTINATION, null
        );
    } catch (e) { console.error('[launcher] saveDesktopPinnedApps:', e.message); }
    try { GLib.spawn_command_line_async('qs ipc call bar refreshDesktop'); } catch (_) { }
    // Signal the dock via SIGUSR2 so hotReload() reloads desktopPinnedApps
    // synchronously — the Gio.FileMonitor in daemon.js is async and can
    // lose the race against the next context-menu open.
    signalDockRefresh();
}

/**
 * Signal the dock to hot-reload (picks up new pinned-apps state).
 * The dock listens for SIGUSR2 (signal 12) to run hotReload().
 */
function signalDockRefresh() {
    try { GLib.spawn_command_line_async('pkill -12 -f "gjs dock-main.js"'); } catch (_) { }
}

/** Spawn an app cleanly (strip LD_PRELOAD, resolve %U %F etc.) */
function spawnApp(exec) {
    if (!exec) return;
    try {
        const clean = exec.replace(/%[UuFfIiDdNnVvKk]/g, '').trim();
        const [, argv] = GLib.shell_parse_argv(clean);
        let envp = GLib.environ_unsetenv(GLib.get_environ(), 'LD_PRELOAD');
        GLib.spawn_async(HOME, argv, envp,
            GLib.SpawnFlags.SEARCH_PATH | GLib.SpawnFlags.DO_NOT_REAP_CHILD,
            null);
    } catch (e) { console.error('[launcher] spawnApp:', e.message); }
}

/** Spawn an app on a specific GPU (extra env vars from switcheroo) */
function spawnAppOnGPU(exec, envVars) {
    if (!exec) return;
    try {
        const clean = exec.replace(/%[UuFfIiDdNnVvKk]/g, '').trim();
        const [, argv] = GLib.shell_parse_argv(clean);
        let envp = GLib.environ_unsetenv(GLib.get_environ(), 'LD_PRELOAD');
        for (const [k, v] of Object.entries(envVars || {}))
            envp = GLib.environ_setenv(envp, k, String(v), true);
        GLib.spawn_async(HOME, argv, envp,
            GLib.SpawnFlags.SEARCH_PATH | GLib.SpawnFlags.DO_NOT_REAP_CHILD,
            null);
    } catch (e) { console.error('[launcher] spawnAppOnGPU:', e.message); }
}

/** Open a URL in the user's default browser cleanly (stripping LD_PRELOAD) */
function openInBrowser(url) {
    if (!url) return;
    try {
        let envp = GLib.environ_unsetenv(GLib.get_environ(), 'LD_PRELOAD');
        GLib.spawn_async(
            HOME,
            ['xdg-open', url],
            envp,
            GLib.SpawnFlags.SEARCH_PATH | GLib.SpawnFlags.DO_NOT_REAP_CHILD,
            null
        );
        return;
    } catch (e) {
        console.warn('[launcher] xdg-open spawn failed, trying Gio.AppInfo:', e.message);
    }
    try {
        Gio.AppInfo.launch_default_for_uri(url, null);
    } catch (e) {
        console.error('[launcher] openInBrowser failed:', e.message);
    }
}

/** Focus a Hyprland window by address */
function focusWindow(address) {
    try {
        GLib.spawn_command_line_async(
            `hyprctl dispatch "hl.dsp.focus({ window = 'address:${address}' })"`
        );
    } catch (_) { }
}

/** Short-lived cache — launcher show + refresh can call this back-to-back. */
let _runningAppsCache = null;
let _runningAppsCacheUs = 0;
const RUNNING_APPS_TTL_US = 800 * 1000;

/**
 * Query running apps via hyprctl clients -j.
 * Returns Map<lowerCaseClass, [{title, address}]>
 */
function getRunningApps() {
    const now = GLib.get_monotonic_time();
    if (_runningAppsCache && (now - _runningAppsCacheUs) < RUNNING_APPS_TTL_US)
        return _runningAppsCache;
    const running = new Map();
    try {
        const [ok, out] = GLib.spawn_command_line_sync('hyprctl clients -j');
        if (ok) {
            const clients = JSON.parse(_dec.decode(out));
            for (const c of clients) {
                const cls = (c.class || '').toLowerCase();
                if (!running.has(cls)) running.set(cls, []);
                running.get(cls).push({ title: c.title || '(no title)', address: c.address });

                // Steam game heuristic: Hyprland reports Steam games as "steam_app_<id>".
                // Also register the instances under the bare numeric app ID so that
                // getAllApps() entries (whose className is derived from the .desktop
                // file ID, e.g. "caliber") can find them via their steamAppId field.
                const steamMatch = cls.match(/^steam_app_(\d+)$/);
                if (steamMatch) {
                    const appId = steamMatch[1];
                    if (!running.has(appId)) running.set(appId, []);
                    // Avoid duplicate entries when multiple instances exist
                    const entry = { title: c.title || '(no title)', address: c.address };
                    if (!running.get(appId).some(e => e.address === entry.address))
                        running.get(appId).push(entry);
                }
            }
        }
    } catch (_) { }
    _runningAppsCache = running;
    _runningAppsCacheUs = now;
    return running;
}

/**
 * Build the full sorted app list from Gio.AppInfo.
 * Returns [{name, iconName, className, exec, info}]
 */
function getAllApps() {
    const apps = [];
    const seen = new Set();
    for (const info of Gio.AppInfo.get_all()) {
        // Steam sets NoDisplay=true on game .desktop files so they don't clutter
        // system app menus — but we want them in the launcher. Pass them through
        // when their Exec contains a Steam game URL; skip everything else that
        // fails should_show() (hidden system entries, OnlyShowIn mismatches, etc.).
        if (!info.should_show()) {
            const cmd = info.get_commandline && info.get_commandline();
            if (!cmd || !cmd.includes('steam://rungameid')) continue;
        }
        const id = info.get_id();
        if (seen.has(id)) continue;
        seen.add(id);

        const name = info.get_display_name() || info.get_name() || id;
        const gicon = info.get_icon();
        let iconName = 'application-x-executable';
        if (gicon) {
            const names = gicon.get_names && gicon.get_names();
            if (names && names.length > 0) {
                iconName = names[0];
            } else {
                const f = gicon.get_file && gicon.get_file();
                iconName = (f && f.get_path && f.get_path()) || gicon.to_string() || iconName;
            }
        }

        // Prefer StartupWMClass for pin matching (same key the dock uses).
        // wmClass is stored separately so pin checks can always test it even
        // when Gio.AppInfo returns the object without get_startup_wm_class.
        const wm = info.get_startup_wm_class && info.get_startup_wm_class();
        const wmClass = wm || null;
        const className = wm || id.replace('.desktop', '');
        // Desktop file ID — used when writing to desktop-pinned so QML can
        // resolve the entry via DesktopEntries.byId() without heuristics.
        const desktopId = id.replace(/\.desktop$/, '');

        const cmd = info.get_commandline && info.get_commandline();
        const exec = cmd ? cmd.replace(/%[UuFfIiDdNnVvKk]/g, '').trim() : null;

        // Steam game heuristic: Steam creates .desktop files with no StartupWMClass
        // but with Exec=steam steam://rungameid/<id>. Extract the app ID so the
        // running-apps map (keyed by app ID via getRunningApps) can match this entry.
        let steamAppId = null;
        if (exec) {
            const steamIdMatch = exec.match(/rungameid\/(\d+)/);
            if (steamIdMatch) steamAppId = steamIdMatch[1];
        }

        apps.push({ name, iconName, className, desktopId, wmClass, exec, steamAppId, info });
    }

    // ── ~/Desktop/ scan ────────────────────────────────────────────────────
    // Gio.AppInfo.get_all() only walks XDG data dirs (e.g. ~/.local/share/applications).
    // Steam creates game shortcuts directly on ~/Desktop/ as plain .desktop files,
    // which Gio never finds. Scan the Desktop directory manually and merge any
    // .desktop files not already present in the list (de-dup by desktopId).
    const seenDesktopIds = new Set(apps.map(a => a.desktopId));
    const desktopDir = GLib.build_filenamev([HOME, 'Desktop']);
    if (GLib.file_test(desktopDir, GLib.FileTest.IS_DIR)) {
        try {
            const dir = Gio.File.new_for_path(desktopDir);
            const iter = dir.enumerate_children('standard::name,standard::type', Gio.FileQueryInfoFlags.NONE, null);
            let fileInfo;
            while ((fileInfo = iter.next_file(null))) {
                const fname = fileInfo.get_name();
                if (!fname.endsWith('.desktop')) continue;
                const fpath = GLib.build_filenamev([desktopDir, fname]);
                try {
                    const dinfo = GioUnix.DesktopAppInfo.new_from_filename(fpath);
                    if (!dinfo) continue;
                    // Skip non-application entries (links, directories, etc.)
                    if (dinfo.get_string('Type') !== 'Application') continue;

                    const did = fname.replace(/\.desktop$/, '');
                    if (seenDesktopIds.has(did)) continue;
                    seenDesktopIds.add(did);

                    const dname = dinfo.get_display_name() || dinfo.get_name() || fname;
                    const dgicon = dinfo.get_icon();
                    let diconName = 'application-x-executable';
                    if (dgicon) {
                        const dnames = dgicon.get_names && dgicon.get_names();
                        if (dnames && dnames.length > 0) {
                            diconName = dnames[0];
                        } else {
                            const df = dgicon.get_file && dgicon.get_file();
                            diconName = (df && df.get_path && df.get_path()) || dgicon.to_string() || diconName;
                        }
                    }

                    const dwm = dinfo.get_startup_wm_class && dinfo.get_startup_wm_class();
                    const dwmClass = dwm || null;
                    const dcls = dwm || did;
                    const dcmd = dinfo.get_commandline && dinfo.get_commandline();
                    const dexec = dcmd ? dcmd.replace(/%[UuFfIiDdNnVvKk]/g, '').trim() : null;

                    let dsteamAppId = null;
                    if (dexec) {
                        const sm = dexec.match(/rungameid\/(\d+)/);
                        if (sm) dsteamAppId = sm[1];
                    }

                    apps.push({
                        name: dname, iconName: diconName, className: dcls,
                        desktopId: did, wmClass: dwmClass, exec: dexec,
                        steamAppId: dsteamAppId, info: dinfo
                    });
                } catch (_) { }
            }
        } catch (_) { }
    }

    apps.sort((a, b) => a.name.localeCompare(b.name));
    return apps;
}

// ── Favorites ──────────────────────────────────────────────────────────────

// nf-md-star_four_points_outline  (U+F06D0 in MDI; mapped in Nerd Fonts 3.x)
// Replace this literal with the glyph from your Nerd Fonts browser if it
// doesn't render as expected — the codepoint varies slightly between NF versions.
const FAV_GLYPH = '';
const CHEV_UP = '󰬬';  // nf-md-chevron_up_circle  (section expanded)
const CHEV_DOWN = '󰬦';  // nf-md-chevron_down_circle (section collapsed)
const GLYPH_INDICATOR = '\u{F09DF}';  //  active-window dot (same glyph as dock)

// FlowBox helpers for arrow-key navigation and item activation
function widgetContains(parent, child) {
    if (!parent || !child) return false;
    if (parent === child) return true;
    if (typeof parent.contains === 'function' && parent.contains(child)) return true;
    let cur = child;
    while (cur) {
        if (cur === parent) return true;
        cur = cur.get_parent ? cur.get_parent() : null;
    }
    return false;
}

function getFlowActiveChild(fb) {
    if (!fb) return null;
    const root = fb.get_root ? fb.get_root() : null;
    const focused = root && root.get_focus ? root.get_focus() : null;
    let cur = focused;
    while (cur && cur.get_parent && cur.get_parent() !== fb) {
        cur = cur.get_parent();
    }
    if (cur && cur.get_parent && cur.get_parent() === fb) return cur;
    let focus = fb.get_focus_child ? fb.get_focus_child() : null;
    while (focus && focus.get_parent && focus.get_parent() !== fb) {
        focus = focus.get_parent();
    }
    if (focus) return focus;
    const sel = fb.get_selected_children ? fb.get_selected_children() : [];
    if (sel && sel.length > 0) return sel[0];
    return fb.get_first_child ? fb.get_first_child() : null;
}

function flowSelIdx(fb) {
    const c = getFlowActiveChild(fb);
    return c && typeof c.get_index === 'function' ? c.get_index() : 0;
}

function getAppDataFromChild(child) {
    if (!child) return null;
    let cur = child;
    if (cur.get_child) cur = cur.get_child(); // Gtk.Overlay
    if (cur && cur.get_child) {
        const inner = cur.get_child(); // Gtk.Button
        if (inner && inner._appData) return inner._appData;
    }
    if (cur && cur._appData) return cur._appData;
    if (child._appData) return child._appData;
    return null;
}

function flowCount(fb) {
    let n = 0, c = fb.get_first_child();
    while (c) { n++; c = c.get_next_sibling(); }
    return n;
}

const FAVORITES_FILE = GLib.build_filenamev([HOME, '.config', 'hyprcandy-launcher-favorites']);

function readFavorites() {
    const set = new Set();
    try {
        const [ok, raw] = GLib.file_get_contents(FAVORITES_FILE);
        if (ok)
            _dec.decode(raw).trim().split('\n')
                .forEach(l => { if (l.trim()) set.add(l.trim()); });
    } catch (_) { }
    return set;
}

function writeFavorites(set) {
    const file = Gio.File.new_for_path(FAVORITES_FILE);
    try {
        // GLib.file_replace_contents requires a non-NULL (non-empty) byte array.
        // Always write at least a newline so an empty set produces a valid write.
        const content = set.size ? [...set].join('\n') + '\n' : '\n';
        file.replace_contents(
            _enc.encode(content),
            null, false, Gio.FileCreateFlags.REPLACE_DESTINATION, null
        );
    } catch (e) { console.error('[launcher] writeFavorites:', e.message); }
}

// ── Groups ─────────────────────────────────────────────────────────────────

const GROUPS_FILE = GLib.build_filenamev([HOME, '.config', 'hyprcandy-launcher-groups']);

/** Read groups from file. Returns { groupName: [className, ...], ... } */
function readGroups() {
    try {
        const [ok, raw] = GLib.file_get_contents(GROUPS_FILE);
        if (ok) return JSON.parse(_dec.decode(raw));
    } catch (_) { }
    return {};
}

/** Write groups to file */
function writeGroups(groups) {
    const file = Gio.File.new_for_path(GROUPS_FILE);
    try {
        file.replace_contents(
            _enc.encode(JSON.stringify(groups, null, 2) + '\n'),
            null, false, Gio.FileCreateFlags.REPLACE_DESTINATION, null
        );
    } catch (e) { console.error('[launcher] writeGroups:', e.message); }
}

/** Add an app to a group */
function addAppToGroup(groups, groupName, className) {
    if (!groups[groupName]) groups[groupName] = [];
    if (!groups[groupName].includes(className))
        groups[groupName].push(className);
    writeGroups(groups);
}

/** Remove an app from a group */
function removeAppFromGroup(groups, groupName, className) {
    if (groups[groupName]) {
        groups[groupName] = groups[groupName].filter(c => c !== className);
        if (groups[groupName].length === 0) delete groups[groupName];
        writeGroups(groups);
    }
}

/** Rename a group, preserving its members and insertion order */
function renameGroup(groups, oldName, newName) {
    if (!groups[oldName] || oldName === newName || !newName) return;
    // Rebuild the object so the renamed entry keeps its position
    const rebuilt = {};
    for (const [k, v] of Object.entries(groups))
        rebuilt[k === oldName ? newName : k] = v;
    writeGroups(rebuilt);
}

/** Delete a group entirely */
function deleteGroup(groups, groupName) {
    delete groups[groupName];
    writeGroups(groups);
}

// ── dGPU detection (mirrors daemon.js _querySwitcheroo logic) ─────────────

let _gpuCache = undefined;  // undefined = not yet queried; [] = queried but none

/**
 * Returns [{name, envVars}] for each discrete GPU reported by
 * switcheroo-control, or [] on single-GPU / unavailable systems.
 * Mirrors the double-deep_unpack pattern from daemon.js exactly.
 */
function getAvailableDGPUs() {
    if (_gpuCache !== undefined) return _gpuCache;
    try {
        const result = Gio.DBus.system.call_sync(
            'net.hadess.SwitcherooControl',
            '/net/hadess/SwitcherooControl',
            'org.freedesktop.DBus.Properties',
            'Get',
            new GLib.Variant('(ss)', ['net.hadess.SwitcherooControl', 'GPUs']),
            null, Gio.DBusCallFlags.NONE, -1, null
        );
        // Properties.Get returns (v). First deep_unpack unwraps the tuple;
        // raw[0] is still a GLib.Variant wrapping aa{sv}, so unpack again.
        const raw = result.deep_unpack();
        const inner = raw[0];
        const unpacked = (inner && typeof inner.deep_unpack === 'function')
            ? inner.deep_unpack() : inner;
        const gpuList = unpacked ? Object.values(unpacked) : [];

        const _u = v => (v && typeof v.deep_unpack === 'function') ? v.deep_unpack() : v;
        _gpuCache = [];
        for (const gpuDict of gpuList) {
            if (!!_u(gpuDict['Default'])) continue;  // skip iGPU / default GPU
            const evArr = _u(gpuDict['Environment']);
            const arr = Array.isArray(evArr) ? evArr : (evArr ? Object.values(evArr) : []);
            const envVars = {};
            for (let i = 0; i + 1 < arr.length; i += 2)
                envVars[arr[i]] = arr[i + 1];
            _gpuCache.push({
                name: _u(gpuDict['Name']) || 'dGPU',
                envVars,
            });
        }
    } catch (_) {
        _gpuCache = [];
    }
    return _gpuCache;
}

/** Strip verbose vendor prefixes for compact popover labels (mirrors daemon.js) */
function abbreviateGpuName(name) {
    if (!name) return 'dGPU';
    let s = name
        .replace(/^Advanced Micro Devices,\s*Inc\.\s*\[AMD\/ATI\]\s*/i, '')
        .replace(/^NVIDIA\s+Corporation\s*/i, '')
        .replace(/^Intel\s+Corporation\s*/i, '')
        .replace(/^Intel\(R\)\s*/i, 'Intel® ')
        .trim();
    return s.length > 32 ? s.slice(0, 31) + '…' : s;
}

// ── CSS ────────────────────────────────────────────────────────────────────

// These rules use the same matugen GTK colour variables the dock uses.
// They are loaded at APPLICATION priority so they win over the GTK default
// theme but still sit below the inline popover provider used for transparency.
function _readLauncherBorderColor() {
    // 1. Try reading from config.js (updated by dock-border.sh)
    try {
        const configPath = GLib.build_filenamev([SCRIPT_DIR, 'config.js']);
        const [ok, raw] = GLib.file_get_contents(configPath);
        if (ok) {
            const text = new TextDecoder().decode(raw);
            const m = text.match(/borderColorVar:\s*['"]([a-zA-Z0-9_]+)['"]/);
            if (m && m[1]) return m[1];
        }
    } catch (_) { }
    // 2. Try reading from style.css
    try {
        const stylePath = GLib.build_filenamev([SCRIPT_DIR, 'style.css']);
        const [ok, raw] = GLib.file_get_contents(stylePath);
        if (ok) {
            const text = new TextDecoder().decode(raw);
            const m = text.match(/border-color:\s*@([a-zA-Z0-9_]+)/);
            if (m && m[1]) return m[1];
        }
    } catch (_) { }
    return 'source_color';
}

function buildLauncherCSS() {
    const r = LauncherConfig.borderRadius || 20;
    const bw = LauncherConfig.borderWidth || 2;
    const sr = LauncherConfig.searchRadius ?? LauncherConfig.innerRadius ?? 12;
    const lr = LauncherConfig.listRadius ?? LauncherConfig.innerRadius ?? 12;
    const ib = LauncherConfig.innerBorderWidth || 1;
    const ip = LauncherConfig.innerPadding || 10;
    const bc = _readLauncherBorderColor();

    return `

* {
    font-family: 'FantasqueSansM Nerd Font Mono Regular', 'FantasqueSansM Nerd Font Mono', monospace;
}

/* ── Window shell ─────────────────────────────────────────────────────── */
window.hyprcandy-launcher {
    background-color: @blur_background;
    border-radius: ${r}px;
    border-style: solid;
    border-width: ${bw}px;
    border-color: @${bc};
    margin: 8px;
}

/* ── Inner section frames (rofi inputbar / listbox equivalent) ────────── */
/* .search-frame wraps the search bar; .list-frame wraps the app grid.
   Both have @primary border + @blur_background fill, padded from the
   window edge — matching rofi's inputbar/listbox visual structure.
   NOTE: left/right margin on .search-frame is set in JS (search width).
   No padding here — the border sits flush against the SearchEntry.       */

.search-frame {
    background-color: alpha(@inverse_primary, 0.85);
    border-radius: ${sr}px;
    border-style: solid;
    border-width: 0px;
    border-color: @scrim;
    margin: 0px;
}

.list-frame {
    background-color: @blur_background8;
    border-radius: ${lr}px;
    border-style: solid;
    border-width: 0px; /*${ib}px;*/
    border-color: @scrim;
    margin: ${Math.round(ip / 2)}px ${ip}px ${ip}px ${ip}px;
}

/* ── Search entry — sits inside .search-frame ─────────────────────────── */
.launcher-search {
    background-color: transparent;
    border-radius: ${sr}px;
    border: none;
    color: @primary;
    caret-color: @primary;
    font-size: 14px;
    padding: 0px 10px;
    min-height: 38px;
    /* Suppress the GTK4 theme focus highlight ring — the .search-frame
       border IS the visual focus indicator for the search area. */
    outline: none;
    box-shadow: none;
}

.launcher-search:focus,
.launcher-search:focus-within {
    background-color: alpha(@primary, 0.05);
    outline: none;
    box-shadow: none;
    border: none;
}

.launcher-search > text,
.launcher-search text {
    background: transparent;
    color: @primary;
}

.launcher-search image {
    color: alpha(@primary, 0.9);
}

/* ── Arrow-key navigation — FlowBoxChild focus/selected state ─────────── */
/* flowboxchild is the GTK node wrapping each item appended to FlowBox.
   :selected fires when the child has keyboard focus in SINGLE/BROWSE mode. */
flowboxchild {
    border-radius: 10px;
    padding: 0;
    margin: 0;
    background: transparent;
    outline: none;
    min-width: ${TILE_WIDTH}px;
    min-height: ${TILE_HEIGHT}px;
}

flowboxchild:selected,
flowboxchild:focus {
    background-color: @inverse_primary;
    outline: none;
    border-radius: 10px;
}

/* Label turns to @primary when the parent child is selected */
flowboxchild:selected .app-tile-label,
flowboxchild:focus .app-tile-label {
    color: @primary;
}

/* The button inside a selected child should stay transparent so the
   flowboxchild background colour shows through unobstructed. */
flowboxchild:selected > button.app-tile,
flowboxchild:focus > button.app-tile {
    background-color: transparent;
    border-color: transparent;
}

/* ── Scroll area — sits inside .list-frame ────────────────────────────── */
.launcher-scroll {
    background: transparent;
    border-radius: ${lr - 1}px;
}
.launcher-scroll undershoot,
.launcher-scroll overshoot {
    background: transparent;
}
.launcher-scroll scrollbar {
    background: transparent;
    padding: 0px;
}
.launcher-scroll scrollbar slider {
    background-color: alpha(@primary, 0.22);
    border-radius: 4px;
    min-width: 4px;
    min-height: 4px;
}
.launcher-scroll scrollbar slider:hover {
    background-color: alpha(@primary, 0.42);
}

/* ── App grid ─────────────────────────────────────────────────────────── */
.launcher-grid {
    background: transparent;
    padding: 6px 10px 12px 10px;
}

/* ── App tiles ────────────────────────────────────────────────────────── */
button.app-tile {
    background: transparent;
    background-color: transparent;
    border-radius: 10px;
    border: 1px solid transparent;
    padding: 0px 6px 20px 6px;
    min-width: ${TILE_WIDTH}px;
    min-height: ${TILE_HEIGHT}px;
    outline: none;
    box-shadow: none;
}

button.app-tile:hover {
    background-color: alpha(@primary, 0.09);
    border-color: alpha(@primary, 0.16);
}

button.app-tile:active {
    background-color: alpha(@inverse_primary, 0.55);
    border-color: @primary;
}

button.app-tile:focus {
    outline: none;
    box-shadow: none;
    border-color: alpha(@primary, 0.3);
}

.app-tile-label {
    color: @surface_tint;
    font-size: ${TEXT_FONT_SIZE}px;
    margin-top: 5px;
}

/* ── Context menu popovers (fallback — inline provider takes priority) ── */
popover.launcher-popover {
    background-color: transparent;
    border: none;
    border-radius: 12px;
    padding: 0px;
    box-shadow: none;
}

popover.launcher-popover > contents {
    background-color: @on_secondary;
    border: 1px solid alpha(@secondary, 0.5);
    border-radius: 12px;
    padding: 0px;
    min-width: 190px;
    box-shadow: 0 4px 14px rgba(0, 0, 0, 0.45);
    color: @primary;
}

popover.launcher-popover > arrow {
    background-color: @on_secondary;
}

popover.launcher-popover > contents separator {
    background-color: alpha(@secondary, 0.6);
    min-height: 1px;
}

popover.launcher-popover .pop-item {
    background: transparent;
    background-color: transparent;
    color: @primary;
    padding: 7px 14px;
    border-radius: 6px;
    border: none;
    box-shadow: none;
    font-size: 13px;
}

popover.launcher-popover .pop-item:hover {
    background-color: alpha(@primary, 0.11);
}

popover.launcher-popover .pop-section-header {
    font-size: 11px;
    font-weight: bold;
    color: @inverse_primary;
    padding: 5px 14px 2px 14px;
}

popover.launcher-popover button {
    background: none;
    background-color: transparent;
    border: none;
    box-shadow: none;
    min-width: 0;
    min-height: 0;
    padding: 0;
    margin: 0;
    outline: none;
}

/* ── Favorites section ────────────────────────────────────────────────── */
.fav-section-row {
    background: transparent;
    padding: 6px 12px 2px 12px;
}

/* Collapse toggle — inherits no button chrome, just the glyph label */
.fav-toggle-btn {
    background: transparent;
    background-color: transparent;
    border: none;
    box-shadow: none;
    padding: 0;
    margin: 0;
    min-width: 0;
    min-height: 0;
    outline: none;
}
.fav-toggle-btn:hover {
    background-color: alpha(@primary, 0.10);
    border-radius: 4px;
}

.fav-glyph {
    color: @color2;
    font-size: ${Math.round(TEXT_FONT_SIZE * 1.27)}px;
    margin-right: 4px;
}

.fav-section-label {
    color: @primary;
    font-size: ${TEXT_FONT_SIZE}px;
    font-weight: bold;
}

.fav-separator {
    background-color: alpha(@primary, 0.25);
    margin-left: 12px;
    margin-right: 12px;
    margin-top: 2px;
    margin-bottom: 2px;
}

/* ── Group drop-target hover highlight ────────────────────────────── */
.launcher-grid.drag-target-hover {
    background-color: alpha(@primary, 0.08);
    border-radius: 10px;
    outline: 2px dashed alpha(@primary, 0.40);
    outline-offset: -2px;
}

/* ── New-group naming dialog ──────────────────────────────────────── */
window.hyprcandy-group-dialog {
    background-color: @inverse_primary;
    border-radius: 16px;
    border-style: solid;
    border-width: 1px;
    border-color: alpha(@primary, 0.30);
}

/* ── Running-app dot indicators (overlaid on tile) ───────────────────── */
#launcher-indicator-dots {
    color: @color3;
}

/* ── Tab sidebar pill ────────────────────────────────────────────────── */
/* The pill lives inside .list-frame, vertically centred on the left.
   It has no border of its own — .list-frame provides the outer border.
   pillWrap margin-start: 2px  → 2px from the list-frame left inner edge.
   pillWrap margin-end:   2px  → 2px gap between pill and stack content.  */
.tab-pill {
    background-color: alpha(@inverse_primary, 0.75);
    border-radius: 30px;
    border: 1px solid alpha(@scrim, 1.00);
    padding: 1px 0;
    min-width: 44px;
}

/* Perfect-circle tab buttons.
   GTK4 may give unequal width/height if we only set CSS — we also call
   set_size_request(36,36) in JS to lock the allocation.                  */
.tab-btn {
    background: transparent;
    background-color: transparent;
    border: none;
    box-shadow: none;
    border-radius: 50%;
    padding: 0;
    margin: 4px 4px;
    min-width: 36px;
    min-height: 36px;
    outline: none;
}

.tab-btn:hover {
    background-color: alpha(@on_secondary, 0.65);
}

.tab-btn.active {
    background-color: alpha(@surface_tint, 0.8);
}

.tab-btn:active {
    background-color: alpha(@surface_tint, 0.25);
}

/* Glyph label — same fixed size as button so it never widens the circle. */
.tab-glyph {
    font-family: 'FantasqueSansM Nerd Font Mono Regular', 'FantasqueSansM Nerd Font Mono', 'NerdFontsSymbols Nerd Font', 'Symbols Nerd Font Mono', monospace;
    color: @color3;
    font-size: 30px;
    min-width: 36px;
    min-height: 36px;
}

.tab-btn.active .tab-glyph {
    color: @on_secondary;
}

/* ── Clipboard tab ───────────────────────────────────────────────────── */
.clip-item-btn {
    background: transparent;
    background-color: transparent;
    border: 1px solid transparent;
    border-radius: 30px;
    padding: 8px 12px;
    outline: none;
    box-shadow: none;
}
.clip-item-btn:hover {
    border-color: alpha(@color3, 0.18);
    background-color: alpha(@primary, 0.07);
}
.clip-item-btn:active {
    background-color: alpha(@inverse_primary, 0.5);
}
.clip-item-label {
    color: @on_surface;
    font-size: 12px;
}
.clip-clear-btn {
    background-color: alpha(@color3, 0.3); 
    border: 1px solid alpha(@color3, 0.8);
    border-radius: 20px;
    padding: 3px 12px;
    color: @primary;
    font-size: 12px;
    outline: none;
    box-shadow: none;
    min-height: 28px;
}
.clip-clear-btn:hover {
    background-color: alpha(@color3, 0.6);
}
.clip-clear-btn:active {
    background-color: alpha(@inverse_primary, 0.6);
}
.clip-empty-label {
    color: alpha(@primary, 0.45);
    font-size: 13px;
    padding: 30px 20px;
}

/* ── Emoji tab ───────────────────────────────────────────────────────── */
/* Mode toggle row */
.emoji-mode-btn {
    background: transparent;
    background-color: alpha(@primary, 0.15);
    border: 1px solid alpha(@primary, 0.3);
    border-radius: 20px;
    padding: 3px 12px;
    color: @primary;
    font-size: 11px;
    font-weight: bold;
    outline: none;
    box-shadow: none;
    min-height: 28px;
}
.emoji-mode-btn:hover {
    background-color: alpha(@primary, 0.25);
    border-color: alpha(@primary, 0.3);
    color: @primary;
}
.emoji-mode-btn:active {
    background-color: alpha(@inverse_primary, 0.45);
}
.emoji-mode-btn.active {
    border-color: alpha(@color3, 0.8);
    background-color: alpha(@color3, 0.3);
    color: @primary;
}
.emoji-mode-btn.active:hover {
    background-color: alpha(@color3, 0.6);
}
.emoji-btn {
    background: transparent;
    background-color: transparent;
    border: none;
    border-radius: 8px;
    padding: 4px;
    min-width: 42px;
    min-height: 42px;
    outline: none;
    box-shadow: none;
    font-size: 22px;
}
.emoji-btn:hover {
    background-color: alpha(@primary, 0.1);
    border-color: alpha(@primary, 0.25);
}
.emoji-btn:active {
    background-color: alpha(@inverse_primary, 0.5);
}
/* Nerd glyph buttons — same layout as emoji but use NF font */
.nerd-btn {
    background: transparent;
    background-color: transparent;
    border: none;
    border-radius: 8px;
    padding: 4px;
    min-width: 42px;
    min-height: 42px;
    outline: none;
    box-shadow: none;
    font-family: 'FantasqueSansM Nerd Font Mono Regular', 'FantasqueSansM Nerd Font Mono', 'NerdFontsSymbols Nerd Font', 'Symbols Nerd Font Mono', monospace;
    font-size: 35px;
    color: @primary;
}
.nerd-btn:hover {
    background-color: alpha(@primary, 0.1);
    border-color: alpha(@primary, 0.25);
}
.nerd-btn:active {
    background-color: alpha(@inverse_primary, 0.45);
}
/* Category bar buttons — NF font so glyph previews render in nerd mode */
.emoji-cat-btn {
    background: transparent;
    background-color: transparent;
    border: none;
    border-radius: 6px;
    padding: 2px 8px;
    color: @primary;
    font-size: 25px;
    min-height: 34px;
    outline: none;
    box-shadow: none;
    font-family: 'FantasqueSansM Nerd Font Mono Regular', 'FantasqueSansM Nerd Font Mono', 'NerdFontsSymbols Nerd Font', 'Symbols Nerd Font Mono', emoji, monospace;
}
.emoji-cat-btn.active {
    background-color: alpha(@inverse_primary, 0.45);
    color: @primary;
}
.emoji-cat-btn:hover {
    background-color: alpha(@primary, 0.08);
    color: @primary;
}
.emoji-copied-bar {
    background-color: alpha(@inverse_primary, 0.85);
    border-radius: 8px;
    padding: 5px 14px;
    margin: 0 ${ip}px 4px ${ip}px;
}
.emoji-copied-label {
    color: @primary;
    font-size: 12px;
}

/* ── SearXNG web search tab ─────────────────────────────────────────── */

/* Header row: title glyph + Docker toggle button */
.searx-header-row {
    background: transparent;
    padding: 0px;
    margin: 0px;
}
.searx-title-btn {
    background: transparent;
    background-color: transparent;
    border: none;
    border-radius: 8px;
    padding: 2px 6px;
    outline: none;
    box-shadow: none;
}
.searx-title-btn:hover {
    background-color: alpha(@primary, 0.12);
}
.searx-title-btn:active {
    background-color: alpha(@inverse_primary, 0.40);
}
.searx-title-glyph {
    font-family: 'FantasqueSansM Nerd Font Mono Regular', 'FantasqueSansM Nerd Font Mono', 'NerdFontsSymbols Nerd Font', monospace;
    color: @color3;
    font-size: 20px;
    margin-right: 6px;
}
.searx-title-label {
    color: @primary;
    font-size: 13px;
    font-weight: bold;
}

/* Docker power toggle button */
.searx-docker-btn {
    background: transparent;
    background-color: alpha(@primary, 0.15);
    border: 1px solid alpha(@primary, 0.3);
    border-radius: 20px;
    padding: 3px 12px;
    outline: none;
    box-shadow: none;
    min-height: 28px;
}
.searx-docker-btn:hover {
    background-color: alpha(@primary, 0.25);
    border-color: alpha(@primary, 0.3);
}
.searx-docker-btn:active {
    background-color: alpha(@inverse_primary, 0.45);
}
/* Running state: green-ish highlight */
.searx-docker-btn.docker-on {
    border-color: alpha(@color3, 0.8);
    background-color: alpha(@color3, 0.3);
}
.searx-docker-btn.docker-on:hover {
    background-color: alpha(@color3, 0.6);
}
/* Stopped state: subtly dimmed */
.searx-docker-btn.docker-off {
    background: transparent;
    background-color: alpha(@primary, 0.15);
    border: 1px solid alpha(@primary, 0.3);
    color: alpha(@primary, 0.55);
}
.searx-docker-glyph {
    font-family: 'FantasqueSansM Nerd Font Mono Regular', 'FantasqueSansM Nerd Font Mono', 'NerdFontsSymbols Nerd Font', monospace;
    font-size: 16px;
    color: @primary;
    margin-right: 5px;
}
.searx-docker-btn.docker-off .searx-docker-glyph {
    color:  @primary;
}
.searx-docker-label {
    color: @primary;
    font-size: 12px;
}
.searx-docker-btn.docker-off .searx-docker-label {
    color: alpha(@primary, 0.55);
}

/* Status / info card (offline, loading, empty) */
.searx-status-card {
    background-color: alpha(@inverse_primary, 0.18);
    border-radius: 14px;
    border: 1px solid alpha(@primary, 0.12);
    margin: 20px ${ip}px 10px ${ip}px;
    padding: 22px 18px;
}
.searx-status-glyph {
    font-family: 'FantasqueSansM Nerd Font Mono Regular', 'FantasqueSansM Nerd Font Mono', 'NerdFontsSymbols Nerd Font', monospace;
    font-size: 36px;
    color: alpha(@primary, 0.50);
    margin-bottom: 8px;
}
.searx-status-title {
    color: @primary;
    font-size: 13px;
    font-weight: bold;
    margin-bottom: 4px;
}
.searx-status-body {
    color: alpha(@primary, 0.60);
    font-size: 11px;
    margin-bottom: 12px;
}
.searx-action-btn {
    background-color: alpha(@primary, 0.15);
    border: 1px solid alpha(@primary, 0.40);
    border-radius: 8px;
    padding: 6px 18px;
    color: @primary;
    font-size: 12px;
    font-weight: bold;
    outline: none;
    box-shadow: none;
    margin-top: 4px;
}
.searx-action-btn:hover {
    background-color: alpha(@primary, 0.28);
    border-color: @primary;
}
.searx-action-btn:active {
    background-color: alpha(@inverse_primary, 0.55);
}

.searx-fallback-btn {
    background: transparent;
    background-color: transparent;
    border: 1px solid alpha(@primary, 0.30);
    border-radius: 8px;
    padding: 5px 14px;
    color: @primary;
    font-size: 12px;
    outline: none;
    box-shadow: none;
    margin-top: 4px;
}
.searx-fallback-btn:hover {
    background-color: alpha(@primary, 0.10);
}

/* ── New Tab & Header Tabs Buttons ───────────────────────────────────── */
.searx-header-tabs-btn {
    background: transparent;
    background-color: alpha(@primary, 0.09);
    border: 1px solid alpha(@primary, 0.15);
    border-radius: 30px;
    padding: 3px 10px;
    margin-right: 6px;
    outline: none;
    box-shadow: none;
}
.searx-header-tabs-btn:hover {
    background-color: alpha(@primary, 0.15);
    border-color: alpha(@primary, 0.3);
}
.searx-header-tabs-btn:active {
    background-color: alpha(@inverse_primary, 0.65);
}
.searx-header-tabs-glyph {
    color: @primary;
    font-size: 13px;
    margin-right: 5px;
}
.searx-header-tabs-label {
    color: @primary;
    font-size: 11px;
    font-weight: bold;
}
.searx-newtab-btn {
    background: transparent;
    background-color: alpha(@primary, 0.15);
    border: 1px solid alpha(@primary, 0.3);
    border-radius: 30px;
    padding: 3px 10px;
    margin-right: 6px;
    outline: none;
    box-shadow: none;
}
.searx-newtab-btn:hover {
    background-color: alpha(@primary, 0.25);
    border-color: alpha(@primary, 0.3);
}
.searx-newtab-btn:active {
    background-color: alpha(@inverse_primary, 0.70);
}
.searx-newtab-glyph {
    color: @primary;
    font-size: 13px;
    margin-right: 4px;
}
.searx-newtab-label {
    color: @primary;
    font-size: 11px;
    font-weight: bold;
}

/* ── WebKit embedded webview container (12px rounded) ────────────────── */
.searx-webview-box {
    border-radius: 12px;
    margin-right: 10px;
    margin-left: 6px;
    margin-bottom: 12px;
}
.searx-webview-wrap {
    border-radius: 12px;
}
.searx-webview-wrap webview,
webview.searx-webview {
    border-radius: 12px;
}

/* ── Agent WebKit embedded webview container (16px rounded) ───────────── */
.agent-webview-box {
    border-radius: 10px;
    margin-top: 12px;
    margin-bottom: 12px;
    margin-right: 10px;
    margin-left: 6px;
}
.agent-webview-wrap {
    border-radius: 16px;
}
.agent-webview-wrap webview,
webview.agent-webview,
.agent-webview {
    border-radius: 10px;
    background-color: transparent;
}
.agent-header-row {
    margin-left: 6px;
}
.agent-llama-btn {
    background: transparent;
    background-color: alpha(@primary, 0.15);
    border: 1px solid alpha(@primary, 0.3);
    border-radius: 20px;
    padding: 3px 12px;
    outline: none;
    box-shadow: none;
    min-height: 28px;
}
.agent-llama-btn:hover {
    background-color: alpha(@primary, 0.25);
    border-color: alpha(@primary, 0.3);
}
.agent-llama-btn:active {
    background-color: alpha(@inverse_primary, 0.45);
}
.agent-llama-btn.agent-llama-on {
    background-color: alpha(@color3, 0.3);
    border-color: alpha(@color3, 0.8);
}
.agent-llama-btn.agent-llama-on:hover {
    background-color: alpha(@color3, 0.6);
    border-color: alpha(@color3, 0.8);
}
.agent-llama-btn.agent-llama-off {
    background: transparent;
    background-color: alpha(@primary, 0.15);
    border: 1px solid alpha(@primary, 0.3);
    color: alpha(@primary, 0.55);
}
.agent-llama-btn.agent-llama-off:hover {
    background-color: alpha(@primary, 0.25);
    border-color: alpha(@primary, 0.3);
}
.agent-llama-glyph {
    font-family: 'FantasqueSansM Nerd Font Mono Regular', 'FantasqueSansM Nerd Font Mono', 'NerdFontsSymbols Nerd Font', monospace;
    font-size: 16px;
    color: @primary;
    margin-right: 5px;
}
.agent-llama-btn.agent-llama-off .agent-llama-glyph {
    color: @primary;
}
.agent-llama-label {
    color: @primary;
    font-size: 12px;
}
.agent-llama-btn.agent-llama-off .agent-llama-label {
    color: alpha(@primary, 0.55);
}
.agent-title-btn {
    border-radius: 8px;
    padding: 3px 8px;
    background-color: alpha(@secondary_container, 0.5);
    border: 1px solid alpha(@outline_variant, 0.4);
}
.agent-title-btn:hover {
    background-color: alpha(@secondary_container, 0.85);
}
.agent-title-glyph {
    color: @primary;
    font-size: 15px;
}
.agent-title-label {
    color: @on_surface;
    font-size: 12px;
    font-weight: bold;
}


/* ── Interactive Web Toolbar Title + URL + Tabs Trigger ──────────────── */
.searx-webview-bar {
    padding: 2px 4px 3px 4px;
    margin-bottom: 2px;
    /* Smoothly fade out instead of jump-cutting when a page requests
       native fullscreen (see 'enter-fullscreen'/'leave-fullscreen' in
       _createTabWebView) — opacity is one of the few properties GTK4's
       CSS engine actually animates on a plain Box. */
    opacity: 1;
    transition: opacity 180ms ease;
}
.searx-webview-bar.fullscreen-hidden {
    opacity: 1;
}
/* Gentle cross-fade while a tab is navigating/reloading, instead of the
   page abruptly popping from blank to fully painted. Toggled from the
   'load-changed' handler in _createTabWebView. */
.searx-webview-wrap {
    opacity: 1;
    transition: opacity 160ms ease;
}
.searx-webview-wrap.page-loading {
    opacity: 0.55;
}
.searx-nav-btn {
    background: transparent;
    background-color: alpha(@inverse_primary, 0.40);
    border: 1px solid alpha(@primary, 0.25);
    border-radius: 20px;
    padding: 3px 10px;
    color: @primary;
    font-size: 11px;
    font-weight: bold;
    outline: none;
    box-shadow: none;
}
.searx-nav-btn:hover {
    background-color: alpha(@primary, 0.18);
    border-color: alpha(@primary, 0.45);
}
.searx-nav-btn:active {
    background-color: alpha(@inverse_primary, 0.70);
}
.searx-nav-circle-btn {
    background: transparent;
    background-color: alpha(@inverse_primary, 0.40);
    border: 1px solid alpha(@primary, 0.25);
    border-radius: 50%;
    padding: 0;
    margin: 0 2px;
    min-width: 26px;
    min-height: 26px;
    color: @primary;
    font-size: 13px;
    outline: none;
    box-shadow: none;
}
.searx-nav-circle-btn:hover {
    background-color: alpha(@primary, 0.22);
    border-color: alpha(@primary, 0.50);
}
.searx-nav-circle-btn:active {
    background-color: alpha(@inverse_primary, 0.75);
}
.searx-nav-circle-btn.close:hover {
    background-color: alpha(@error, 0.28);
    border-color: alpha(@error, 0.60);
    color: @error;
}
.searx-nav-info-btn {
    background: transparent;
    background-color: transparent;
    border: 1px solid transparent;
    border-radius: 10px;
    padding: 2px 8px;
    outline: none;
    box-shadow: none;
}
.searx-nav-info-btn:hover {
    background-color: alpha(@primary, 0.12);
    border-color: alpha(@primary, 0.25);
}
.searx-nav-info-btn:active {
    background-color: alpha(@inverse_primary, 0.40);
}
.searx-tabs-badge {
    background-color: alpha(@primary, 0.20);
    color: @primary;
    border-radius: 10px;
    font-size: 9px;
    font-weight: bold;
    padding: 1px 5px;
    margin-left: 6px;
}
.searx-tabs-chevron {
    color: alpha(@primary, 0.60);
    font-size: 11px;
    margin-left: 4px;
}

/* ── Tabs Popover List ────────────────────────────────────────────────── */
.searx-tab-row {
    background: transparent;
    background-color: transparent;
    border: 1px solid transparent;
    border-radius: 12px;
    padding: 6px 8px;
    margin: 2px 0;
}
.searx-tab-row:hover {
    background-color: alpha(@primary, 0.12);
}
.searx-tab-row.active {
    background-color: alpha(@primary, 0.20);
    border-color: alpha(@primary, 0.35);
}
.searx-tab-glyph {
    color: @primary;
    font-size: 14px;
    margin-right: 8px;
}
.searx-tab-title {
    color: @primary;
    font-size: 12px;
    font-weight: bold;
}
.searx-tab-url {
    color: alpha(@color3, 0.85);
    font-size: 10px;
}
.searx-tab-close-btn {
    background: transparent;
    background-color: transparent;
    border: none;
    border-radius: 6px;
    padding: 2px 6px;
    color: alpha(@primary, 0.55);
    font-size: 11px;
    outline: none;
    box-shadow: none;
}
.searx-tab-close-btn:hover {
    background-color: alpha(@error, 0.25);
    color: @error;
}

/* Individual result rows */
.searx-result-item {
    background: transparent;
    background-color: transparent;
    border: 1px solid transparent;
    border-radius: 99px;
    padding: 8px 12px;
    outline: none;
    box-shadow: none;
    margin: 1px 0;
}
.searx-result-item:hover {
    border-color: alpha(@color3, 0.18);
    background-color: alpha(@primary, 0.07);
}
.searx-result-item:active {
    background-color: alpha(@inverse_primary, 0.45);
}
.searx-result-title {
    color: @primary;
    font-size: 13px;
    font-weight: bold;
}
.searx-result-url {
    color: alpha(@color3, 0.80);
    font-size: 10px;
    margin-top: 1px;
}
.searx-result-snippet {
    color: alpha(@on_surface, 0.75);
    font-size: 11px;
    margin-top: 3px;
}

/* Thin separator between results */
listbox.searx-list row {
    background: transparent;
    padding: 0;
}
listbox.searx-list row:selected {
    background-color: alpha(@inverse_primary, 0.35);
    border-radius: 10px;
}
listbox.searx-list row:focus {
    outline: none;
}


/*Webkit-wrap*/
.searx-webview-wrap {
    border-radius: 12px;
}

/* ── Bookmarks ─────────────────────────────────────────────────────── */
/* Header toggle button — same visual as searx-docker-btn */
.searx-bookmarks-btn {
    background: transparent;
    background-color: alpha(@primary, 0.15);
    border: 1px solid alpha(@primary, 0.3);
    border-radius: 20px;
    padding: 3px 12px;
    outline: none;
    box-shadow: none;
    min-height: 28px;
}
.searx-bookmarks-btn:hover {
    background-color: alpha(@primary, 0.25);
    border-color: alpha(@primary, 0.3);
}
.searx-bookmarks-btn:active {
    background-color: alpha(@inverse_primary, 0.45);
}
.searx-bookmarks-glyph {
    font-family: 'FantasqueSansM Nerd Font Mono Regular', 'FantasqueSansM Nerd Font Mono', 'NerdFontsSymbols Nerd Font', monospace;
    font-size: 15px;
    color: @primary;
    margin-right: 5px;
}
.searx-bookmarks-label {
    color: @primary;
    font-size: 12px;
}
/* Inline add/remove bookmark button on result rows and webview toolbar */
.searx-bookmark-add-btn {
    background: transparent;
    background-color: transparent;
    border: 1px solid transparent;
    border-radius: 50%;
    padding: 0;
    margin: 0 2px;
    min-width: 26px;
    min-height: 26px;
    color: alpha(@primary, 0.55);
    font-size: 14px;
    font-family: 'FantasqueSansM Nerd Font Mono Regular', 'FantasqueSansM Nerd Font Mono', 'NerdFontsSymbols Nerd Font', monospace;
    outline: none;
    box-shadow: none;
}
.searx-bookmark-add-btn:hover {
    background-color: alpha(@primary, 0.12);
    border-color: alpha(@primary, 0.30);
    color: @primary;
}
.searx-bookmark-add-btn.bookmarked {
    color: @primary;
    border-color: alpha(@primary, 0.35);
    background-color: alpha(@inverse_primary, 0.25);
}
.searx-bookmark-add-btn.bookmarked:hover {
    background-color: alpha(@error, 0.20);
    border-color: alpha(@error, 0.45);
    color: @error;
}
/* Popover bookmark rows */
.searx-bookmark-pop-row {
    border-radius: 8px;
    padding: 1px 0;
}
.searx-bookmark-pop-row:hover {
    background-color: alpha(@primary, 0.07);
}
.searx-bookmark-pop-open-btn {
    background: transparent;
    background-color: transparent;
    border: none;
    border-radius: 8px;
    padding: 5px 8px;
    outline: none;
    box-shadow: none;
}
.searx-bookmark-pop-open-btn:hover {
    background-color: alpha(@primary, 0.09);
}
.searx-bookmark-pop-remove-btn {
    background: transparent;
    background-color: transparent;
    border: none;
    border-radius: 50%;
    padding: 0;
    margin: 0 4px;
    min-width: 22px;
    min-height: 22px;
    color: alpha(@primary, 0.45);
    font-size: 12px;
    outline: none;
    box-shadow: none;
}
.searx-bookmark-pop-remove-btn:hover {
    background-color: alpha(@error, 0.22);
    color: @error;
}
`;
}

// Inline popover provider — same pattern the dock uses to fix GTK4 popover
// transparency on Wayland (popover > contents needs an explicit bg rule).
const POPOVER_INLINE_CSS = `
popover.launcher-popover {
    background-color: transparent;
    border: none;
    border-radius: 12px;
}
popover.launcher-popover > contents {
    background-color: @on_secondary;
    border-radius: 12px;
    border: 1px solid alpha(@secondary, 0.5);
    box-shadow: 0 4px 14px rgba(0, 0, 0, 0.45);
    color: @primary;
}
popover.launcher-popover > arrow {
    background-color: @on_secondary;
}
popover.launcher-popover > contents separator {
    background-color: alpha(@secondary, 0.6);
    min-height: 1px;
}
popover.launcher-popover .pop-item {
    background: transparent;
    background-color: transparent;
    color: @primary;
    padding: 7px 14px;
    border-radius: 6px;
    border: none;
    box-shadow: none;
    font-size: 13px;
}
popover.launcher-popover .pop-item:hover {
    background-color: alpha(@primary, 0.11);
}
popover.launcher-popover .pop-section-header {
    font-size: 11px;
    font-weight: bold;
    color: @inverse_primary;
    padding: 5px 14px 2px 14px;
}
popover.launcher-popover button {
    background: none;
    background-color: transparent;
    border: none;
    box-shadow: none;
    min-width: 0;
    min-height: 0;
    padding: 0;
    margin: 0;
    outline: none;
}
`;

// ── AppLauncherWindow ──────────────────────────────────────────────────────

const AppLauncherWindow = GObject.registerClass({
    GTypeName: 'HyprCandyAppLauncherWindow',
}, class AppLauncherWindow extends Gtk.Window {

    constructor(application) {
        super({ title: 'HyprCandy Launcher', decorated: false, application });

        this._dockPos = readDockPos();
        this._isVert = (this._dockPos === 'left' || this._dockPos === 'right');
        this._allApps = [];           // populated lazily on first show
        this._pinnedSet = readPinnedApps();
        this._favoritesSet = readFavorites();
        this._runningApps = getRunningApps();
        this._popoverCSS = null;
        this._popoverOpen = false;
        this._postPopoverGrace = false;
        this._graceTimer = 0;
        // Guards the empty-space/background click-to-close logic against
        // false positives caused by embedded WebKit views: set while any
        // WebView is transitioning to/from native fullscreen, or briefly
        // after a WebView requests a popup/permission/dialog, so a stray
        // pick()/click during that churn never hides the whole launcher.
        this._webviewBusy = false;
        this._webviewBusyTimer = 0;
        this._pendingFavRefreshQuery = undefined;
        this._pendingGroupRefresh = false;   // set by group menu handler; consumed by closed handler
        this._colorMonitor = null;   // Gio.FileMonitor for gtk-4.0/colors.css
        this._colorReloadTimer = 0;      // debounce source ID
        this._groupDragClass = null;   // className being dragged into/within a group
        this._appDirMonitors = [];     // Gio.FileMonitor[] for XDG application directories
        this._appDirReloadTimer = 0;      // debounce source ID for app-dir changes
        this._appsDirty = false;  // true when app directories changed while hidden
        // ── SearXNG search tab state ────────────────────────────────────
        const savedState = readLauncherWebState();
        // Cold start (fresh process — Hyprland session startup, or after a
        // hard-kill) always opens on the Launcher tab, regardless of which
        // tab was active before the process died. This only runs once, in
        // the constructor, when a brand-new process boots — it does NOT
        // affect SIGUSR1 show/hide toggles while this daemon process keeps
        // running (those correctly read the in-memory this._win._lastTab
        // set by _switchTab(), further down, and are unaffected by this).
        this._lastTab = 'launcher';
        this._searxDockerRunning = false;  // last known Docker container state
        this._searxDockerStarting = false; // true while searxng-control.sh start is in flight
        this._searxSearchTimer = 0;      // debounce GLib source ID for queries
        this._soupSession = null;   // lazy-initialised Soup.Session
        this._searxLastQuery = savedState.searxLastQuery || '';
        this._searxWebView = null;   // active WebKit.WebView
        this._searxCurrentWebUrl = savedState.searxCurrentWebUrl || '';
        this._searxNavTitleText = savedState.searxNavTitle || '';
        this._searxWebBoxOpen = !!savedState.searxWebBoxOpen;
        this._searxTabs = [];     // array of { id, url, title, webView, webWrap }
        this._searxActiveTabId = savedState.searxActiveTabId || null;
        this._searxPendingNewTab = false;  // when true, next search result opens in new tab
        this._searxSavedTabs = savedState.searxTabs || [];
        this._searxBookmarks = savedState.searxBookmarks || [];   // [{title, url}]
        this._agentWorkspaceBtn = null;
        this._agentWorkspaceGlyph = null;
        this._agentWorkspaceLabel = null;
        this._agentLlamaBtn = null;
        this._agentLlamaGlyph = null;
        this._agentLlamaLabel = null;
        this._agentLlamaRunning = false;
        this._agentLlamaStarting = false;
        this._agentLlamaEnabled = false;
        this._workspaceStartupEnabled = readWorkspaceStartupState();
        this._agentWebView = null;
        this._agentHttpServer = null;
        this._agentHttpPort = 0;
        // Host replies must return to the renderer that made the request:
        // visible WebKitGTK for UI requests, hidden Electron for inference
        // renderer requests.  Without this map, the old Electron-first reply
        // path leaves WebKit promises pending forever.
        this._agentReplyTargets = new Map();

        this._loadGlobalCSS();
        this._setupLayerShell();
        this._buildUI();
        this._agentCheckLlamaStatus((running) => {
            this._agentLlamaRunning = !!running;
            this._agentLlamaEnabled = !!running;
            this._agentUpdateLlamaBtn();
        });
        this._setupKeyboard();
        this._setupFocusClose();
        this._setupColorMonitor();
        this._setupAppDirMonitors();

        // Daemon mode: close() must hide the window rather than destroy it,
        // so the process stays alive between toggles and all state is preserved.
        this.set_hide_on_close(true);

        this.connect('destroy', () => {
            this._teardownColorMonitor();
            this._teardownAppDirMonitors();
            if (this._agentHttpServer) {
                try { this._agentHttpServer.disconnect(); } catch (_) { }
                this._agentHttpServer = null;
                this._agentHttpPort = 0;
            }
            // Gracefully terminate the embedded Electron agent renderer so it
            // doesn't persist as a zombie after launcher is destroyed (we
            // use Gio.Subprocess so it IS a child of the launcher process,
            // but we still request clean shutdown via quit message so the
            // Chromium user-data-dir IndexedDB model caches are flushed).
            if (this._agentElectronProc && !this._agentElectronExited) {
                try {
                    const quitMsg = JSON.stringify({ type: 'quit' }) + '\n';
                    try {
                        const stdinP = this._agentElectronProc.get_stdin_pipe();
                        if (stdinP) stdinP.write_all(new TextEncoder().encode(quitMsg), null);
                    } catch (_) { }
                    GLib.timeout_add(GLib.PRIORITY_DEFAULT, 500, () => {
                        try {
                            if (this._agentElectronProc && !this._agentElectronExited) {
                                this._agentElectronProc.force_exit();
                            }
                        } catch (_) { }
                        return GLib.SOURCE_REMOVE;
                    });
                } catch (_) { }
                this._agentElectronProc = null;
                this._agentElectronStdin = null;
            }
            // Write "closed" to launcher.state so dock autohide is never left
            // permanently suppressed if the launcher exits while visible.
            try {
                const stateDir = GLib.build_filenamev([HOME, '.cache', 'hyprcandy']);
                const statePath = GLib.build_filenamev([stateDir, 'launcher.state']);
                GLib.file_set_contents(statePath, new TextEncoder().encode('closed\n'));
            } catch (_) { }
            // Null the module-level running-apps cache so the next launcher
            // instance starts with a fresh query rather than stale data.
            _runningAppsCache = null;
            _runningAppsCacheUs = 0;
        });
        this.add_css_class('hyprcandy-launcher');
    }

    // ─── CSS ────────────────────────────────────────────────────────────

    _loadGlobalCSS() {
        const display = Gdk.Display.get_default();

        // Load matugen colors (same paths the dock uses) so @primary etc. resolve
        const paths = [
            GLib.build_filenamev([HOME, '.config', 'gtk-3.0', 'colors.css']),
            GLib.build_filenamev([HOME, '.config', 'gtk-4.0', 'colors.css']),
        ];
        for (const p of paths) {
            if (!GLib.file_test(p, GLib.FileTest.EXISTS)) continue;
            const prov = new Gtk.CssProvider();
            try {
                prov.load_from_path(p);
                Gtk.StyleContext.add_provider_for_display(
                    display, prov, Gtk.STYLE_PROVIDER_PRIORITY_USER
                );
            } catch (_) { }
        }

        // Launcher-specific rules (built dynamically from LauncherConfig & live border color)
        if (!this._launcherCSSProv) {
            this._launcherCSSProv = new Gtk.CssProvider();
            Gtk.StyleContext.add_provider_for_display(
                display, this._launcherCSSProv, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
        }
        try {
            this._launcherCSSProv.load_from_data(buildLauncherCSS(), -1);
        } catch (e) { console.error('[launcher] CSS load failed:', e.message); }
        this._agentInjectTheme();
    }

    _getPopoverCSSProvider() {
        if (!this._popoverCSS) {
            this._popoverCSS = new Gtk.CssProvider();
            try { this._popoverCSS.load_from_data(POPOVER_INLINE_CSS, -1); } catch (_) { }
        }
        return this._popoverCSS;
    }

    // ─── Layer shell ─────────────────────────────────────────────────────

    // ─── Dock thickness query ────────────────────────────────────────────
    // Ask Hyprland for the live rendered height/width of the dock surface so
    // the launcher margin is exact regardless of config edits or innerPadding.
    // Falls back to a formula-based estimate if hyprctl is unavailable.
    _queryDockThick(pos) {
        try {
            const [ok, out] = GLib.spawn_command_line_sync('hyprctl layers -j');
            if (!ok) return null;
            const data = JSON.parse(_dec.decode(out));
            for (const monData of Object.values(data)) {
                for (const surfList of Object.values(monData.levels ?? {})) {
                    for (const s of (Array.isArray(surfList) ? surfList : [])) {
                        if (s.namespace === 'hyprcandy-dock') {
                            // w/h are the actual surface pixel dimensions
                            return (pos === 'left' || pos === 'right') ? s.w : s.h;
                        }
                    }
                }
            }
        } catch (_) { }
        return null;  // caller falls back to formula
    }

    // ─── Shared margin helper ────────────────────────────────────────────
    // Computes the margin (screen-edge → launcher edge) needed to clear the
    // dock, using the live dock size when available.
    _computeMargin(pos) {
        const cfg = DockConfig;
        const iconPx = cfg.appIconSize || 20;
        const borderPx = cfg.borderWidth || 2;
        const padPx = cfg.innerPadding || 0;  // actual value, not hardcoded 4

        // Live dock thickness beats the formula; formula is the fallback.
        const measured = this._queryDockThick(pos);
        const dockThick = measured ?? ((iconPx + 8) + 2 * padPx + 2 * borderPx);

        const ov = cfg.positionOverrides?.[pos] ?? {};
        let edgeMargin;
        if (pos === 'bottom') edgeMargin = ov.marginBottom ?? cfg.marginBottom ?? 6;
        else if (pos === 'top') edgeMargin = ov.marginTop ?? cfg.marginTop ?? 2;
        else if (pos === 'left') edgeMargin = ov.marginLeft ?? cfg.marginLeft ?? 6;
        else edgeMargin = ov.marginRight ?? cfg.marginRight ?? 6;

        return dockThick + edgeMargin + GAP_FROM_DOCK;
    }

    _setupLayerShell() {
        const cfg = DockConfig;
        const pos = this._dockPos;

        Gtk4LayerShell.init_for_window(this);
        Gtk4LayerShell.set_namespace(this, 'hyprcandy-launcher');
        // OVERLAY sits above the dock's TOP layer so it renders on top of the dock.
        Gtk4LayerShell.set_layer(this, Gtk4LayerShell.Layer.OVERLAY);
        // -1 = don't steal screen real-estate from other windows
        Gtk4LayerShell.set_exclusive_zone(this, -1);
        // ON_DEMAND: gets keyboard only when the surface has focus, so other
        // surfaces still receive input (unlike EXCLUSIVE which grabs everything).
        Gtk4LayerShell.set_keyboard_mode(this, Gtk4LayerShell.KeyboardMode.ON_DEMAND);

        // Anchor to ONE edge (the dock's edge).  The compositor will centre the
        // surface on the perpendicular axis because neither opposite anchor is set.
        Gtk4LayerShell.set_anchor(this, Gtk4LayerShell.Edge.BOTTOM, pos === 'bottom');
        Gtk4LayerShell.set_anchor(this, Gtk4LayerShell.Edge.TOP, pos === 'top');
        Gtk4LayerShell.set_anchor(this, Gtk4LayerShell.Edge.LEFT, pos === 'left');
        Gtk4LayerShell.set_anchor(this, Gtk4LayerShell.Edge.RIGHT, pos === 'right');

        // ── Compute margin from the screen edge using live dock size ─────
        const totalMargin = this._computeMargin(pos);

        Gtk4LayerShell.set_margin(this, Gtk4LayerShell.Edge.BOTTOM, pos === 'bottom' ? totalMargin : 0);
        Gtk4LayerShell.set_margin(this, Gtk4LayerShell.Edge.TOP, pos === 'top' ? totalMargin : 0);
        Gtk4LayerShell.set_margin(this, Gtk4LayerShell.Edge.LEFT, pos === 'left' ? totalMargin : 0);
        Gtk4LayerShell.set_margin(this, Gtk4LayerShell.Edge.RIGHT, pos === 'right' ? totalMargin : 0);

        // Window size — wider for horizontal docks, taller for vertical
        if (this._isVert) {
            this.set_size_request(W_VERT, H_VERT);
            this.set_default_size(W_VERT, H_VERT);
        } else {
            this.set_size_request(W_HORIZ, H_HORIZ);
            this.set_default_size(W_HORIZ, H_HORIZ);
        }
    }

    // ─── Live position refresh ───────────────────────────────────────────
    // Called from the SIGUSR1 show path so the launcher re-anchors to the
    // current dock edge even when the dock has cycled since last use.
    // gtk4-layer-shell allows set_anchor / set_margin after init_for_window;
    // the new values take effect on the next Wayland surface commit.

    _refreshLayerShell() {
        const newPos = readDockPos();
        const newVert = (newPos === 'left' || newPos === 'right');

        // Always re-apply anchors/margins (dock may have moved even if pos
        // string is the same, e.g. after a restart with stale dock.pos).
        this._dockPos = newPos;
        this._isVert = newVert;

        // ── Anchors — only the dock edge is anchored; compositor centres
        //             the launcher on the perpendicular axis automatically.
        Gtk4LayerShell.set_anchor(this, Gtk4LayerShell.Edge.BOTTOM, newPos === 'bottom');
        Gtk4LayerShell.set_anchor(this, Gtk4LayerShell.Edge.TOP, newPos === 'top');
        Gtk4LayerShell.set_anchor(this, Gtk4LayerShell.Edge.LEFT, newPos === 'left');
        Gtk4LayerShell.set_anchor(this, Gtk4LayerShell.Edge.RIGHT, newPos === 'right');

        // ── Margin from screen edge (uses live dock size via _computeMargin)
        const totalMargin = this._computeMargin(newPos);
        Gtk4LayerShell.set_margin(this, Gtk4LayerShell.Edge.BOTTOM, newPos === 'bottom' ? totalMargin : 0);
        Gtk4LayerShell.set_margin(this, Gtk4LayerShell.Edge.TOP, newPos === 'top' ? totalMargin : 0);
        Gtk4LayerShell.set_margin(this, Gtk4LayerShell.Edge.LEFT, newPos === 'left' ? totalMargin : 0);
        Gtk4LayerShell.set_margin(this, Gtk4LayerShell.Edge.RIGHT, newPos === 'right' ? totalMargin : 0);

        // ── Window size and FlowBox column counts
        const W = newVert ? W_VERT : W_HORIZ;
        const H = newVert ? H_VERT : H_HORIZ;
        const cols = newVert ? COLS_VERT : COLS_HORIZ;
        this.set_size_request(W, H);
        this.set_default_size(W, H);

        if (this._root) {
            this._root.set_size_request(W, H);
        }
        if (this._searchFrame) {
            const lc = LauncherConfig;
            const ip = lc.innerPadding || 10;
            const frac = Math.min(1, Math.max(0.2, lc.searchWidthFraction ?? 1.0));
            this._searchFrame.set_size_request(Math.max(1, Math.round(W * frac) - (2 * ip)), -1);
        }

        if (this._flow) {
            this._flow.set_max_children_per_line(cols);
            this._flow.set_min_children_per_line(cols);
        }
        if (this._favFlow) {
            this._favFlow.set_max_children_per_line(cols);
            this._favFlow.set_min_children_per_line(cols);
        }
    }

    // ─── Build UI ────────────────────────────────────────────────────────

    _buildUI() {
        const lc = LauncherConfig;
        const winW = this._isVert ? W_VERT : W_HORIZ;
        const ip = lc.innerPadding || 10;
        const frac = Math.min(1, Math.max(0.2, lc.searchWidthFraction ?? 1.0));
        const sfExtraH = Math.max(0, Math.floor((winW - Math.round(winW * frac)) / 2));

        // ── Root: vertical box (search row on top, inner panel below) ────
        const root = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        const winH = this._isVert ? H_VERT : H_HORIZ;
        root.set_size_request(winW, winH);
        this.set_child(root);
        this._root = root;

        // Centered search row using Gtk.CenterBox: left controls, locked center search, right actions.
        const searchRow = new Gtk.CenterBox();
        searchRow.set_orientation(Gtk.Orientation.HORIZONTAL);
        searchRow.set_hexpand(true);
        searchRow.set_margin_start(ip);
        searchRow.set_margin_end(ip);
        searchRow.set_margin_top(ip);
        searchRow.set_margin_bottom(Math.round(ip / 2));
        root.append(searchRow);

        // Left slot for tab-specific controls (Emojis/Glyphs toggle, SearXNG title)
        const searchLeftSlot = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 4);
        searchLeftSlot.set_halign(Gtk.Align.START);
        searchLeftSlot.set_valign(Gtk.Align.CENTER);
        searchRow.set_start_widget(searchLeftSlot);

        // Workspace visibility/startup control. This never starts or stops llama-server.
        const agentWorkspaceBtn = Gtk.Button.new();
        agentWorkspaceBtn.add_css_class('agent-llama-btn');
        agentWorkspaceBtn.add_css_class('agent-llama-off');
        agentWorkspaceBtn.set_can_focus(false);
        agentWorkspaceBtn.set_valign(Gtk.Align.CENTER);
        agentWorkspaceBtn.set_visible(false);
        const agentWorkspaceBox = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 4);
        const agentWorkspaceGlyph = Gtk.Label.new('󰒏');
        agentWorkspaceGlyph.add_css_class('agent-llama-glyph');
        const agentWorkspaceLabel = Gtk.Label.new('Workspace OFF');
        agentWorkspaceLabel.add_css_class('agent-llama-label');
        agentWorkspaceBox.append(agentWorkspaceGlyph);
        agentWorkspaceBox.append(agentWorkspaceLabel);
        agentWorkspaceBtn.set_child(agentWorkspaceBox);
        agentWorkspaceBtn.connect('clicked', () => this._agentToggleWorkspace());
        searchLeftSlot.append(agentWorkspaceBtn);
        this._agentWorkspaceBtn = agentWorkspaceBtn;
        this._agentWorkspaceGlyph = agentWorkspaceGlyph;
        this._agentWorkspaceLabel = agentWorkspaceLabel;

        const webHeaderLeftSlot = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 6);
        webHeaderLeftSlot.set_halign(Gtk.Align.START);
        webHeaderLeftSlot.set_valign(Gtk.Align.CENTER);
        webHeaderLeftSlot.set_visible(false);
        searchLeftSlot.append(webHeaderLeftSlot);
        this._webHeaderLeftSlot = webHeaderLeftSlot;

        const emojiModeSlot = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 4);
        emojiModeSlot.set_halign(Gtk.Align.START);
        emojiModeSlot.set_valign(Gtk.Align.CENTER);
        emojiModeSlot.set_visible(false);
        searchLeftSlot.append(emojiModeSlot);
        this._emojiModeSlot = emojiModeSlot;

        // Clipboard tab: Clear history button lives in the header (outside list frame)
        const clipClearSlot = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 4);
        clipClearSlot.set_halign(Gtk.Align.START);
        clipClearSlot.set_valign(Gtk.Align.CENTER);
        clipClearSlot.set_visible(false);
        searchLeftSlot.append(clipClearSlot);
        this._clipClearSlot = clipClearSlot;

        // Center slot: search bar (always perfectly centered)
        const searchFrame = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        searchFrame.add_css_class('search-frame');
        searchFrame.set_size_request(Math.max(1, Math.round(winW * frac) - (2 * ip)), -1);
        searchFrame.set_halign(Gtk.Align.CENTER);
        searchRow.set_center_widget(searchFrame);
        this._searchFrame = searchFrame;

        this._searchEntry = new Gtk.SearchEntry();
        this._searchEntry.set_placeholder_text(' Search applications…');
        this._searchEntry.add_css_class('launcher-search');
        this._searchEntry.set_hexpand(true);
        searchFrame.append(this._searchEntry);

        // Right slot for tab-specific controls (+ New Tab, Docker button, Tabs button)
        const searchRightSlot = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 6);
        searchRightSlot.set_halign(Gtk.Align.END);
        searchRightSlot.set_valign(Gtk.Align.CENTER);
        searchRow.set_end_widget(searchRightSlot);
        this._searchRightSlot = searchRightSlot;
        // Explicit llama-server control, immediately after the Ask the agent… input.
        const agentLlamaBtn = Gtk.Button.new();
        agentLlamaBtn.add_css_class('agent-llama-btn');
        agentLlamaBtn.add_css_class('agent-llama-off');
        agentLlamaBtn.set_can_focus(false);
        agentLlamaBtn.set_valign(Gtk.Align.CENTER);
        agentLlamaBtn.set_visible(false);
        const agentLlamaBox = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 4);
        const agentLlamaGlyph = Gtk.Label.new('󰒏');
        agentLlamaGlyph.add_css_class('agent-llama-glyph');
        const agentLlamaLabel = Gtk.Label.new('Llama OFF');
        agentLlamaLabel.add_css_class('agent-llama-label');
        agentLlamaBox.append(agentLlamaGlyph);
        agentLlamaBox.append(agentLlamaLabel);
        agentLlamaBtn.set_child(agentLlamaBox);
        agentLlamaBtn.connect('clicked', () => this._agentToggleLlama());
        searchRightSlot.append(agentLlamaBtn);
        this._agentLlamaBtn = agentLlamaBtn;
        this._agentLlamaGlyph = agentLlamaGlyph;
        this._agentLlamaLabel = agentLlamaLabel;
        const webHeaderRightSlot = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 6);
        webHeaderRightSlot.set_halign(Gtk.Align.END);
        webHeaderRightSlot.set_valign(Gtk.Align.CENTER);
        webHeaderRightSlot.set_visible(false);
        searchRightSlot.append(webHeaderRightSlot);
        this._webHeaderRightSlot = webHeaderRightSlot;

        // ── Inner panel: list-frame hosts pill + stack side-by-side ──────
        // .list-frame provides the bordered inner container (same as before).
        // Inside it we place an HBox: [pill | 2px spacer | stack].
        // The pill is vertically centred; the stack fills the rest.
        const innerFrame = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        innerFrame.add_css_class('list-frame');
        innerFrame.set_vexpand(true);
        root.append(innerFrame);

        const innerRow = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 0);
        innerRow.set_vexpand(true);
        innerFrame.append(innerRow);

        // ── Pill wrapper — pins pill to left border with 2px gap, centred ─
        const pillWrap = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        pillWrap.set_valign(Gtk.Align.CENTER);
        pillWrap.set_halign(Gtk.Align.START);
        pillWrap.set_margin_start(6);   // 6px from the list-frame left border
        pillWrap.set_margin_end(0);     // 0px gap between pill and stack content
        innerRow.append(pillWrap);

        const pill = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        pill.add_css_class('tab-pill');
        pillWrap.append(pill);

        // Tab definitions  [nerd-glyph, tooltip, id]
        // nf-md-rocket_launch U+F0B43 | nf-md-clipboard_text U+F0ECC | nf-md-emoticon U+F0629
        const TABS = [
            ['󰉋', 'Launcher', 'launcher'],
            ['󰅇', 'Clipboard', 'clipboard'],
            ['', 'Icons', 'emoji'],
            ['󰾔', 'Web Search', 'websearch'],
            ['󰚩', 'Agent', 'agent'],
        ];
        // Keep the tab that was visible before the persistent daemon was hidden.
        // The daemon must not force the Agent tab on every SIGUSR1 show.
        const tabIds = new Set(TABS.map(t => t[2]));
        this._activeTab = tabIds.has(this._lastTab) ? this._lastTab : 'launcher';
        this._tabBtns = {};

        for (const [glyph, tip, id] of TABS) {
            const btn = Gtk.Button.new();
            btn.add_css_class('tab-btn');
            btn.set_size_request(36, 36);
            btn.set_tooltip_text(tip);
            btn.set_can_focus(false);
            btn.set_halign(Gtk.Align.CENTER);

            const glyphLbl = Gtk.Label.new(glyph);
            glyphLbl.add_css_class('tab-glyph');
            glyphLbl.set_halign(Gtk.Align.CENTER);
            glyphLbl.set_valign(Gtk.Align.CENTER);
            glyphLbl.set_size_request(36, 36);
            glyphLbl.set_xalign(0.5);
            btn.set_child(glyphLbl);

            if (id === this._activeTab) btn.add_css_class('active');
            btn.connect('clicked', () => this._switchTab(id));
            pill.append(btn);
            this._tabBtns[id] = btn;
        }

        // ── Stack — content area for each tab, fills remaining width ─────
        this._stack = new Gtk.Stack();
        this._stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE);
        this._stack.set_transition_duration(120);
        this._stack.set_vexpand(true);
        this._stack.set_hexpand(true);
        innerRow.append(this._stack);

        // ── Launcher tab page ────────────────────────────────────────────
        // No extra list-frame border here — innerFrame already provides it.
        const listPage = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        listPage.set_vexpand(true);
        this._stack.add_named(listPage, 'launcher');

        const scroll = new Gtk.ScrolledWindow();
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        scroll.set_vexpand(true);
        scroll.add_css_class('launcher-scroll');
        listPage.append(scroll);
        this._launcherScroll = scroll;   // saved for scroll-to-top on tab switch

        const scrollInner = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        scrollInner.set_vexpand(true);
        scroll.set_child(scrollInner);

        // ── Favorites section (now inside scroll) ────────────────────────
        this._favSection = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        scrollInner.append(this._favSection);

        const favHeaderRow = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 4);
        favHeaderRow.add_css_class('fav-section-row');
        this._favSection.append(favHeaderRow);

        // Full-width toggle button: "Favorites" title left, chevron right.
        // Clicking anywhere on the row collapses / expands the favorites grid.
        this._favCollapsed = true;   // collapsed by default on clean launch
        const favToggleBtn = Gtk.Button.new();
        favToggleBtn.add_css_class('fav-toggle-btn');
        favToggleBtn.set_can_focus(true);
        favToggleBtn.set_hexpand(true);
        this._favToggleBtn = favToggleBtn;

        const favBtnBox = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 4);
        favBtnBox.set_hexpand(true);

        const favGlyphLbl = Gtk.Label.new(FAV_GLYPH);
        favGlyphLbl.add_css_class('fav-glyph');
        favBtnBox.append(favGlyphLbl);

        const favSectionLabel = Gtk.Label.new('Favorites');
        favSectionLabel.add_css_class('fav-section-label');
        favSectionLabel.set_halign(Gtk.Align.START);
        favSectionLabel.set_hexpand(true);
        favBtnBox.append(favSectionLabel);

        // Chevron on right: CHEV_UP when expanded (click to collapse),
        // CHEV_UP when collapsed (click to expand) — standard accordion UX.
        // Start collapsed, so chevron shows CHEV_UP.
        this._favChevron = Gtk.Label.new(CHEV_UP);
        this._favChevron.add_css_class('fav-glyph');
        favBtnBox.append(this._favChevron);

        favToggleBtn.set_child(favBtnBox);
        favHeaderRow.append(favToggleBtn);

        this._toggleFav = () => {
            this._favCollapsed = !this._favCollapsed;
            this._favFlow.set_visible(!this._favCollapsed);
            this._favSep.set_visible(!this._favCollapsed);
            this._favChevron.set_text(this._favCollapsed ? CHEV_UP : CHEV_DOWN);
        };
        favToggleBtn.connect('clicked', () => this._toggleFav());

        this._favFlow = new Gtk.FlowBox();
        this._favFlow.set_max_children_per_line(this._isVert ? COLS_VERT : COLS_HORIZ);
        this._favFlow.set_min_children_per_line(this._isVert ? COLS_VERT : COLS_HORIZ);
        this._favFlow.set_row_spacing(2);
        this._favFlow.set_column_spacing(2);
        this._favFlow.set_homogeneous(true);
        this._favFlow.set_selection_mode(Gtk.SelectionMode.SINGLE);
        this._favFlow.add_css_class('launcher-grid');
        this._favFlow.set_visible(false);   // hidden — collapsed by default
        this._favSection.append(this._favFlow);

        // Keyboard Enter on a focused favorites item → launch
        this._favFlow.connect('child-activated', (_fb, child) => {
            const appData = getAppDataFromChild(child);
            if (appData && appData.exec) { spawnApp(appData.exec); this.close(); }
        });

        const favSep = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
        favSep.add_css_class('fav-separator');
        favSep.set_visible(false);          // hidden — collapsed by default
        this._favSep = favSep;
        this._favSection.append(favSep);

        this._favSection.set_visible(false);  // hidden until populated

        // ── Groups container (collapsible strips, one per group) ─────────
        this._groupsContainer = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        scrollInner.append(this._groupsContainer);

        // ── Main FlowBox (app grid) ────────────────────────────────────
        this._flow = new Gtk.FlowBox();
        this._flow.set_max_children_per_line(this._isVert ? COLS_VERT : COLS_HORIZ);
        this._flow.set_min_children_per_line(this._isVert ? COLS_VERT : COLS_HORIZ);
        this._flow.set_row_spacing(2);
        this._flow.set_column_spacing(2);
        this._flow.set_homogeneous(true);
        this._flow.set_valign(Gtk.Align.START);   // prevents rows stretching when content is short
        this._flow.set_selection_mode(Gtk.SelectionMode.SINGLE);
        this._flow.add_css_class('launcher-grid');
        scrollInner.append(this._flow);

        // Keyboard Enter on a focused main-grid item → launch
        this._flow.connect('child-activated', (_fb, child) => {
            const appData = getAppDataFromChild(child);
            if (appData && appData.exec) { spawnApp(appData.exec); this.close(); }
        });

        // ── Build other tab pages ─────────────────────────────────────
        this._buildClipboardTab(ip);
        this._buildEmojiTab(ip);
        this._buildWebSearchTab(ip);
        this._buildAgentTab(ip);

        // Initial population
        this._refreshFavorites('');
        this._refreshGroups('');
        this._populateApps(this._allApps);

        // ── Search filtering ───────────────────────────────────────────
        this._searchEntry.connect('search-changed', () => {
            const q = this._searchEntry.get_text().toLowerCase().trim();
            if (this._activeTab === 'launcher') {
                this._refreshFavorites(q);
                this._refreshGroups(q);
                this._populateApps(
                    q ? this._allApps.filter(a => a.name.toLowerCase().includes(q)) : this._allApps
                );
            } else if (this._activeTab === 'clipboard') {
                this._filterClipboard(q);
            } else if (this._activeTab === 'emoji') {
                this._filterEmoji(q);
            } else if (this._activeTab === 'websearch') {
                this._performWebSearch(q, false);
            }
        });

        // Enter on search → launch first filtered app (launcher tab) or instant search (websearch tab)
        this._searchEntry.connect('activate', () => {
            const rawQ = this._searchEntry.get_text().trim();
            if (this._activeTab === 'launcher') {
                const lowerQ = rawQ.toLowerCase();
                const filtered = lowerQ
                    ? this._allApps.filter(a => a.name.toLowerCase().includes(lowerQ))
                    : this._allApps;
                if (filtered.length > 0) {
                    spawnApp(filtered[0].exec);
                    this.close();
                }
            } else if (this._activeTab === 'websearch') {
                if (rawQ) {
                    this._performWebSearch(rawQ, true);
                }
            } else if (this._activeTab === 'agent') {
                if (rawQ) {
                    this._agentPostMessage({ type: 'user_prompt', payload: rawQ });
                    this._searchEntry.set_text('');
                }
            }
        });

    }

    // ── Tab switching ─────────────────────────────────────────────────────

    _switchTab(id, force = false) {
        if (this._activeTab === id && !force) return;
        this._lastTab = id;
        this._activeTab = id;
        // Persist immediately, not only when the window is hidden.
        // This makes a later toggle restore the last open tab even if the
        // process is interrupted between tab switching and hiding.
        try { this._persistWebState(); } catch (_) { }

        // Update sidebar button active state
        for (const [tid, btn] of Object.entries(this._tabBtns)) {
            if (tid === id) btn.add_css_class('active');
            else btn.remove_css_class('active');
        }

        this._stack.set_visible_child_name(id);

        // Unified top-row controls follow the active tab.
        if (this._webHeaderLeftSlot) this._webHeaderLeftSlot.set_visible(id === 'websearch');
        if (this._webHeaderRightSlot) this._webHeaderRightSlot.set_visible(id === 'websearch');
        if (this._emojiModeSlot) this._emojiModeSlot.set_visible(id === 'emoji');
        if (this._clipClearSlot) this._clipClearSlot.set_visible(id === 'clipboard');
        if (this._agentWorkspaceBtn) this._agentWorkspaceBtn.set_visible(id === 'agent');
        if (this._agentLlamaBtn) this._agentLlamaBtn.set_visible(id === 'agent');
        this._agentUpdateWorkspaceBtn();
        this._agentUpdateLlamaBtn();
        if (id === 'agent') this._agentCheckLlamaStatus((running) => {
            this._agentLlamaRunning = !!running;
            this._agentUpdateLlamaBtn();
        });

        // ── websearch tab
        if (id === 'websearch') {
            if (this._searxWebBoxOpen && this._searxTabs && this._searxTabs.length > 0 && this._searxActiveTabId) {
                // Naturally bring back active tab in WebKit view
                const activeTab = this._searxTabs.find(t => t.id === this._searxActiveTabId) || this._searxTabs[0];
                if (activeTab) {
                    this._searxSwitchToTab(activeTab.id);
                    this._searchEntry.set_placeholder_text(' Search the web…');
                }
            } else if (this._searxPendingNewTab) {
                this._searchEntry.set_placeholder_text(' Search in current tab…');
                this._searchEntry.set_text('');
                this._searxLastQuery = '';
                this._searxClearList();
                this._searxShowIdle();
            } else {
                this._searchEntry.set_placeholder_text(' Search the web…');
                this._searchEntry.set_text('');
                this._searxLastQuery = '';
                this._searxClearList();
                this._searxShowIdle();
            }

            // Probe Docker just to update the Docker button indicator
            this._searxCheckDockerStatus((running) => {
                this._searxDockerRunning = running;
                if (!running && !this._searxWebBoxOpen) {
                    this._searxShowStatus('󰡨', 'Docker stopped',
                        'Click Start SearXNG or the Docker button to launch.', false, true);
                }
            });
        } else if (id === 'agent') {
            this._searchEntry.set_placeholder_text(' Ask the agent…');
            this._searchEntry.set_text('');
            this._agentInjectTheme();
            this._agentCheckLlamaStatus((running) => {
                this._agentLlamaRunning = !!running;
                this._agentLlamaEnabled = !!running;
                this._agentUpdateLlamaBtn();
            });
        } else if (id === 'clipboard') {
            this._searchEntry.set_placeholder_text(' Search clipboard…');
            this._searchEntry.set_text('');
            this._loadClipboard('');
        } else if (id === 'emoji') {
            this._searchEntry.set_placeholder_text(
                this._emojiMode === 'nerd' ? ' Search glyph…' : ' Search emoji…');
            this._searchEntry.set_text('');
            this._filterEmoji('');
        } else {
            // Launcher tab: clear search, scroll to top
            this._searchEntry.set_placeholder_text(' Search applications…');
            this._searchEntry.set_text('');
            this._refreshFavorites('');
            this._refreshGroups('');
            this._populateApps(this._allApps);
            if (this._launcherScroll) {
                const adj = this._launcherScroll.get_vadjustment();
                if (adj) adj.set_value(0);
            }
        }

        GLib.idle_add(GLib.PRIORITY_HIGH, () => {
            this._searchEntry.grab_focus();
            return GLib.SOURCE_REMOVE;
        });
    }

    // ── Clipboard tab ─────────────────────────────────────────────────────

    _buildClipboardTab(ip) {
        const clipPage = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        clipPage.set_vexpand(true);
        this._stack.add_named(clipPage, 'clipboard');

        // Clear history button lives in the header slot (this._clipClearSlot), built during _buildUI.
        // Attach it here so the callback can reference this._loadClipboard.
        if (this._clipClearSlot) {
            const clearBtn = Gtk.Button.new_with_label('󰃢  Clear history');
            clearBtn.add_css_class('clip-clear-btn');
            clearBtn.set_can_focus(false);
            clearBtn.set_valign(Gtk.Align.CENTER);
            clearBtn.connect('clicked', () => {
                try {
                    GLib.spawn_command_line_sync('cliphist wipe');
                } catch (_) { }
                this._loadClipboard('');
            });
            this._clipClearSlot.append(clearBtn);
        }

        const clipScroll = new Gtk.ScrolledWindow();
        clipScroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        clipScroll.set_vexpand(true);
        clipScroll.add_css_class('launcher-scroll');
        clipPage.append(clipScroll);

        this._clipBox = Gtk.Box.new(Gtk.Orientation.VERTICAL, 2);
        this._clipBox.set_vexpand(true);
        this._clipBox.set_margin_start(ip);
        this._clipBox.set_margin_end(ip);
        this._clipBox.set_margin_top(4);
        this._clipBox.set_margin_bottom(8);
        clipScroll.set_child(this._clipBox);

        // Store all raw entries for filtering
        this._clipEntries = [];
    }

    _loadClipboard(query) {
        const q = (query ?? '').toLowerCase().trim();

        // Clear existing items
        let ch = this._clipBox.get_first_child();
        while (ch) {
            const nx = ch.get_next_sibling();
            this._clipBox.remove(ch);
            ch = nx;
        }

        // Fetch from cliphist
        try {
            const [ok, stdout] = GLib.spawn_command_line_sync('cliphist list');
            if (ok) {
                const lines = new TextDecoder().decode(stdout).trim().split('\n')
                    .filter(l => l.trim());
                this._clipEntries = lines;
                const filtered = q ? lines.filter(l => l.toLowerCase().includes(q)) : lines;
                const toShow = filtered.slice(0, 80);

                if (toShow.length === 0) {
                    const empty = Gtk.Label.new('No clipboard history found');
                    empty.add_css_class('clip-empty-label');
                    empty.set_halign(Gtk.Align.CENTER);
                    this._clipBox.append(empty);
                    return;
                }

                for (const entry of toShow) {
                    // cliphist format: "INDEX\tCONTENT"
                    const tabIdx = entry.indexOf('\t');
                    const idx = tabIdx >= 0 ? entry.slice(0, tabIdx) : '';
                    const text = tabIdx >= 0 ? entry.slice(tabIdx + 1) : entry;

                    const btn = Gtk.Button.new();
                    btn.add_css_class('clip-item-btn');
                    btn.set_halign(Gtk.Align.FILL);

                    const lbl = Gtk.Label.new(text.length > 120 ? text.slice(0, 120) + '…' : text);
                    lbl.add_css_class('clip-item-label');
                    lbl.set_halign(Gtk.Align.START);
                    lbl.set_ellipsize(3);
                    lbl.set_max_width_chars(60);
                    lbl.set_wrap(false);
                    btn.set_child(lbl);

                    btn.connect('clicked', () => {
                        // Decode & paste via cliphist + wl-copy
                        try {
                            const [, argv] = GLib.shell_parse_argv(
                                `sh -c "cliphist decode <<< ${GLib.shell_quote(entry)} | wl-copy"`
                            );
                            GLib.spawn_async(null, argv, null,
                                GLib.SpawnFlags.SEARCH_PATH | GLib.SpawnFlags.DO_NOT_REAP_CHILD, null);
                        } catch (e) {
                            console.error('[launcher] clipboard paste:', e.message);
                        }
                        this.close();
                    });

                    this._clipBox.append(btn);
                }
                return;
            }
        } catch (_) { }

        // cliphist not available
        const notAvail = Gtk.Label.new('cliphist not found');
        notAvail.add_css_class('clip-empty-label');
        notAvail.set_halign(Gtk.Align.CENTER);
        this._clipBox.append(notAvail);
    }

    _filterClipboard(query) {
        this._loadClipboard(query);
    }

    // ── Emoji tab ──────────────────────────────────────────────────────────

    _buildEmojiTab(ip) {
        const emojiFrame = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        emojiFrame.set_vexpand(true);
        this._stack.add_named(emojiFrame, 'emoji');

        // ── Copied feedback bar ──────────────────────────────────────────
        this._emojiCopiedBar = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 0);
        this._emojiCopiedBar.add_css_class('emoji-copied-bar');
        this._emojiCopiedBar.set_visible(false);
        this._emojiCopiedLbl = Gtk.Label.new('');
        this._emojiCopiedLbl.add_css_class('emoji-copied-label');
        this._emojiCopiedBar.append(this._emojiCopiedLbl);
        emojiFrame.append(this._emojiCopiedBar);

        // ── Mode toggle (Emoji | Nerd Glyphs) ───────────────────────────
        const modeRow = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 4);
        modeRow.set_valign(Gtk.Align.CENTER);
        // Keep Emojis/Glyphs outside the bordered icon list frame.
        if (this._emojiModeSlot) this._emojiModeSlot.append(modeRow);
        else emojiFrame.append(modeRow);

        const modeEmoji = Gtk.Button.new_with_label('Emojis');
        modeEmoji.add_css_class('emoji-mode-btn'); modeEmoji.add_css_class('active');
        modeEmoji.set_can_focus(false); modeRow.append(modeEmoji);

        const modeNerd = Gtk.Button.new_with_label('Glyphs');
        modeNerd.add_css_class('emoji-mode-btn');
        modeNerd.set_can_focus(false); modeRow.append(modeNerd);


        const setMode = (mode, btn) => {
            if (this._emojiMode === mode) return;
            this._emojiMode = mode;
            [modeEmoji, modeNerd].forEach(b => b.remove_css_class('active'));
            btn.add_css_class('active');
            this._searchEntry.set_placeholder_text(
                mode === 'nerd' ? ' Search glyph…' : ' Search emoji…');
            this._searchEntry.set_text('');
            this._emojiCatRow.set_visible(true);
            this._refreshEmojiGroups();
            this._filterEmoji('');
        };

        modeEmoji.connect('clicked', () => setMode('emoji', modeEmoji));
        modeNerd.connect('clicked', () => setMode('nerd', modeNerd));

        // ── Category scrollbar ───────────────────────────────────────────
        const catScroll = new Gtk.ScrolledWindow();
        catScroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.NEVER);
        catScroll.set_min_content_height(42);
        catScroll.set_max_content_height(42);
        emojiFrame.append(catScroll);

        this._emojiCatRow = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 2);
        this._emojiCatRow.set_margin_start(ip); this._emojiCatRow.set_margin_end(ip);
        this._emojiCatRow.set_margin_top(4); this._emojiCatRow.set_margin_bottom(4);
        catScroll.set_child(this._emojiCatRow);

        // ── Glyph flowbox ────────────────────────────────────────────────
        const emojiScroll = new Gtk.ScrolledWindow();
        emojiScroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        emojiScroll.set_vexpand(true);
        emojiScroll.add_css_class('launcher-scroll');
        emojiFrame.append(emojiScroll);

        this._emojiFlow = new Gtk.FlowBox();
        this._emojiFlow.set_max_children_per_line(10);
        this._emojiFlow.set_min_children_per_line(6);
        this._emojiFlow.set_row_spacing(2);
        this._emojiFlow.set_column_spacing(2);
        this._emojiFlow.set_homogeneous(true);
        this._emojiFlow.set_valign(Gtk.Align.START);
        this._emojiFlow.set_selection_mode(Gtk.SelectionMode.NONE);
        this._emojiFlow.set_margin_start(ip); this._emojiFlow.set_margin_end(ip);
        this._emojiFlow.set_margin_bottom(8);
        emojiScroll.set_child(this._emojiFlow);

        this._emojiCopiedTimer = 0;
        this._emojiMode = 'emoji';

        // ── All emojis from GTK4 data (corrected categorization) ─
        // ── Emoji / Nerd Font glyph picker data — externalized to
        // glyph-data.js (previously ~12,000 lines inline here). See that
        // file for the full data; these three names are kept identical so
        // every reference below is unaffected.
        const EMOJI_ALL = GlyphData.EMOJI_ALL;
        const EMOJI_GROUPS = GlyphData.EMOJI_GROUPS;
        const NERD_CATS = GlyphData.NERD_CATS;

        // Store for filtering
        this._emojiAll = EMOJI_ALL;
        this._emojiGroups = EMOJI_GROUPS;
        this._nerdCats = NERD_CATS;
        this._emojiActiveGroup = 0;
        this._nerdActiveCat = 0;
        this._emojiCatBtns = [];
        this._nerdCatBtns = [];

        // ── Helper: rebuild category buttons ────────────────────────────
        const buildCatBtns = (items, isNerd) => {
            let ch = this._emojiCatRow.get_first_child();
            while (ch) { const nx = ch.get_next_sibling(); this._emojiCatRow.remove(ch); ch = nx; }
            const btns = [];
            const activeIdx = isNerd ? this._nerdActiveCat : this._emojiActiveGroup;
            for (let i = 0; i < items.length; i++) {
                const item = items[i];
                const cb = Gtk.Button.new_with_label(item.glyph);
                cb.add_css_class('emoji-cat-btn');
                cb.set_tooltip_text(item.name);
                cb.set_can_focus(false);
                if (i === activeIdx) cb.add_css_class('active');
                const _i = i;
                cb.connect('clicked', () => {
                    const q = this._searchEntry.get_text().toLowerCase().trim();
                    if (!q) {
                        if (isNerd) { this._nerdActiveCat = _i; }
                        else { this._emojiActiveGroup = _i; }
                        const allBtns = isNerd ? this._nerdCatBtns : this._emojiCatBtns;
                        for (let j = 0; j < allBtns.length; j++) {
                            if (j === _i) allBtns[j].add_css_class('active');
                            else allBtns[j].remove_css_class('active');
                        }
                        this._filterEmoji('');
                    }
                });
                this._emojiCatRow.append(cb);
                btns.push(cb);
            }
            return btns;
        };

        this._emojiCatBtns = buildCatBtns(EMOJI_GROUPS, false);

        // ── Mode toggle handlers ─────────────────────────────────────────
        modeEmoji.connect('clicked', () => {
            if (this._emojiMode === 'emoji') return;
            this._emojiMode = 'emoji';
            modeEmoji.add_css_class('active'); modeNerd.remove_css_class('active');
            if (this._activeTab === 'emoji')
                this._searchEntry.set_placeholder_text(' Search emoji...');
            this._emojiCatBtns = buildCatBtns(EMOJI_GROUPS, false);
            this._filterEmoji(this._searchEntry.get_text().toLowerCase().trim());
        });
        modeNerd.connect('clicked', () => {
            if (this._emojiMode === 'nerd') return;
            this._emojiMode = 'nerd';
            modeNerd.add_css_class('active'); modeEmoji.remove_css_class('active');
            if (this._activeTab === 'emoji')
                this._searchEntry.set_placeholder_text(' Search glyph...');
            this._nerdCatBtns = buildCatBtns(NERD_CATS, true);
            this._filterEmoji(this._searchEntry.get_text().toLowerCase().trim());
        });

        this._filterEmoji('');
    }


    _refreshEmojiGroups() {
        if (!this._emojiCatRow) return;
        // Clear existing category buttons
        let ch = this._emojiCatRow.get_first_child();
        while (ch) {
            const nx = ch.get_next_sibling();
            this._emojiCatRow.remove(ch);
            ch = nx;
        }

        const isNerd = this._emojiMode === 'nerd';
        const groups = isNerd ? this._nerdCats : this._emojiGroups;

        groups.forEach((g, i) => {
            const btn = Gtk.Button.new_with_label(isNerd ? g.glyph : g.glyph);
            btn.add_css_class('emoji-cat-btn');
            if ((isNerd && i === this._nerdActiveCat) || (!isNerd && i === this._emojiActiveGroup)) {
                btn.add_css_class('active');
            }
            btn.set_can_focus(false);
            btn.set_tooltip_text(g.name);
            btn.connect('clicked', () => {
                let child = this._emojiCatRow.get_first_child();
                while (child) {
                    child.remove_css_class('active');
                    child = child.get_next_sibling();
                }
                btn.add_css_class('active');
                if (isNerd) this._nerdActiveCat = i;
                else this._emojiActiveGroup = i;
                this._filterEmoji(this._searchEntry.get_text());
            });
            this._emojiCatRow.append(btn);
        });
    }

    _filterEmoji(query) {
        const q = (query ?? '').toLowerCase().trim();
        const isNerd = this._emojiMode === 'nerd';

        // Clear flow
        let ch = this._emojiFlow.get_first_child();
        while (ch) { const nx = ch.get_next_sibling(); this._emojiFlow.remove(ch); ch = nx; }

        let items;
        if (isNerd) {
            const cats = this._nerdCats ?? [];
            if (q) {
                items = cats.flatMap(cat => cat.glyphs.filter(g => (g.s ?? g.n.toLowerCase()).includes(q) || cat.name.toLowerCase().includes(q) || (cat.prefix ?? '').includes(q)));
            } else {
                items = cats[this._nerdActiveCat]?.glyphs ?? [];
            }
        } else {
            const all = this._emojiAll ?? [];
            if (q) {
                items = all.filter(e => e.n.toLowerCase().includes(q)).map(e => ({ c: e.c, n: e.n }));
            } else {
                const g = this._emojiActiveGroup ?? 0;
                items = all.filter(e => e.g === g).map(e => ({ c: e.c, n: e.n }));
            }
        }

        for (const item of items) {
            const btn = Gtk.Button.new_with_label(item.c);
            btn.add_css_class(isNerd ? 'nerd-btn' : 'emoji-btn');
            btn.set_can_focus(false);
            btn.set_tooltip_text(item.n ?? '');
            const _it = item.c;
            btn.connect('clicked', () => {
                try {
                    const [, argv] = GLib.shell_parse_argv(`wl-copy -- ${GLib.shell_quote(_it)}`);
                    GLib.spawn_async(null, argv, null, GLib.SpawnFlags.SEARCH_PATH | GLib.SpawnFlags.DO_NOT_REAP_CHILD, null);
                } catch (e2) { console.error('[launcher] copy:', e2.message); }
                if (this._emojiCopiedTimer) { GLib.source_remove(this._emojiCopiedTimer); this._emojiCopiedTimer = 0; }
                this._emojiCopiedLbl.set_text(`${_it}  Copied`);
                this._emojiCopiedBar.set_visible(true);
                this._emojiCopiedTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT_IDLE, 1800, () => {
                    this._emojiCopiedBar.set_visible(false);
                    this._emojiCopiedTimer = 0;
                    return GLib.SOURCE_REMOVE;
                });
            });
            this._emojiFlow.append(btn);
        }
    }

    _populateApps(apps) {
        let child = this._flow.get_first_child();
        while (child) {
            const next = child.get_next_sibling();
            this._flow.remove(child);
            child = next;
        }
        for (const app of apps)
            this._flow.append(this._makeAppTile(app));
    }

    /**
     * Rebuild all group strips under _groupsContainer.
     * Each group is a collapsible accordion strip identical in style to
     * the Favorites section. Strips are fully recreated on each call so
     * ordering stays consistent with the JSON object key order.
     * Each group FlowBox is a drop target — tiles dragged from the main
     * grid (or other groups) are added to the group on drop.
     */
    _refreshGroups(query) {
        const q = (query ?? '').toLowerCase().trim();

        // Remove all existing strips
        let ch = this._groupsContainer.get_first_child();
        while (ch) {
            const nx = ch.get_next_sibling();
            this._groupsContainer.remove(ch);
            ch = nx;
        }

        const groups = readGroups();   // plain object { name: [className, …] }

        for (const [groupName, members] of Object.entries(groups).sort(([a], [b]) => a.localeCompare(b))) {
            // All apps that belong to this group (ignoring query).
            const allGroupApps = this._allApps.filter(a => members.includes(a.className));
            // Always skip genuinely empty groups (no installed members).
            if (allGroupApps.length === 0) continue;

            // During search: show ALL group members so the strip is informative
            // and the drop-target grid is always reachable for drag-and-drop.
            const groupApps = allGroupApps;

            // Respect stored collapse state during search (collapsed by default);
            // user can expand manually just as in normal mode.
            if (!this._groupCollapsed) this._groupCollapsed = {};
            const collapsed = this._groupCollapsed[groupName] ?? true;

            const strip = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);

            // ── Header row (identical structure to Favorites header) ────
            const headerRow = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 4);
            headerRow.add_css_class('fav-section-row');

            const toggleBtn = Gtk.Button.new();
            toggleBtn.add_css_class('fav-toggle-btn');
            toggleBtn.set_can_focus(true);
            toggleBtn.set_hexpand(true);
            strip._toggleBtn = toggleBtn;

            const btnInner = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 4);
            btnInner.set_hexpand(true);

            const glyphLbl = Gtk.Label.new('󰌨');  // nf-md-layers
            glyphLbl.add_css_class('fav-glyph');
            btnInner.append(glyphLbl);

            const titleLbl = Gtk.Label.new(groupName);
            titleLbl.add_css_class('fav-section-label');
            titleLbl.set_halign(Gtk.Align.START);
            titleLbl.set_hexpand(true);
            btnInner.append(titleLbl);

            const chevron = Gtk.Label.new(collapsed ? CHEV_UP : CHEV_DOWN);
            chevron.add_css_class('fav-glyph');
            btnInner.append(chevron);

            toggleBtn.set_child(btnInner);
            headerRow.append(toggleBtn);
            strip.append(headerRow);

            // ── FlowBox grid ─────────────────────────────────────────────
            const flow = new Gtk.FlowBox();
            const cols = this._isVert ? COLS_VERT : COLS_HORIZ;
            flow.set_max_children_per_line(cols);
            flow.set_min_children_per_line(2);
            flow.set_row_spacing(2);
            flow.set_column_spacing(2);
            flow.set_homogeneous(true);
            flow.set_selection_mode(Gtk.SelectionMode.SINGLE);
            flow.add_css_class('launcher-grid');
            flow.set_visible(!collapsed);
            strip._flow = flow;
            // Pass groupName so tiles show "Remove from <group>" context menu
            for (const app of groupApps) flow.append(this._makeAppTile(app, groupName));
            flow.connect('child-activated', (_fb, child) => {
                const appData = getAppDataFromChild(child);
                if (appData && appData.exec) { spawnApp(appData.exec); this.close(); }
            });
            strip.append(flow);

            // ── Drop target — accept tiles dragged from main grid / other groups ─
            const dropTarget = new Gtk.DropTarget({ actions: Gdk.DragAction.MOVE });
            dropTarget.set_gtypes([GObject.TYPE_STRING]);
            dropTarget.connect('motion', () => {
                flow.add_css_class('drag-target-hover');
                return Gdk.DragAction.MOVE;
            });
            dropTarget.connect('leave', () => {
                flow.remove_css_class('drag-target-hover');
            });
            dropTarget.connect('drop', (_t, className) => {
                flow.remove_css_class('drag-target-hover');
                if (!className || members.includes(className)) return false;
                addAppToGroup(readGroups(), groupName, className);
                this._pendingGroupRefresh = true;
                // Refresh immediately (no open popover to wait for)
                GLib.idle_add(GLib.PRIORITY_LOW, () => {
                    const curQ = this._searchEntry
                        ? this._searchEntry.get_text().toLowerCase().trim() : '';
                    this._refreshGroups(curQ);
                    return GLib.SOURCE_REMOVE;
                });
                return true;
            });
            flow.add_controller(dropTarget);

            // ── Separator ────────────────────────────────────────────────
            const sep = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
            sep.add_css_class('fav-separator');
            sep.set_visible(!collapsed);
            strip.append(sep);

            // Toggle collapse on header click or Return key
            strip._toggleFn = () => {
                this._groupCollapsed[groupName] = !this._groupCollapsed[groupName];
                const nowCollapsed = this._groupCollapsed[groupName];
                flow.set_visible(!nowCollapsed);
                sep.set_visible(!nowCollapsed);
                chevron.set_text(nowCollapsed ? CHEV_UP : CHEV_DOWN);
            };
            toggleBtn.connect('clicked', () => strip._toggleFn());

            // ── Right-click on header → Rename / Delete group popover ────
            const headerRc = new Gtk.GestureClick();
            headerRc.set_button(3);
            headerRc.connect('released', () => {
                this._showGroupHeaderMenu(groupName, headerRow);
            });
            headerRow.add_controller(headerRc);

            this._groupsContainer.append(strip);
        }
    }

    _makeAppTile(app, groupName) {
        // groupName — if set, this tile lives inside a group strip.
        //   Right-click will show "Remove from <groupName>" in place of "New Group…".

        // ── Button ─────────────────────────────────────────────────────
        const btn = Gtk.Button.new();
        btn.add_css_class('app-tile');
        btn.set_tooltip_text(app.name);
        // Hard-pin dimensions so tiles never stretch when the row is short
        btn.set_size_request(TILE_WIDTH, TILE_HEIGHT);
        // Tag the app data so child-activated (Enter key) can retrieve it
        btn._appData = app;
        btn._groupCtx = groupName ?? null;
        // Don't let the button steal keyboard focus — FlowBoxChild handles
        // arrow-key selection; the button only reacts to pointer events.
        btn.set_can_focus(false);

        // ── Icon + label ───────────────────────────────────────────────
        const col = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        col.set_halign(Gtk.Align.CENTER);
        col.set_valign(Gtk.Align.CENTER);
        btn.set_child(col);

        const img = (app.iconName.startsWith('/') || app.iconName.startsWith('~'))
            ? Gtk.Image.new_from_file(app.iconName)
            : Gtk.Image.new_from_icon_name(app.iconName);
        img.set_pixel_size(APP_ICON_SIZE);
        img.set_halign(Gtk.Align.CENTER);
        col.append(img);

        const lbl = Gtk.Label.new(app.name);
        lbl.add_css_class('app-tile-label');
        lbl.set_halign(Gtk.Align.CENTER);
        lbl.set_max_width_chars(12);
        lbl.set_ellipsize(3 /* Pango.EllipsizeMode.END */);
        lbl.set_wrap(false);
        col.append(lbl);

        // ── Left-click → launch ────────────────────────────────────────
        btn.connect('clicked', () => {
            spawnApp(app.exec);
            this.close();
        });

        // ── Right-click → context menu ─────────────────────────────────
        const rc = new Gtk.GestureClick();
        rc.set_button(3);
        rc.connect('released', () => this._showContextMenu(app, btn, groupName ?? null));
        btn.add_controller(rc);

        // ── Drag source (so tiles can be dragged into group strips) ────
        const dragSrc = new Gtk.DragSource({ actions: Gdk.DragAction.MOVE });
        dragSrc.connect('prepare', () => {
            return Gdk.ContentProvider.new_for_value(app.className);
        });
        dragSrc.connect('drag-begin', (src) => {
            this._groupDragClass = app.className;
            btn.set_opacity(0.4);
            try { src.set_icon(Gtk.WidgetPaintable.new(btn), 0, 0); } catch (_) { }
        });
        dragSrc.connect('drag-end', () => {
            btn.set_opacity(1.0);
            this._groupDragClass = null;
        });
        btn.add_controller(dragSrc);

        // ── Running-app dot indicators ────────────────────────────────────
        // Cairo DrawingArea instead of font glyphs — exact pixel sizing
        // ensures the Overlay's valign=END places dots flush at the tile bottom.
        const _appKey = app.className.toLowerCase();
        const _instances = this._runningApps.get(_appKey)
            ?? this._runningApps.get(app.className)
            ?? (app.steamAppId ? this._runningApps.get(app.steamAppId) : null)
            ?? [];
        const _instanceCount = _instances.length;

        const _dotR = 5;   // px radius — 10px diameter dot, clearly visible
        const _dotGap = 2;   // px gap between 2 dots

        const indicatorArea = new Gtk.DrawingArea();
        indicatorArea.set_name('launcher-indicator-dots');
        indicatorArea.set_halign(Gtk.Align.CENTER);
        indicatorArea.set_valign(Gtk.Align.END);   // flush at tile bottom
        indicatorArea._instanceCount = _instanceCount;

        const _setLauncherIndicatorSize = (area) => {
            const n = Math.min(area._instanceCount, 2);
            if (n === 0) {
                area.set_size_request(0, 0);
                area.set_visible(false);
            } else {
                area.set_visible(true);
                const w = n === 1 ? _dotR * 2 : _dotR * 4 + _dotGap;
                area.set_size_request(w, _dotR * 2);
            }
        };
        _setLauncherIndicatorSize(indicatorArea);

        indicatorArea.set_draw_func((area, cr, _w, _h) => {
            const n = Math.min(area._instanceCount, 2);
            if (n === 0) return;
            const rgba = area.get_style_context().get_color();
            cr.setSourceRGBA(rgba.red, rgba.green, rgba.blue, rgba.alpha);
            for (let i = 0; i < n; i++) {
                cr.arc(_dotR + i * (_dotR * 2 + _dotGap), _dotR, _dotR - 0.5, 0, 2 * Math.PI);
                cr.fill();
            }
        });

        // Wrap btn + indicator in an overlay — no layout cost to the tile.
        const tileOverlay = new Gtk.Overlay();
        tileOverlay.set_halign(Gtk.Align.CENTER);
        tileOverlay.set_valign(Gtk.Align.CENTER);
        tileOverlay.set_child(btn);
        tileOverlay.add_overlay(indicatorArea);
        tileOverlay.set_measure_overlay(indicatorArea, false);
        tileOverlay.set_clip_overlay(indicatorArea, false);

        return tileOverlay;
    }

    // ─── Context menu ────────────────────────────────────────────────────

    _showContextMenu(app, parentBtn, groupName) {
        // groupName — if non-null, this tile is inside a group strip.
        //   The "Groups" section shows "Remove from <groupName>" at the top,
        //   and "New Group…" is hidden (app is already grouped).

        // Choose popover direction to open away from the dock edge (same logic
        // the dock uses in _showContextMenu / _showStartMenu)
        const pos = this._dockPos;
        let popPos;
        if (pos === 'right') popPos = Gtk.PositionType.LEFT;
        else popPos = Gtk.PositionType.RIGHT; // bottom, top, left

        const pop = new Gtk.Popover();
        // Parent to the launcher window rather than the tile button so that
        // _refreshFavorites can safely remove tiles (including parentBtn) from
        // _favFlow without corrupting the popover's parent chain.
        pop.set_parent(this);
        pop.set_has_arrow(false);
        pop.set_position(popPos);
        // Point at the button so the popover opens in the right place.
        {
            const [ok, bx, by] = parentBtn.translate_coordinates(this, 0, 0);
            if (ok)
                pop.set_pointing_to(new Gdk.Rectangle({
                    x: Math.round(bx), y: Math.round(by),
                    width: parentBtn.get_width(),
                    height: parentBtn.get_height(),
                }));
        }
        pop.add_css_class('launcher-popover');
        // Inline provider to force correct background on Wayland
        pop.get_style_context().add_provider(
            this._getPopoverCSSProvider(),
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
        pop.connect('closed', () => {
            this._popoverOpen = false;
            // Grace period: block focus-loss close for 600 ms after any popover
            // closes so that pin/unpin actions (which popdown() the menu) don't
            // immediately dismiss the launcher when focus briefly returns to it.
            if (this._graceTimer) {
                GLib.source_remove(this._graceTimer);
                this._graceTimer = 0;
            }
            this._postPopoverGrace = true;
            this._graceTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT_IDLE, 600, () => {
                this._postPopoverGrace = false;
                this._graceTimer = 0;
                return GLib.SOURCE_REMOVE;
            });
            // Unparent the popover first, THEN refresh the favorites grid.
            // Running _refreshFavorites while GTK4 is still tearing down the
            // popover surface caused widget-tree corruption that left favorites
            // stuck and made "Remove from Favorites" appear to do nothing.
            const pendingQuery = this._pendingFavRefreshQuery;
            this._pendingFavRefreshQuery = undefined;
            const pendingGroup = this._pendingGroupRefresh;
            this._pendingGroupRefresh = false;
            GLib.idle_add(GLib.PRIORITY_LOW, () => {
                try { pop.unparent(); } catch (_) { }
                if (pendingQuery !== undefined) {
                    this._favoritesSet = readFavorites();
                    this._refreshFavorites(pendingQuery);
                    const filtered = pendingQuery
                        ? this._allApps.filter(a => a.name.toLowerCase().includes(pendingQuery) && !this._favoritesSet.has(a.className))
                        : this._allApps.filter(a => !this._favoritesSet.has(a.className));
                    this._populateApps(filtered);
                }
                if (pendingGroup) {
                    const q = this._searchEntry
                        ? this._searchEntry.get_text().toLowerCase().trim() : '';
                    this._refreshGroups(q);
                }
                return GLib.SOURCE_REMOVE;
            });
        });
        this._popoverOpen = true;

        // ── Menu content ───────────────────────────────────────────────
        const menu = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        menu.set_margin_top(6);
        menu.set_margin_bottom(6);
        menu.set_margin_start(6);
        menu.set_margin_end(6);

        // ── Running instances (same-as-dock UX) ────────────────────────
        const key = app.className.toLowerCase();
        const instances = this._runningApps.get(key)
            ?? this._runningApps.get(app.className)
            ?? (app.steamAppId ? this._runningApps.get(app.steamAppId) : null)
            ?? [];

        if (instances.length > 0) {
            // Section header (only when more than one instance)
            if (instances.length > 1) {
                const hdr = Gtk.Label.new('Running Windows');
                hdr.set_halign(Gtk.Align.START);
                hdr.add_css_class('pop-section-header');
                menu.append(hdr);
            }

            for (const inst of instances) {
                const short = inst.title.length > 34
                    ? inst.title.slice(0, 34) + '…'
                    : inst.title;
                const focBtn = Gtk.Button.new_with_label(
                    instances.length === 1 ? `Switch to Window` : short
                );
                focBtn.add_css_class('pop-item');
                focBtn.set_halign(Gtk.Align.FILL);
                focBtn.set_tooltip_text(inst.title);
                focBtn.connect('clicked', () => {
                    focusWindow(inst.address);
                    pop.popdown();
                    this.close();
                });
                menu.append(focBtn);
            }

            const sep0 = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
            sep0.set_margin_top(4);
            sep0.set_margin_bottom(4);
            menu.append(sep0);
        }

        // ── New Window (always) — with workspace sub-popover on hover ──
        // Compute sub-popover direction (same rule as the main popover but
        // the sub-popover always opens to the opposite side of the launcher).
        const _launcherPos = this._dockPos;
        const _subPopPos = (_launcherPos === 'right')
            ? Gtk.PositionType.LEFT : Gtk.PositionType.RIGHT;

        // Helper shared by New Window and each dGPU button:
        // attaches a workspace sub-popover that opens on hover.
        // Clicking the parent button (without entering the sub-popover)
        // launches on the current workspace; clicking a WS entry first
        // switches to that workspace then launches.
        let _openSubPop = null;  // track which sub-popover is open

        const _attachLauncherWsSub = (parentBtn, launchFn) => {
            // Parent to parentBtn (inside pop's content tree) so wsSub shares
            // the same Wayland grab chain as pop.  Parenting to `this` (the
            // launcher window) gives wsSub its own grab, which immediately
            // dismisses pop when wsSub.popup() is called — causing the cascade
            // breakage (pop closes, subsequent right-clicks broken).
            // NOTE: do NOT call wsSub.unparent() in a 'closed' handler here;
            // pop's own 'closed' → idle_add(unparent) tears down the whole tree
            // including parentBtn and wsSub automatically.
            const wsSub = new Gtk.Popover();
            wsSub.set_parent(parentBtn);
            wsSub.set_has_arrow(false);
            wsSub.set_position(_subPopPos);
            wsSub.add_css_class('launcher-popover');
            wsSub.get_style_context().add_provider(
                this._getPopoverCSSProvider(),
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );

            const wsBox = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
            wsBox.set_margin_start(6);
            wsBox.set_margin_end(6);
            wsBox.set_margin_top(6);
            wsBox.set_margin_bottom(6);

            const wsHdr = Gtk.Label.new('Open on Workspace');
            wsHdr.set_halign(Gtk.Align.CENTER);
            wsHdr.add_css_class('pop-section-header');
            wsBox.append(wsHdr);

            const wsHdrSep = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
            wsHdrSep.set_margin_top(4);
            wsHdrSep.set_margin_bottom(4);
            wsBox.append(wsHdrSep);

            for (let i = 1; i <= 10; i++) {
                const wsBtn = Gtk.Button.new_with_label('→ WS ' + i);
                wsBtn.add_css_class('pop-item');
                wsBtn.set_halign(Gtk.Align.FILL);
                wsBtn.connect('clicked', () => {
                    try {
                        const cmd = app.exec.replace(/%[UuFfIiDdNnVvKk]/g, '').trim();
                        // Combine workspace focus with exec_cmd rule to fix race conditions for apps like Nautilus
                        GLib.spawn_command_line_async(`hyprctl dispatch "hl.dsp.focus({ workspace = ${i} })"`);
                        GLib.timeout_add(GLib.PRIORITY_DEFAULT, 50, () => {
                            GLib.spawn_command_line_async(`hyprctl dispatch "hl.dsp.exec_cmd('${cmd}', { workspace = ${i} })"`);
                            return GLib.SOURCE_REMOVE;
                        });
                    } catch (_) { }
                    wsSub.popdown();
                    pop.popdown();
                    this.close();
                });
                wsBox.append(wsBtn);
            }
            wsSub.set_child(wsBox);

            // Open sub-popover on hover; GTK's grab handles close-on-leave
            // automatically once the pointer exits the popover surface — no
            // manual leave handler needed (and a leave handler on wsBox would
            // fire as the cursor crosses the gap between button and popover,
            // dismissing wsSub before the user can reach it).
            const hoverCtrl = new Gtk.EventControllerMotion();
            hoverCtrl.connect('enter', () => {
                if (_openSubPop && _openSubPop !== wsSub) _openSubPop.popdown();
                _openSubPop = wsSub;
                wsSub.popup();
            });
            parentBtn.add_controller(hoverCtrl);
            wsSub.connect('closed', () => {
                if (_openSubPop === wsSub) _openSubPop = null;
            });
        };

        // New Window row with chevron hint
        const newWinRowBox = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 6);
        const newWinRowLabel = Gtk.Label.new('New Window');
        newWinRowLabel.set_halign(Gtk.Align.START);
        newWinRowLabel.set_hexpand(true);
        newWinRowBox.append(newWinRowLabel);
        const newWinChev = Gtk.Label.new('›');
        newWinChev.set_halign(Gtk.Align.END);
        newWinChev.set_valign(Gtk.Align.CENTER);
        newWinChev.set_margin_start(8);
        newWinRowBox.append(newWinChev);

        const newBtn = Gtk.Button.new();
        newBtn.set_child(newWinRowBox);
        newBtn.add_css_class('pop-item');
        newBtn.set_halign(Gtk.Align.FILL);
        const _newWinLaunch = () => { spawnApp(app.exec); };
        newBtn.connect('clicked', () => {
            _newWinLaunch();
            pop.popdown();
            this.close();
        });
        _attachLauncherWsSub(newBtn, _newWinLaunch);
        menu.append(newBtn);

        // ── Separator ──────────────────────────────────────────────────
        const sep1 = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
        sep1.set_margin_top(4);
        sep1.set_margin_bottom(4);
        menu.append(sep1);

        // ── Pin / Unpin ────────────────────────────────────────────────
        this._pinnedSet = readPinnedApps();
        // ~/.config/pinned may store the WMClass ("spotify"), the desktop ID
        // ("spotify-launcher"), or className (whichever getAllApps() resolved).
        // Check all three so the button label is always correct regardless of
        // which form was written at pin time.
        const dockKey = app.desktopId || app.className;
        const isPinned = this._pinnedSet.has(dockKey)
            || this._pinnedSet.has(app.className)
            || (app.wmClass && this._pinnedSet.has(app.wmClass));
        const pinBtn = Gtk.Button.new_with_label(isPinned ? 'Unpin from Dock' : 'Pin to Dock');
        pinBtn.add_css_class('pop-item');
        pinBtn.set_halign(Gtk.Align.FILL);
        pinBtn.connect('clicked', () => {
            this._pinnedSet = readPinnedApps();
            if (isPinned) {
                // Remove whichever form(s) are present.
                this._pinnedSet.delete(dockKey);
                this._pinnedSet.delete(app.className);
                if (app.wmClass) this._pinnedSet.delete(app.wmClass);
            } else {
                this._pinnedSet.add(dockKey);
            }
            savePinnedApps(this._pinnedSet);
            signalDockRefresh();
            pop.popdown();
        });
        menu.append(pinBtn);

        // ── Pin / Unpin Desktop ────────────────────────────────────────
        const desktopPinnedSet = readDesktopPinnedApps();
        // Use desktop file ID, not WMClass — QML resolves pinned entries via
        // DesktopEntries.byId(desktopId), so "spotify-launcher" is correct
        // whereas the WMClass "spotify" would require heuristic fallbacks.
        const desktopKey = app.desktopId || app.className;
        const isDesktopPinned = desktopPinnedSet.has(desktopKey)
            || desktopPinnedSet.has(app.className);
        const desktopPinBtn = Gtk.Button.new_with_label(isDesktopPinned ? 'Unpin from Desktop' : 'Pin to Desktop');
        desktopPinBtn.add_css_class('pop-item');
        desktopPinBtn.set_halign(Gtk.Align.FILL);
        desktopPinBtn.connect('clicked', () => {
            const ds = readDesktopPinnedApps();
            // Remove both possible stored forms (migration: old entries may
            // have been stored under WMClass; new ones use desktop file ID).
            ds.delete(app.className);
            if (desktopKey !== app.className) ds.delete(desktopKey);
            if (!isDesktopPinned) ds.add(desktopKey);
            saveDesktopPinnedApps(ds);
            pop.popdown();
        });
        menu.append(desktopPinBtn);

        // ── Favorites ──────────────────────────────────────────────────
        const sep2 = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
        sep2.set_margin_top(4);
        sep2.set_margin_bottom(4);
        menu.append(sep2);

        this._favoritesSet = readFavorites();
        const isFav = this._favoritesSet.has(app.className);
        const favBtn = Gtk.Button.new_with_label(isFav ? 'Remove from Favorites' : 'Add to Favorites');
        favBtn.add_css_class('pop-item');
        favBtn.set_halign(Gtk.Align.FILL);
        favBtn.connect('clicked', () => {
            this._favoritesSet = readFavorites();
            if (this._favoritesSet.has(app.className))
                this._favoritesSet.delete(app.className);
            else
                this._favoritesSet.add(app.className);
            writeFavorites(this._favoritesSet);
            // Capture query now (before popdown clears any state)
            const q = this._searchEntry
                ? this._searchEntry.get_text().toLowerCase().trim() : '';
            // Defer the grid refresh until after the popover is fully unparented
            // so GTK4 doesn't encounter widget-tree mutations while tearing down
            // the popover surface (which was the cause of favorites getting "stuck"
            // and Remove-from-Favorites having no visible effect).
            this._pendingFavRefreshQuery = q;
            pop.popdown();
            // _refreshFavorites will be called from the 'closed' handler once
            // pop.unparent() has been scheduled via idle_add.
        });
        menu.append(favBtn);

        // ── Groups ─────────────────────────────────────────────────────
        const sep3 = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
        sep3.set_margin_top(4);
        sep3.set_margin_bottom(4);
        menu.append(sep3);

        const groupsHdr = Gtk.Label.new('Groups');
        groupsHdr.set_halign(Gtk.Align.START);
        groupsHdr.add_css_class('pop-section-header');
        menu.append(groupsHdr);

        const currentGroups = readGroups();

        if (groupName) {
            // ── Tile is INSIDE a group — show "Remove from <groupName>" only ──
            const removeBtn = Gtk.Button.new_with_label(`Remove from "${groupName}"`);
            removeBtn.add_css_class('pop-item');
            removeBtn.set_halign(Gtk.Align.FILL);
            removeBtn.connect('clicked', () => {
                removeAppFromGroup(readGroups(), groupName, app.className);
                this._pendingGroupRefresh = true;
                pop.popdown();
            });
            menu.append(removeBtn);
        } else {
            // ── Tile is in main grid — "Remove from X", "Add to X", "New Group…" ──

            // "Remove from <group>" for each group this app already belongs to
            for (const [gName, members] of Object.entries(currentGroups)) {
                if (!members.includes(app.className)) continue;
                const removeBtn = Gtk.Button.new_with_label(`Remove from "${gName}"`);
                removeBtn.add_css_class('pop-item');
                removeBtn.set_halign(Gtk.Align.FILL);
                removeBtn.connect('clicked', () => {
                    removeAppFromGroup(readGroups(), gName, app.className);
                    this._pendingGroupRefresh = true;
                    pop.popdown();
                });
                menu.append(removeBtn);
            }

            // "Add to <group>" for each group this app is NOT yet in
            for (const [gName, members] of Object.entries(currentGroups)) {
                if (members.includes(app.className)) continue;
                const addBtn = Gtk.Button.new_with_label(`Add to "${gName}"`);
                addBtn.add_css_class('pop-item');
                addBtn.set_halign(Gtk.Align.FILL);
                addBtn.connect('clicked', () => {
                    addAppToGroup(readGroups(), gName, app.className);
                    this._pendingGroupRefresh = true;
                    pop.popdown();
                });
                menu.append(addBtn);
            }

            // "New Group…" — opens a naming dialog over the launcher window
            const newGroupBtn = Gtk.Button.new_with_label('New Group…');
            newGroupBtn.add_css_class('pop-item');
            newGroupBtn.set_halign(Gtk.Align.FILL);
            newGroupBtn.connect('clicked', () => {
                pop.popdown();
                // Show naming dialog after the popover finishes closing
                GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
                    this._showNewGroupDialog(app);
                    return GLib.SOURCE_REMOVE;
                });
            });
            menu.append(newGroupBtn);
        }
        const gpus = getAvailableDGPUs();
        if (gpus.length > 0) {
            const gpuSepTop = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
            gpuSepTop.set_margin_top(4);
            gpuSepTop.set_margin_bottom(4);
            menu.append(gpuSepTop);

            const gpuHdr = Gtk.Label.new('Launch on GPU');
            gpuHdr.set_halign(Gtk.Align.CENTER);
            gpuHdr.add_css_class('pop-section-header');
            menu.append(gpuHdr);

            const gpuSepBot = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
            gpuSepBot.set_margin_top(4);
            gpuSepBot.set_margin_bottom(4);
            menu.append(gpuSepBot);

            for (const gpu of gpus) {
                const gpuRowBox = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 6);
                const gpuRowLabel = Gtk.Label.new(abbreviateGpuName(gpu.name));
                gpuRowLabel.set_halign(Gtk.Align.START);
                gpuRowLabel.set_hexpand(true);
                gpuRowBox.append(gpuRowLabel);
                const gpuChev = Gtk.Label.new('›');
                gpuChev.set_halign(Gtk.Align.END);
                gpuChev.set_valign(Gtk.Align.CENTER);
                gpuChev.set_margin_start(8);
                gpuRowBox.append(gpuChev);

                const gpuBtn = Gtk.Button.new();
                gpuBtn.set_child(gpuRowBox);
                gpuBtn.add_css_class('pop-item');
                gpuBtn.set_halign(Gtk.Align.FILL);
                const _gpuLaunch = ((_g) => () => { spawnAppOnGPU(app.exec, _g.envVars); })(gpu);
                gpuBtn.connect('clicked', () => {
                    _gpuLaunch();
                    pop.popdown();
                    this.close();
                });
                _attachLauncherWsSub(gpuBtn, _gpuLaunch);
                menu.append(gpuBtn);
            }
        }

        pop.set_child(menu);
        pop.popup();
    }

    // ─── Group-header context menu (right-click on group bar) ────────────
    /**
     * Shows a small popover anchored to the group header row with:
     *   • Rename Group… — opens a rename dialog
     *   • Delete Group   — removes the group from disk and refreshes
     */
    _showGroupHeaderMenu(groupName, parentWidget) {
        const pos = this._dockPos;
        let popPos;
        popPos = Gtk.PositionType.TOP; // bottom, top, left,right

        const pop = new Gtk.Popover();
        pop.set_parent(this);
        pop.set_has_arrow(false);
        pop.set_position(popPos);
        {
            const [ok, bx, by] = parentWidget.translate_coordinates(this, 0, 0);
            if (ok)
                pop.set_pointing_to(new Gdk.Rectangle({
                    x: Math.round(bx), y: Math.round(by),
                    width: parentWidget.get_width(),
                    height: parentWidget.get_height(),
                }));
        }
        pop.add_css_class('launcher-popover');
        pop.get_style_context().add_provider(
            this._getPopoverCSSProvider(),
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
        pop.connect('closed', () => {
            this._popoverOpen = false;
            if (this._graceTimer) {
                GLib.source_remove(this._graceTimer);
                this._graceTimer = 0;
            }
            this._postPopoverGrace = true;
            this._graceTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT_IDLE, 600, () => {
                this._postPopoverGrace = false;
                this._graceTimer = 0;
                return GLib.SOURCE_REMOVE;
            });
            const pendingGroup = this._pendingGroupRefresh;
            this._pendingGroupRefresh = false;
            GLib.idle_add(GLib.PRIORITY_LOW, () => {
                try { pop.unparent(); } catch (_) { }
                if (pendingGroup) {
                    const q = this._searchEntry
                        ? this._searchEntry.get_text().toLowerCase().trim() : '';
                    this._refreshGroups(q);
                }
                return GLib.SOURCE_REMOVE;
            });
        });
        this._popoverOpen = true;

        const menu = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        menu.set_margin_top(6);
        menu.set_margin_bottom(6);
        menu.set_margin_start(6);
        menu.set_margin_end(6);

        // Group name as header label
        const hdr = Gtk.Label.new(groupName);
        hdr.set_halign(Gtk.Align.START);
        hdr.add_css_class('pop-section-header');
        menu.append(hdr);

        const sep1 = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
        sep1.set_margin_top(4);
        sep1.set_margin_bottom(4);
        menu.append(sep1);

        // ── Rename Group… ───────────────────────────────────────────────
        const renameBtn = Gtk.Button.new_with_label('Rename Group…');
        renameBtn.add_css_class('pop-item');
        renameBtn.set_halign(Gtk.Align.FILL);
        renameBtn.connect('clicked', () => {
            pop.popdown();
            GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
                this._showRenameGroupDialog(groupName);
                return GLib.SOURCE_REMOVE;
            });
        });
        menu.append(renameBtn);

        const sep2 = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
        sep2.set_margin_top(4);
        sep2.set_margin_bottom(4);
        menu.append(sep2);

        // ── Delete Group ────────────────────────────────────────────────
        const deleteBtn = Gtk.Button.new_with_label('Delete Group');
        deleteBtn.add_css_class('pop-item');
        deleteBtn.set_halign(Gtk.Align.FILL);
        deleteBtn.connect('clicked', () => {
            deleteGroup(readGroups(), groupName);
            // Drop stale collapse state for this group
            if (this._groupCollapsed) delete this._groupCollapsed[groupName];
            this._pendingGroupRefresh = true;
            pop.popdown();
        });
        menu.append(deleteBtn);

        pop.set_child(menu);
        pop.popup();
    }

    // ─── New-group naming dialog ─────────────────────────────────────────
    /**
     * Shows a modal-style naming dialog centered over the launcher.
     * The dialog is a layer-shell OVERLAY window parented to the same app.
     * On confirm: creates the group, adds the app, refreshes strips.
     */
    _showNewGroupDialog(app) {
        // ── Build a simple dialog window ─────────────────────────────────
        const dlg = new Gtk.Window({
            title: 'New Group',
            decorated: false,
            modal: true,
            transient_for: this,
        });
        dlg.add_css_class('hyprcandy-launcher');
        dlg.add_css_class('hyprcandy-group-dialog');

        const thisApp = this.get_application();
        if (thisApp) thisApp.add_window(dlg);

        // Use layer-shell so it floats above the launcher on Wayland
        try {
            Gtk4LayerShell.init_for_window(dlg);
            Gtk4LayerShell.set_layer(dlg, Gtk4LayerShell.Layer.OVERLAY);
            Gtk4LayerShell.set_exclusive_zone(dlg, -1);
            Gtk4LayerShell.set_keyboard_mode(dlg, Gtk4LayerShell.KeyboardMode.ON_DEMAND);
            // Centre on screen (no anchor = compositor centres it)
        } catch (_) { }

        // ── Layout ───────────────────────────────────────────────────────
        const box = Gtk.Box.new(Gtk.Orientation.VERTICAL, 12);
        box.set_margin_top(20);
        box.set_margin_bottom(20);
        box.set_margin_start(24);
        box.set_margin_end(24);
        dlg.set_child(box);

        // App name as subtitle
        const titleLbl = Gtk.Label.new(`New group for "${app.name}"`);
        titleLbl.add_css_class('fav-section-label');
        titleLbl.set_halign(Gtk.Align.START);
        box.append(titleLbl);

        // Name entry wrapped in search-frame style
        const entryFrame = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        entryFrame.add_css_class('search-frame');
        box.append(entryFrame);

        const nameEntry = new Gtk.Entry();
        nameEntry.set_placeholder_text('Group name…');
        nameEntry.add_css_class('launcher-search');
        nameEntry.set_hexpand(true);
        entryFrame.append(nameEntry);

        // Buttons row
        const btnRow = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 8);
        btnRow.set_halign(Gtk.Align.END);
        box.append(btnRow);

        const cancelBtn = Gtk.Button.new_with_label('Cancel');
        cancelBtn.add_css_class('pop-item');
        btnRow.append(cancelBtn);

        const createBtn = Gtk.Button.new_with_label('Create');
        createBtn.add_css_class('pop-item');
        btnRow.append(createBtn);

        dlg.set_size_request(320, -1);

        // ── Actions ──────────────────────────────────────────────────────
        const doCreate = () => {
            const name = nameEntry.get_text().trim();
            if (!name) return;
            addAppToGroup(readGroups(), name, app.className);
            dlg.close();
            dlg.destroy();
            // Expand the new group immediately
            if (!this._groupCollapsed) this._groupCollapsed = {};
            this._groupCollapsed[name] = false;
            const curQ = this._searchEntry
                ? this._searchEntry.get_text().toLowerCase().trim() : '';
            this._refreshGroups(curQ);
        };

        createBtn.connect('clicked', doCreate);
        nameEntry.connect('activate', doCreate);
        cancelBtn.connect('clicked', () => { dlg.close(); dlg.destroy(); });

        // ESC closes the dialog
        const kc = new Gtk.EventControllerKey();
        kc.connect('key-pressed', (_ctrl, keyval) => {
            if (keyval === Gdk.KEY_Escape) { dlg.close(); dlg.destroy(); return true; }
            return false;
        });
        dlg.add_controller(kc);

        dlg.set_hide_on_close(false);
        dlg.present();
        nameEntry.grab_focus();
    }

    // ─── Rename-group dialog ──────────────────────────────────────────────
    /**
     * Shows a layer-shell dialog pre-filled with the current group name.
     * On confirm: renames the group in the JSON file and refreshes strips.
     */
    _showRenameGroupDialog(groupName) {
        const dlg = new Gtk.Window({
            title: 'Rename Group',
            decorated: false,
            modal: true,
            transient_for: this,
        });
        dlg.add_css_class('hyprcandy-launcher');
        dlg.add_css_class('hyprcandy-group-dialog');

        const thisApp = this.get_application();
        if (thisApp) thisApp.add_window(dlg);

        try {
            Gtk4LayerShell.init_for_window(dlg);
            Gtk4LayerShell.set_layer(dlg, Gtk4LayerShell.Layer.OVERLAY);
            Gtk4LayerShell.set_exclusive_zone(dlg, -1);
            Gtk4LayerShell.set_keyboard_mode(dlg, Gtk4LayerShell.KeyboardMode.ON_DEMAND);
            // No anchor → compositor centres the dialog
        } catch (_) { }

        const box = Gtk.Box.new(Gtk.Orientation.VERTICAL, 12);
        box.set_margin_top(20);
        box.set_margin_bottom(20);
        box.set_margin_start(24);
        box.set_margin_end(24);
        dlg.set_child(box);

        const titleLbl = Gtk.Label.new(`Rename group "${groupName}"`);
        titleLbl.add_css_class('fav-section-label');
        titleLbl.set_halign(Gtk.Align.START);
        box.append(titleLbl);

        const entryFrame = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        entryFrame.add_css_class('search-frame');
        box.append(entryFrame);

        const nameEntry = new Gtk.Entry();
        nameEntry.set_placeholder_text('New group name…');
        nameEntry.set_text(groupName);           // pre-fill with current name
        nameEntry.add_css_class('launcher-search');
        nameEntry.set_hexpand(true);
        entryFrame.append(nameEntry);

        const btnRow = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 8);
        btnRow.set_halign(Gtk.Align.END);
        box.append(btnRow);

        const cancelBtn = Gtk.Button.new_with_label('Cancel');
        cancelBtn.add_css_class('pop-item');
        btnRow.append(cancelBtn);

        const confirmBtn = Gtk.Button.new_with_label('Rename');
        confirmBtn.add_css_class('pop-item');
        btnRow.append(confirmBtn);

        dlg.set_size_request(320, -1);

        const doRename = () => {
            const newName = nameEntry.get_text().trim();
            if (!newName) return;
            if (newName !== groupName)
                renameGroup(readGroups(), groupName, newName);
            dlg.close();
            dlg.destroy();
            // Migrate collapse state to the new name
            if (!this._groupCollapsed) this._groupCollapsed = {};
            this._groupCollapsed[newName] = this._groupCollapsed[groupName] ?? true;
            delete this._groupCollapsed[groupName];
            const curQ = this._searchEntry
                ? this._searchEntry.get_text().toLowerCase().trim() : '';
            this._refreshGroups(curQ);
        };

        confirmBtn.connect('clicked', doRename);
        nameEntry.connect('activate', doRename);
        cancelBtn.connect('clicked', () => { dlg.close(); dlg.destroy(); });

        const kc = new Gtk.EventControllerKey();
        kc.connect('key-pressed', (_ctrl, keyval) => {
            if (keyval === Gdk.KEY_Escape) { dlg.close(); dlg.destroy(); return true; }
            return false;
        });
        dlg.add_controller(kc);

        dlg.set_hide_on_close(false);
        dlg.present();
        nameEntry.grab_focus();
        nameEntry.select_region(0, -1);  // select all so user can type straight away
    }

    // ─── Keyboard / close ────────────────────────────────────────────────

    _setupKeyboard() {
        const cols = this._isVert ? COLS_VERT : COLS_HORIZ;
        const TAB_IDS = ['launcher', 'clipboard', 'emoji', 'websearch', 'agent'];

        // Helper: retrieve navigatable UI elements in natural top-to-bottom order
        const getNavElements = () => {
            const list = [];
            // 1. Favorites header (+ flow if expanded)
            if (this._favSection?.get_visible() && this._favToggleBtn) {
                list.push({ type: 'header', widget: this._favToggleBtn, toggleFn: this._toggleFav });
                if (!this._favCollapsed && this._favFlow?.get_visible() && flowCount(this._favFlow) > 0) {
                    list.push({ type: 'flow', widget: this._favFlow });
                }
            }
            // 2. Group strips (header + flow if expanded)
            if (this._groupsContainer?.get_visible()) {
                let strip = this._groupsContainer.get_first_child();
                while (strip) {
                    if (strip._toggleBtn) {
                        list.push({ type: 'header', widget: strip._toggleBtn, toggleFn: strip._toggleFn });
                        if (strip._flow && strip._flow.get_visible() && flowCount(strip._flow) > 0) {
                            list.push({ type: 'flow', widget: strip._flow });
                        }
                    }
                    strip = strip.get_next_sibling();
                }
            }
            // 3. Main grid
            if (this._flow?.get_visible() && flowCount(this._flow) > 0) {
                list.push({ type: 'flow', widget: this._flow });
            }
            return list;
        };

        const focusNav = (elem, pos = 'first') => {
            if (!elem) return;
            if (elem.type === 'header') {
                elem.widget.grab_focus();
            } else if (elem.type === 'flow') {
                const fb = elem.widget;
                if (pos === 'last') {
                    let last = fb.get_first_child();
                    while (last?.get_next_sibling()) last = last.get_next_sibling();
                    if (last) {
                        fb.select_child(last);
                        last.grab_focus();
                    } else {
                        fb.grab_focus();
                    }
                } else {
                    const first = fb.get_first_child();
                    if (first) {
                        fb.select_child(first);
                        first.grab_focus();
                    } else {
                        fb.grab_focus();
                    }
                }
            }
        };

        // ── Window-level key handler in CAPTURE phase ─────────────────────
        const winKc = new Gtk.EventControllerKey();
        winKc.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
        winKc.connect('key-pressed', (_ctrl, keyval, _code, state) => {
            if (keyval === Gdk.KEY_Escape) { this.close(); return true; }

            // Ctrl+Tab cycle between sidebar tabs
            const ctrl = (state & Gdk.ModifierType.CONTROL_MASK) !== 0;
            if (ctrl && keyval === Gdk.KEY_Tab) {
                const idx = TAB_IDS.indexOf(this._activeTab);
                const next = TAB_IDS[(idx + 1) % TAB_IDS.length];
                this._switchTab(next);
                return true;
            }

            // Only custom-handle arrow/return navigation on the Launcher tab
            if (this._activeTab !== 'launcher') return false;

            const nav = getNavElements();
            if (nav.length === 0) return false;

            const focused = this.get_focus();
            const isSearch = !focused || focused === this._searchEntry || widgetContains(this._searchEntry, focused);

            // ── Case 1: Focus is in Search Entry ─────────────────────────────
            if (isSearch) {
                if (keyval === Gdk.KEY_Down) {
                    focusNav(nav[0], 'first');
                    return true;
                }
                if (keyval === Gdk.KEY_Up) {
                    focusNav(nav[nav.length - 1], 'last');
                    return true;
                }
                return false;
            }

            // ── Case 2: Focus is on a Section Header ─────────────────────────
            const headerIdx = nav.findIndex(n => n.type === 'header' && (n.widget === focused || widgetContains(n.widget, focused)));
            if (headerIdx !== -1) {
                const item = nav[headerIdx];
                if (keyval === Gdk.KEY_Return || keyval === Gdk.KEY_KP_Enter || keyval === Gdk.KEY_space) {
                    if (item.toggleFn) item.toggleFn();
                    return true;
                }
                if (keyval === Gdk.KEY_Down) {
                    if (headerIdx < nav.length - 1) {
                        focusNav(nav[headerIdx + 1], 'first');
                    } else {
                        this._searchEntry.grab_focus();
                    }
                    return true;
                }
                if (keyval === Gdk.KEY_Up) {
                    if (headerIdx > 0) {
                        focusNav(nav[headerIdx - 1], 'last');
                    } else {
                        this._searchEntry.grab_focus();
                    }
                    return true;
                }
                return false;
            }

            // ── Case 3: Focus is inside a FlowBox (App Grid / Fav / Group) ───
            const flowIdx = nav.findIndex(n => n.type === 'flow' && (n.widget === focused || widgetContains(n.widget, focused)));
            if (flowIdx !== -1) {
                const fb = nav[flowIdx].widget;
                if (keyval === Gdk.KEY_Return || keyval === Gdk.KEY_KP_Enter) {
                    const active = getFlowActiveChild(fb);
                    const appData = getAppDataFromChild(active);
                    if (appData && appData.exec) {
                        spawnApp(appData.exec);
                        this.close();
                        return true;
                    }
                    return false;
                }

                // Left Arrow: wrap from first item to last item
                if (keyval === Gdk.KEY_Left) {
                    const idx = flowSelIdx(fb);
                    if (idx <= 0) {
                        focusNav(nav[flowIdx], 'last');
                        return true;
                    }
                    return false;
                }

                // Right Arrow: wrap from last item to first item
                if (keyval === Gdk.KEY_Right) {
                    const idx = flowSelIdx(fb);
                    const total = flowCount(fb);
                    if (idx >= total - 1) {
                        focusNav(nav[flowIdx], 'first');
                        return true;
                    }
                    return false;
                }

                // Down Arrow: move to next section or search
                if (keyval === Gdk.KEY_Down) {
                    const idx = flowSelIdx(fb);
                    const total = flowCount(fb);
                    const lastRowStart = total > 0 ? Math.floor((total - 1) / cols) * cols : 0;
                    if (idx >= lastRowStart) {
                        if (flowIdx < nav.length - 1) {
                            focusNav(nav[flowIdx + 1], 'first');
                        } else {
                            this._searchEntry.grab_focus();
                        }
                        return true;
                    }
                    return false;
                }

                // Up Arrow: move to previous section or search
                if (keyval === Gdk.KEY_Up) {
                    const idx = flowSelIdx(fb);
                    if (idx >= 0 && idx < cols) {
                        if (flowIdx > 0) {
                            focusNav(nav[flowIdx - 1], 'last');
                        } else {
                            this._searchEntry.grab_focus();
                        }
                        return true;
                    }
                    return false;
                }

                if (keyval === Gdk.KEY_BackSpace ||
                    (keyval >= Gdk.KEY_space && keyval <= Gdk.KEY_asciitilde)) {
                    this._searchEntry.grab_focus();
                    return false;
                }
            }

            return false;
        });
        this.add_controller(winKc);
    }

    /**
     * Close when the launcher window loses compositor focus — gives the
     * same click-outside-to-dismiss behaviour as rofi.
     * Guards:
     *   _popoverOpen      — a context-menu popover is currently visible
     *   _postPopoverGrace — popover just closed; wait 600 ms before allowing
     *                       focus-loss to dismiss (keeps launcher alive after
     *                       "Pin to Dock" which popdowns the menu)
     */
    // ── CSS hot-reload (mirrors dock-main.js setupColorMonitor) ─────────────

    _setupColorMonitor() {
        const file = Gio.File.new_for_path(GTK4_COLORS_PATH);
        try {
            this._colorMonitor = file.monitor_file(Gio.FileMonitorFlags.NONE, null);
            this._colorMonitor.connect('changed', (_m, _f, _o, ev) => {
                if (ev !== Gio.FileMonitorEvent.CHANGES_DONE_HINT &&
                    ev !== Gio.FileMonitorEvent.CREATED) return;
                if (this._colorReloadTimer) {
                    GLib.source_remove(this._colorReloadTimer);
                    this._colorReloadTimer = 0;
                }
                this._colorReloadTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT_IDLE, 300, () => {
                    this._colorReloadTimer = 0;
                    this._loadGlobalCSS();
                    this.queue_draw();
                    return GLib.SOURCE_REMOVE;
                });
            });
        } catch (e) {
            console.warn('[launcher] color monitor setup failed:', e.message);
        }
    }

    _teardownColorMonitor() {
        if (this._colorReloadTimer) {
            GLib.source_remove(this._colorReloadTimer);
            this._colorReloadTimer = 0;
        }
        if (this._colorMonitor) {
            this._colorMonitor.cancel();
            this._colorMonitor = null;
        }
    }

    // ── App directory hot-reload ─────────────────────────────────────────
    // Watches XDG application directories so newly installed or removed
    // apps are reflected without restarting the launcher daemon.
    // A 500 ms debounce prevents rapid successive refreshes during batch
    // installs.  If the launcher is hidden the dirty flag is set and the
    // list is refreshed on the next show (SIGUSR1 path).

    _setupAppDirMonitors() {
        const dirs = [];
        // User applications directory
        try {
            const userApps = GLib.build_filenamev([GLib.get_user_data_dir(), 'applications']);
            if (GLib.file_test(userApps, GLib.FileTest.EXISTS)) dirs.push(userApps);
        } catch (_) { }
        // System applications directories
        try {
            for (const d of GLib.get_system_data_dirs()) {
                const sysApps = GLib.build_filenamev([d, 'applications']);
                if (GLib.file_test(sysApps, GLib.FileTest.EXISTS)) dirs.push(sysApps);
            }
        } catch (_) { }
        // Flatpak exports (user + system)
        try {
            const flatpakUser = GLib.build_filenamev([HOME, '.local', 'share', 'flatpak', 'exports', 'share', 'applications']);
            if (GLib.file_test(flatpakUser, GLib.FileTest.EXISTS)) dirs.push(flatpakUser);
        } catch (_) { }
        try {
            const flatpakSystem = '/var/lib/flatpak/exports/share/applications';
            if (GLib.file_test(flatpakSystem, GLib.FileTest.EXISTS)) dirs.push(flatpakSystem);
        } catch (_) { }
        // ~/Desktop — Steam creates game shortcuts here as plain .desktop files.
        // Gio.AppInfo.get_all() doesn't scan it, but we do in getAllApps().
        try {
            const desktopDir = GLib.build_filenamev([HOME, 'Desktop']);
            if (GLib.file_test(desktopDir, GLib.FileTest.EXISTS)) dirs.push(desktopDir);
        } catch (_) { }

        for (const dirPath of dirs) {
            try {
                const dir = Gio.File.new_for_path(dirPath);
                const mon = dir.monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, null);
                mon.connect('changed', (_m, _f, _other, ev) => {
                    if (ev !== Gio.FileMonitorEvent.CHANGES_DONE_HINT &&
                        ev !== Gio.FileMonitorEvent.CREATED &&
                        ev !== Gio.FileMonitorEvent.DELETED &&
                        ev !== Gio.FileMonitorEvent.RENAMED) return;
                    this._appsDirty = true;
                    // If currently visible, debounced refresh
                    if (this.get_visible()) {
                        if (this._appDirReloadTimer) {
                            GLib.source_remove(this._appDirReloadTimer);
                            this._appDirReloadTimer = 0;
                        }
                        this._appDirReloadTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT_IDLE, 500, () => {
                            this._appDirReloadTimer = 0;
                            this._reloadAndRefreshApps();
                            return GLib.SOURCE_REMOVE;
                        });
                    }
                });
                this._appDirMonitors.push(mon);
            } catch (e) {
                console.warn('[launcher] app-dir monitor failed for', dirPath, e.message);
            }
        }
    }

    _teardownAppDirMonitors() {
        if (this._appDirReloadTimer) {
            GLib.source_remove(this._appDirReloadTimer);
            this._appDirReloadTimer = 0;
        }
        for (const mon of this._appDirMonitors) {
            try { mon.cancel(); } catch (_) { }
        }
        this._appDirMonitors = [];
    }

    _reloadAndRefreshApps() {
        this._allApps = getAllApps();
        this._appsDirty = false;
        const q = this._searchEntry ? this._searchEntry.get_text().toLowerCase().trim() : '';
        this._favoritesSet = readFavorites();
        this._runningApps = getRunningApps();
        this._refreshFavorites(q);
        this._refreshGroups(q);
        const filtered = q ? this._allApps.filter(a => a.name.toLowerCase().includes(q)) : this._allApps;
        this._populateApps(filtered);
        console.log('[launcher] app list refreshed —', this._allApps.length, 'apps');
    }


    // Mark the launcher as "WebView busy" for `ms` (default 600, matching the
    // existing post-popover grace window). While busy, the background
    // click-catcher and the empty-space-click-to-close gesture both bail out
    // instead of hiding the launcher. Call this from any WebKit signal whose
    // firing can transiently restructure the widget tree or synthesize a
    // native dialog/popover (fullscreen transitions, permission requests,
    // script dialogs, popup creation) so that churn is never misread as
    // "the user clicked outside the launcher."
    _markWebviewBusy(ms = 600) {
        this._webviewBusy = true;
        if (this._webviewBusyTimer) {
            GLib.source_remove(this._webviewBusyTimer);
            this._webviewBusyTimer = 0;
        }
        this._webviewBusyTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT_IDLE, ms, () => {
            this._webviewBusy = false;
            this._webviewBusyTimer = 0;
            return GLib.SOURCE_REMOVE;
        });
    }

    _setupFocusClose() {
        this._bgWin = null;

        // ── 1. TOP-layer transparent click-catcher ─────────────────────
        // Covers the full screen at the TOP layer (normal windows level.
        try {
            const bgWin = new Gtk.Window({ decorated: false });
            const thisApp = this.get_application();
            if (thisApp) thisApp.add_window(bgWin);

            Gtk4LayerShell.init_for_window(bgWin);
            Gtk4LayerShell.set_namespace(bgWin, 'hyprcandy-launcher-bg');
            Gtk4LayerShell.set_layer(bgWin, Gtk4LayerShell.Layer.TOP);
            Gtk4LayerShell.set_exclusive_zone(bgWin, -1);
            // Anchor all four edges → covers the full output
            Gtk4LayerShell.set_anchor(bgWin, Gtk4LayerShell.Edge.TOP, true);
            Gtk4LayerShell.set_anchor(bgWin, Gtk4LayerShell.Edge.BOTTOM, true);
            Gtk4LayerShell.set_anchor(bgWin, Gtk4LayerShell.Edge.LEFT, true);
            Gtk4LayerShell.set_anchor(bgWin, Gtk4LayerShell.Edge.RIGHT, true);

            // Fully transparent content — must have a child or GTK won't map it
            bgWin.set_child(new Gtk.Box());
            bgWin.set_opacity(0.002);  // non-zero so the compositor maps the surface

            const bgClick = new Gtk.GestureClick();
            bgClick.connect('pressed', () => {
                if (this._fileChooserOpen) return;
                if (this._webviewBusy) return;
                // set_visible(false) on the launcher triggers notify::visible
                // which hides bgWin automatically (see handler below).
                this.set_visible(false);
            });
            bgWin.add_controller(bgClick);

            bgWin.set_visible(false);
            this._bgWin = bgWin;
        } catch (e) {
            console.warn('[launcher] click-catcher setup failed:', e.message);
        }

        // Sync bgWin visibility with the launcher — single source of truth.
        // Covers ALL hide paths: ESC, app-tile click, empty-space click,
        // SIGUSR1 hide, and the bgWin click handler above.
        this.connect('notify::visible', () => {
            if (this._bgWin) this._bgWin.set_visible(this.get_visible());
            // Show/hide the embedded Electron agent renderer in lockstep with the
            // launcher layer window.  This avoids the always-on-top Electron window
            // "ghosting" over other workspaces when the launcher is hidden.
            try {
                if (this._agentElectronProc && !this._agentElectronExited && this._agentUsingElectron) {
                    const msgType = this.get_visible()
                        ? JSON.stringify({ type: 'show' }) + '\n'
                        : JSON.stringify({ type: 'hide' }) + '\n';
                    if (this._agentElectronStdin) {
                        try {
                            const b = new TextEncoder().encode(msgType);
                            this._agentElectronStdin.write_all(b, null);
                        } catch (_) { }
                    }
                }
            } catch (_) { }
            // Write launcher state so dock-main.js can suppress autohide
            // while the launcher is visible.
            try {
                const stateDir = GLib.build_filenamev([HOME, '.cache', 'hyprcandy']);
                const statePath = GLib.build_filenamev([stateDir, 'launcher.state']);
                GLib.mkdir_with_parents(stateDir, 0o755);
                const content = this.get_visible() ? 'open\n' : 'closed\n';
                const bytes = new TextEncoder().encode(content);
                GLib.file_set_contents(statePath, bytes);
            } catch (e) {
                // Non-fatal — dock autohide guard is best-effort
            }
            // Invalidate the module-level running-apps cache on hide so the
            // next show always calls hyprctl fresh rather than returning
            // potentially stale window data from the previous toggle.
            if (!this.get_visible()) {
                _runningAppsCache = null;
                _runningAppsCacheUs = 0;
                this._persistWebState();
                try {
                    imports.system.gc();
                } catch (_) { }
            }
        });

        // ── 2. Empty-space-click-to-close (BUBBLE-phase gesture) ─────────
        // GtkButton and GtkSearchEntry claim their gesture sequences during
        // BUBBLE propagation, denying parent gestures for the same sequence.
        // A GestureClick on the root box therefore only fires when the click
        // lands on blank background / padding that no child widget consumed —
        // i.e. "empty space" inside the launcher frame.
        const rootChild = this.get_child();
        if (rootChild) {
            const emptyClick = new Gtk.GestureClick();
            emptyClick.set_button(1);   // primary / left button only
            emptyClick.connect('released', (_g, _n, x, y) => {
                if (!this.get_visible()) return;
                if (this._popoverOpen || this._postPopoverGrace || this._fileChooserOpen) return;
                if (this._webviewBusy) return;
                // pick() returns the deepest widget under the pointer; if it
                // resolves to something other than the root box (or window),
                // an interactive child already claimed the sequence — skip.
                // Walk the ancestor chain (not just a direct-equality check)
                // so that any descendant of an embedded WebView — including
                // internal WebKit sub-widgets whose exact identity can shift
                // during ad-blocked/partially-loaded page churn — is treated
                // as "consumed" rather than "empty space".
                const pick = this.pick(
                    x + rootChild.get_margin_start(),
                    y + rootChild.get_margin_top(),
                    Gtk.PickFlags.DEFAULT
                );
                if (pick && pick !== rootChild && pick !== this) {
                    let node = pick;
                    while (node) {
                        if (node === rootChild) break;
                        if (typeof node.get_css_classes === 'function') {
                            const classes = node.get_css_classes();
                            if (classes && (classes.includes('searx-webview') || classes.includes('searx-webview-wrap'))) {
                                return; // click landed inside an embedded WebView — never treat as empty space.
                            }
                        }
                        node = (typeof node.get_parent === 'function') ? node.get_parent() : null;
                    }
                    return;
                }
                this.set_visible(false);
            });
            rootChild.add_controller(emptyClick);
        }
    }

    // ── Fix 1: safe favorites clear ──────────────────────────────────────
    // Uses get_first_child() each iteration so GTK4 sibling pointer
    // rebinding after remove() never leaves a stale reference (fixes
    // the single-last-favorite stuck-tile bug).

    // ── Web Search Tab — SearXNG native results ──────────────────────────────
    //
    // Architecture:
    //   • Header row: SearXNG title + Docker toggle button (start/stop container)
    //   • Status card: shown when Docker is stopped, starting, or unreachable
    //   • Native Gtk.ListBox: one row per SearXNG result — no WebKitGTK
    //   • Soup 3 async GET to http://127.0.0.1:8080/search?q=…&format=json
    //   • Fallback: xdg-open to SearXNG HTML when JSON fails
    //
    // Setup (first use):
    //   cd ~/.hyprcandy/GJS/hyprcandydock && docker compose up -d
    //   Settings are in ./searxng-settings/settings.yml (JSON format enabled)

    _buildWebSearchTab(ip) {
        const page = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        page.set_hexpand(true);
        page.set_vexpand(true);

        // ── Header: title + Docker toggle ────────────────────────────────
        // The header is intentionally outside the bordered result/list frame.
        const headerLeft = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 6);
        headerLeft.add_css_class('searx-header-row');
        headerLeft.set_valign(Gtk.Align.CENTER);
        if (this._webHeaderLeftSlot) this._webHeaderLeftSlot.append(headerLeft);
        else page.append(headerLeft);

        const titleBtn = Gtk.Button.new();
        titleBtn.add_css_class('searx-title-btn');
        titleBtn.set_valign(Gtk.Align.CENTER);
        titleBtn.set_can_focus(false);
        titleBtn.set_tooltip_text('Open SearXNG source repository (GitHub)');

        const titleBtnBox = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 6);
        titleBtnBox.set_valign(Gtk.Align.CENTER);

        const titleGlyph = Gtk.Label.new('󱎸');
        titleGlyph.add_css_class('searx-title-glyph');
        titleGlyph.set_valign(Gtk.Align.CENTER);
        titleBtnBox.append(titleGlyph);

        const titleLbl = Gtk.Label.new('SearXNG');
        titleLbl.add_css_class('searx-title-label');
        titleLbl.set_halign(Gtk.Align.START);
        titleBtnBox.append(titleLbl);

        titleBtn.set_child(titleBtnBox);
        titleBtn.connect('clicked', () => {
            this._searxOpenUrlInNewTab('https://github.com/searxng/searxng', 'SearXNG GitHub');
        });
        headerLeft.append(titleBtn);

        // Bookmarks toggle button — placed next to SearXNG button with 6px margin
        const bookmarksBtnBox = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 0);
        bookmarksBtnBox.set_valign(Gtk.Align.CENTER);
        const bookmarksGlyph = Gtk.Label.new('󰃀');
        bookmarksGlyph.add_css_class('searx-bookmarks-glyph');
        bookmarksGlyph.set_valign(Gtk.Align.CENTER);
        bookmarksBtnBox.append(bookmarksGlyph);
        const bookmarksLbl = Gtk.Label.new('Bookmarks');
        bookmarksLbl.add_css_class('searx-bookmarks-label');
        bookmarksBtnBox.append(bookmarksLbl);

        const bookmarksBtn = Gtk.Button.new();
        bookmarksBtn.add_css_class('searx-bookmarks-btn');
        bookmarksBtn.set_can_focus(false);
        bookmarksBtn.set_valign(Gtk.Align.CENTER);
        bookmarksBtn.set_child(bookmarksBtnBox);
        bookmarksBtn.set_visible(!!(this._searxBookmarks && this._searxBookmarks.length > 0));
        bookmarksBtn.connect('clicked', () => this._searxShowBookmarksPopover(bookmarksBtn));
        headerLeft.append(bookmarksBtn);
        this._bookmarksBtn = bookmarksBtn;
        this._bookmarksGlyph = bookmarksGlyph;

        // ── Header Tabs button (visible in plain search mode when open tabs exist) ─
        const headerTabsBtn = Gtk.Button.new();
        headerTabsBtn.add_css_class('searx-header-tabs-btn');
        headerTabsBtn.set_valign(Gtk.Align.CENTER);
        headerTabsBtn.set_can_focus(false);
        headerTabsBtn.set_visible(false);
        const headerTabsBox = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 4);
        headerTabsBox.set_valign(Gtk.Align.CENTER);
        const headerTabsGlyph = Gtk.Label.new('󰖟');
        headerTabsGlyph.add_css_class('searx-header-tabs-glyph');
        headerTabsBox.append(headerTabsGlyph);
        const headerTabsLbl = Gtk.Label.new('Tabs (0)');
        headerTabsLbl.add_css_class('searx-header-tabs-label');
        this._searxHeaderTabsLbl = headerTabsLbl;
        headerTabsBox.append(headerTabsLbl);
        const headerTabsChev = Gtk.Label.new('󰅀');
        headerTabsChev.add_css_class('searx-tabs-chevron');
        headerTabsBox.append(headerTabsChev);
        headerTabsBtn.set_child(headerTabsBox);
        this._searxHeaderTabsBtn = headerTabsBtn;
        headerTabsBtn.connect('clicked', () => this._searxShowTabsPopover(headerTabsBtn));
        if (this._webHeaderRightSlot) this._webHeaderRightSlot.append(headerTabsBtn);

        // ── "+ New Tab" button ───────────────────────────────────────────
        const newTabBtn = Gtk.Button.new();
        newTabBtn.add_css_class('searx-newtab-btn');
        newTabBtn.set_valign(Gtk.Align.CENTER);
        newTabBtn.set_can_focus(false);
        const newTabBox = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 4);
        newTabBox.set_valign(Gtk.Align.CENTER);
        const newTabGlyph = Gtk.Label.new('󰐕');
        newTabGlyph.add_css_class('searx-newtab-glyph');
        newTabBox.append(newTabGlyph);
        const newTabLbl = Gtk.Label.new('New Tab');
        newTabLbl.add_css_class('searx-newtab-label');
        newTabBox.append(newTabLbl);
        newTabBtn.set_child(newTabBox);
        this._searxNewTabBtn = newTabBtn;
        newTabBtn.connect('clicked', () => this._searxCreateNewTab());
        if (this._webHeaderRightSlot) this._webHeaderRightSlot.append(newTabBtn);

        // Docker toggle button
        const dockerBtn = Gtk.Button.new();
        dockerBtn.add_css_class('searx-docker-btn');
        dockerBtn.set_can_focus(false);
        dockerBtn.set_valign(Gtk.Align.CENTER);
        const dockerBtnBox = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 0);
        dockerBtnBox.set_valign(Gtk.Align.CENTER);
        const dockerGlyph = Gtk.Label.new('󰡨');
        dockerGlyph.add_css_class('searx-docker-glyph');
        this._searxDockerGlyph = dockerGlyph;
        dockerBtnBox.append(dockerGlyph);
        const dockerLbl = Gtk.Label.new('Docker');
        dockerLbl.add_css_class('searx-docker-label');
        this._searxDockerLbl = dockerLbl;
        dockerBtnBox.append(dockerLbl);
        dockerBtn.set_child(dockerBtnBox);
        this._searxDockerBtn = dockerBtn;
        dockerBtn.connect('clicked', () => this._searxToggleDocker());
        if (this._webHeaderRightSlot) this._webHeaderRightSlot.append(dockerBtn);

        // ── Status card (offline / loading / empty) ───────────────────────
        const statusCard = Gtk.Box.new(Gtk.Orientation.VERTICAL, 4);
        statusCard.add_css_class('searx-status-card');
        statusCard.set_halign(Gtk.Align.FILL);
        statusCard.set_valign(Gtk.Align.START);
        statusCard.set_visible(true);
        this._searxStatusCard = statusCard;
        page.append(statusCard);

        const statusGlyph = Gtk.Label.new('󰡨');
        statusGlyph.add_css_class('searx-status-glyph');
        statusGlyph.set_halign(Gtk.Align.CENTER);
        this._searxStatusGlyph = statusGlyph;
        statusCard.append(statusGlyph);

        const statusTitle = Gtk.Label.new('Docker stopped');
        statusTitle.add_css_class('searx-status-title');
        statusTitle.set_halign(Gtk.Align.CENTER);
        statusTitle.set_wrap(true);
        statusTitle.set_max_width_chars(32);
        this._searxStatusTitle = statusTitle;
        statusCard.append(statusTitle);

        const statusBody = Gtk.Label.new('Click Start SearXNG or the Docker button above to launch.');
        statusBody.add_css_class('searx-status-body');
        statusBody.set_halign(Gtk.Align.CENTER);
        statusBody.set_wrap(true);
        statusBody.set_max_width_chars(40);
        this._searxStatusBody = statusBody;
        statusCard.append(statusBody);

        // Action button (Start SearXNG / Retry)
        const actionBtn = Gtk.Button.new_with_label('󰡨  Start SearXNG');
        actionBtn.add_css_class('searx-action-btn');
        actionBtn.set_halign(Gtk.Align.CENTER);
        actionBtn.set_visible(true);
        this._searxActionBtn = actionBtn;
        actionBtn.connect('clicked', () => this._searxToggleDocker());
        statusCard.append(actionBtn);

        // Fallback: open in browser
        const fallbackBtn = Gtk.Button.new_with_label('󰖟  Open in Browser');
        fallbackBtn.add_css_class('searx-fallback-btn');
        fallbackBtn.set_halign(Gtk.Align.CENTER);
        fallbackBtn.set_visible(false);
        this._searxFallbackBtn = fallbackBtn;
        fallbackBtn.connect('clicked', () => {
            const q = this._searchEntry.get_text().trim();
            const url = q
                ? `http://127.0.0.1:8080/search?q=${encodeURIComponent(q)}`
                : 'http://127.0.0.1:8080';
            openInBrowser(url);
            this.close();
        });
        statusCard.append(fallbackBtn);

        // ── Result list (native Gtk.ListBox) ──────────────────────────────
        const resultScroll = new Gtk.ScrolledWindow();
        resultScroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        resultScroll.set_vexpand(true);
        resultScroll.add_css_class('launcher-scroll');
        resultScroll.set_margin_start(6);
        resultScroll.set_margin_end(8);
        resultScroll.set_margin_bottom(8);
        resultScroll.set_visible(false);
        this._searxResultScroll = resultScroll;
        page.append(resultScroll);

        const listBox = new Gtk.ListBox();
        listBox.add_css_class('searx-list');
        listBox.set_selection_mode(Gtk.SelectionMode.NONE);
        listBox.set_vexpand(false);
        listBox.set_valign(Gtk.Align.START);
        this._searxList = listBox;
        resultScroll.set_child(listBox);

        // ── Embedded WebKit View (multi-tab content stack) ────────────────
        const webBox = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        webBox.add_css_class('searx-webview-box');
        // GTK4's CSS engine has no "overflow" property — it's rejected by
        // the theme parser (logged as "Theme parser error: No property
        // named 'overflow'") and silently does nothing, so the box's
        // rounded corners were never actually clipping their children.
        // Gtk.Widget.set_overflow() is the real API for this.
        webBox.set_overflow(Gtk.Overflow.HIDDEN);
        webBox.set_vexpand(true);
        webBox.set_hexpand(true);
        webBox.set_visible(false);
        this._searxWebBox = webBox;
        page.append(webBox);

        // Mini web toolbar
        const webBar = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 6);
        webBar.add_css_class('searx-webview-bar');
        webBar.set_valign(Gtk.Align.CENTER);
        webBox.append(webBar);
        this._searxWebBar = webBar;

        const backBtn = Gtk.Button.new_with_label('󰁍  Results');
        backBtn.add_css_class('searx-nav-btn');
        backBtn.set_valign(Gtk.Align.CENTER);
        backBtn.connect('clicked', () => this._searxCloseWebView());
        webBar.append(backBtn);

        // Interactive Title + URL section (triggers tabs popover)
        const infoBtn = Gtk.Button.new();
        infoBtn.add_css_class('searx-nav-info-btn');
        infoBtn.set_hexpand(true);
        infoBtn.set_valign(Gtk.Align.CENTER);
        this._searxWebInfoBtn = infoBtn;

        const infoBtnBox = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 4);
        infoBtnBox.set_valign(Gtk.Align.CENTER);

        const webInfoCol = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        webInfoCol.set_hexpand(true);
        webInfoCol.set_valign(Gtk.Align.CENTER);
        infoBtnBox.append(webInfoCol);

        const navTitle = Gtk.Label.new('Web Page');
        navTitle.add_css_class('searx-nav-title');
        navTitle.set_halign(Gtk.Align.START);
        navTitle.set_ellipsize(3);
        navTitle.set_max_width_chars(42);
        this._searxNavTitle = navTitle;
        webInfoCol.append(navTitle);

        const navUrl = Gtk.Label.new('');
        navUrl.add_css_class('searx-nav-url');
        navUrl.set_halign(Gtk.Align.START);
        navUrl.set_ellipsize(3);
        navUrl.set_max_width_chars(50);
        this._searxNavUrl = navUrl;
        webInfoCol.append(navUrl);

        const tabsBadge = Gtk.Label.new('');
        tabsBadge.add_css_class('searx-tabs-badge');
        tabsBadge.set_valign(Gtk.Align.CENTER);
        tabsBadge.set_visible(false);
        this._searxTabsBadge = tabsBadge;
        infoBtnBox.append(tabsBadge);

        const chevron = Gtk.Label.new('󰅀');
        chevron.add_css_class('searx-tabs-chevron');
        chevron.set_valign(Gtk.Align.CENTER);
        infoBtnBox.append(chevron);

        infoBtn.set_child(infoBtnBox);
        infoBtn.connect('clicked', () => this._searxShowTabsPopover(infoBtn));
        webBar.append(infoBtn);

        const reloadBtn = Gtk.Button.new_with_label('󰑐');
        reloadBtn.add_css_class('searx-nav-circle-btn');
        reloadBtn.set_valign(Gtk.Align.CENTER);
        reloadBtn.set_size_request(26, 26);
        reloadBtn.set_tooltip_text('Reload');
        reloadBtn.connect('clicked', () => {
            if (this._searxWebView) this._searxWebView.reload();
        });
        webBar.append(reloadBtn);

        const openExtBtn = Gtk.Button.new_with_label('󰌹');
        openExtBtn.add_css_class('searx-nav-circle-btn');
        openExtBtn.set_valign(Gtk.Align.CENTER);
        openExtBtn.set_size_request(26, 26);
        openExtBtn.set_tooltip_text('Open in external browser');
        openExtBtn.connect('clicked', () => {
            const u = this._searxCurrentWebUrl;
            if (u) {
                openInBrowser(u);
            }
        });
        webBar.append(openExtBtn);

        // Bookmark button in WebKit toolbar
        const bmNavBtn = Gtk.Button.new();
        bmNavBtn.add_css_class('searx-nav-circle-btn');
        bmNavBtn.set_valign(Gtk.Align.CENTER);
        bmNavBtn.set_size_request(26, 26);
        const bmNavLabel = Gtk.Label.new('󰃀');
        bmNavBtn.set_child(bmNavLabel);
        bmNavBtn.set_tooltip_text('Bookmark this page');
        this._searxNavBmBtn = bmNavBtn;
        this._searxNavBmLabel = bmNavLabel;
        bmNavBtn.connect('clicked', () => {
            const u = this._searxCurrentWebUrl;
            const t = (this._searxNavTitle && this._searxNavTitle.get_text()) || this._searxNavTitleText || u;
            if (!u) return;
            if (this._searxIsBookmarked(u)) {
                this._searxRemoveBookmark(u);
            } else {
                this._searxAddBookmark(u, t);
            }
            this._searxUpdateNavBmBtn();
        });
        webBar.append(bmNavBtn);

        const closeTabBtn = Gtk.Button.new_with_label('󰅖');
        closeTabBtn.add_css_class('searx-nav-circle-btn');
        closeTabBtn.add_css_class('close');
        closeTabBtn.set_valign(Gtk.Align.CENTER);
        closeTabBtn.set_size_request(26, 26);
        closeTabBtn.set_tooltip_text('Close active tab');
        closeTabBtn.connect('clicked', () => {
            if (this._searxActiveTabId) {
                this._searxCloseTab(this._searxActiveTabId);
            }
        });
        webBar.append(closeTabBtn);

        // Multi-tab view container (Gtk.Stack)
        const webStack = new Gtk.Stack();
        webStack.add_css_class('searx-webview-wrap');
        webStack.set_overflow(Gtk.Overflow.HIDDEN);
        webStack.set_vexpand(true);
        webStack.set_hexpand(true);
        webStack.set_transition_type(Gtk.StackTransitionType.CROSSFADE);
        this._searxWebStack = webStack;
        webBox.append(webStack);

        this._stack.add_named(page, 'websearch');

        // Restore previous webview session if saved
        if (this._searxWebBoxOpen && this._searxSavedTabs && this._searxSavedTabs.length > 0) {
            for (const st of this._searxSavedTabs) {
                if (st.url) this._createTabWebView(st.url, st.title);
            }
            const activeId = this._searxActiveTabId || (this._searxTabs[0] && this._searxTabs[0].id);
            if (activeId) {
                this._searxSwitchToTab(activeId);
            }
        } else if (this._searxWebBoxOpen && this._searxCurrentWebUrl) {
            this._searxOpenUrl(this._searxCurrentWebUrl, this._searxNavTitleText);
        }

        // Probe Docker state immediately so the button shows correct status
        this._searxCheckDockerStatus();
    }

    // ── SearXNG: persist web tab state ────────────────────────────────────
    _persistWebState() {
        saveLauncherWebState({
            lastTab: this._lastTab || this._activeTab || 'launcher',
            searxLastQuery: this._searxLastQuery || '',
            searxCurrentWebUrl: this._searxCurrentWebUrl || '',
            searxNavTitle: (this._searxNavTitle && this._searxNavTitle.get_text()) || this._searxNavTitleText || '',
            searxWebBoxOpen: !!(this._searxWebBox && this._searxWebBox.get_visible()),
            searxTabs: (this._searxTabs || []).filter(t => t.url).map(t => ({
                id: t.id,
                url: t.url,
                title: t.title || t.url
            })),
            searxActiveTabId: this._searxActiveTabId || null,
            searxBookmarks: this._searxBookmarks || [],
        });
    }

    // ── SearXNG: Bookmarks ────────────────────────────────────────────────

    _searxIsBookmarked(url) {
        if (!url) return false;
        const clean = url.split('#')[0];
        return (this._searxBookmarks || []).some(b => b.url === clean);
    }

    _searxAddBookmark(url, title) {
        if (!url) return;
        const clean = url.split('#')[0];
        if (!this._searxBookmarks) this._searxBookmarks = [];
        if (this._searxBookmarks.some(b => b.url === clean)) return;
        this._searxBookmarks.push({
            url: clean,
            title: (title || clean).trim(),
            added: Date.now()
        });
        this._persistWebState();
        this._searxUpdateBookmarksSlot();
        this._searxUpdateNavBmBtn();
    }

    _searxRemoveBookmark(url) {
        if (!this._searxBookmarks || !url) return;
        const clean = url.split('#')[0];
        const before = this._searxBookmarks.length;
        this._searxBookmarks = this._searxBookmarks.filter(b => b.url !== clean && b.url !== url);
        if (this._searxBookmarks.length !== before) {
            this._persistWebState();
            this._searxUpdateBookmarksSlot();
            this._searxUpdateNavBmBtn();
        }
    }

    _searxUpdateBookmarksSlot() {
        const hasBookmarks = !!(this._searxBookmarks && this._searxBookmarks.length > 0);
        if (this._bookmarksBtn) {
            this._bookmarksBtn.set_visible(hasBookmarks);
        }
    }

    _searxUpdateNavBmBtn() {
        if (!this._searxNavBmBtn || !this._searxNavBmLabel) return;
        const u = this._searxCurrentWebUrl;
        const isBm = this._searxIsBookmarked(u);
        this._searxNavBmLabel.set_text(isBm ? '󰃂' : '󰃀');
        if (isBm) {
            this._searxNavBmBtn.add_css_class('bookmarked');
            this._searxNavBmBtn.set_tooltip_text('Remove bookmark');
        } else {
            this._searxNavBmBtn.remove_css_class('bookmarked');
            this._searxNavBmBtn.set_tooltip_text('Bookmark this page');
        }
    }

    _searxShowBookmarksPopover(parentBtn) {
        if (!parentBtn) return;
        if (this._bookmarksPopover) {
            try { this._bookmarksPopover.popdown(); } catch (_) { }
            this._bookmarksPopover = null;
        }

        const pop = new Gtk.Popover();
        pop.set_parent(parentBtn);
        pop.set_has_arrow(true);
        pop.set_position(Gtk.PositionType.BOTTOM);
        pop.add_css_class('launcher-popover');
        pop.get_style_context().add_provider(
            this._getPopoverCSSProvider(),
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );

        const contentBox = Gtk.Box.new(Gtk.Orientation.VERTICAL, 4);
        contentBox.set_margin_top(8);
        contentBox.set_margin_bottom(8);
        contentBox.set_margin_start(8);
        contentBox.set_margin_end(8);

        // Header row: "Bookmarks (N)"
        const header = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 8);
        header.set_valign(Gtk.Align.CENTER);
        header.set_margin_bottom(4);

        const count = this._searxBookmarks ? this._searxBookmarks.length : 0;
        const headerLbl = Gtk.Label.new(`Bookmarks (${count})`);
        headerLbl.add_css_class('pop-section-header');
        headerLbl.set_halign(Gtk.Align.START);
        headerLbl.set_hexpand(true);
        header.append(headerLbl);

        if (count > 1) {
            const clearAllBtn = Gtk.Button.new_with_label('Clear All');
            clearAllBtn.add_css_class('searx-tab-close-all-btn');
            clearAllBtn.set_valign(Gtk.Align.CENTER);
            clearAllBtn.connect('clicked', () => {
                this._searxBookmarks = [];
                this._persistWebState();
                this._searxUpdateBookmarksSlot();
                this._searxUpdateNavBmBtn();
                pop.popdown();
            });
            header.append(clearAllBtn);
        }
        contentBox.append(header);

        const sep = new Gtk.Separator({ orientation: Gtk.Orientation.HORIZONTAL });
        contentBox.append(sep);

        // Scrollable list of bookmarks — capped at 260px max height
        const scroll = new Gtk.ScrolledWindow();
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        scroll.set_max_content_height(260);
        scroll.set_propagate_natural_height(true);
        scroll.add_css_class('launcher-scroll');

        const list = new Gtk.ListBox();
        list.set_selection_mode(Gtk.SelectionMode.NONE);

        const renderList = () => {
            let child = list.get_first_child();
            while (child) {
                const next = child.get_next_sibling();
                list.remove(child);
                child = next;
            }

            if (!this._searxBookmarks || this._searxBookmarks.length === 0) {
                const emptyRow = new Gtk.ListBoxRow();
                emptyRow.set_activatable(false);
                const emptyLbl = Gtk.Label.new('No bookmarks saved yet');
                emptyLbl.add_css_class('searx-bm-empty');
                emptyLbl.set_halign(Gtk.Align.CENTER);
                emptyRow.set_child(emptyLbl);
                list.append(emptyRow);
                return;
            }

            for (const bm of [...this._searxBookmarks]) {
                const row = new Gtk.ListBoxRow();
                const rowBox = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 6);
                rowBox.add_css_class('searx-tab-row');

                // Custom glyph based on URL
                let glyphChar = '󰖟';
                if (bm.url.includes('youtube.com') || bm.url.includes('youtu.be')) glyphChar = '';
                else if (bm.url.includes('github.com')) glyphChar = '󰊤';
                else if (bm.url.includes('reddit.com')) glyphChar = '󰑍';
                else if (bm.url.includes('wikipedia.org')) glyphChar = '󰖬';

                const glyph = Gtk.Label.new(glyphChar);
                glyph.add_css_class('searx-tab-glyph');
                glyph.set_valign(Gtk.Align.CENTER);
                rowBox.append(glyph);

                const textCol = Gtk.Box.new(Gtk.Orientation.VERTICAL, 1);
                textCol.set_hexpand(true);
                textCol.set_valign(Gtk.Align.CENTER);

                const titleLbl = Gtk.Label.new(bm.title || bm.url);
                titleLbl.add_css_class('searx-tab-title');
                titleLbl.set_halign(Gtk.Align.START);
                titleLbl.set_ellipsize(3);
                titleLbl.set_max_width_chars(32);
                textCol.append(titleLbl);

                const urlLbl = Gtk.Label.new(bm.url || '');
                urlLbl.add_css_class('searx-tab-url');
                urlLbl.set_halign(Gtk.Align.START);
                urlLbl.set_ellipsize(3);
                urlLbl.set_max_width_chars(36);
                textCol.append(urlLbl);
                rowBox.append(textCol);

                // Bookmark click target
                const clickBtn = Gtk.Button.new();
                clickBtn.set_child(rowBox);
                clickBtn.add_css_class('pop-item');
                clickBtn.set_hexpand(true);
                clickBtn.connect('clicked', () => {
                    pop.popdown();
                    this._searxOpenUrl(bm.url, bm.title || bm.url);
                    this._searxEnsureDockerRunning();
                });

                const fullRowBox = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 2);
                fullRowBox.append(clickBtn);

                // Bookmark delete button
                const removeBtn = Gtk.Button.new_with_label('󰅖');
                removeBtn.add_css_class('searx-tab-close-btn');
                removeBtn.set_valign(Gtk.Align.CENTER);
                removeBtn.set_tooltip_text('Remove bookmark');
                removeBtn.connect('clicked', () => {
                    this._searxRemoveBookmark(bm.url);
                    if (!this._searxBookmarks || this._searxBookmarks.length === 0) {
                        pop.popdown();
                    } else {
                        headerLbl.set_text(`Bookmarks (${this._searxBookmarks.length})`);
                        renderList();
                    }
                });
                fullRowBox.append(removeBtn);

                row.set_child(fullRowBox);
                list.append(row);
            }
        };

        renderList();
        scroll.set_child(list);
        contentBox.append(scroll);
        pop.set_child(contentBox);
        this._bookmarksPopover = pop;
        pop.connect('closed', () => { this._bookmarksPopover = null; });
        pop.popup();
    }

    // ── WebKit: Shared Network Session ───────────────────────────────────
    _getWebKitSession() {
        if (!this._searxNetworkSession) {
            try {
                const ctx = WebKit.WebContext.get_default();
                if (ctx && typeof ctx.set_cache_model === 'function') {
                    ctx.set_cache_model(WebKit.CacheModel.DOCUMENT_VIEWER);
                }
            } catch (e) {
                console.warn('[launcher] Failed to set WebKit cache model:', e.message);
            }

            const webkitDataDir = GLib.build_filenamev([HOME, '.local', 'share', 'hyprcandy', 'webkit']);
            const webkitCacheDir = GLib.build_filenamev([HOME, '.cache', 'hyprcandy', 'webkit']);
            GLib.mkdir_with_parents(webkitDataDir, 0o755);
            GLib.mkdir_with_parents(webkitCacheDir, 0o755);

            const session = new WebKit.NetworkSession({
                data_directory: webkitDataDir,
                cache_directory: webkitCacheDir,
            });
            const cookieMgr = session.get_cookie_manager();
            const cookieFile = GLib.build_filenamev([webkitDataDir, 'cookies.sqlite']);
            cookieMgr.set_persistent_storage(cookieFile, WebKit.CookiePersistentStorage.SQLITE);
            cookieMgr.set_accept_policy(WebKit.CookieAcceptPolicy.ALWAYS);
            this._searxNetworkSession = session;
            this._searxWebkitCacheDir = webkitCacheDir;
        }
        return this._searxNetworkSession;
    }

    // ── WebKit: Native Ad & Tracker Blocker setup ────────────────────────
    // ── WebKit: Native Ad & Tracker Blocker setup (hardened version) ─────
    _setupAdBlocker(ucm, cacheDir) {
        try {
            if (!ucm || typeof ucm.add_filter !== 'function') {
                console.warn('[launcher] _setupAdBlocker: invalid ucm, skipping');
                return false;
            }

            // The block rules, cosmetic stylesheet, and YouTube scripts are
            // identical for every tab. WebKitUserContentFilterStore.save()
            // recompiles the whole rule set from scratch and writes it to
            // disk — real CPU + I/O cost that has no reason to repeat on
            // every single new tab. Compile/build everything once per app
            // run and hand the same already-built objects to every
            // subsequent tab's UserContentManager instead.
            if (this._cachedAdblockFilter) {
                try { ucm.add_filter(this._cachedAdblockFilter); } catch (e) {
                    console.warn('[launcher] Adblock add_filter (cached) failed:', e.message);
                }
            }
            if (this._cachedAdblockStyleSheet) {
                try { ucm.add_style_sheet(this._cachedAdblockStyleSheet); } catch (e) {
                    console.warn('[launcher] Adblock add_style_sheet (cached) failed:', e.message);
                }
            }
            if (this._cachedAdblockUserScripts) {
                for (const s of this._cachedAdblockUserScripts) {
                    try { ucm.add_script(s); } catch (e) {
                        console.warn('[launcher] Adblock add_script (cached) failed:', e.message);
                    }
                }
            }
            // Everything above is cheap to re-run (just attaching already-
            // built objects to a new UCM); the expensive part — building
            // the rule JSON and asking WebKit to compile+persist it — only
            // needs to happen once.
            if (this._adblockAssetsBuilt) return true;
            this._adblockAssetsBuilt = true;

            if (!cacheDir || typeof cacheDir !== 'string') {
                console.warn('[launcher] _setupAdBlocker: invalid cacheDir, skipping filter store');
            }

            let storePath = null;
            if (cacheDir) {
                try {
                    storePath = GLib.build_filenamev([cacheDir, 'filters']);
                    GLib.mkdir_with_parents(storePath, 0o755);
                    if (!GLib.file_test(storePath, GLib.FileTest.IS_DIR)) {
                        storePath = null;
                    }
                } catch (_e) {
                    storePath = null;
                }
            }

            const adDomains = [
                "doubleclick.net", "googlesyndication.com", "googleadservices.com",
                "adservice.google.com", "google-analytics.com",
                "googletagmanager.com", "googletagservices.com",
                "adnxs.com", "taboola.com", "outbrain.com", "scorecardresearch.com",
                "criteo.com", "advertising.com", "popads.net", "adroll.com",
                "pubmatic.com", "rubiconproject.com", "amazon-adsystem.com",
                "moatads.com", "buysellads.com", "casalemedia.com", "openx.net",
                "bidswitch.net", "quantserve.com", "lijit.com", "trafficjunky.net",
                "adsystem.com", "adsrvr.org", "sharethrough.com", "sovrn.com",
                "facebook.net", "connect.facebook.net", "pixel.facebook.com",
                "ads-twitter.com", "ads.pinterest.com", "snap.licdn.com",
                // Additional widely-blocked ad/analytics/tracking domains
                // (drawn from EasyList/EasyPrivacy's most common entries) —
                // WebKit's native content-blocker format can't reuse a full
                // EasyList directly (different rule syntax entirely, see
                // note below), but expanding the curated domain list gets
                // meaningfully closer to uBlock/EasyList-level coverage for
                // the price of one extra rule object per domain.
                "adform.net", "adition.com", "adtechus.com", "adsafeprotected.com",
                "media.net", "mediavine.com", "revcontent.com", "zergnet.com",
                "gemini.yahoo.com", "smartadserver.com", "yieldmo.com",
                "contextweb.com", "indexww.com", "33across.com", "adcolony.com",
                "chartbeat.com", "hotjar.com", "mixpanel.com", "segment.io",
                "amplitude.com", "crazyegg.com", "mouseflow.com",
                "doubleverify.com", "moatpixel.com", "serving-sys.com",
                "flashtalking.com", "adthrive.com", "ezoic.net", "sitescout.com"
            ];

            // IMPORTANT #1: WebKit content-extension "if-domain" matches the
            // domain of the TOP-LEVEL document being viewed — not the domain
            // a resource is being fetched from. "url-filter": ".*" combined
            // with "if-domain": adDomains (the original code here) therefore
            // only ever activated when the user directly navigated to an ad
            // domain as the page itself, which practically never happens; it
            // silently blocked nothing on ordinary pages. To actually block
            // a third-party ad request regardless of what site it's embedded
            // in, the domain has to be encoded into "url-filter" itself. See
            // https://webkit.org/blog/4062/targeting-domains-with-content-blockers/
            //
            // IMPORTANT #2: WebKit's url-filter regex dialect only allows
            // "^" (and "$") to appear as the very first (or last) character
            // of the WHOLE pattern — never inside an alternation group. The
            // previous code combined every domain into one pattern like
            // "(^https?://…a|^https?://…b|^https?://…c)", where "^" is the
            // first character of each *branch* but not of the pattern as a
            // whole, so WebKit's content-extension compiler rejected it
            // outright on every run ("Start of line assertion can only
            // appear as the first term in a filter" — visible in the
            // wrapper log's save_finish failure). That meant this rule
            // silently never blocked anything. The fix is what WebKit's own
            // docs recommend and what compiled EasyList->WebKit converters
            // (e.g. AdGuard's SafariConverterLib / eyeo's abp2blocklist)
            // actually emit: one independent rule object per domain, each
            // with "^" legitimately as the first character of its own
            // pattern. See https://webkit.org/blog/3476/content-blockers-first-look/
            const domainToUrlFilter = (domain) => {
                const escaped = domain.replace(/\./g, '\\.');
                // scheme + optional subdomains + domain + port/path boundary.
                // NOTE: this deliberately does NOT use "([:/]|$)" — WebKitGTK's
                // content-extension regex engine (2.52.x) rejects ANY
                // disjunction ("|"), not just ones that misuse "^"/"$" (see
                // the "Disjunctions are not supported yet" parser error in
                // the wrapper log once the anchor bug above was fixed). A
                // plain character class has no such restriction, at the
                // minor cost of not matching the rare bare
                // "https://domain.tld" request with no trailing slash/port.
                return `^https?://([a-z0-9-]+\\.)*${escaped}[:/]`;
            };

            const domainBlockRules = adDomains.map(domain => ({
                "trigger": {
                    "url-filter": domainToUrlFilter(domain),
                    "url-filter-is-case-sensitive": false
                },
                "action": { "type": "block" }
            }));

            // YouTube ad-tracking/telemetry beacons. This deliberately does
            // NOT touch the video CDN itself (googlevideo.com), which
            // YouTube shares between ads and real content — domain-blocking
            // that would break playback outright rather than just the ads.
            // Actual ad *playback* is prevented instead by stripping ad
            // placements out of the player response before playback starts
            // (see ytAdScript below), which is the same technique Brave and
            // uBlock Origin use for YouTube.
            const ytAdEndpoints = [
                'youtube\\.com/api/stats/ads',
                'youtube\\.com/pagead/',
                'youtube\\.com/ptracking',
                'youtube\\.com/youtubei/v1/log_event'
            ];
            // One rule per endpoint, same reason as domainBlockRules above:
            // WebKitGTK's content-extension engine doesn't support "|"
            // disjunctions at all yet, so the previous single combined
            // "(a|b|c|d)" pattern would also have failed to compile.
            const ytBlockRules = ytAdEndpoints.map(endpoint => ({
                "trigger": {
                    "url-filter": `^https?://([a-z0-9-]+\\.)*${endpoint}`,
                    "url-filter-is-case-sensitive": false,
                    "if-domain": ["youtube.com"]
                },
                "action": { "type": "block" }
            }));

            const cosmeticSelector = [
                ".adsbygoogle", ".ad-container", ".ad-banner", ".advertisement",
                "[id^=\"google_ads_iframe\"]", ".taboola-placeholder",
                ".outbrain_widget", ".criteo-ad", ".ad-slot", ".sponsored-post",
                ".ytp-ad-overlay-container", ".ytp-ad-message-container",
                ".ytp-ad-preview-container", "ytd-ad-slot-renderer",
                "ytd-in-feed-ad-layout-renderer", "ytd-banner-promo-renderer",
                "ytd-statement-banner-renderer", "ytd-action-companion-ad-renderer",
                "#player-ads"
            ].join(", ");

            const cosmeticRule = {
                "trigger": { "url-filter": ".*" },
                "action": { "type": "css-display-none", "selector": cosmeticSelector }
            };

            const filterRules = [...domainBlockRules, ...ytBlockRules, cosmeticRule];

            let filterStore = null;
            if (storePath) {
                try {
                    filterStore = new WebKit.UserContentFilterStore({ path: storePath });
                } catch (e) {
                    console.warn('[launcher] Adblock UserContentFilterStore unavailable:', e.message);
                    filterStore = null;
                }
            }

            if (filterStore) {
                try {
                    const ruleJson = JSON.stringify(filterRules);
                    const ruleBytes = new GLib.Bytes(new TextEncoder().encode(ruleJson));
                    // NOTE: `new WeakRef ? new WeakRef(ucm) : null` (the
                    // previous form here) is an operator-precedence bug —
                    // `new WeakRef` without parens/args calls the
                    // constructor with zero arguments immediately, and
                    // WeakRef always throws when constructed without a
                    // target object. That exception was being caught by the
                    // surrounding try/catch and logged as "Adblock
                    // filterStore.save error", but its real effect was to
                    // abort *before* filterStore.save() ever ran — so the
                    // native WebKit content filter (domain + cosmetic ad
                    // rules) was silently never installed on any tab.
                    const ucmRef = (typeof WeakRef !== 'undefined') ? new WeakRef(ucm) : null;
                    filterStore.save("adblock-v2", ruleBytes, null, (s, res) => {
                        try {
                            if (!s || !res) return;
                            let filter = null;
                            try {
                                filter = s.save_finish(res);
                            } catch (saveErr) {
                                console.warn('[launcher] Adblock filter save_finish failed:', saveErr.message);
                                filter = null;
                            }
                            if (!filter) return;
                            // Cache for every future tab — see the guard at
                            // the top of this function.
                            this._cachedAdblockFilter = filter;
                            const targetUcm = ucmRef ? ucmRef.deref() : ucm;
                            if (targetUcm && typeof targetUcm.add_filter === 'function') {
                                try {
                                    targetUcm.add_filter(filter);
                                } catch (addErr) {
                                    console.warn('[launcher] Adblock add_filter failed:', addErr.message);
                                }
                            }
                        } catch (outerErr) {
                            console.warn('[launcher] Adblock filter callback error:', outerErr.message);
                        }
                    });
                } catch (e) {
                    console.warn('[launcher] Adblock filterStore.save error:', e.message);
                }
            }

            try {
                const cosmeticCSS = [
                    ".adsbygoogle, .ad-container, .ad-banner, .advertisement,",
                    "[id^=\"google_ads_iframe\"], .taboola-placeholder, .outbrain_widget,",
                    ".criteo-ad, .ad-slot, .sponsored-post, .ytp-ad-overlay-container,",
                    ".ytp-ad-message-container, .ytp-ad-preview-container,",
                    "ytd-ad-slot-renderer, ytd-in-feed-ad-layout-renderer,",
                    "ytd-banner-promo-renderer, ytd-statement-banner-renderer,",
                    "ytd-action-companion-ad-renderer, #player-ads {",
                    "  display: none !important;",
                    "  visibility: hidden !important;",
                    "  height: 0 !important;",
                    "  max-height: 0 !important;",
                    "  opacity: 0 !important;",
                    "  pointer-events: none !important;",
                    "}"
                ].join("\n");
                const styleSheet = new WebKit.UserStyleSheet(
                    cosmeticCSS,
                    WebKit.UserContentInjectedFrames.ALL_FRAMES,
                    WebKit.UserStyleLevel.USER,
                    null, null
                );
                try { ucm.add_style_sheet(styleSheet); } catch (e) {
                    console.warn('[launcher] Adblock add_style_sheet failed:', e.message);
                }
                this._cachedAdblockStyleSheet = styleSheet;
            } catch (e) {
                console.warn('[launcher] Adblock UserStyleSheet create failed:', e.message);
            }

            try {
                // Strip ad placements out of YouTube's player-response JSON
                // *before* the page's own JS ever sees it, so the player
                // never schedules an ad in the first place — this is the
                // actual "stop it before it even partially loads" behavior
                // (the same technique Brave/uBlock Origin use), as opposed
                // to the reactive skip-after-it-starts script below, which
                // only catches whatever this one misses.
                const ytPlayerResponseScript = `(function() {
                    'use strict';
                    try {
                        function _stripAds(obj) {
                            try {
                                if (!obj || typeof obj !== 'object') return obj;
                                delete obj.adPlacements;
                                delete obj.adSlots;
                                delete obj.playerAds;
                                delete obj.adBreakHeartbeatParams;
                                if (obj.playerConfig && obj.playerConfig.audioConfig) {
                                    // leave audio config alone — only ad scheduling data is removed
                                }
                            } catch (_) {}
                            return obj;
                        }
                        function _isPlayerEndpoint(url) {
                            try {
                                var s = String(url || '');
                                return s.indexOf('/youtubei/v1/player') !== -1 ||
                                       s.indexOf('get_video_info') !== -1;
                            } catch (_) { return false; }
                        }
                        try {
                            var _origFetch = window.fetch;
                            if (typeof _origFetch === 'function') {
                                window.fetch = function(input, init) {
                                    var url = (typeof input === 'string') ? input : (input && input.url);
                                    var p = _origFetch.apply(this, arguments);
                                    if (!_isPlayerEndpoint(url)) return p;
                                    return p.then(function(res) {
                                        try {
                                            var cloned = res.clone();
                                            cloned.json().then(function(data) {
                                                _stripAds(data);
                                            }).catch(function(){});
                                        } catch (_) {}
                                        return res;
                                    });
                                };
                            }
                        } catch (_) {}
                        try {
                            var _OrigXHR = window.XMLHttpRequest;
                            if (_OrigXHR) {
                                var _origOpen = _OrigXHR.prototype.open;
                                _OrigXHR.prototype.open = function(method, url) {
                                    try { this.__hc_url = url; } catch (_) {}
                                    return _origOpen.apply(this, arguments);
                                };
                                var _origSend = _OrigXHR.prototype.send;
                                _OrigXHR.prototype.send = function() {
                                    try {
                                        if (_isPlayerEndpoint(this.__hc_url)) {
                                            this.addEventListener('readystatechange', function() {
                                                if (this.readyState === 4) {
                                                    try {
                                                        var data = JSON.parse(this.responseText);
                                                        _stripAds(data);
                                                        Object.defineProperty(this, 'responseText', { value: JSON.stringify(data), configurable: true });
                                                        Object.defineProperty(this, 'response', { value: JSON.stringify(data), configurable: true });
                                                    } catch (_) {}
                                                }
                                            });
                                        }
                                    } catch (_) {}
                                    return _origSend.apply(this, arguments);
                                };
                            }
                        } catch (_) {}
                        // ytInitialPlayerResponse is inlined into the very
                        // first HTML response for a watch page — strip it as
                        // soon as it's assigned, before the player reads it.
                        try {
                            var _ipr;
                            Object.defineProperty(window, 'ytInitialPlayerResponse', {
                                configurable: true,
                                get: function() { return _ipr; },
                                set: function(v) { _ipr = _stripAds(v); }
                            });
                        } catch (_) {}
                    } catch (_) {}
                })();`;
                const ytPlayerResponseUserScript = new WebKit.UserScript(
                    ytPlayerResponseScript,
                    WebKit.UserContentInjectedFrames.ALL_FRAMES,
                    WebKit.UserScriptInjectionTime.START,
                    null, null
                );
                try { ucm.add_script(ytPlayerResponseUserScript); } catch (e) {
                    console.warn('[launcher] Adblock YouTube player-response script add failed:', e.message);
                }
                this._cachedYtPlayerResponseUserScript = ytPlayerResponseUserScript;
            } catch (e) {
                console.warn('[launcher] Adblock YouTube player-response script create failed:', e.message);
            }

            try {
                const ytAdScript = `(function() {
                    'use strict';
                    try {
                        var _lastRun = 0;
                        function _safeRemove(el) {
                            try { if (el && el.parentNode) el.parentNode.removeChild(el); } catch(_) {}
                        }
                        function _safeClick(btn) {
                            try { if (btn && typeof btn.click === 'function') btn.click(); } catch(_) {}
                        }
                        function cleanYouTubeAds() {
                            try {
                                var hn = (window.location && window.location.hostname) ? window.location.hostname : '';
                                if (hn.indexOf('youtube.com') === -1 && hn.indexOf('youtu.be') === -1) return;
                                var now = Date.now();
                                if (now - _lastRun < 250) return;
                                _lastRun = now;
                                var v = document.querySelector('video');
                                var ad = document.querySelector('.ad-showing, .ad-interrupting, .ytp-ad-player-overlay');
                                if (ad && v && !isNaN(v.duration) && isFinite(v.duration)) {
                                    try { v.muted = true; } catch(_) {}
                                    try { if (v.playbackRate < 16) v.playbackRate = 16; } catch(_) {}
                                    try { if (v.duration > 0) v.currentTime = v.duration; } catch(_) {}
                                }
                                var skips = [
                                    '.ytp-ad-skip-button', '.ytp-ad-skip-button-modern',
                                    '.ytp-skip-ad-button', '.ytp-ad-skip-button-slot',
                                    'button.ytp-ad-skip-button-modern', '.ytp-ad-overlay-close-button'
                                ];
                                for (var i = 0; i < skips.length; i++) {
                                    var b = document.querySelector(skips[i]);
                                    if (b) _safeClick(b);
                                }
                                var sel = [
                                    '.ytp-ad-overlay-container', '.ytp-ad-message-container',
                                    'ytd-ad-slot-renderer', 'ytd-banner-promo-renderer',
                                    'ytd-in-feed-ad-layout-renderer', 'ytd-statement-banner-renderer',
                                    '#player-ads'
                                ].join(',');
                                var nodes = document.querySelectorAll(sel);
                                for (var j = 0; j < nodes.length; j++) _safeRemove(nodes[j]);
                            } catch (_) {}
                        }
                        var _observerInstalled = false;
                        function _installObserver() {
                            if (_observerInstalled) return;
                            try {
                                var tgt = document.body || document.documentElement;
                                if (!tgt) { setTimeout(_installObserver, 200); return; }
                                if (typeof MutationObserver !== 'undefined') {
                                    var obs = new MutationObserver(function() { cleanYouTubeAds(); });
                                    obs.observe(tgt, { childList: true, subtree: true });
                                    _observerInstalled = true;
                                } else {
                                    setInterval(cleanYouTubeAds, 1500);
                                    _observerInstalled = true;
                                }
                                cleanYouTubeAds();
                            } catch (_) {
                                setTimeout(_installObserver, 500);
                            }
                        }
                        if (document.readyState === 'loading') {
                            document.addEventListener('DOMContentLoaded', _installObserver);
                        } else {
                            _installObserver();
                        }
                    } catch (_) {}
                })();`;
                const ytUserScript = new WebKit.UserScript(
                    ytAdScript,
                    WebKit.UserContentInjectedFrames.ALL_FRAMES,
                    WebKit.UserScriptInjectionTime.START,
                    null, null
                );
                try { ucm.add_script(ytUserScript); } catch (e) {
                    console.warn('[launcher] Adblock YouTube script add failed:', e.message);
                }
                this._cachedYtUserScript = ytUserScript;
            } catch (e) {
                console.warn('[launcher] Adblock YouTube script create failed:', e.message);
            }

            try {
                const codecScript = `(function() {
                    'use strict';
                    try {
                        function _isBlocked(t) {
                            if (!t || typeof t !== 'string') return false;
                            var l = t.toLowerCase();
                            return (l.indexOf('vp8') !== -1 || l.indexOf('vp9') !== -1 ||
                                    l.indexOf('vp09') !== -1 || l.indexOf('av01') !== -1 ||
                                    l.indexOf('av1') !== -1 || l.indexOf('webm') !== -1);
                        }
                        try {
                            if (window.MediaSource && typeof window.MediaSource.isTypeSupported === 'function') {
                                var _orig = window.MediaSource.isTypeSupported.bind(window.MediaSource);
                                window.MediaSource.isTypeSupported = function(t) {
                                    try { if (_isBlocked(t)) return false; } catch(_) {}
                                    return _orig(t);
                                };
                            }
                        } catch (_) {}
                        try {
                            var hp = window.HTMLMediaElement && window.HTMLMediaElement.prototype;
                            if (hp && typeof hp.canPlayType === 'function') {
                                var _orig2 = hp.canPlayType;
                                hp.canPlayType = function(t) {
                                    try { if (_isBlocked(t)) return ''; } catch(_) {}
                                    return _orig2.call(this, t);
                                };
                            }
                        } catch (_) {}
                    } catch (_) {}
                })();`;
                const codecUserScript = new WebKit.UserScript(
                    codecScript,
                    WebKit.UserContentInjectedFrames.ALL_FRAMES,
                    WebKit.UserScriptInjectionTime.START,
                    null, null
                );
                try { ucm.add_script(codecUserScript); } catch (e) {
                    console.warn('[launcher] Adblock codec script add failed:', e.message);
                }
                // Cache all three user scripts together so future tabs skip
                // straight to add_script() with already-built objects.
                this._cachedAdblockUserScripts = [
                    this._cachedYtPlayerResponseUserScript,
                    this._cachedYtUserScript,
                    codecUserScript
                ].filter(Boolean);
            } catch (e) {
                console.warn('[launcher] Adblock codec script create failed:', e.message);
            }

            return true;
        } catch (e) {
            console.warn('[launcher] _setupAdBlocker top-level error:', e.message);
            return false;
        }
    }

    // A WebProcess crash/termination only kills that tab's sandboxed
    // renderer, not the launcher itself — but leaving the WebView pointed
    // at a dead renderer means every subsequent call into it (get_title(),
    // load_uri(), JS evaluation, etc.) keeps failing, and those repeated
    // failures piling up on top of a torn-down GTK surface is what actually
    // surfaces to the user as the launcher UI "crashing". Recover by
    // respawning a fresh WebProcess (WebKit does this automatically the
    // next time load_uri() is called on the WebView) instead of leaving it
    // in a zombie state.
    _recoverCrashedWebView(webView, label) {
        try {
            let target = 'about:blank';
            try {
                const current = webView.get_uri && webView.get_uri();
                if (current) target = current;
            } catch (_) { }
            // Give the sandbox/D-Bus teardown from the old WebProcess a
            // moment to finish before spawning a new one for the same view.
            GLib.timeout_add(GLib.PRIORITY_DEFAULT, 300, () => {
                try {
                    if (webView && typeof webView.load_uri === 'function') {
                        webView.load_uri(target);
                    }
                } catch (e) {
                    console.warn('[launcher] WebProcess recovery reload failed:', label || 'unknown', e.message);
                }
                return GLib.SOURCE_REMOVE;
            });
        } catch (e) {
            console.warn('[launcher] WebProcess recovery failed:', label || 'unknown', e.message);
        }
    }

    _attachWebViewCrashHandlers(webView, label) {
        if (!webView) return;
        try {
            if (typeof webView.connect === 'function') {
                try {
                    webView.connect('web-process-crashed', (wv) => {
                        console.warn('[launcher] WebProcess crashed:', label || 'unknown');
                        try { wv.stop_loading(); } catch (_) { }
                        this._recoverCrashedWebView(wv, label);
                        return true;
                    });
                } catch (_) { }
                try {
                    webView.connect('web-process-terminated', (wv, reason) => {
                        console.warn('[launcher] WebProcess terminated:', label || 'unknown', 'reason:', reason);
                        this._recoverCrashedWebView(wv, label);
                        return true;
                    });
                } catch (_) { }
            }
        } catch (e) {
            console.warn('[launcher] attach crash handlers failed:', e.message);
        }
    }

    // ── WebKit: Create a new Tab & WebView ───────────────────────────────
    _createTabWebView(url, title) {
        if (!this._searxTabs) this._searxTabs = [];
        const session = this._getWebKitSession();
        const tabId = 'tab_' + Date.now() + '_' + Math.random().toString(36).substring(2, 6);

        const tabWrap = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        tabWrap.add_css_class('searx-webview-wrap');
        tabWrap.set_hexpand(true);
        tabWrap.set_vexpand(true);

        const webView = new WebKit.WebView({ network_session: session });
        try {
            const transparent = new Gdk.RGBA();
            transparent.parse('rgba(0,0,0,0)');
            webView.set_background_color(transparent);
        } catch (_) { }
        webView.add_css_class('searx-webview');
        webView.set_hexpand(true);
        webView.set_vexpand(true);
        webView.set_visible(true);
        tabWrap.append(webView);

        const settings = webView.get_settings();
        if (settings) {
            settings.set_enable_page_cache(false); // Proactively free page cache memory
            settings.set_enable_back_forward_navigation_gestures(true);
            settings.set_enable_javascript(true);
            settings.set_enable_smooth_scrolling(true);
            settings.set_enable_media_stream(false); // Avoid WebRTC background polling
            settings.set_enable_dns_prefetching(false);
            settings.set_enable_developer_extras(false);
            try {
                // ALWAYS forces every tab's WebProcess to bring up a GPU
                // context even when the driver stack can't actually serve
                // one. This machine's log shows the VA-API driver failing
                // to initialize ("iHD_drv_video.so init failed") and
                // incomplete Vulkan support on this Intel GPU generation —
                // exactly the conditions under which forced GPU compositing
                // crashes the WebProcess on video-heavy pages like YouTube.
                // ON_DEMAND lets WebKit request acceleration only when a
                // page actually needs it and fall back to software
                // rendering when the driver can't provide it, instead of
                // hard-failing. On a hybrid-graphics machine where we
                // detected and offloaded to a discrete GPU (see
                // _detectGpuTopology near the top of this file),
                // ON_DEMAND still applies cleanly — WebKit will now request
                // acceleration from the healthier dGPU via DRI_PRIME instead
                // of the broken iGPU, so there's no need to force ALWAYS.
                settings.set_hardware_acceleration_policy(WebKit.HardwareAccelerationPolicy.ON_DEMAND);
            } catch (_) { }
        }

        this._attachWebViewCrashHandlers(webView, 'tab-' + tabId);
        try {
            const ucm = (webView && typeof webView.get_user_content_manager === 'function')
                ? webView.get_user_content_manager()
                : null;
            if (ucm && this._searxWebkitCacheDir) {
                try {
                    this._setupAdBlocker(ucm, this._searxWebkitCacheDir);
                } catch (abErr) {
                    console.warn('[launcher] _createTabWebView adblock setup failed:', abErr.message);
                }
            }
        } catch (ucmErr) {
            console.warn('[launcher] _createTabWebView ucm setup error:', ucmErr.message);
        }

        const tab = {
            id: tabId,
            url: url || '',
            title: title || url || 'New Tab',
            webView: webView,
            webWrap: tabWrap
        };

        webView.connect('notify::title', () => {
            const t = webView.get_title();
            if (t) {
                tab.title = t;
                if (this._searxActiveTabId === tabId && this._searxNavTitle) {
                    this._searxNavTitle.set_text(t);
                }
                this._persistWebState();
            }
        });

        webView.connect('notify::uri', () => {
            const u = webView.get_uri();
            if (u) {
                tab.url = u;
                if (this._searxActiveTabId === tabId) {
                    this._searxCurrentWebUrl = u;
                    if (this._searxNavUrl) this._searxNavUrl.set_text(u);
                    this._searxUpdateNavBmBtn();
                }
                this._persistWebState();
            }
        });

        webView.connect('load-failed', (wv, loadEvent, failingUri, error) => {
            console.warn('[launcher] WebKit load-failed:', failingUri, error.message);
            // Otherwise a failed load leaves the tab permanently dimmed at
            // the "page-loading" opacity, since LoadEvent.FINISHED never
            // fires for a load that errored out instead of completing.
            try { tabWrap.remove_css_class('page-loading'); } catch (_) { }
        });

        webView.connect('run-file-chooser', (wv, request) => {
            this._handleWebKitFileChooser(request);
            return true;
        });

        // ── Popup / close / fullscreen / permission hardening ────────────
        // Ads very commonly try to open popups or pop-unders (`create`),
        // call `window.close()` on themselves once "done" (`close`), request
        // autoplay/media permissions (`permission-request`), or force a
        // fullscreen takeover as part of an interstitial (`enter-fullscreen`).
        // None of these were previously handled, which left WebKitGTK's
        // default/undefined behavior in charge — and left the launcher's own
        // "click outside closes" logic exposed to the resulting widget-tree
        // churn. Handling all of them explicitly, and marking the launcher
        // "WebView busy" while they resolve, keeps ad interactions scoped to
        // the tab instead of ever reaching the launcher window itself.
        webView.connect('create', (wv) => {
            // Never spawn a real top-level GTK window for a popup — this is
            // almost always an ad/pop-under. Block it outright, like a
            // browser's popup blocker. Returning null refuses the request.
            console.warn('[launcher] WebKit blocked a popup/window.open() in tab:', tabId);
            return null;
        });

        webView.connect('close', (wv) => {
            // A page (most often an ad/interstitial) asked to close itself.
            // Only ever close *this tab*, and only if it isn't the last one —
            // this must never cascade to the launcher window.
            console.warn('[launcher] WebKit tab requested self-close:', tabId);
            this._markWebviewBusy();
            try {
                if (this._searxTabs && this._searxTabs.length > 1 && typeof this._searxCloseTab === 'function') {
                    this._searxCloseTab(tabId);
                } else {
                    wv.stop_loading();
                    wv.load_uri('about:blank');
                }
            } catch (_) { }
        });

        webView.connect('permission-request', (wv, request) => {
            // Deny everything by default (autoplay-with-sound, EME/DRM,
            // notifications, geolocation, etc.). Ads are the overwhelming
            // source of unsolicited permission prompts; legitimate sites the
            // user actually wants audio/video from are rare enough in this
            // launcher's embedded browser that "deny by default" is the safe
            // choice, and it prevents a native permission popover from
            // interacting with the focus/click-to-close logic.
            this._markWebviewBusy();
            try { request.deny(); } catch (_) { }
            return true;
        });

        webView.connect('enter-fullscreen', () => {
            this._markWebviewBusy(1200);
            // Fade the toolbar (back/reload/bookmark row) out smoothly
            // instead of it just vanishing the instant the page's video/
            // player goes fullscreen — the CSS transition on
            // .searx-webview-bar (see the stylesheet) does the actual
            // animating; this only toggles the class.
            try { if (this._searxWebBar) this._searxWebBar.add_css_class('fullscreen-hidden'); } catch (_) { }
            return false; // allow the fullscreen request to proceed
        });

        webView.connect('leave-fullscreen', () => {
            this._markWebviewBusy();
            try { if (this._searxWebBar) this._searxWebBar.remove_css_class('fullscreen-hidden'); } catch (_) { }
            return false;
        });

        // Smooth cross-fade during navigation/refresh instead of an abrupt
        // blank-then-painted pop: dim this tab's wrapper slightly the moment
        // a load starts (covers both clicking a link AND pressing reload,
        // since both fire the same STARTED/FINISHED sequence) and restore
        // full opacity once the page has actually finished loading. The
        // dim level (CSS ".page-loading" -> opacity 0.55) is deliberately
        // subtle so the previous frame stays legible throughout rather than
        // flashing to a blank/white page.
        webView.connect('load-changed', (wv, loadEvent) => {
            try {
                if (loadEvent === WebKit.LoadEvent.STARTED) {
                    tabWrap.add_css_class('page-loading');
                } else if (loadEvent === WebKit.LoadEvent.FINISHED) {
                    tabWrap.remove_css_class('page-loading');
                }
            } catch (_) { }
        });

        webView.connect('script-dialog', (wv, dialog) => {
            // alert()/confirm()/prompt() triggered from within a page (often
            // an ad) — same busy-guard treatment as a permission popover.
            this._markWebviewBusy();
            return false; // let WebKit show its default dialog
        });

        this._searxWebStack.add_named(tabWrap, tabId);
        this._searxTabs.push(tab);

        if (url) {
            let targetUrl = url;
            if (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://') && !targetUrl.startsWith('file://')) {
                targetUrl = 'https://' + targetUrl;
            }
            webView.load_uri(targetUrl);
        }

        return tab;
    }

    // ── SearXNG: handle file upload/selection dialogs safely ──────────────
    _handleWebKitFileChooser(request) {
        this._fileChooserOpen = true;
        const isMultiple = (typeof request.get_select_multiple === 'function') ? request.get_select_multiple() : false;
        const mimeTypes = (typeof request.get_mime_types === 'function') ? (request.get_mime_types() || []) : [];

        const cmd = ['zenity', '--file-selection', '--title=Select file to upload'];
        if (isMultiple) {
            cmd.push('--multiple', '--separator=|');
        }
        if (mimeTypes.length > 0) {
            const exts = [];
            for (const m of mimeTypes) {
                if (m.includes('/')) {
                    const sub = m.split('/')[1].trim();
                    if (sub && sub !== '*') exts.push('*.' + sub);
                }
            }
            if (exts.length > 0) {
                cmd.push(`--file-filter=Supported Files (${exts.join(', ')}) | ${exts.join(' ')}`);
            }
        }

        try {
            const proc = Gio.Subprocess.new(cmd, Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
            proc.communicate_utf8_async(null, null, (p, res) => {
                this._fileChooserOpen = false;
                try {
                    const [ok, stdout] = p.communicate_utf8_finish(res);
                    if (ok && p.get_exit_status() === 0 && stdout) {
                        const raw = stdout.trim();
                        if (raw) {
                            const files = isMultiple ? raw.split('|').map(s => s.trim()).filter(Boolean) : [raw];
                            request.select_files(files);
                            return;
                        }
                    }
                } catch (err) {
                    console.warn('[launcher] File chooser finished with error:', err.message);
                }
                try { request.cancel(); } catch (_) { }
            });
        } catch (e) {
            console.warn('[launcher] Failed to spawn zenity file chooser:', e.message);
            this._fileChooserOpen = false;
            try { request.cancel(); } catch (_) { }
        }
    }

    // ── SearXNG: open URL in a fresh new tab ─────────────────────────────
    _searxOpenUrlInNewTab(url, title) {
        if (!this._searxTabs) this._searxTabs = [];
        const tab = this._createTabWebView(url, title);
        if (tab) {
            this._searxSwitchToTab(tab.id);
        }
    }

    // ── SearXNG: create a new search tab ─────────────────────────────────
    _searxCreateNewTab() {
        this._searxPendingNewTab = true;
        this._searxWebBoxOpen = false;
        if (this._searxWebBox) this._searxWebBox.set_visible(false);
        if (this._searxResultScroll) this._searxResultScroll.set_visible(false);
        this._searchEntry.set_placeholder_text(' Search in current tab…');
        this._searchEntry.set_text('');
        this._searxLastQuery = '';
        this._searxClearList();
        this._searxShowIdle();
        this._searchEntry.grab_focus();
        this._searxUpdateTabsBadge();
    }

    // ── SearXNG: switch to a specific tab ────────────────────────────────
    _searxSwitchToTab(tabId) {
        if (!this._searxTabs) return;
        const tab = this._searxTabs.find(t => t.id === tabId);
        if (!tab) return;

        this._searxActiveTabId = tab.id;
        this._searxWebView = tab.webView;
        this._searxCurrentWebUrl = tab.url;
        this._searxWebBoxOpen = true;
        this._searxPendingNewTab = false;

        if (this._searxNavTitle) this._searxNavTitle.set_text(tab.title || tab.url);
        if (this._searxNavUrl) this._searxNavUrl.set_text(tab.url);

        if (this._searxResultScroll) this._searxResultScroll.set_visible(false);
        if (this._searxStatusCard) this._searxStatusCard.set_visible(false);
        if (this._searxWebBox) this._searxWebBox.set_visible(true);

        if (this._searxWebStack) {
            this._searxWebStack.set_visible_child_name(tab.id);
        }
        this._searxUpdateTabsBadge();
        this._searxUpdateNavBmBtn();
        this._persistWebState();
    }

    // ── SearXNG: close a specific tab ────────────────────────────────────
    _searxCloseTab(tabId) {
        if (!this._searxTabs) return;
        const idx = this._searxTabs.findIndex(t => t.id === tabId);
        if (idx === -1) return;

        const [removed] = this._searxTabs.splice(idx, 1);
        if (removed) {
            if (removed.webView) {
                try {
                    removed.webView.stop_loading();
                    removed.webView.load_plain_text('');
                    if (typeof removed.webView.try_close === 'function') {
                        removed.webView.try_close();
                    }
                    if (typeof removed.webView.terminate_web_process === 'function') {
                        removed.webView.terminate_web_process();
                    }
                } catch (e) {
                    console.warn('[launcher] Failed to terminate webView process:', e.message);
                }
            }
            if (removed.webWrap) {
                try {
                    if (removed.webView) {
                        removed.webWrap.remove(removed.webView);
                    }
                    this._searxWebStack.remove(removed.webWrap);
                } catch (_) { }
            }
            removed.webView = null;
            removed.webWrap = null;
        }

        if (this._searxTabs.length === 0) {
            this._searxActiveTabId = null;
            this._searxWebView = null;
            this._searxCloseWebView();
        } else {
            if (this._searxActiveTabId === tabId) {
                const nextTab = this._searxTabs[Math.min(idx, this._searxTabs.length - 1)];
                this._searxSwitchToTab(nextTab.id);
            }
        }
        this._searxUpdateTabsBadge();
        this._persistWebState();
        try {
            imports.system.gc();
        } catch (_) { }
    }

    // ── SearXNG: close all open tabs ──────────────────────────────────────
    _searxCloseAllTabs() {
        if (!this._searxTabs) return;
        const toClose = [...this._searxTabs];
        for (const t of toClose) {
            this._searxCloseTab(t.id);
        }
    }

    // ── SearXNG: update badge text/visibility ─────────────────────────────
    _searxUpdateTabsBadge() {
        const count = (this._searxTabs && this._searxTabs.length) || 0;
        const inWebKitView = !!(this._searxWebBox && this._searxWebBox.get_visible());

        // Badge pill on interactive title+url button inside WebKit toolbar
        if (this._searxTabsBadge) {
            if (count > 1) {
                this._searxTabsBadge.set_text(`${count} tabs`);
                this._searxTabsBadge.set_visible(true);
            } else {
                this._searxTabsBadge.set_visible(false);
            }
        }

        // Header "Tabs (N)" button: only visible in search mode when tabs exist
        if (this._searxHeaderTabsBtn && this._searxHeaderTabsLbl) {
            if (!inWebKitView && count > 0) {
                this._searxHeaderTabsLbl.set_text(`Tabs (${count})`);
                this._searxHeaderTabsBtn.set_visible(true);
            } else {
                this._searxHeaderTabsBtn.set_visible(false);
            }
        }
    }

    // ── SearXNG: show interactive tabs popover ────────────────────────────
    _searxShowTabsPopover(parentBtn) {
        if (!this._searxTabs || this._searxTabs.length === 0) return;

        const pop = new Gtk.Popover();
        pop.set_parent(parentBtn);
        pop.set_has_arrow(true);
        pop.set_position(Gtk.PositionType.BOTTOM);
        pop.add_css_class('launcher-popover');
        pop.get_style_context().add_provider(
            this._getPopoverCSSProvider(),
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );

        const contentBox = Gtk.Box.new(Gtk.Orientation.VERTICAL, 4);
        contentBox.set_margin_top(8);
        contentBox.set_margin_bottom(8);
        contentBox.set_margin_start(8);
        contentBox.set_margin_end(8);

        // Header row: "Open Tabs (N)"
        const header = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 8);
        header.set_valign(Gtk.Align.CENTER);
        header.set_margin_bottom(4);

        const headerLbl = Gtk.Label.new(`Open Tabs (${this._searxTabs.length})`);
        headerLbl.add_css_class('pop-section-header');
        headerLbl.set_halign(Gtk.Align.START);
        headerLbl.set_hexpand(true);
        header.append(headerLbl);

        if (this._searxTabs.length > 1) {
            const closeAllBtn = Gtk.Button.new_with_label('Close All');
            closeAllBtn.add_css_class('searx-tab-close-all-btn');
            closeAllBtn.set_valign(Gtk.Align.CENTER);
            closeAllBtn.connect('clicked', () => {
                pop.popdown();
                this._searxCloseAllTabs();
            });
            header.append(closeAllBtn);
        }
        contentBox.append(header);

        const sep = new Gtk.Separator({ orientation: Gtk.Orientation.HORIZONTAL });
        contentBox.append(sep);

        // Scrollable list of open tabs
        const scroll = new Gtk.ScrolledWindow();
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        scroll.set_max_content_height(240);
        scroll.set_propagate_natural_height(true);
        scroll.add_css_class('launcher-scroll');

        const list = new Gtk.ListBox();
        list.set_selection_mode(Gtk.SelectionMode.NONE);

        for (const tab of this._searxTabs) {
            const row = new Gtk.ListBoxRow();
            const rowBox = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 6);
            rowBox.add_css_class('searx-tab-row');
            if (tab.id === this._searxActiveTabId) {
                rowBox.add_css_class('active');
            }

            // Tab icon (custom glyph for popular sites)
            let glyphChar = '󰖟';
            if (tab.url.includes('youtube.com') || tab.url.includes('youtu.be')) glyphChar = '';
            else if (tab.url.includes('github.com')) glyphChar = '󰊤';
            else if (tab.url.includes('reddit.com')) glyphChar = '󰑍';
            else if (tab.url.includes('wikipedia.org')) glyphChar = '󰖬';

            const glyph = Gtk.Label.new(glyphChar);
            glyph.add_css_class('searx-tab-glyph');
            glyph.set_valign(Gtk.Align.CENTER);
            rowBox.append(glyph);

            const textCol = Gtk.Box.new(Gtk.Orientation.VERTICAL, 1);
            textCol.set_hexpand(true);
            textCol.set_valign(Gtk.Align.CENTER);

            const titleLbl = Gtk.Label.new(tab.title || tab.url);
            titleLbl.add_css_class('searx-tab-title');
            titleLbl.set_halign(Gtk.Align.START);
            titleLbl.set_ellipsize(3);
            titleLbl.set_max_width_chars(32);
            textCol.append(titleLbl);

            const urlLbl = Gtk.Label.new(tab.url || '');
            urlLbl.add_css_class('searx-tab-url');
            urlLbl.set_halign(Gtk.Align.START);
            urlLbl.set_ellipsize(3);
            urlLbl.set_max_width_chars(36);
            textCol.append(urlLbl);
            rowBox.append(textCol);

            // Tab Click target
            const clickBtn = Gtk.Button.new();
            clickBtn.set_child(rowBox);
            clickBtn.add_css_class('pop-item');
            clickBtn.set_hexpand(true);
            clickBtn.connect('clicked', () => {
                pop.popdown();
                this._searxSwitchToTab(tab.id);
            });

            const fullRowBox = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 2);
            fullRowBox.append(clickBtn);

            // Tab Close button
            const closeBtn = Gtk.Button.new_with_label('󰅖');
            closeBtn.add_css_class('searx-tab-close-btn');
            closeBtn.set_valign(Gtk.Align.CENTER);
            closeBtn.set_tooltip_text('Close tab');
            closeBtn.connect('clicked', () => {
                this._searxCloseTab(tab.id);
                pop.popdown();
                if (this._searxTabs && this._searxTabs.length > 0 && this._searxWebBoxOpen) {
                    this._searxShowTabsPopover(parentBtn);
                }
            });
            fullRowBox.append(closeBtn);

            row.set_child(fullRowBox);
            list.append(row);
        }

        scroll.set_child(list);
        contentBox.append(scroll);
        pop.set_child(contentBox);
        pop.popup();
    }

    // ── SearXNG: open URL in embedded WebKit view ─────────────────────────
    _searxOpenUrl(url, title) {
        if (!this._searxTabs) this._searxTabs = [];
        this._searxCurrentWebUrl = url;
        this._searxWebBoxOpen = true;

        let tab;
        if (this._searxPendingNewTab || this._searxTabs.length === 0) {
            tab = this._createTabWebView(url, title);
            this._searxPendingNewTab = false;
        } else {
            tab = this._searxTabs.find(t => t.id === this._searxActiveTabId) || this._searxTabs[0];
            if (!tab) {
                tab = this._createTabWebView(url, title);
            } else {
                tab.title = title || url;
                tab.url = url;
                let targetUrl = url;
                if (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://') && !targetUrl.startsWith('file://')) {
                    targetUrl = 'https://' + targetUrl;
                }
                if (tab.webView.get_uri() !== targetUrl) {
                    tab.webView.load_uri(targetUrl);
                }
            }
        }

        this._searxActiveTabId = tab.id;
        this._searxWebView = tab.webView;

        if (this._searxNavTitle) this._searxNavTitle.set_text(tab.title || url);
        if (this._searxNavUrl) this._searxNavUrl.set_text(url);

        // Hide search results and status card
        if (this._searxResultScroll) this._searxResultScroll.set_visible(false);
        if (this._searxStatusCard) this._searxStatusCard.set_visible(false);

        // Show webview container and set stack active child
        if (this._searxWebBox) this._searxWebBox.set_visible(true);
        if (this._searxWebStack) {
            this._searxWebStack.set_visible(true);
            this._searxWebStack.set_visible_child_name(tab.id);
        }

        this._searxUpdateTabsBadge();
        this._searxUpdateNavBmBtn();
        this._persistWebState();
    }

    // ── SearXNG: return from WebKit view back to results list ────────────
    _searxCloseWebView() {
        this._searxWebBoxOpen = false;
        if (this._searxWebBox) this._searxWebBox.set_visible(false);
        if (this._searxResultScroll) this._searxResultScroll.set_visible(true);
        this._persistWebState();
    }

    // ── SearXNG: check if Docker container is running ─────────────────────
    _searxCheckDockerStatus(onDone) {
        try {
            const proc = new Gio.Subprocess({
                argv: [SCRIPT_DIR + '/searxng-control.sh', 'status'],
                flags: Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE,
            });
            proc.init(null);
            proc.communicate_utf8_async(null, null, (p, res) => {
                try {
                    const [, stdout] = p.communicate_utf8_finish(res);
                    const running = !!(stdout && stdout.trim() === 'running');
                    this._searxDockerRunning = running;
                    this._searxUpdateDockerBtn(running);
                    if (onDone) onDone(running);
                } catch (_) {
                    this._searxDockerRunning = false;
                    this._searxUpdateDockerBtn(false);
                    if (onDone) onDone(false);
                }
            });
        } catch (_) {
            this._searxDockerRunning = false;
            this._searxUpdateDockerBtn(false);
            if (onDone) onDone(false);
        }
    }

    // ── SearXNG: update Docker toggle button appearance ───────────────────
    _searxUpdateDockerBtn(running) {
        if (!this._searxDockerBtn) return;
        if (running) {
            this._searxDockerBtn.remove_css_class('docker-off');
            this._searxDockerBtn.add_css_class('docker-on');
            if (this._searxDockerGlyph) this._searxDockerGlyph.set_text('󰡨');
            if (this._searxDockerLbl) this._searxDockerLbl.set_text('Docker 󰓛');
        } else {
            this._searxDockerBtn.remove_css_class('docker-on');
            this._searxDockerBtn.add_css_class('docker-off');
            if (this._searxDockerGlyph) this._searxDockerGlyph.set_text('󰡨');
            if (this._searxDockerLbl) this._searxDockerLbl.set_text('Docker ▶');
        }
    }

    // ── SearXNG: toggle Docker container on/off ───────────────────────────
    _searxToggleDocker() {
        if (this._searxDockerRunning) {
            this._searxShowStatus('󰡨', 'Stopping SearXNG…', 'Stopping container...', false, false);
            this._searxUpdateDockerBtn(false);

            try {
                const proc = new Gio.Subprocess({
                    argv: [SCRIPT_DIR + '/searxng-control.sh', 'stop'],
                    flags: Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE,
                });
                proc.init(null);
                proc.wait_async(null, () => {
                    this._searxDockerRunning = false;
                    this._searxUpdateDockerBtn(false);
                    this._searxShowStatus('󰡨', 'Docker stopped', 'SearXNG is stopped to save CPU & memory.', false, true);
                });
            } catch (_) {
                this._searxDockerRunning = false;
                this._searxUpdateDockerBtn(false);
                this._searxShowStatus('󰡨', 'Docker stopped', 'SearXNG is stopped.', false, true);
            }
        } else {
            this._searxStartDocker();
        }
    }

    // ── SearXNG: auto-start Docker if a bookmark is opened and it isn't running ──
    _searxEnsureDockerRunning() {
        if (this._searxDockerStarting) return;
        this._searxCheckDockerStatus((running) => {
            if (!running) this._searxStartDocker({ background: true });
        });
    }

    // ── SearXNG: start Docker container (idempotent — safe to call speculatively) ──
    // opts.background: start without the status card (bookmark open keeps the WebKit view).
    _searxStartDocker(opts) {
        const background = !!(opts && opts.background);
        if (this._searxDockerRunning || this._searxDockerStarting) return;
        this._searxDockerStarting = true;

        if (!background) {
            this._searxShowStatus('󰡨', 'Starting Docker & SearXNG…', 'Starting service and container (authenticate if prompted)...', false, false);
        }

        let settled = false;
        const onStarted = () => {
            if (settled) return;
            settled = true;
            this._searxDockerStarting = false;
            if (background) return;
            this._searxShowIdle();
            const q = this._searchEntry.get_text().trim() || this._searxLastQuery;
            if (q) this._doSearxQuery(q);
        };

        const onFailed = (title, body, showFallback) => {
            if (settled) return;
            settled = true;
            this._searxDockerStarting = false;
            if (background) return;
            this._searxShowStatus('󰡨', title, body, showFallback, true);
        };

        try {
            const proc = new Gio.Subprocess({
                argv: [SCRIPT_DIR + '/searxng-control.sh', 'start'],
                flags: Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE,
            });
            proc.init(null);

            let pollCount = 0;
            let pollSource = 0;
            pollSource = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1200, () => {
                pollCount++;
                this._searxCheckDockerStatus((running) => {
                    if (running) {
                        if (pollSource) { GLib.source_remove(pollSource); pollSource = 0; }
                        onStarted();
                    }
                });
                if (pollCount > 60) return GLib.SOURCE_REMOVE;
                return GLib.SOURCE_CONTINUE;
            });

            proc.wait_async(null, (p, res) => {
                if (pollSource) { try { GLib.source_remove(pollSource); pollSource = 0; } catch (_) { } }
                try {
                    p.wait_finish(res);
                    this._searxCheckDockerStatus((running) => {
                        if (running) {
                            onStarted();
                        } else {
                            onFailed('Could not start Docker', 'Authentication was cancelled or Docker service failed to start.', true);
                        }
                    });
                } catch (err) {
                    onFailed('Could not start Docker', 'Error: ' + (err.message || 'Unknown error'), true);
                }
            });
        } catch (e) {
            onFailed('Docker error', 'Could not execute ' + SCRIPT_DIR + '/searxng-control.sh', false);
        }
    }

    // ── SearXNG: show the status card (hides result list & webview) ──────
    _searxShowStatus(glyph, title, body, showFallback, showActionBtn = false) {
        if (this._searxWebBox) this._searxWebBox.set_visible(false);
        if (this._searxStatusGlyph) this._searxStatusGlyph.set_text(glyph);
        if (this._searxStatusTitle) this._searxStatusTitle.set_text(title);
        if (this._searxStatusBody) this._searxStatusBody.set_text(body);
        if (this._searxActionBtn) this._searxActionBtn.set_visible(!!showActionBtn);
        if (this._searxFallbackBtn) this._searxFallbackBtn.set_visible(!!showFallback);
        if (this._searxStatusCard) this._searxStatusCard.set_visible(true);
        if (this._searxResultScroll) this._searxResultScroll.set_visible(false);
    }

    // ── SearXNG: show idle/empty state (result area hidden) ───────────────
    _searxShowIdle() {
        if (this._searxWebBox) this._searxWebBox.set_visible(false);
        if (this._searxStatusCard) this._searxStatusCard.set_visible(false);
        if (this._searxResultScroll) this._searxResultScroll.set_visible(false);
    }

    // ── SearXNG: clear the result list widget ─────────────────────────────
    _searxClearList() {
        if (!this._searxList) return;
        let ch = this._searxList.get_first_child();
        while (ch) {
            const nx = ch.get_next_sibling();
            this._searxList.remove(ch);
            ch = nx;
        }
    }

    // ── SearXNG: perform a search (debounced entry point) ─────────────────
    _performWebSearch(query, immediate = false) {
        // Cancel any pending debounce timer immediately
        if (this._searxSearchTimer) {
            GLib.source_remove(this._searxSearchTimer);
            this._searxSearchTimer = 0;
        }

        const trimmed = (query || '').trim();

        // If WebKit view is open and user typed a non-empty query — leave webkit and search
        if (this._searxWebBoxOpen && this._searxCurrentWebUrl) {
            if (trimmed.length > 0) {
                this._searxWebBoxOpen = false;
                this._searxCurrentWebUrl = '';
                if (this._searxWebBox) this._searxWebBox.set_visible(false);
                if (this._searxResultScroll) this._searxResultScroll.set_visible(false);
                this._persistWebState();
            } else {
                return;
            }
        }

        if (!trimmed) {
            this._searxLastQuery = '';
            this._searxClearList();
            if (this._searxDockerRunning) {
                this._searxShowIdle();
            } else {
                this._searxShowStatus('󰡨', 'Docker stopped',
                    'Click Start SearXNG or the Docker button to launch.', false, true);
            }
            return;
        }

        // If we already have results for this exact query, just show them
        if (trimmed === this._searxLastQuery && this._searxList && this._searxList.get_first_child()) {
            if (this._searxStatusCard) this._searxStatusCard.set_visible(false);
            if (this._searxResultScroll) this._searxResultScroll.set_visible(true);
            return;
        }

        // Use cached Docker status for instant per-keystroke feedback.
        if (!this._searxDockerRunning) {
            this._searxShowStatus('󰡨', 'Docker stopped',
                'Click Start SearXNG or the Docker button to launch.', false, true);
            return;
        }

        // Show searching feedback immediately
        this._searxShowStatus('󱃎', 'Searching…', trimmed, false, false);

        if (immediate) {
            this._doSearxQuery(trimmed);
        } else {
            // Debounce: fire query after user pauses typing (400ms)
            this._searxSearchTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 400, () => {
                this._searxSearchTimer = 0;
                this._doSearxQuery(trimmed);
                return GLib.SOURCE_REMOVE;
            });
        }
    }

    // ── SearXNG: execute JSON search via Soup 3 ───────────────────────────
    _doSearxQuery(query) {
        if (!query || !query.trim()) return;
        const trimmed = query.trim();
        this._searxLastQuery = trimmed;

        // Lazy-init Soup session (one per launcher process lifetime)
        if (!this._soupSession) {
            this._soupSession = new Soup.Session();
            this._soupSession.timeout = 8;  // seconds
        }

        const url = `http://127.0.0.1:8080/search?q=${encodeURIComponent(trimmed)}&format=json`;
        const msg = new Soup.Message({ method: 'GET', uri: GLib.Uri.parse(url, GLib.UriFlags.NONE) });

        this._soupSession.send_and_read_async(
            msg, GLib.PRIORITY_DEFAULT, null,
            (session, res) => {
                try {
                    const bytes = session.send_and_read_finish(res);
                    if (!bytes) throw new Error('empty response');
                    const status = msg.get_status();
                    if (status !== Soup.Status.OK) throw new Error(`HTTP ${status}`);

                    const text = new TextDecoder().decode(bytes.get_data());
                    const json = JSON.parse(text);

                    // Discard response if user has already queried something newer
                    if (this._searxLastQuery !== trimmed) return;

                    this._renderSearxResults(json.results || [], trimmed);
                } catch (e) {
                    if (this._searxLastQuery !== trimmed) return;
                    console.warn('[launcher] SearXNG query failed:', e.message);
                    this._searxShowStatus(
                        '󰖟',
                        'SearXNG unreachable',
                        'Make sure Docker is running:\n  docker compose up -d',
                        true  // show browser fallback button
                    );
                }
            }
        );
    }

    // ── SearXNG: render result list ───────────────────────────────────────
    _renderSearxResults(results, query) {
        this._searxClearList();

        if (!results || results.length === 0) {
            this._searxShowStatus('󰍉', 'No results', `Nothing found for "${query}"`, true);
            return;
        }

        // Show result area, hide status card & webview only if webview not active
        if (this._searxWebBoxOpen && this._searxCurrentWebUrl && this._searxWebBox && this._searxWebBox.get_visible()) {
            if (this._searxWebBox) this._searxWebBox.set_visible(true);
            if (this._searxStatusCard) this._searxStatusCard.set_visible(false);
            if (this._searxResultScroll) this._searxResultScroll.set_visible(false);
        } else {
            if (this._searxWebBox) this._searxWebBox.set_visible(false);
            if (this._searxStatusCard) this._searxStatusCard.set_visible(false);
            if (this._searxResultScroll) this._searxResultScroll.set_visible(true);
        }

        for (const r of results) {
            const title = r.title || '(no title)';
            const url = r.url || '';
            const snippet = r.content || '';

            // Row container: HBox [ main button (flex) | mini external-browser button ]
            const itemRow = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 4);
            itemRow.set_hexpand(true);

            // Each result is a button for clean keyboard + click activation
            const rowBtn = Gtk.Button.new();
            rowBtn.add_css_class('searx-result-item');
            rowBtn.set_hexpand(true);
            rowBtn.set_halign(Gtk.Align.FILL);

            const colBox = Gtk.Box.new(Gtk.Orientation.VERTICAL, 2);
            colBox.set_hexpand(true);

            const titleLbl = Gtk.Label.new(title);
            titleLbl.add_css_class('searx-result-title');
            titleLbl.set_halign(Gtk.Align.START);
            titleLbl.set_ellipsize(3 /* Pango.EllipsizeMode.END */);
            titleLbl.set_max_width_chars(52);
            colBox.append(titleLbl);

            if (url) {
                // Trim URL to a readable length
                const displayUrl = url.length > 60 ? url.slice(0, 58) + '…' : url;
                const urlLbl = Gtk.Label.new(displayUrl);
                urlLbl.add_css_class('searx-result-url');
                urlLbl.set_halign(Gtk.Align.START);
                urlLbl.set_ellipsize(3);
                urlLbl.set_max_width_chars(56);
                colBox.append(urlLbl);
            }

            if (snippet) {
                const snipLbl = Gtk.Label.new(snippet);
                snipLbl.add_css_class('searx-result-snippet');
                snipLbl.set_halign(Gtk.Align.START);
                snipLbl.set_wrap(true);
                snipLbl.set_max_width_chars(54);
                snipLbl.set_lines(2);
                snipLbl.set_ellipsize(3);
                colBox.append(snipLbl);
            }

            rowBtn.set_child(colBox);

            // Click → open in embedded WebKit view inside launcher
            const resultUrl = url;
            const resultTitle = title;
            rowBtn.connect('clicked', () => {
                if (resultUrl) {
                    this._searxOpenUrl(resultUrl, resultTitle);
                }
            });
            itemRow.append(rowBtn);

            // Bookmark button for result item
            const bmBtn = Gtk.Button.new();
            bmBtn.add_css_class('searx-ext-btn');
            bmBtn.add_css_class('searx-row-bm-btn');
            bmBtn.set_valign(Gtk.Align.CENTER);
            const isBm = this._searxIsBookmarked(resultUrl);
            const bmLbl = Gtk.Label.new(isBm ? '󰃂' : '󰃀');
            bmBtn.set_child(bmLbl);
            bmBtn.set_tooltip_text(isBm ? 'Remove bookmark' : 'Bookmark result');
            if (isBm) bmBtn.add_css_class('bookmarked');
            bmBtn.connect('clicked', () => {
                if (this._searxIsBookmarked(resultUrl)) {
                    this._searxRemoveBookmark(resultUrl);
                    bmLbl.set_text('󰃀');
                    bmBtn.remove_css_class('bookmarked');
                    bmBtn.set_tooltip_text('Bookmark result');
                } else {
                    this._searxAddBookmark(resultUrl, resultTitle);
                    bmLbl.set_text('󰃂');
                    bmBtn.add_css_class('bookmarked');
                    bmBtn.set_tooltip_text('Remove bookmark');
                }
            });
            itemRow.append(bmBtn);

            // Dedicated external browser button
            const extBtn = Gtk.Button.new_with_label('󰖟');
            extBtn.add_css_class('searx-ext-btn');
            extBtn.set_valign(Gtk.Align.CENTER);
            extBtn.set_tooltip_text('Open in external browser');
            extBtn.connect('clicked', () => {
                if (resultUrl) {
                    openInBrowser(resultUrl);
                }
            });
            itemRow.append(extBtn);

            const row = new Gtk.ListBoxRow();
            row.set_child(itemRow);
            row.set_activatable(false);
            this._searxList.append(row);
        }

        // Scroll back to top after populating
        if (this._searxResultScroll) {
            const adj = this._searxResultScroll.get_vadjustment();
            if (adj) adj.set_value(0);
        }
    }
    _refreshFavorites(query) {
        const q = (query ?? '').toLowerCase().trim();
        while (true) {
            const ch = this._favFlow.get_first_child();
            if (!ch) break;
            this._favFlow.remove(ch);
        }
        // Section header stays visible as long as ANY favorites exist so the
        // user can see (and drag to) the bar even when the query filters them out.
        const allFavApps = this._allApps.filter(a => this._favoritesSet.has(a.className));
        this._favSection.set_visible(allFavApps.length > 0);
        // Only populate the grid with apps that match the current query.
        const favApps = q
            ? allFavApps.filter(a => a.name.toLowerCase().includes(q))
            : allFavApps;
        for (const app of favApps)
            this._favFlow.append(this._makeAppTile(app));
    }

    // ── Agent Tab (WebKitGTK + WebLLM + React) ─────────────────────────────
    _enableWebKitWebGPU(settings) {
        // WebGPU is a development/experimental feature in WebKitGTK. On
        // versions where it is exposed, WebGPU also needs the GPU-process
        // rendering flags enabled before the page is loaded. A previous
        // implementation enabled only WebGPU/WebGPUHDR and silently stopped
        // when one feature-list operation threw, leaving navigator.gpu absent.
        // NOTE: On many WebKitGTK6 builds, WebGPU ships as a stub navigator.gpu
        // (Object.prototype only, no requestAdapter) — in that case the launcher
        // will transparently fall back to the embedded Chromium/Electron renderer.
        const wanted = new Set([
            'WebGPU',
            'WebGPUHDR',
            'WebGPUDeveloperFeatures',
            'GPUProcessDOMRendering',
            'GPUProcessCanvasRendering',
            'UseGPUProcessForWebGL',
        ]);
        const lists = [];
        for (const getter of [
            () => WebKit.Settings.get_all_features(),
            () => WebKit.Settings.get_development_features(),
            () => WebKit.Settings.get_experimental_features(),
        ]) {
            try {
                const list = getter();
                if (list) lists.push(list);
            } catch (_) { }
        }

        const seen = new Set();
        for (const fl of lists) {
            try {
                const count = typeof fl.get_length === 'function' ? fl.get_length() : (fl.length || 0);
                for (let i = 0; i < count; i++) {
                    const feat = typeof fl.get === 'function' ? fl.get(i) : fl[i];
                    if (!feat || typeof feat.get_identifier !== 'function') continue;
                    const ident = feat.get_identifier();
                    if (seen.has(ident) || !wanted.has(ident)) continue;
                    seen.add(ident);
                    try {
                        settings.set_feature_enabled(feat, true);
                        const enabled = typeof settings.get_feature_enabled === 'function'
                            ? settings.get_feature_enabled(feat) : 'unknown';
                        console.log('[launcher] WebKit feature state:', ident, enabled);
                    } catch (e) {
                        console.warn('[launcher] Failed to enable WebKit feature:', ident, e.message);
                    }
                }
            } catch (e) {
                console.warn('[launcher] Failed to inspect WebKit feature list:', e.message);
            }
        }

        if (!seen.has('WebGPU')) {
            console.warn('[launcher] WebKitGTK does not expose a WebGPU feature flag in this build');
        }
    }

    _startAgentLoopbackServer() {
        if (this._agentHttpServer && this._agentHttpPort) {
            return `http://${AGENT_LOOPBACK_HOST}:${this._agentHttpPort}/index.html`;
        }

        const appDist = GLib.build_filenamev([HOME, '.hyprcandy', 'GJS', 'hyprcandydock', 'agent-app', 'dist']);
        const indexPath = GLib.build_filenamev([appDist, 'index.html']);
        if (!GLib.file_test(indexPath, GLib.FileTest.IS_REGULAR)) {
            console.warn('[launcher] Agent dist not found at:', indexPath);
            return null;
        }

        try {
            this._agentHttpServer = createAgentLoopbackServer(appDist);
            this._agentHttpPort = AGENT_LOOPBACK_PORT;
            console.log(`[launcher] Agent WebLLM loopback origin: http://${AGENT_LOOPBACK_HOST}:${AGENT_LOOPBACK_PORT}/`);
            return `http://${AGENT_LOOPBACK_HOST}:${AGENT_LOOPBACK_PORT}/index.html`;
        } catch (error) {
            this._agentHttpServer = null;
            this._agentHttpPort = 0;
            console.warn('[launcher] Failed to start agent loopback server:', error.message);
            return null;
        }
    }

    _startAgentElectronProc(launcherScript, agentUrl, wrapWidget) {
        // Spawns the embedded Electron child process that renders the React
        // agent-app with real mature Chromium WebGPU (matching CandyCode).
        // IPC uses line-delimited JSON on stdin/stdout (no sockets, no HTTP).
        //   stdout JSON lines (Electron → GJS):
        //     { type: 'ready' }
        //     { type: 'console', level, msg }
        //     { type: 'error', message, stack }
        //     { type: 'postMessage', data: '<envelope JSON string>' }
        //   stdin JSON lines (GJS → Electron):
        //     { type: 'bounds', x, y, w, h }
        //     { type: 'dispatch', payload: {...} }
        //     { type: 'show' | 'hide' | 'focus' | 'quit' | 'reload' | 'devtools' }
        if (!launcherScript || !wrapWidget) return;

        // Build argv
        const argv = [launcherScript, agentUrl];
        const envv = GLib.get_environ();
        // Disable GPU sandbox for Mesa/DRI fd permissions issue on some kernels
        const flags = Gio.SubprocessFlags.STDIN_PIPE
            | Gio.SubprocessFlags.STDOUT_PIPE
            | Gio.SubprocessFlags.STDERR_MERGE
            | Gio.SubprocessFlags.NONE;
        const proc = new Gio.Subprocess({
            argv: argv,
            flags: flags,
            // envv is applied implicitly via current process env (inherited)
        });
        proc.init(null);
        this._agentElectronProc = proc;
        this._agentElectronExited = false;

        // ── stdout/stderr reader (line JSONL) ──────────────────────────────
        const stdoutPipe = proc.get_stdout_pipe();
        if (stdoutPipe) {
            const dataIn = new Gio.DataInputStream({ base_stream: stdoutPipe, close_base_stream: true });
            dataIn.set_newline_type(Gio.DataStreamNewlineType.ANY);
            this._agentElectronStdin = proc.get_stdin_pipe();
            const readOne = () => {
                dataIn.read_line_async(GLib.PRIORITY_DEFAULT, null, (s, res) => {
                    try {
                        const [line, len] = s.read_line_finish_utf8(res);
                        if (line === null) {
                            console.warn('[launcher:electron] Child process closed stdout (EOF)');
                            this._agentOnElectronDead(proc);
                            return;
                        }
                        if (line.trim().length > 0) {
                            this._agentOnElectronLine(line);
                        }
                        readOne();
                    } catch (err) {
                        // If error is IOError (EOF-ish), stop; fallback
                        if (err.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.CLOSED)
                            || err.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.CONNECTION_CLOSED)
                            || err.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.BROKEN_PIPE)) {
                            console.warn('[launcher:electron] Read EOF; falling back to WebKit');
                            this._agentOnElectronDead(proc);
                            return;
                        }
                        console.warn('[launcher:electron] Stdout read error:', err.message);
                        try { readOne(); } catch (_) { }
                    }
                });
            };
            readOne();
        }

        // Watch process exit so we can fall back to WebKit if it crashes.
        proc.wait_check_async(null, (p, res) => {
            try {
                const ok = p.wait_check_finish(res);
                const code = p.get_exit_status();
                console.warn(`[launcher:electron] Child exited ok=${ok} status=${code}; activating WebKit fallback`);
            } catch (_) { }
            this._agentOnElectronDead(proc);
        });

        // ── Bounds / position sync removed.
        // In the new headless-Electron architecture (HYPRCANDY_ELECTRON_EMBEDDED=1)
        // the Electron BrowserWindow is never shown, so there is no foreign window
        // to reposition. Bounds messages are no longer sent.

        console.log('[launcher:electron] Spawned headless inference worker (Chromium WebGPU)');
    }

    _agentElectronSyncBounds(_wrapWidget) {
        // No-op in headless embedded mode — Electron window is never shown.
    }

    _agentElectronWriteStdin(lineOrMsg) {
        if (!this._agentElectronStdin) return;
        try {
            const str = typeof lineOrMsg === 'string' ? lineOrMsg : JSON.stringify(lineOrMsg);
            const line = str.endsWith('\n') ? str : (str + '\n');
            const bytes = new TextEncoder().encode(line);
            this._agentElectronStdin.write_all(bytes, null);
        } catch (e) {
            console.warn('[launcher:electron] stdin write error:', e.message);
        }
    }

    _agentOnElectronLine(line) {
        if (!line || !line.trim()) return;
        let msg = null;
        try { msg = JSON.parse(line.trim()); }
        catch {
            // Electron stderr is merged into stdout by the subprocess. Keep
            // it visible in launcher logs instead of silently discarding the
            // reason Chromium never reaches the ready handshake.
            console.warn('[launcher:electron:raw]', line.trim().slice(0, 4000));
            return;
        }
        if (!msg || typeof msg !== 'object') return;
        if (msg.type === 'ready') {
            this._agentElectronActive = true;
            // In the new headless-Electron architecture the WebKitGTK view IS the
            // UI — keep it visible. The 'ready' signal just means the Chromium
            // inference engine has fully booted and WebLLM is available.
            console.log('[launcher:electron] Inference worker ready (Chromium WebGPU enabled; embedded headless mode)');
            try {
                // Push current theme + user prompt state into the hidden renderer.
                // Even though the renderer window is not shown, the React app inside
                // it must receive theme vars to correctly theme the WebKit UI side.
                if (this._cachedThemeVars) this._agentPostMessage({ type: 'theme_update', payload: this._cachedThemeVars });
            } catch (_) { }
            if (this._agentElectronQueue && this._agentElectronQueue.length > 0) {
                const q = this._agentElectronQueue.slice();
                this._agentElectronQueue = [];
                for (const queued of q) {
                    try {
                        this._agentElectronWriteStdin({
                            type: 'dispatch',
                            payload: queued,
                        });
                    } catch (err) {
                        console.warn('[launcher:electron] Failed to dispatch queued payload:', err.message);
                    }
                }
            }
            return;
        }
        if (msg.type === 'console') {
            const lvl = String(msg.level || 'log');
            const m = String(msg.msg || '');
            if (lvl === 'error') console.error('[agent-react-electron]', m);
            else if (lvl === 'warn') console.warn('[agent-react-electron]', m);
            // Drop browser/info/log chatter from the hidden Electron renderer.
            return;
        }
        if (msg.type === 'error') {
            console.warn('[launcher:electron] Renderer error:', msg.message || '(unknown)', msg.stack || '');
            return;
        }
        if (msg.type === 'postMessage') {
            // Mirrors WebKit script-message-received::agent handler (same envelope string)
            this._agentHandleMessage(String(msg.data || ''), 'electron');
            return;
        }
        // ── Worker/native inference relay: Electron → GJS → WebKit ────────────────
        if (msg.type === 'llama_response') {
            const response = msg.payload || {};
            this._agentPostMessage({ id: response.requestId, type: 'response', payload: response.value, error: response.error || undefined }, 'webkit');
            return;
        }
        if (msg.type === 'llama_progress') {
            this._agentInjectToWebView({ type: msg.type, payload: msg.payload }, true);
            return;
        }
        if (msg.type === 'worker_progress' || msg.type === 'worker_model_ready' ||
            msg.type === 'worker_done' ||
            msg.type === 'worker_error' || msg.type === 'worker_cache_status' ||
            msg.type === 'worker_cache_cleared') {
            // Relay the exact message object into the WebKit React app so that
            // bridge.ts dispatches it as an agent_worker_* CustomEvent which
            // agent-engine.ts listens for in WebKit-delegate mode.
            this._agentInjectToWebView({ type: msg.type, payload: msg.payload });
            return;
        }
        if (msg.type === 'worker_token') {
            this._agentInjectToWebView({ type: msg.type, payload: msg.payload }, 'token');
            return;
        }
    }

    // ── Inject a message directly into the WebKit React bridge ───────────────────
    // Calls window.__hyprcandy_agent_dispatch(msg) in the WebKit renderer via
    // evaluate_javascript. Used to push worker_* inference events from Electron
    // back into the WebKit React app's bridge handlers.
    _agentInjectToWebView(msg, throttle = false) {
        const wv = this._agentWebView;
        if (!wv) return;
        if (throttle) {
            const pending = this._agentInjectThrottlePending;
            if (throttle === 'token' && pending?.type === 'worker_token' && msg.type === 'worker_token') {
                this._agentInjectThrottlePending = {
                    type: 'worker_token',
                    payload: {
                        ...(pending.payload || {}),
                        ...(msg.payload || {}),
                        token: String(pending.payload?.token || '') + String(msg.payload?.token || ''),
                    },
                };
            } else {
                this._agentInjectThrottlePending = msg;
            }
            if (this._agentInjectThrottleTimer) return;
            const delay = throttle === 'token' ? 50 : 200;
            this._agentInjectThrottleTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, delay, () => {
                this._agentInjectThrottleTimer = 0;
                const pending = this._agentInjectThrottlePending;
                this._agentInjectThrottlePending = null;
                if (pending) this._agentInjectToWebView(pending);
                return GLib.SOURCE_REMOVE;
            });
            return;
        }
        try {
            const js = `(function(){
  try {
    if (typeof window.__hyprcandy_agent_dispatch === 'function') {
      window.__hyprcandy_agent_dispatch(${JSON.stringify(msg)});
    } else {
      window.dispatchEvent(new CustomEvent('agent_host_message', { detail: ${JSON.stringify(msg)} }));
    }
  } catch(e) { console.warn('[bridge-inject]', e.message); }
})();`;
            // evaluate_javascript is the standard WebKitGTK4 API
            if (typeof wv.evaluate_javascript === 'function') {
                wv.evaluate_javascript(js, -1, null, null, null, null);
            } else if (typeof wv.run_javascript === 'function') {
                wv.run_javascript(js, null, null);
            }
        } catch (e) {
            console.warn('[launcher] agentInjectToWebView error:', e.message);
        }
    }

    _agentOnElectronDead(deadProc = null) {
        // A previous worker can finish its wait/read callback after a restart.
        // Never let that stale callback clear the currently active worker.
        if (deadProc && this._agentElectronProc && this._agentElectronProc !== deadProc) return;
        if (this._agentElectronExited && !this._agentElectronProc) return;
        this._agentElectronExited = true;
        this._agentElectronActive = false;
        this._agentUsingElectron = false;
        this._agentElectronProc = null;
        this._agentElectronStdin = null;
        if (this._agentElectronQueue && this._agentElectronQueue.length > 0) {
            const errPayload = { message: 'Electron worker exited unexpectedly.' };
            for (const item of this._agentElectronQueue) {
                this._agentInjectToWebView({ type: 'worker_error', payload: errPayload });
            }
            this._agentElectronQueue = [];
        }
        // Do not silently switch WebLLM to WebKitGTK: WebKitGTK may expose a
        // navigator.gpu stub without requestAdapter, producing a misleading
        // model/cache error. Opt into the legacy fallback only for debugging.
        const allowWebKitFallback = GLib.getenv('HYPRCANDY_AGENT_ALLOW_WEBKIT_FALLBACK') === '1';
        if (!allowWebKitFallback) {
            console.error('[launcher:electron] Electron agent exited; WebKitGTK fallback disabled because WebLLM requires Chromium WebGPU.');
            return;
        }
        // Activate WebKit fallback widget only when explicitly requested.
        try {
            if (this._agentWebView) {
                this._agentWebView.set_visible(true);
                // If loopback server is up but webview has not loaded, load now
                if (!this._agentWebView.get_uri()) {
                    const url = `http://${AGENT_LOOPBACK_HOST}:${AGENT_LOOPBACK_PORT}/index.html`;
                    try { this._agentWebView.load_uri(url); } catch (_) { }
                }
            }
        } catch (_) { }
    }

    _sendOrQueueElectronDispatch(payload) {
        const action = payload?.action || '';
        const type = payload?.type || '';
        const isLlamaRequest = type === 'llama_request' || action.startsWith('llama_');
        const isLlamaStop = isLlamaRequest && action === 'llama_stop';
        const allowed = isLlamaRequest ? (this._agentLlamaEnabled || isLlamaStop) : this._workspaceStartupEnabled;
        if (!allowed) {
            console.log(`[launcher:${isLlamaRequest ? 'llama' : 'workspace'}] Dispatch suppressed while its independent toggle is OFF.`);
            return;
        }
        if (this._agentElectronActive && this._agentElectronStdin) {
            try {
                this._agentElectronWriteStdin({
                    type: 'dispatch',
                    payload: payload,
                });
                return;
            } catch (e) {
                console.warn('[launcher:electron] Stdin write error, re-queueing:', e.message);
            }
        }
        if (!this._agentElectronQueue) this._agentElectronQueue = [];
        this._agentElectronQueue.push(payload);
        this._ensureElectronWorker();
    }

    _ensureElectronWorker() {
        if (!this._workspaceStartupEnabled && !this._agentLlamaEnabled) {
            console.log('[launcher] Workspace and llama toggles are OFF; refusing to start the hidden Electron worker.');
            return;
        }
        if (this._agentElectronProc) return;
        const electronLauncher = GLib.build_filenamev([HOME, '.hyprcandy', 'GJS', 'hyprcandydock', 'start-electron-agent.sh']);
        const agentUrl = this._startAgentLoopbackServer();
        if (GLib.file_test(electronLauncher, GLib.FileTest.IS_REGULAR) && agentUrl) {
            console.log('[launcher:electron] (Re)starting headless Electron inference worker...');
            try {
                this._startAgentElectronProc(electronLauncher, agentUrl, this._agentWrap || this._appView);
                this._agentUsingElectron = true;
            } catch (err) {
                console.warn('[launcher:electron] Failed to start Electron worker:', err.message);
            }
        }
    }

    _warmupWorkspaceShell() {
        if (!this._workspaceStartupEnabled) return;
        const agentUrl = this._startAgentLoopbackServer();
        if (!agentUrl) return;
        // Workspace startup only warms the WebKit/Electron shell. It must never
        // start llama-server; the model server is an explicit user choice.
        this._ensureElectronWorker();
        console.log('[launcher:workspace] Warmed workspace shell without starting llama-server.');
    }

    _agentCheckLlamaStatus(onDone) {
        try {
            if (!this._soupSession) this._soupSession = new Soup.Session();
            const req = new Soup.Message({
                method: 'GET',
                uri: GLib.Uri.parse(`http://127.0.0.1:${LLAMA_SERVER_PORT}/health`, GLib.UriFlags.NONE)
            });
            this._soupSession.send_and_read_async(req, GLib.PRIORITY_DEFAULT, null, (session, res) => {
                try {
                    const bytes = session.send_and_read_finish(res);
                    const text = new TextDecoder().decode(bytes.get_data());
                    const payload = text ? JSON.parse(text) : null;
                    const running = !!(payload && (payload.status === 'ok' || payload.ok === true || payload.running === true));
                    this._agentLlamaRunning = running;
                    this._agentUpdateLlamaBtn();
                    if (onDone) onDone(running);
                } catch (_) {
                    this._agentLlamaRunning = false;
                    this._agentUpdateLlamaBtn();
                    if (onDone) onDone(false);
                }
            });
        } catch (_) {
            this._agentLlamaRunning = false;
            this._agentUpdateLlamaBtn();
            if (onDone) onDone(false);
        }
    }

    _agentConfirmLlamaHealth(maxMs = 8000, intervalMs = 250) {
        const started = Date.now();
        const probe = () => {
            this._agentCheckLlamaStatus((running) => {
                if (running) {
                    this._agentLlamaRunning = true;
                    this._agentUpdateLlamaBtn();
                    return;
                }
                if (Date.now() - started < maxMs) {
                    GLib.timeout_add(GLib.PRIORITY_DEFAULT, intervalMs, () => {
                        probe();
                        return GLib.SOURCE_REMOVE;
                    });
                } else {
                    this._agentLlamaRunning = false;
                    this._agentUpdateLlamaBtn();
                }
            });
        };
        probe();
    }

    _agentStopElectronWorker() {
        const proc = this._agentElectronProc;
        if (!proc) return;
        try {
            try { proc.send_signal(Gio.ProcessSignal.TERM); } catch (_) { }
            try { proc.force_exit(); } catch (_) { }
        } catch (_) { }
        try {
            if (this._agentElectronQueue && this._agentElectronQueue.length > 0) {
                this._agentElectronQueue.length = 0;
            }
        } catch (_) { }
        this._agentElectronProc = null;
        this._agentElectronStdin = null;
        this._agentElectronActive = false;
        this._agentUsingElectron = false;
        this._agentElectronExited = true;
    }

    _agentStopNativeLlamaServer() {
        try {
            const [ok, stdout, stderr] = GLib.spawn_command_line_sync('pkill -9 -f "llama-server" || true');
            if (!ok) console.warn('[launcher:workspace] llama-server stop probe failed:', stderr?.toString?.() || '');
        } catch (_) { }
    }

    _agentStopWorkspaceProcesses() {
        try {
            // Harden the shutdown path: the launcher has a single worker script
            // and a single Electron main file, so the kill scope stays narrow.
            const cleanup = [
                'pkill -9 -f "start-electron-agent.sh" || true',
                'pkill -9 -f "agent-app/electron/main.cjs" || true',
                'pkill -9 -f "electron/dist/electron" || true',
            ];
            for (const cmd of cleanup) {
                try {
                    const [ok, stdout, stderr] = GLib.spawn_command_line_sync(cmd);
                    if (!ok) {
                        console.warn('[launcher:workspace] cleanup command failed:', stderr?.toString?.() || cmd);
                    }
                } catch (_) { }
            }
        } catch (_) { }
    }

    _agentRevealWorkspace() {
        if (!this._agentWebView) return;
        try {
            this._agentWebView.set_visible(true);
            this._agentWebView.set_opacity(1.0);
        } catch (_) { }
        const agentUrl = this._startAgentLoopbackServer();
        if (agentUrl && !this._agentWebView.get_uri()) {
            try { this._agentWebView.load_uri(agentUrl); } catch (_) { }
        } else if (agentUrl) {
            try { this._agentWebView.reload(); } catch (_) { }
        }
    }

    _agentUpdateWorkspaceBtn() {
        if (!this._agentWorkspaceBtn || !this._agentWorkspaceGlyph || !this._agentWorkspaceLabel) return;
        const on = !!this._workspaceStartupEnabled;
        this._agentWorkspaceBtn.remove_css_class(on ? 'agent-llama-off' : 'agent-llama-on');
        this._agentWorkspaceBtn.add_css_class(on ? 'agent-llama-on' : 'agent-llama-off');
        this._agentWorkspaceGlyph.set_text(on ? '󰒋' : '󰒏');
        this._agentWorkspaceLabel.set_text(on ? 'Workspace ON' : 'Workspace OFF');
    }

    _agentUpdateLlamaBtn() {
        if (!this._agentLlamaBtn || !this._agentLlamaGlyph || !this._agentLlamaLabel) return;
        const on = !!this._agentLlamaRunning;
        this._agentLlamaBtn.remove_css_class(on ? 'agent-llama-off' : 'agent-llama-on');
        this._agentLlamaBtn.add_css_class(on ? 'agent-llama-on' : 'agent-llama-off');
        this._agentLlamaGlyph.set_text(on ? '󰒋' : '󰒏');
        this._agentLlamaLabel.set_text(on ? 'Llama ON' : 'Llama OFF');
    }

    _agentMaybeStopElectronWorker() {
        if (!this._workspaceStartupEnabled && !this._agentLlamaEnabled) this._agentStopElectronWorker();
    }

    _agentToggleWorkspace() {
        const next = !this._workspaceStartupEnabled;
        this._workspaceStartupEnabled = next;
        writeWorkspaceStartupState(next);
        this._agentUpdateWorkspaceBtn();
        if (next) {
            this._agentRevealWorkspace();
            this._ensureElectronWorker();
            this._switchTab('agent', true);
        } else {
            if (this._agentWebView) try { this._agentWebView.set_visible(false); } catch (_) { }
            this._agentMaybeStopElectronWorker();
            this._switchTab('launcher', true);
        }
    }

    _agentToggleLlama() {
        if (this._agentLlamaRunning || this._agentLlamaEnabled) {
            this._agentLlamaEnabled = false;
            this._agentPostMessage({ type: 'llama_state', payload: { enabled: false } });
            this._sendOrQueueElectronDispatch({ type: 'llama_request', requestId: `agent_llama_stop_${Date.now()}`, action: 'llama_stop', payload: {} });
            this._agentStopNativeLlamaServer();
            this._agentLlamaRunning = false;
            this._agentUpdateLlamaBtn();
            this._agentMaybeStopElectronWorker();
            return;
        }
        const model = readCachedLlamaModel();
        if (!model) {
            console.warn('[launcher:llama] No cached GGUF model found; llama-server remains OFF.');
            return;
        }
        this._agentLlamaEnabled = true;
        this._agentPostMessage({ type: 'llama_state', payload: { enabled: true } });
        this._ensureElectronWorker();
        this._sendOrQueueElectronDispatch({
            type: 'llama_request', requestId: `agent_llama_start_${Date.now()}`,
            action: 'llama_start', payload: { model, options: { context: 0, maxTokens: 2048 } }
        });
        this._agentConfirmLlamaHealth();
    }

    _buildAgentTab(ip) {
        const agentPage = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        agentPage.set_hexpand(true);
        agentPage.set_vexpand(true);
        agentPage.set_overflow(Gtk.Overflow.HIDDEN);
        agentPage.add_css_class('agent-webview-box');
        this._stack.add_named(agentPage, 'agent');

        const agentWrap = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        this._agentWrap = agentWrap;
        agentWrap.add_css_class('agent-webview-wrap');
        agentWrap.set_overflow(Gtk.Overflow.HIDDEN);
        agentWrap.set_hexpand(true);
        agentWrap.set_vexpand(true);
        agentPage.append(agentWrap);

        const session = this._getWebKitSession();
        const webView = new WebKit.WebView({ network_session: session });
        try {
            const transparent = new Gdk.RGBA();
            transparent.parse('rgba(0,0,0,0)');
            webView.set_background_color(transparent);
        } catch (_) { }
        webView.add_css_class('agent-webview');
        webView.set_overflow(Gtk.Overflow.HIDDEN);
        webView.set_hexpand(true);
        webView.set_vexpand(true);
        webView.set_visible(this._workspaceStartupEnabled);
        agentWrap.append(webView);
        this._agentWebView = webView;

        const settings = webView.get_settings();
        if (settings) {
            settings.set_enable_javascript(true);
            settings.set_enable_webgl(false);
            settings.set_enable_developer_extras(false);
            settings.set_allow_file_access_from_file_urls(true);
            settings.set_allow_universal_access_from_file_urls(true);
            settings.set_enable_smooth_scrolling(true);
            try { settings.set_enable_html5_database(true); } catch (_) { }
            try { settings.set_enable_html5_local_storage(true); } catch (_) { }
            try { settings.set_write_console_messages_to_stdout(false); } catch (_) { }
            try { settings.set_hardware_acceleration_policy(WebKit.HardwareAccelerationPolicy.NEVER); } catch (_) { }
            try { settings.set_enable_accelerated_2d_canvas(false); } catch (_) { }
        }

        const ucm = webView.get_user_content_manager();
        if (ucm) {
            try {
                ucm.register_script_message_handler('agent', null);
                ucm.connect('script-message-received::agent', (mgr, jsResult) => {
                    let raw = '';
                    try {
                        if (typeof jsResult.to_string === 'function') raw = jsResult.to_string();
                        else if (typeof jsResult.to_json === 'function') raw = jsResult.to_json(0);
                        else raw = String(jsResult);
                    } catch (e) {
                        raw = String(jsResult);
                    }
                    this._agentHandleMessage(raw);
                });
                const logScript = new WebKit.UserScript(
                    `
                    (function() {
                    const _send = (action, data) => {
                        try { window.webkit.messageHandlers.agent.postMessage(JSON.stringify({ action, payload: data })); } catch(_) {}
                    };
                    window.addEventListener('error', (e) => {
                        _send('client_error', { message: e.message, filename: e.filename, lineno: e.lineno, stack: e.error ? e.error.stack : '' });
                    });
                    window.addEventListener('unhandledrejection', (e) => {
                        _send('client_error', { message: 'UnhandledRejection: ' + String(e.reason) });
                    });
                    const _origLog = console.log, _origWarn = console.warn, _origError = console.error;
                    console.log = (...a) => { _origLog(...a); _send('console_log', { level:'log', msg: a.map(String).join(' ') }); };
                    console.warn = (...a) => { _origWarn(...a); _send('console_log', { level:'warn', msg: a.map(String).join(' ') }); };
                    console.error = (...a) => { _origError(...a); _send('console_log', { level:'error', msg: a.map(String).join(' ') }); };
                    })();
                    `,
                    WebKit.UserContentInjectedFrames.ALL_FRAMES,
                    WebKit.UserScriptInjectionTime.START,
                    null,
                    null
                );
                ucm.add_script(logScript);
            } catch (e) {
                console.warn('[launcher] Failed to register agent script message handler:', e.message);
            }
        }

        this._attachWebViewCrashHandlers(webView, 'agent-ui');

        // Defense-in-depth: same rationale as the browser tab webview — an
        // unhandled `close`/`create` from any embedded WebView should never
        // be able to affect the launcher window itself.
        webView.connect('close', () => {
            console.warn('[launcher] Agent WebKit view requested self-close (ignored)');
            this._markWebviewBusy();
        });
        webView.connect('create', () => {
            console.warn('[launcher] Agent WebKit view blocked a popup/window.open()');
            return null;
        });

        if (!this._workspaceStartupEnabled) {
            console.log('[launcher:workspace] Workspace startup policy is OFF; Agent UI shell is present but WebKit process/Electron/llama stack is dormant.');
            this._agentUpdateWorkspaceBtn();
            this._agentUpdateLlamaBtn();
            return;
        }

        // ── 1) Start loopback HTTP server first (shared by both renderers) ──
        const agentUrl = this._startAgentLoopbackServer();
        if (agentUrl && this._agentWebView && !this._agentWebView.get_uri()) {
            try { this._agentWebView.load_uri(agentUrl); } catch (_) { }
        }
        // Use the loopback origin for Electron as well as WebKit.  Electron's
        // file:// loader can report ERR_FAILED for the Vite bundle in this
        // embedded launch mode, while the Soup-served origin is reliable and
        // preserves the renderer's IndexedDB/cache origin.
        const electronAgentUrl = agentUrl;

        // ── 2) Launch Electron as a headless WebLLM inference co-process.
        // HYPRCANDY_ELECTRON_EMBEDDED=1 (set by start-electron-agent.sh) means
        // the Electron BrowserWindow is never shown. The React/WebLLM engine runs
        // inside that hidden Chromium renderer (real WebGPU), streaming tokens back
        // to GJS via stdout JSONL. GJS injects them into the WebKitGTK view below
        // via evaluate_javascript / __hyprcandy_agent_dispatch. ──────────────────
        const electronLauncher = GLib.build_filenamev([HOME, '.hyprcandy', 'GJS', 'hyprcandydock', 'start-electron-agent.sh']);
        this._agentElectronActive = false;
        this._agentUsingElectron = false;

        // ── 2) WebKitGTK WebView: THE primary visible UI surface.
        // In the new headless-Electron architecture this view always shows the
        // full React agent app. Electron runs as an invisible inference worker
        // (HYPRCANDY_ELECTRON_EMBEDDED=1) and posts tokens back via stdout JSONL;
        // GJS injects them here via evaluate_javascript → __hyprcandy_agent_dispatch.
        // If Electron is unavailable WebKit handles both UI and (limited) WebGPU. ──

        // 

        webView.connect('run-file-chooser', (wv, request) => {
            this._handleWebKitFileChooser(request);
            return true;
        });

        // The agent React surface owns project-tree context menus. Consume
        // WebKit's native navigation menu so it cannot replace the React menu
        // after the DOM contextmenu event has been handled.
        webView.connect('context-menu', () => true);

        webView.connect('load-changed', (wv, loadEvent) => {
            if (loadEvent === WebKit.LoadEvent.FINISHED) {
                this._agentInjectTheme();
                GLib.timeout_add(GLib.PRIORITY_DEFAULT, 2000, () => {
                    webView.evaluate_javascript(
                        `(() => {
                            return JSON.stringify({
                                title: document.title,
                                href: location.href,
                                origin: location.origin,
                                isSecureContext: window.isSecureContext,
                                navigatorGpu: typeof navigator.gpu,
                                hasRequestAdapter: typeof navigator.gpu?.requestAdapter,
                                userAgent: navigator.userAgent,
                                rootHTML: document.getElementById('root')?.innerHTML?.substring(0, 300),
                                children: document.getElementById('root')?.children?.length,
                                bodyText: document.body?.innerText?.substring(0, 200)
                            });
                        })()`,
                        -1, null, null, null,
                        (wv, res) => {
                            try {
                                const val = wv.evaluate_javascript_finish(res);
                                console.log('[launcher agent DOM after 2s]:', val.to_string());
                            } catch (e) {
                                console.warn('[launcher agent eval error]:', e.message);
                            }
                        }
                    );
                    return GLib.SOURCE_REMOVE;
                });
            }
        });

        webView.connect('load-failed', (wv, loadEvent, failingUri, error) => {
            console.warn('[launcher] Agent WebKit load-failed:', failingUri, error.message);
        });
    }

    _agentPostMessage(payload, explicitTarget = null) {
        // The visible WebKitGTK page is now the primary UI surface.  Only
        // responses to a request originating in the hidden Electron renderer
        // go back through Electron; ordinary host responses must be injected
        // into WebKit or its pending Promise never resolves.
        const target = explicitTarget
            || (payload?.id ? this._agentReplyTargets.get(payload.id) : null)
            || 'webkit';
        if (payload?.id && payload?.type === 'response') this._agentReplyTargets.delete(payload.id);

        if (target === 'electron') {
            if (this._agentElectronActive && this._agentElectronStdin) {
                this._agentElectronWriteStdin({ type: 'dispatch', payload });
            } else {
                this._sendOrQueueElectronDispatch(payload);
            }
            return;
        }

        if (!this._agentWebView) return;
        try {
            const jsonStr = JSON.stringify(payload);
            const script = `if (window.__hyprcandy_agent_dispatch) { window.__hyprcandy_agent_dispatch(${jsonStr}); }`;
            this._agentWebView.evaluate_javascript(script, -1, null, null, null, null);
        } catch (e) {
            console.warn('[launcher] _agentPostMessage webkit error:', e.message);
        }
    }

    _agentInjectTheme() {
        // Theme cache is replayed to Electron when it signals "ready" on stdout
        // (prevents timing race where theme update fires before renderer ready).
        try {
            const colorsPath = GLib.build_filenamev([HOME, '.config', 'gtk-4.0', 'colors.css']);
            const map = {};
            if (GLib.file_test(colorsPath, GLib.FileTest.EXISTS)) {
                const [ok, bytes] = GLib.file_get_contents(colorsPath);
                if (ok) {
                    const text = new TextDecoder().decode(bytes);
                    const re = /@define-color\s+([a-zA-Z0-9_-]+)\s+([^;]+);/g;
                    let match;
                    while ((match = re.exec(text)) !== null) {
                        map[match[1]] = match[2].trim();
                    }
                }
            }
            this._cachedThemeVars = map;
            // No subpath assumption here — HOME is a neutral "nothing
            // opened yet" fallback. Which actual project is active is up
            // to the user (folder picker) and persists in the frontend's
            // own storage; this is only a safety net for a brand-new
            // install where nothing has been chosen yet.
            this._agentPostMessage({
                type: 'runtime_config', payload: {
                    inferenceProvider: GLib.getenv('HYPRCANDY_INFERENCE_PROVIDER') || 'llama.cpp',
                    llamaEnabled: !!this._agentLlamaEnabled,
                    homeDir: HOME,
                    defaultProjectRoot: HOME,
                }
            });
            this._agentPostMessage({ type: 'theme_update', payload: map });
        } catch (e) {
            console.warn('[launcher] _agentInjectTheme failed:', e.message);
        }
    }

    _agentHandleMessage(raw, source = 'webkit') {
        let msg;
        try {
            msg = typeof raw === 'string' ? JSON.parse(raw) : raw;
        } catch (e) {
            console.warn('[launcher] Malformed agent message:', raw);
            return;
        }

        const id = msg.id;
        const action = msg.action;
        const payload = msg.payload || {};
        if (id) this._agentReplyTargets.set(id, source);

        if (action === 'client_error') {
            console.warn('[launcher agent client error]:', JSON.stringify(payload));
            return;
        }

        if (action === 'console_log') {
            const lvl = payload.level || 'log';
            if (lvl === 'error') console.error('[agent-react]', payload.msg);
            else if (lvl === 'warn') console.warn('[agent-react]', payload.msg);
            // Ignore log/info/debug chatter from the WebKit/Electron agent UI.
            return;
        }

        if (action === 'web_search') {
            const query = payload.query || '';
            this._searxEnsureDockerRunning();
            if (!this._soupSession) {
                this._soupSession = new Soup.Session();
                this._soupSession.timeout = 10;
            }
            const url = `http://127.0.0.1:8080/search?q=${encodeURIComponent(query)}&format=json`;
            const req = new Soup.Message({ method: 'GET', uri: GLib.Uri.parse(url, GLib.UriFlags.NONE) });
            this._soupSession.send_and_read_async(req, GLib.PRIORITY_DEFAULT, null, (session, res) => {
                try {
                    const bytes = session.send_and_read_finish(res);
                    const text = new TextDecoder().decode(bytes.get_data());
                    const json = JSON.parse(text);
                    this._agentPostMessage({ id, type: 'response', payload: json.results || [] });
                } catch (e) {
                    this._agentPostMessage({ id, type: 'response', error: e.message });
                }
            });
        } else if (action === 'searxng_status') {
            this._searxCheckDockerStatus((running) => {
                this._agentPostMessage({ id, type: 'response', payload: { running } });
            });
        } else if (action === 'searxng_start') {
            this._searxStartDocker({ background: true });
            this._agentPostMessage({ id, type: 'response', payload: { success: true } });
        } else if (action === 'read_file') {
            try {
                const [ok, bytes] = GLib.file_get_contents(payload.path);
                if (ok) {
                    let text = new TextDecoder().decode(bytes);
                    const offset = Number(payload.offset) || 0;
                    const limit = Number(payload.limit) || 0;
                    if (offset > 0 || limit > 0) {
                        const lines = text.split('\n');
                        const start = offset > 0 ? offset - 1 : 0;
                        const end = limit > 0 ? start + limit : lines.length;
                        text = lines.slice(start, end).join('\n');
                    } else if (text.length > 200000) {
                        // Safety cap so one huge file can't blow the model's
                        // context on its own; the model can re-read with an
                        // offset/limit slice if it needs more of the file.
                        text = text.slice(0, 200000) + `\n\n[...truncated; file is larger, use offset/limit to read more...]`;
                    }
                    this._agentPostMessage({ id, type: 'response', payload: text });
                } else {
                    this._agentPostMessage({ id, type: 'response', error: 'Failed to read file' });
                }
            } catch (e) {
                this._agentPostMessage({ id, type: 'response', error: e.message });
            }
        } else if (action === 'fetch_url') {
            try {
                const url = String(payload.url || '');
                if (!/^https?:\/\//i.test(url)) throw new Error('fetch_url requires an absolute http(s) URL');
                if (!this._soupSession) {
                    this._soupSession = new Soup.Session();
                    this._soupSession.timeout = 10;
                }
                const req = new Soup.Message({ method: 'GET', uri: GLib.Uri.parse(url, GLib.UriFlags.NONE) });
                this._soupSession.send_and_read_async(req, GLib.PRIORITY_DEFAULT, null, (session, res) => {
                    try {
                        const bytes = session.send_and_read_finish(res);
                        const raw = new TextDecoder().decode(bytes.get_data());
                        // Cheap HTML → text: strip scripts/styles/tags so the model
                        // gets readable prose instead of raw markup eating its context.
                        const text = raw
                            .replace(/<script[\s\S]*?<\/script>/gi, ' ')
                            .replace(/<style[\s\S]*?<\/style>/gi, ' ')
                            .replace(/<!--[\s\S]*?-->/g, ' ')
                            .replace(/<[^>]+>/g, ' ')
                            .replace(/&nbsp;/g, ' ')
                            .replace(/&amp;/g, '&')
                            .replace(/&lt;/g, '<')
                            .replace(/&gt;/g, '>')
                            .replace(/\s+/g, ' ')
                            .trim()
                            .slice(0, 20000);
                        this._agentPostMessage({ id, type: 'response', payload: { url, text } });
                    } catch (e) {
                        this._agentPostMessage({ id, type: 'response', error: e.message });
                    }
                });
            } catch (e) {
                this._agentPostMessage({ id, type: 'response', error: e.message });
            }
        } else if (action === 'write_file') {
            try {
                if (!payload?.path || typeof payload.content !== 'string') {
                    throw new Error('write_file requires a path and string content');
                }
                // GJS GLib.file_set_contents expects a byte array on the GTK4
                // bindings used by the launcher. Passing a JS string causes
                // “Expected type guint8 for Argument contents” at approval time.
                const contents = new TextEncoder().encode(payload.content);
                GLib.file_set_contents(payload.path, contents);
                this._agentPostMessage({ id, type: 'response', payload: { success: true } });
            } catch (e) {
                this._agentPostMessage({ id, type: 'response', error: e.message });
            }
        } else if (action === 'list_directory') {
            try {
                const dirPath = payload.path || HOME;
                const file = Gio.File.new_for_path(dirPath);
                const enumerator = file.enumerate_children(
                    'standard::name,standard::type,standard::size',
                    Gio.FileQueryInfoFlags.NONE,
                    null
                );
                const items = [];
                let info;
                while ((info = enumerator.next_file(null)) !== null) {
                    items.push({
                        name: info.get_name(),
                        isDir: info.get_file_type() === Gio.FileType.DIRECTORY,
                        size: info.get_size(),
                    });
                }
                enumerator.close(null);
                this._agentPostMessage({ id, type: 'response', payload: items });
            } catch (e) {
                this._agentPostMessage({ id, type: 'response', error: e.message });
            }
        } else if (action === 'exec_command') {
            try {
                const cmd = payload.command;
                const cwd = payload.cwd || HOME;
                const [ok, stdout, stderr, exitStatus] = GLib.spawn_command_line_sync(
                    `/bin/bash -c "cd ${GLib.shell_quote(cwd)} && ${cmd}"`
                );
                const outStr = stdout ? new TextDecoder().decode(stdout) : '';
                const errStr = stderr ? new TextDecoder().decode(stderr) : '';
                this._agentPostMessage({
                    id,
                    type: 'response',
                    payload: { exitCode: exitStatus, stdout: outStr, stderr: errStr }
                });
            } catch (e) {
                this._agentPostMessage({ id, type: 'response', error: e.message });
            }
        } else if (action === 'file_dialog') {
            this._fileChooserOpen = true;
            try {
                const isDir = !!payload.directory;
                const curr = payload.currentFolder || HOME;
                const args = ['zenity', '--file-selection', `--filename=${curr}/`];
                if (isDir) args.push('--directory');
                // Never block the GTK main loop with spawn_sync: Zenity must
                // run asynchronously so the launcher remains responsive and
                // can restore pointer/keyboard focus when it exits.
                const proc = Gio.Subprocess.new(
                    args, Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE
                );
                proc.communicate_utf8_async(null, null, (p, res) => {
                    this._fileChooserOpen = false;
                    try {
                        const [ok, stdout] = p.communicate_utf8_finish(res);
                        if (ok && p.get_exit_status() === 0 && stdout) {
                            const picked = stdout.trim();
                            this._agentPostMessage({ id, type: 'response', payload: picked || null });
                        } else {
                            this._agentPostMessage({ id, type: 'response', payload: null });
                        }
                    } catch (err) {
                        this._agentPostMessage({ id, type: 'response', error: err.message });
                    }
                    try { this.present(); } catch (_) { }
                });
            } catch (e) {
                this._fileChooserOpen = false;
                this._agentPostMessage({ id, type: 'response', error: e.message });
            }
        } else if (action === 'workspace_startup_state') {
            const nextEnabled = typeof payload?.enabled === 'boolean' ? payload.enabled : readWorkspaceStartupState();
            this._workspaceStartupEnabled = nextEnabled;
            writeWorkspaceStartupState(nextEnabled);
            // Persist only the future launcher-default policy here. Do not
            // orphan the visible Agent WebView into the same reveal/stop UI
            // lifecycle as the header workspace button's live workspace toggle.
            this._agentPostMessage({ id, type: 'response', payload: { enabled: nextEnabled } });
        } else if (action && action.startsWith('llama_')) {
            if (action === 'llama_start') {
                this._agentLlamaEnabled = true;
                this._agentPostMessage({ type: 'llama_state', payload: { enabled: true } });
                this._ensureElectronWorker();
            } else if (action === 'llama_stop') {
                this._agentLlamaEnabled = false;
                this._agentPostMessage({ type: 'llama_state', payload: { enabled: false } });
            }
            this._sendOrQueueElectronDispatch({ type: 'llama_request', requestId: id, action, payload });
            if (action === 'llama_start') this._agentConfirmLlamaHealth();
            if (action === 'llama_stop') {
                this._agentStopNativeLlamaServer();
                this._agentLlamaRunning = false;
                this._agentUpdateLlamaBtn();
                this._agentMaybeStopElectronWorker();
            }
        } else if (action === 'worker_load_model') {
            // Forward inference delegation to the Electron co-process via stdin.
            // Automatically ensures Electron is running and queues if booting.
            this._sendOrQueueElectronDispatch({
                type: 'worker_load_model',
                ...payload,
            });
        } else if (action === 'worker_chat') {
            // Forward chat inference to Electron.
            this._sendOrQueueElectronDispatch({
                type: 'worker_chat',
                ...payload,
            });
        } else if (action === 'worker_cancel_model') {
            this._sendOrQueueElectronDispatch({
                type: 'worker_cancel_model',
                ...payload,
            });
        } else {
            this._agentPostMessage({ id, type: 'response', payload: { ok: true } });
        }
    }

}); // end GObject.registerClass(AppLauncherWindow)

// ── Daemon Application (Fix 4) ─────────────────────────────────────────────
// Runs as a persistent daemon. SIGUSR1 (10) toggles visibility.
// The window is never destroyed between toggles — CSS and app-list are kept.

const LauncherApp = GObject.registerClass({
    GTypeName: 'HyprCandyLauncherApp',
}, class LauncherApp extends Gtk.Application {

    // ── Smooth opacity ramp helpers (same pattern as dock-main.js) ────────
    // GTK4 top-level windows don’t support CSS opacity transitions.
    _laFadeTimerId = 0;
    _LA_STEPS = 12;
    _LA_INTERVAL = 17;  // ms/step  (12 × 17 ≈ 200 ms total)

    _laCancelFade() {
        if (this._laFadeTimerId) {
            GLib.source_remove(this._laFadeTimerId);
            this._laFadeTimerId = 0;
        }
    }

    _laFadeOut(win, onDone) {
        this._laCancelFade();
        let step = 0;
        this._laFadeTimerId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, this._LA_INTERVAL, () => {
            step++;
            const t = step / this._LA_STEPS;
            const eased = 1 - Math.pow(1 - t, 3);  // ease-out cubic
            win.set_opacity(1.0 - eased);
            if (step >= this._LA_STEPS) {
                win.set_opacity(0.0);
                this._laFadeTimerId = 0;
                onDone();
                return GLib.SOURCE_REMOVE;
            }
            return GLib.SOURCE_CONTINUE;
        });
    }

    _laFadeIn(win, onReady) {
        this._laCancelFade();
        win.set_opacity(0.0);
        win.set_visible(true);
        let step = 0;
        this._laFadeTimerId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, this._LA_INTERVAL, () => {
            step++;
            const t = step / this._LA_STEPS;
            const eased = 1 - Math.pow(1 - t, 3);  // ease-out cubic
            win.set_opacity(eased);
            if (step >= this._LA_STEPS) {
                win.set_opacity(1.0);
                this._laFadeTimerId = 0;
                if (onReady) onReady();
                return GLib.SOURCE_REMOVE;
            }
            return GLib.SOURCE_CONTINUE;
        });
    }

    vfunc_activate() {
        this._win = new AppLauncherWindow(this);
        this.add_window(this._win);
        // Start hidden; SIGUSR1 will show it on first toggle
        this._win.set_visible(false);
        // Warm only the workspace shell when its startup policy is enabled.
        // Never start llama-server automatically.
        GLib.idle_add(GLib.PRIORITY_LOW, () => {
            try {
                if (!this._win?._workspaceStartupEnabled) {
                    console.log('[launcher:workspace] Workspace startup policy is OFF; skipping workspace shell warm-up.');
                    return GLib.SOURCE_REMOVE;
                }
                this._win._warmupWorkspaceShell();
            } catch (e) {
                console.warn('[launcher:llama] Startup warm-up failed:', e.message);
            }
            return GLib.SOURCE_REMOVE;
        });

        // SIGUSR1 (10): toggle show/hide.
        // dock-main.js sends pkill -10 -f "gjs app-launcher.js" instead of
        // spawning toggle-app-launcher.sh, which is faster (no shell fork).
        try {
            GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, 10, () => {
                if (this._win.get_visible()) {
                    // Hide with fade-out
                    this._laCancelFade();
                    this._laFadeOut(this._win, () => {
                        this._win.set_visible(false);
                    });
                } else {
                    // Re-anchor to the current dock edge (user may have cycled
                    // positions since the launcher daemon last showed).
                    this._win._refreshLayerShell();
                    // Refresh app list and running apps from disk on each show
                    this._win._allApps = (this._win._appsDirty || this._win._allApps.length === 0) ? getAllApps() : this._win._allApps;
                    this._win._appsDirty = false;
                    this._win._runningApps = getRunningApps();
                    // Reset collapse state — favorites and groups start collapsed
                    // on every fresh open; the user expands what they want.
                    this._win._favCollapsed = true;
                    this._win._favFlow.set_visible(false);
                    this._win._favSep.set_visible(false);
                    this._win._favChevron.set_text(CHEV_UP);
                    this._win._groupCollapsed = {};
                    // Restore last active tab (or 'launcher' if none was saved).
                    // Launcher tab always resets scroll position to the top.
                    const tabToOpen = this._win._lastTab || 'launcher';
                    this._win._switchTab(tabToOpen, true);
                    // Show with fade-in
                    this._laFadeIn(this._win, () => {
                        this._win.present();
                        GLib.idle_add(GLib.PRIORITY_HIGH, () => {
                            // Only restore search text when NOT in webkit view
                            // to avoid spurious search-changed that hijacks the view
                            if (tabToOpen !== 'websearch') {
                                this._win._searchEntry.set_text('');
                            }
                            this._win._searchEntry.grab_focus();
                            return GLib.SOURCE_REMOVE;
                        });
                    });
                }
                return GLib.SOURCE_CONTINUE;
            });
        } catch (e) {
            console.warn('[launcher] SIGUSR1 handler failed:', e.message);
        }

        // SIGUSR2 (12): Hot-reload CSS and colors in-place without restarting process
        try {
            GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, 12, () => {
                if (this._win) {
                    this._win._loadGlobalCSS();
                    this._win.queue_draw();
                    if (this._win._agentWebView) {
                        this._win._agentWebView.evaluate_javascript(
                            `(() => {
                                const chatBtn = document.querySelector('button[title*="chat"]');
                                if (chatBtn) chatBtn.click();
                                const themeBtn = document.querySelector('button[title*="Theme"]');
                                if (themeBtn) themeBtn.click();
                                return 'Toggled chat and theme picker';
                            })()`,
                            -1, null, null, null,
                            (wv, res) => {
                                try {
                                    const val = wv.evaluate_javascript_finish(res);
                                    console.log('[AGENT DEBUG ON SIGUSR2]:', val.to_string());
                                } catch (e) {
                                    console.warn('[AGENT DEBUG EVAL ERR]:', e.message);
                                }
                            }
                        );
                    }
                }
                return GLib.SOURCE_CONTINUE;
            });
        } catch (e) {
            console.warn('[launcher] SIGUSR2 handler failed:', e.message);
        }

        // Keep the application alive indefinitely (daemon mode)
        this.hold();
    }
}); // end GObject.registerClass(LauncherApp)

const app = new LauncherApp({
    application_id: 'org.hyprcandy.HC-launcher',
    // NON_UNIQUE so multiple invocations don't conflict; only one daemon
    // should run at a time — managed by autostart.sh / dock-main.js.
    flags: Gio.ApplicationFlags.NON_UNIQUE,
});

app.run([imports.system.programInvocationName, ...ARGV]);
