// HyprCandy Dock Daemon - Modern Event-Driven Architecture
// Efficient socket monitoring with zero polling

const {Gio, GLib} = imports.gi;

// Module-level singletons — avoids repeated allocation in hot paths
const _decoder = new TextDecoder();
const _encoder = new TextEncoder();

// ── GPU detection via switcheroo-control ─────────────────────────────────
// switcheroo-control (net.hadess.SwitcherooControl) is the standard D-Bus
// service for GPU switching on hybrid-graphics Linux systems.  It is used by
// GNOME itself and correctly handles all topologies: iGPU-only, dGPU-only,
// hybrid Intel+NVIDIA, hybrid Intel+AMD, AMD APU+dGPU, etc.
//
// Each GPU entry has:
//   name      — human-readable GPU name
//   isDefault — true for the iGPU / default rendering GPU
//   envVars   — {KEY: VALUE} dict of env vars to route rendering to that GPU
//               (e.g. {DRI_PRIME: 'pci-0000:01:00.0'} or empty {} for default)
//
// Falls back to /sys/class/drm vendor ID probing if switcheroo is unavailable.
// Results are cached permanently — hardware topology never changes at runtime.

let _switcherooCache = undefined;  // undefined = not yet queried; null = unavailable

function _querySwitcheroo() {
    // Only cache success — never permanently cache null (would happen if called
    // before the D-Bus system bus connection is ready, e.g. at dock startup).
    if (_switcherooCache !== undefined && _switcherooCache !== null)
        return _switcherooCache;

    console.log('[switcheroo] querying...');
    try {
        const result = Gio.DBus.system.call_sync(
            'net.hadess.SwitcherooControl',
            '/net/hadess/SwitcherooControl',
            'org.freedesktop.DBus.Properties',
            'Get',
            new GLib.Variant('(ss)', ['net.hadess.SwitcherooControl', 'GPUs']),
            null,
            Gio.DBusCallFlags.NONE,
            -1,
            null
        );

        // Properties.Get returns (v). deep_unpack() on GLib.Variant is FULLY
        // recursive — all nested variants are unpacked to plain JS types in one call.
        // result.deep_unpack() → [aa{sv_already_unpacked}]
        // Do NOT call .deep_unpack() on the individual field values — they are
        // already plain JS strings/booleans/arrays at this point.
        // Properties.Get returns (v) — result.deep_unpack() unpacks the tuple
        // leaving raw[0] as a GLib.Variant (the inner v wrapping aa{sv}).
        // We must call deep_unpack() on it a second time to reach the GPU list.
        // That second unpack in GJS gives a plain object with integer-string keys
        // {"0":{...},"1":{...}} — Object.values() normalises it to a real array.
        const raw = result.deep_unpack();
        console.log('[switcheroo] raw length:', raw ? raw.length : 'null');

        const inner = raw[0];
        const unpacked = (inner && typeof inner.deep_unpack === 'function')
            ? inner.deep_unpack()
            : inner;
        const gpuList = unpacked ? Object.values(unpacked) : [];
        console.log('[switcheroo] gpuList length after double-unpack:', gpuList.length);

        if (gpuList.length === 0) {
            console.log('[switcheroo] empty — no GPUs reported');
            return null;
        }

        console.log('[switcheroo] first entry keys:', Object.keys(gpuList[0]).join(', '));

        _switcherooCache = gpuList.map(gpuDict => {
            const name       = gpuDict['Name']        || 'Unknown GPU';
            const isDefault  = gpuDict['Default']     || false;
            const isDiscrete = gpuDict['Discrete']    || false;
            // Each dict value may still be a GLib.Variant — unpack if needed
            const _u = v => (v && typeof v.deep_unpack === 'function') ? v.deep_unpack() : v;
            const evArr = _u(gpuDict['Environment']);
            const envVars = {};
            const arr = Array.isArray(evArr) ? evArr : (evArr ? Object.values(evArr) : []);
            for (let i = 0; i + 1 < arr.length; i += 2)
                envVars[arr[i]] = arr[i + 1];
            console.log('[switcheroo]', name, 'default=' + _u(gpuDict['Default']),
                'discrete=' + _u(gpuDict['Discrete']), 'env=' + JSON.stringify(envVars));
            return { name: _u(gpuDict['Name']) || 'Unknown GPU',
                     isDefault: !!_u(gpuDict['Default']),
                     isDiscrete: !!_u(gpuDict['Discrete']),
                     envVars };
        });

        console.log('[switcheroo] parsed GPUs:',
            _switcherooCache.map(g => `${g.name} default=${g.isDefault} discrete=${g.isDiscrete} env=${JSON.stringify(g.envVars)}`).join(' | '));

    } catch (e) {
        console.log('[switcheroo] query exception:', e.message);
        console.log('[switcheroo] stack:', e.stack || '(no stack)');
        return null;  // NOT stored — allow retry next time
    }
    return _switcherooCache;
}

