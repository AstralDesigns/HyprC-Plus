// HyprCandy Dock Daemon - Modern Event-Driven Architecture
// Efficient socket monitoring with zero polling

const {Gio, GLib} = imports.gi;

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
        // Debounce state — prevents main-loop saturation from rapid events
        this._refreshTimer   = null;
        this._refreshing     = false;
        
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
                const enumerator = dir.enumerate_children('standard::name', Gio.FileQueryInfoFlags.NONE, null);
                let fileInfo;
                while ((fileInfo = enumerator.next_file(null)) !== null) {
                    const name = fileInfo.get_name();
                    if (name.includes('.socket.sock')) {
                        this.his = name.replace('.socket.sock', '');
                        break;
                    }
                }
            }
        }
        
        console.log(`🔌 Daemon paths: ${this.hyprDir}/${this.his}`);
    }
    
    // Efficient direct socket communication
    async hyprctl(cmd) {
        return new Promise((resolve, reject) => {
            const socketFile = `${this.hyprDir}/${this.his}/.socket.sock`;
            const socketAddress = Gio.UnixSocketAddress.new(socketFile);
            const socketClient = Gio.SocketClient.new();
            
            socketClient.connect_async(socketAddress, null, (source, result) => {
                try {
                    const connection = source.connect_finish(result);
                    if (!connection) {
                        reject(new Error('Failed to connect'));
                        return;
                    }
                    
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
                                        const data = bytes.get_data();
                                        const response = new TextDecoder().decode(data);
                                        connection.close(null);
                                        resolve(response);
                                    } else {
                                        connection.close(null);
                                        resolve('');
                                    }
                                } catch (e) {
                                    connection.close(null);
                                    reject(e);
                                }
                            });
                        } catch (e) {
                            connection.close(null);
                            reject(e);
                        }
                    });
                } catch (e) {
                    reject(e);
                }
            });
        });
    }
    
    // Load pinned apps efficiently
    loadPinnedApps() {
        const pinnedFile = `${GLib.getenv('HOME')}/.config/pinned`;
        const file = Gio.File.new_for_path(pinnedFile);
        
        if (file.query_exists(null)) {
            const [, contents] = file.load_contents(null);
            const pinned = new TextDecoder().decode(contents);
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

    // Spawn a child process with LD_PRELOAD cleared.
    // The dock is launched with LD_PRELOAD=libgtk4-layer-shell.so — if we don't
    // unset it every child process inherits it, which breaks GTK3, Electron,
    // Firefox-based apps and anything launched transitively (e.g. apps from rofi).
    _spawnClean(argv, extraEnv) {
        let envp = GLib.get_environ();
        envp = GLib.environ_unsetenv(envp, 'LD_PRELOAD');
        if (extraEnv) {
            for (const [k, v] of Object.entries(extraEnv))
                envp = GLib.environ_setenv(envp, k, v, true);
        }
        GLib.spawn_async(
            GLib.get_home_dir(),
            argv,
            envp,
            GLib.SpawnFlags.SEARCH_PATH | GLib.SpawnFlags.DO_NOT_REAP_CHILD,
            null, null
        );
    }

    // Resolve the best exec command for a class name.
    // Strategy (in order):
    //   1. Desktop entry via _findAppInfo (covers XDG, Flatpak, Snap)
    //   2. Scan all desktop files matching Exec= or Name= basename
    //   3. which — covers plain binaries and scripts with no .desktop
    _resolveExec(className) {
        const info = this._findAppInfo(className);
        if (info) {
            const cmd = info.get_commandline && info.get_commandline();
            if (cmd) return cmd.replace(/%[UuFfIiDdNnVvKk]/g, '').trim();
        }
        const needle = this._normalizeClass(className).toLowerCase();
        try {
            for (const appInfo of Gio.AppInfo.get_all()) {
                const cmd = appInfo.get_commandline && appInfo.get_commandline();
                if (!cmd) continue;
                const execBase = cmd.split(/\s+/)[0].split('/').pop().toLowerCase();
                const name = (appInfo.get_name && appInfo.get_name() || '').toLowerCase();
                if (execBase === needle || name === needle ||
                        name.includes(needle) || execBase.includes(needle)) {
                    return cmd.replace(/%[UuFfIiDdNnVvKk]/g, '').trim();
                }
            }
        } catch (_) {}
        try {
            const bin = GLib.find_program_in_path(className) ||
                        GLib.find_program_in_path(className.toLowerCase()) ||
                        GLib.find_program_in_path(this._normalizeClass(className));
            if (bin) return bin;
        } catch (_) {}
        return null;
    }

    // Launch a pinned-but-not-running app.
    launchApp(className) {
        const raw = this._resolveExec(className);
        if (!raw) {
            console.warn(`⚠️ launchApp: could not resolve exec for "${className}"`);
            return;
        }
        console.log(`🚀 Launching ${className} → ${raw}`);
        try {
            const [, argv] = GLib.shell_parse_argv(raw);
            this._spawnClean(argv);
            console.log(`✅ Launched ${className}`);
        } catch (e) {
            console.error(`❌ Launch failed for ${className}:`, e.message);
        }
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
        const socketClient = Gio.SocketClient.new();
        
        socketClient.connect_async(socketAddress, null, (source, result) => {
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
                        const event = new TextDecoder().decode(line);
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
        const content = new TextEncoder().encode(Array.from(this.pinnedApps).join('\n') + '\n');
        try {
            file.replace_contents(content, null, false, Gio.FileCreateFlags.REPLACE_DESTINATION, null);
            console.log(`💾 Saved ${this.pinnedApps.size} pinned apps`);
        } catch (e) {
            console.error('❌ savePinnedApps failed:', e.message);
        }
    }

    // Get available GPUs from the system
    getAvailableGPUs() {
        const gpus = [];
        const gpuTypes = { intel: [], amd: [], nvidia: [] };
        
        // Check for NVIDIA GPUs
        try {
            const nvidiaSmi = GLib.find_program_in_path('nvidia-smi');
            if (nvidiaSmi) {
                const [, stdout] = GLib.spawn_command_line_sync('nvidia-smi --query-gpu=name --format=csv,noheader');
                const gpuNames = new TextDecoder().decode(stdout).trim().split('\n');
                gpuNames.forEach(name => {
                    if (name.trim()) {
                        gpus.push(name.trim());
                        gpuTypes.nvidia.push(name.trim());
                    }
                });
            }
        } catch (e) {
            console.warn('⚠️ Could not detect NVIDIA GPUs:', e);
        }

        // Check for AMD/Intel GPUs via lspci
        try {
            const [, stdout] = GLib.spawn_command_line_sync('lspci -k | grep -EA3 \'VGA|3D\'');
            const output = new TextDecoder().decode(stdout);
            
            // Parse AMD GPUs
            if (output.toLowerCase().includes('amd') || output.toLowerCase().includes('radeon')) {
                const lines = output.split('\n');
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i];
                    if (line.toLowerCase().includes('amd') || line.toLowerCase().includes('radeon')) {
                        const gpuName = line.trim().replace(/\s+/g, ' ');
                        if (gpuName && !gpus.includes(gpuName)) {
                            gpus.push(gpuName);
                            gpuTypes.amd.push(gpuName);
                        }
                    }
                }
            }
            
            // Parse Intel GPUs
            if (output.toLowerCase().includes('intel')) {
                const lines = output.split('\n');
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i];
                    if (line.toLowerCase().includes('intel') && !line.toLowerCase().includes('wireless')) {
                        const gpuName = line.trim().replace(/\s+/g, ' ');
                        if (gpuName && !gpus.includes(gpuName)) {
                            gpus.push(gpuName);
                            gpuTypes.intel.push(gpuName);
                        }
                    }
                }
            }
        } catch (e) {
            console.warn('⚠️ Could not detect Intel/AMD GPUs:', e);
        }

        // Build user-friendly GPU list with launch methods
        const result = [];
        
        // Add integrated GPU option (always available)
        if (gpuTypes.intel.length > 0 || gpuTypes.amd.length > 0) {
            result.push('Integrated GPU (iGPU)');
        } else if (gpus.length > 0) {
            result.push('Integrated GPU');
        }
        
        // Add discrete GPU options
        if (gpuTypes.nvidia.length > 0) {
            gpuTypes.nvidia.forEach(gpu => {
                result.push('NVIDIA ' + gpu + ' (prime-run)');
            });
        }
        
        if (gpuTypes.amd.length > 0) {
            gpuTypes.amd.forEach(gpu => {
                result.push('AMD ' + gpu + ' (DRI_PRIME=1)');
            });
        }
        
        if (gpuTypes.intel.length > 1) {
            // Multiple Intel GPUs - add discrete Intel option
            result.push('Intel dGPU (DRI_PRIME=1)');
        }

        // Fallback if nothing detected
        if (result.length === 0) {
            result.push('Integrated GPU');
            result.push('Discrete GPU');
        }

        console.log('🎮 Available GPUs:', result.join(', '));
        return result;
    }

    // Launch application with specific GPU
    launchWithGPU(className, gpuLabel) {
        const execCmd = this.getExecFromDesktop(className);
        
        if (!execCmd) {
            console.warn('⚠️ Could not find exec command for:', className);
            try { GLib.spawn_command_line_async(className.toLowerCase()); } catch(e) {}
            return;
        }

        // Strip desktop field codes (%U etc.) and split into argv
        const clean = execCmd.replace(/%[UuFfIiDdNnVvKk]/g, '').trim();
        const argv  = clean.split(/\s+/).filter(Boolean);
        let envp    = null; // null = inherit current environment

        if (gpuLabel.includes('prime-run')) {
            // NVIDIA: prepend prime-run wrapper to argv
            argv.unshift('prime-run');
            console.log('🚀 NVIDIA (prime-run):', argv.join(' '));
        } else if (gpuLabel.includes('DRI_PRIME=1')) {
            // AMD/Intel dGPU: set env var — spawn_command_line_async does NOT parse env prefixes
            envp = GLib.environ_setenv(GLib.get_environ(), 'DRI_PRIME', '1', true);
            console.log('🚀 dGPU (DRI_PRIME=1):', argv.join(' '));
        } else {
            // iGPU / default: plain launch, no env changes
            console.log('🚀 iGPU (default):', argv.join(' '));
        }

        try {
            // _spawnClean handles LD_PRELOAD removal; extraEnv overlays GPU vars on top
            const extraEnv = envp ? Object.fromEntries(
                envp.map(e => e.split('=')).filter(p => p.length === 2).map(([k,v]) => [k,v])
            ) : {};
            this._spawnClean(argv, extraEnv);
        } catch (e) {
            console.error('❌ launchWithGPU failed:', e.message);
        }
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