// ── /sys/class/drm fallback ───────────────────────────────────────────────
// Only used when switcheroo-control is not available.
// Returns {KEY: VALUE} env vars for the dGPU, or null on single-GPU systems.
function _sysDetectDgpuEnv() {
    let cards = [];
    try {
        const drm = Gio.File.new_for_path('/sys/class/drm');
        let en = null;
        try {
            en = drm.enumerate_children('standard::name', Gio.FileQueryInfoFlags.NONE, null);
            let fi;
            while ((fi = en.next_file(null)) !== null) {
                const name = fi.get_name();
                if (!name.match(/^card\d+$/)) continue;
                try {
                    const [, vb] = Gio.File.new_for_path(
                        `/sys/class/drm/${name}/device/vendor`).load_contents(null);
                    cards.push(_decoder.decode(vb).trim());
                } catch (_) {}
            }
        } finally {
            if (en) try { en.close(null); } catch (_) {}
        }
    } catch (_) {}
    if (cards.length <= 1) return null;   // single GPU — no routing needed
    const hasNvidia = cards.some(v => v === '0x10de');
    const hasAmd    = cards.some(v => v === '0x1002');
    return hasNvidia ? { CUDA_VISIBLE_DEVICES: '0' }
         : hasAmd    ? { DRI_PRIME: '1' }
         : null;
}

// ── detectDgpuEnv (exported) ──────────────────────────────────────────────
// Available for external callers that need /sys-based GPU env detection.
// No longer applied automatically — dGPU routing is explicit-only via the popover.
let _gpuEnvCache = undefined;

function _detectDgpuEnv() {
    if (_gpuEnvCache !== undefined) return _gpuEnvCache;
    // Use /sys directly — called at startup before main loop is running,
    // so switcheroo D-Bus may not be available yet. Keeps _switcherooCache clean.
    _gpuEnvCache = _sysDetectDgpuEnv();
    console.log('[daemon] startup dGPU env (via /sys):',
        _gpuEnvCache ? JSON.stringify(_gpuEnvCache) : '(none)');
    return _gpuEnvCache;
}

var detectDgpuEnv = _detectDgpuEnv;

// ── GPU name abbreviation ─────────────────────────────────────────────────
// Strips verbose vendor prefixes and truncates to 32 chars for the popover.
function _abbreviateGpuName(name) {
    if (!name) return 'Unknown GPU';
    let s = name
        .replace(/^Advanced Micro Devices,\s*Inc\.\s*\[AMD\/ATI\]\s*/i, '')
        .replace(/^NVIDIA\s+Corporation\s*/i, '')
        .replace(/^Intel\s+Corporation\s*/i, '')
        .replace(/^Intel\(R\)\s*/i, 'Intel® ')
        .trim();
    return s.length > 32 ? s.slice(0, 31) + '…' : s;
}
var abbreviateGpuName = _abbreviateGpuName;

var Daemon = class {
    // Normalize Hyprland class names: strip reverse-DNS prefixes.
    // "org.gnome.Nautilus" → "nautilus"  |  "firefox" → "firefox"
    _normalizeClass(cls) {
        if (!cls) return cls;
        const parts = cls.split('.');
        return parts.length >= 3 ? parts[parts.length - 1].toLowerCase() : cls;
    }

    constructor(dock) {
        this.dock = dock;
        this.clients = new Map(); // Map<className, client[]>
        this.activeAddress = '';
        this.pinnedApps = new Set();
        this.iconCache = new Map();
        this._appInfoCache = new Map();
        this.socketConnection = null;
        this.eventSource = null;
        this.hyprDir = '';
        this.his = '';
        // Persistent socket client — reused across all hyprctl() calls to avoid
        // allocating a new Gio.SocketClient + Gio.UnixSocketAddress per command.
        this._socketClient = Gio.SocketClient.new();
        // Debounce state — prevents main-loop saturation from rapid events
        this._refreshTimer   = null;
        this._refreshing     = false;
        // GPU list cache — getAvailableGPUs() is called from the context menu;
        // hardware doesn't change at runtime so one scan per process is enough.
        this._gpuListCache   = null;
        
        this.setupHyprlandPaths();
        this.loadPinnedApps();
    }
    
    setupHyprlandPaths() {
        const xdgRuntime = GLib.getenv('XDG_RUNTIME_DIR') || '/tmp';
        const his = GLib.getenv('HYPRLAND_INSTANCE_SIGNATURE');
        
        if (his) {
            this.hyprDir = `${xdgRuntime}/hypr`;
            this.his = his;
        } else {
            this.hyprDir = '/tmp/hypr';
            const dir = Gio.File.new_for_path(this.hyprDir);
            if (dir.query_exists(null)) {
                let enumerator = null;
                try {
                    enumerator = dir.enumerate_children('standard::name', Gio.FileQueryInfoFlags.NONE, null);
                    let fileInfo;
                    while ((fileInfo = enumerator.next_file(null)) !== null) {
                        const name = fileInfo.get_name();
                        if (name.includes('.socket.sock')) {
                            this.his = name.replace('.socket.sock', '');
                            break;
                        }
                    }
                } catch (e) {
                    console.error('setupHyprlandPaths enum error:', e.message);
                } finally {
                    if (enumerator) try { enumerator.close(null); } catch (_) {}
                }
            }
        }
        
        console.log(`🔌 Daemon paths: ${this.hyprDir}/${this.his}`);
    }
    
    // Efficient direct socket communication
    async hyprctl(cmd) {
        return new Promise((resolve, reject) => {
            const socketFile = `${this.hyprDir}/${this.his}/.socket.sock`;
            // Reuse persistent _socketClient — Gio.UnixSocketAddress is
            // lightweight but Gio.SocketClient construction is not; reusing
            // it avoids one GObject allocation + GLib type lookup per call.
            const socketAddress = Gio.UnixSocketAddress.new(socketFile);
            
            this._socketClient.connect_async(socketAddress, null, (source, result) => {
                try {
                    const connection = source.connect_finish(result);
                    if (!connection) { reject(new Error('Failed to connect')); return; }
                    
                    const message = new GLib.Bytes(cmd);
                    const outputStream = connection.get_output_stream();
                    outputStream.write_bytes_async(message, 0, null, (source, result) => {
                        try {
                            source.write_bytes_finish(result);
                            
                            const inputStream = connection.get_input_stream();
                            const dataStream = Gio.DataInputStream.new(inputStream);
                            
                            dataStream.read_bytes_async(102400, 0, null, (source, result) => {
                                try {
                                    const bytes = source.read_bytes_finish(result);
                                    if (bytes) {
                                        // Use module-level singleton decoder — avoids
                                        // allocating a new TextDecoder on every call.
                                        const response = _decoder.decode(bytes.get_data());
                                        connection.close(null);
                                        resolve(response);
                                    } else {
                                        connection.close(null);
                                        resolve('');
                                    }
                                } catch (e) { connection.close(null); reject(e); }
                            });
                        } catch (e) { connection.close(null); reject(e); }
                    });
                } catch (e) { reject(e); }
            });
        });
    }
    
    // Load pinned apps efficiently
    loadPinnedApps() {
        const pinnedFile = `${GLib.getenv('HOME')}/.config/pinned`;
        const file = Gio.File.new_for_path(pinnedFile);
        
        if (file.query_exists(null)) {
            const [, contents] = file.load_contents(null);
            const pinned = _decoder.decode(contents);
            pinned.trim().split('\n').forEach(app => {
                const a = app.trim();
                if (a) this.pinnedApps.add(a); // store original class as-is
            });
        }
        
        console.log(`📌 Loaded ${this.pinnedApps.size} pinned apps`);
    }
    
    // Unified app-info lookup via GLib's native XDG database.
    // Handles ~/.local/share, /usr/share, Flatpak, Snap automatically.
    // Results (including misses) are cached to avoid repeated scans.
    _findAppInfo(className) {
        if (this._appInfoCache.has(className)) return this._appInfoCache.get(className);

        // Name variants to try as desktop IDs (GLib searches all XDG paths)
        const variants = [
            className,
            className.toLowerCase(),
            className.replace(/([A-Z])/g, '-$1').toLowerCase().replace(/^-/, ''),
            className.split('.').pop(),
            className.split('.').pop().toLowerCase(),
        ];

        for (const name of variants) {
            try {
                const info = Gio.DesktopAppInfo.new(`${name}.desktop`);
                if (info) {
                    this._appInfoCache.set(className, info);
                    return info;
                }
            } catch (_) {}
        }

        // Slow path: scan all installed apps for a matching StartupWMClass.
        // Note: Gio.AppInfo.get_all() returns AppInfo-typed wrappers in GJS
        // so instanceof Gio.DesktopAppInfo is unreliable — use duck-typing.
        const normCls = this._normalizeClass(className);
        try {
            for (const info of Gio.AppInfo.get_all()) {
                const wm = info.get_startup_wm_class && info.get_startup_wm_class();
                if (!wm) continue;
                if (wm.toLowerCase() === className.toLowerCase() ||
                        this._normalizeClass(wm) === normCls) {
                    this._appInfoCache.set(className, info);
                    return info;
                }
            }
        } catch (_) {}

        this._appInfoCache.set(className, null);
        return null;
    }

    // Human-readable app name via the XDG desktop entry (same source as rofi/nwg-dock).
    getDisplayName(className) {
        const info = this._findAppInfo(className);
        if (info) return info.get_display_name() || info.get_name() || this._normalizeClass(className);
        return this._normalizeClass(className);
    }

    // Icon name for a given class — uses Gio icon metadata, no file parsing.
    getIcon(className) {
        if (this.iconCache.has(className)) return this.iconCache.get(className);

        let iconName = 'application-x-executable';
        const info = this._findAppInfo(className);
        if (info) {
            const gicon = info.get_icon();
            if (gicon) {
                // Duck-type: ThemedIcon has get_names(), FileIcon has get_file()
                const names = gicon.get_names && gicon.get_names();
                if (names && names.length > 0) {
                    iconName = names[0];
                } else {
                    const file = gicon.get_file && gicon.get_file();
                    const path = file && file.get_path && file.get_path();
                    iconName = path || gicon.to_string() || iconName;
                }
            }
        }

        this.iconCache.set(className, iconName);
        return iconName;
    }

    _spawnClean(argv, extraEnv) {
        let envp = GLib.get_environ();
        envp = GLib.environ_unsetenv(envp, 'LD_PRELOAD');
        // Only apply GPU env when the user explicitly requested it via the
        // context menu ("Launch on GPU"). Blanket-applying DRI_PRIME to all
        // launches breaks apps like Steam that manage their own GPU routing.
        if (extraEnv)
            for (const [k, v] of Object.entries(extraEnv))
                envp = GLib.environ_setenv(envp, k, v, true);
        GLib.spawn_async(GLib.get_home_dir(), argv, envp,
            GLib.SpawnFlags.SEARCH_PATH | GLib.SpawnFlags.DO_NOT_REAP_CHILD,
            null, null);
    }

    _resolveExec(className) {
        const info = this._findAppInfo(className);
        if (info) {
            const cmd = info.get_commandline && info.get_commandline();
            if (cmd) return cmd.replace(/%[UuFfIiDdNnVvKk]/g, '').trim();
        }
        // _findAppInfo already performed a full Gio.AppInfo.get_all() scan in its
        // slow path and cached the result (including null for misses). If it returned
        // null, a second scan here would find the same nothing at higher cost.
        // Only fall through to the exec-name heuristic if _findAppInfo is uncached
        // (shouldn't happen) or if we want to match by executable base-name, which
        // _findAppInfo doesn't do. We skip the full re-scan and go straight to
        // the cheap GLib.find_program_in_path check.
        const needle = this._normalizeClass(className).toLowerCase();
        try {
            const bin = GLib.find_program_in_path(className) ||
                        GLib.find_program_in_path(className.toLowerCase()) ||
                        GLib.find_program_in_path(needle);
            if (bin) return bin;
        } catch (_) {}
        return null;
    }

    launchApp(className) {
        const raw = this._resolveExec(className);
        if (!raw) { console.warn('launchApp: no exec for ' + className); return; }
        try {
            const [, argv] = GLib.shell_parse_argv(raw);
            this._spawnClean(argv);
        } catch (e) { console.error('Launch failed: ' + e.message); }
    }

    reorderPinned(draggedClass, afterClass) {
        const findOrig = (n) => {
            for (const orig of this.pinnedApps)
                if (this._normalizeClass(orig) === n || orig === n) return orig;
            return n;
        };
        const draggedOrig = findOrig(draggedClass);
        const afterOrig   = afterClass ? findOrig(afterClass) : null;
        if (!this.pinnedApps.has(draggedOrig)) return;
        const order = Array.from(this.pinnedApps);
        const from  = order.indexOf(draggedOrig);
        if (from === -1) return;
        order.splice(from, 1);
        const to = afterOrig ? order.indexOf(afterOrig) : -1;
        if (to === -1) order.unshift(draggedOrig);
        else order.splice(to + 1, 0, draggedOrig);
        this.pinnedApps = new Set(order);
        this.savePinnedApps();
        console.log('Reordered: ' + draggedOrig + ' after ' + (afterOrig || 'start'));
    }
    
    // Get initial client list
    async loadInitialClients() {
        try {
            const response = await this.hyprctl('j/clients');
            if (response) {
                const clients = JSON.parse(response);
                this.updateClientMap(clients);
                
                // Get active window
                const activeResponse = await this.hyprctl('j/activewindow');
                if (activeResponse) {
                    const active = JSON.parse(activeResponse);
                    this.activeAddress = active.address || '';
                }
                
                console.log(`📊 Loaded ${clients.length} clients`);
                return clients;
            }
        } catch (e) {
            console.error('❌ Error loading initial clients:', e);
        }
        return [];
    }
    
    // Update client map efficiently
    updateClientMap(clients) {
        this.clients.clear();

        clients.forEach(client => {
            if (!client.class) return;
            // Store under the ORIGINAL class name so findIcon can match
            // against StartupWMClass and desktop filenames without loss.
            if (!this.clients.has(client.class)) {
                this.clients.set(client.class, []);
            }
            this.clients.get(client.class).push(client);
        });

        // Update dock
        if (this.dock._updateFromDaemon) {
            this.dock._updateFromDaemon(this.getClientData());
        }
    }
    
    // Get client data for dock
    getClientData() {
        const data = [];

        // pinnedApps and clients both use original Hyprland class names now.
        // Direct key match — no normalization needed for lookup.
        this.pinnedApps.forEach(pinnedOrig => {
            const instances = this.clients.get(pinnedOrig) || [];
            data.push({
                className: this._normalizeClass(pinnedOrig), // unique widget key
                displayName: this.getDisplayName(pinnedOrig), // "Files", "Zen Browser" etc.
                iconClass: pinnedOrig,                        // original for icon/exec/launch
                instances,
                pinned: true,
                running: instances.length > 0,
                active: instances.some(c => c.address === this.activeAddress)
            });
        });

        // Running apps not covered by a pinned entry.
        this.clients.forEach((instances, originalCls) => {
            if (!this.pinnedApps.has(originalCls)) {
                data.push({
                    className: this._normalizeClass(originalCls),
                    displayName: this.getDisplayName(originalCls),
                    iconClass: originalCls,
                    instances,
                    pinned: false,
                    running: true,
                    active: instances.some(c => c.address === this.activeAddress)
                });
            }
        });

        return data;
    }
    
    // Start event monitoring - NO POLLING
    startEventMonitoring() {
        const socketFile = `${this.hyprDir}/${this.his}/.socket2.sock`;
        const socketAddress = Gio.UnixSocketAddress.new(socketFile);
        // Reuse the persistent _socketClient — same reasoning as hyprctl()
        this._socketClient.connect_async(socketAddress, null, (source, result) => {
            try {
                const connection = source.connect_finish(result);
                if (!connection) {
                    console.error('❌ Failed to connect to event socket');
                    return;
                }
                
                console.log('🪟 Started efficient event monitoring');
                this.socketConnection = connection;
                this.monitorEvents();
                
            } catch (e) {
                console.error('❌ Event socket error:', e);
            }
        });
    }
    
    // Monitor events efficiently
    monitorEvents() {
        const inputStream = this.socketConnection.get_input_stream();
        const dataStream = Gio.DataInputStream.new(inputStream);
        
        const readEvent = () => {
            dataStream.read_line_async(0, null, (source, result) => {
                try {
                    const [line] = source.read_line_finish(result);
                    if (line) {
                        // Use module-level singleton — this fires on every
                        // Hyprland event so avoiding allocation here matters.
                        const event = _decoder.decode(line);
                        this.processEvent(event);
                        readEvent(); // Continue reading
                    }
                } catch (e) {
                    console.error('❌ Event read error:', e);
                    // Reconnect after error
                    GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1000, () => {
                        this.startEventMonitoring();
                        return false;
                    });
                }
            });
        };
        
        readEvent();
    }
    
    // Process events efficiently — debounced to prevent main-loop saturation
    processEvent(event) {
        if (event.includes('activewindowv2')) {
            const match = event.match(/activewindowv2>>(0x[a-f0-9]+)/);
            if (match) {
                const newAddress = match[1];
                if (newAddress !== this.activeAddress) {
                    this.activeAddress = newAddress;
                    this._scheduleRefresh();
                }
            }
        } else if (event.includes('openwindow') || event.includes('closewindow') ||
                   event.includes('movewindow')  || event.includes('workspace')) {
            this._scheduleRefresh();
        }
    }

    // Debounce: coalesces rapid event bursts into one refresh after refreshDebounceMs
    _scheduleRefresh() {
        if (this._refreshTimer) {
            GLib.source_remove(this._refreshTimer);
            this._refreshTimer = null;
        }
        const debounceMs = (typeof DockConfig !== 'undefined') ? DockConfig.refreshDebounceMs : 80;
        this._refreshTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, debounceMs, () => {
            this._refreshTimer = null;
            this._doRefresh();
            return GLib.SOURCE_REMOVE;
        });
    }

    // Single in-flight guard so concurrent hyprctl calls never pile up
    _doRefresh() {
        if (this._refreshing) return;
        this._refreshing = true;
        this.hyprctl('j/clients').then(response => {
            this._refreshing = false;
            if (response) {
                try {
                    const clients = JSON.parse(response);
                    this.updateClientMap(clients);
                } catch (e) {
                    console.error('❌ JSON parse error in _doRefresh:', e);
                }
            }
        }).catch(e => {
            this._refreshing = false;
            console.error('❌ _doRefresh hyprctl failed:', e);
        });
    }
    
    // Refresh clients when needed (public API — schedules debounced refresh)
    refreshClients() {
        this._scheduleRefresh();
    }
    
    // Focus window
    focusWindow(address) {
        this.hyprctl(`dispatch focuswindow address:${address}`).then(() => {
            console.log(`🎯 Focused: ${address}`);
        }).catch(e => {
            console.error('❌ Error focusing window:', e);
        });
    }
    
    // Close window
    closeWindow(address) {
        this.hyprctl(`dispatch closewindow address:${address}`).then(() => {
            console.log(`❌ Closed: ${address}`);
        }).catch(e => {
            console.error('❌ Error closing window:', e);
        });
    }
    
    // Toggle pin
    togglePin(className) {
        if (this.pinnedApps.has(className)) {
            this.pinnedApps.delete(className);
        } else {
            this.pinnedApps.add(className);
        }
        this.savePinnedApps();
        this.refreshClients();
    }
    
    // Save pinned apps
    savePinnedApps() {
        const pinnedFile = `${GLib.getenv('HOME')}/.config/pinned`;
        const file = Gio.File.new_for_path(pinnedFile);
        // replace_contents requires a Uint8Array, not a string
        const content = _encoder.encode(Array.from(this.pinnedApps).join('\n') + '\n');
        try {
            file.replace_contents(content, null, false, Gio.FileCreateFlags.REPLACE_DESTINATION, null);
            console.log(`💾 Saved ${this.pinnedApps.size} pinned apps`);
        } catch (e) {
            console.error('❌ savePinnedApps failed:', e.message);
        }
    }


    // Get non-default (discrete) GPUs for the context-menu popover.
    // Uses switcheroo-control — returns [{name, envVars}] for each dGPU,
    // or [] when switcheroo is unavailable or only one GPU exists.
    // "New Window" (plain launch) is always shown by dock-main; these entries
    // appear as additional "Launch on <name>" options.
    getAvailableGPUs() {
        if (this._gpuListCache !== null && this._gpuListCache !== undefined)
            return this._gpuListCache;

        const sw = _querySwitcheroo();
        if (!sw || sw.length <= 1) {
            // switcheroo unavailable or single-GPU system — no extra options
            this._gpuListCache = [];
            console.log('🎮 GPU options: (none — single GPU or switcheroo unavailable)');
            return [];
        }

        // Return only non-default GPUs (the default is covered by "New Window")
        this._gpuListCache = sw
            .filter(g => g.isDiscrete)
            .map(g => ({ name: g.name, envVars: g.envVars }));

        console.log('🎮 dGPU options:', this._gpuListCache.map(g => g.name).join(', '));
        return this._gpuListCache;
    }

    // Launch application on a specific GPU.
    // gpuObj: {name, envVars} as returned by getAvailableGPUs().
    // envVars is a {KEY: VALUE} dict from switcheroo — typically
    //   {DRI_PRIME: 'pci-0000:01:00.0'} for AMD/Intel dGPU
    //   {} for the default GPU (same as plain launch)
    launchWithGPU(className, gpuObj) {
        const execCmd = this.getExecFromDesktop(className);
        if (!execCmd) {
            console.warn('⚠️ No exec for:', className);
            try { GLib.spawn_command_line_async(className.toLowerCase()); } catch(e) {}
            return;
        }

        const clean = execCmd.replace(/%[UuFfIiDdNnVvKk]/g, '').trim();
        const argv  = clean.split(/\s+/).filter(Boolean);

        // Build env from current environment, remove LD_PRELOAD, apply GPU vars
        let envp = GLib.environ_unsetenv(GLib.get_environ(), 'LD_PRELOAD');

        const envVars = (gpuObj && gpuObj.envVars) ? gpuObj.envVars : {};
        for (const [k, v] of Object.entries(envVars))
            envp = GLib.environ_setenv(envp, k, v, true);

        console.log('🚀 Launch on', (gpuObj && gpuObj.name) || 'default GPU',
            Object.keys(envVars).length ? JSON.stringify(envVars) : '(no env override)');

        try {
            GLib.spawn_async(GLib.get_home_dir(), argv, envp,
                GLib.SpawnFlags.SEARCH_PATH | GLib.SpawnFlags.DO_NOT_REAP_CHILD,
                null, null);
        } catch (e) { console.error('launchWithGPU failed:', e.message); }
    }

    // Get executable command from desktop file
    getExecFromDesktop(className) {
        const info = this._findAppInfo(className);
        if (!info) return null;
        const cmd = info.get_commandline && info.get_commandline();
        return cmd ? cmd.replace(/%[UuFfIiDdNnVvKk]/g, '').trim() : null;
    }

    // Clean shutdown
    shutdown() {
        if (this._refreshTimer) {
            GLib.source_remove(this._refreshTimer);
            this._refreshTimer = null;
        }
        if (this.socketConnection) {
            try { this.socketConnection.close(null); } catch (_) {}
        }
        if (this.eventSource) {
            GLib.source_remove(this.eventSource);
        }
        console.log('🔌 Daemon shutdown complete');
    }
};
