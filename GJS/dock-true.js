#!/usr/bin/env gjs

imports.gi.versions.Gtk = '4.0';
imports.gi.versions.Gdk = '4.0';

const {Gtk, Gdk, Gio, GLib, GObject, GioUnix} = imports.gi;

// True Wayland Layer Shell Dock
const HyprCandyDock = GObject.registerClass({
    GTypeName: 'HyprCandyDock'
}, class extends Gtk.ApplicationWindow {
    constructor(app) {
        super({
            application: app,
            title: 'HyprCandy Dock',
            decorated: false,
            resizable: false,
            default_width: 800,
            default_height: 80
        });
        
        // State
        this.pinnedApps = [];
        this.runningApps = [];
        
        this.setupWindow();
        this.setupStyle();
        this.setupIconTheme();
        this.createDock();
        this.loadConfiguration();
        this.startWindowMonitoring();
        
        // Apply Wayland layer shell
        this.setupLayerShell();
    }
    
    setupLayerShell() {
        // Use Hyprland to make this a proper dock
        try {
            // Window rules for dock behavior
            const rules = [
                'windowrule float, title:HyprCandy Dock',
                'windowrule noborder, title:HyprCandy Dock', 
                'windowrule noshadow, title:HyprCandy Dock',
                'windowrule nofocus, title:HyprCandy Dock',
                'windowrule pinned, title:HyprCandy Dock',
                'windowrule workspace special, title:HyprCandy Dock'
            ];
            
            rules.forEach(rule => {
                const proc = new Gio.Subprocess({
                    argv: ['hyprctl', 'keyword', rule],
                    flags: Gio.SubprocessFlags.NONE
                });
                proc.init(null);
            });
            
            console.log('🔧 Applied Wayland dock rules');
        } catch (e) {
            console.log('⚠️ Could not apply dock rules:', e);
        }
    }
    
    setupWindow() {
        // Set up screen geometry
        const display = Gdk.Display.get_default();
        const monitor = display.get_monitors().get_item(0);
        const geometry = monitor.get_geometry();
        
        // Position dock at bottom center
        const dockWidth = Math.min(800, geometry.width * 0.8);
        const dockHeight = 80;
        
        this.set_default_size(dockWidth, dockHeight);
        this.set_decorated(false);
        this.set_resizable(false);
        
        // Present and position
        this.present();
        
        try {
            this.move(
                geometry.x + (geometry.width - dockWidth) / 2,
                geometry.y + geometry.height - dockHeight - 20
            );
        } catch (e) {
            console.log('🪟 Wayland detected, using default positioning');
        }
        
        console.log(`📊 Screen: ${geometry.width}x${geometry.height}, Dock: ${dockWidth}x${dockHeight}`);
    }
    
    setupStyle() {
        // Modern GNOME-like styling with matugen integration
        const cssProvider = new Gtk.CssProvider();
        
        // Clean CSS without matugen imports for now
        const cssContent = `
            window {
                background: rgba(26, 26, 26, 0.9);
                border-radius: 25px;
                border: 1px solid rgba(255, 255, 255, 0.1);
                box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
            }
            
            .dock-container {
                background: transparent;
                border-radius: 20px;
                padding: 8px 16px;
            }
            
            .dock-item {
                background: transparent;
                border-radius: 14px;
                padding: 8px;
                margin: 2px;
                transition: all 200ms ease;
            }
            
            .dock-item:hover {
                background: rgba(255, 255, 255, 0.1);
                transform: scale(1.05);
            }
            
            .dock-item.running {
                background: rgba(74, 159, 191, 0.2);
                border: 2px solid rgba(74, 159, 191, 0.6);
            }
            
            .dock-item.running:hover {
                background: rgba(74, 159, 191, 0.3);
                border-color: rgba(74, 159, 191, 0.8);
            }
            
            .running-indicator {
                background: #4CAF50;
                border-radius: 50%;
                min-width: 8px;
                min-height: 8px;
            }
            
            .launcher-button {
                background: linear-gradient(135deg, rgba(255, 255, 255, 0.1), rgba(255, 255, 255, 0.05));
                border: 1px solid rgba(255, 255, 255, 0.2);
            }
            
            .launcher-button:hover {
                background: linear-gradient(135deg, rgba(255, 255, 255, 0.2), rgba(255, 255, 255, 0.1));
                border-color: rgba(255, 255, 255, 0.3);
            }
            
            .separator {
                background: rgba(255, 255, 255, 0.2);
                min-width: 1px;
                min-height: 32px;
                margin: 8px 4px;
            }
            
            label {
                color: #ffffff;
            }
            
            image {
                -gtk-icon-palette: #ffffff;
            }
        `;
        
        cssProvider.load_from_data(cssContent, -1);
        
        const styleContext = this.get_style_context();
        styleContext.add_provider(cssProvider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
    }
    
    setupIconTheme() {
        // Enhanced icon theme setup
        this.iconTheme = Gtk.IconTheme.get_for_display(Gdk.Display.get_default());
        
        // Add comprehensive icon search paths
        const iconPaths = [
            '/usr/share/icons/hicolor',
            '/usr/share/icons/Papirus',
            '/usr/share/icons/Adwaita',
            '/usr/share/icons/breeze',
            GLib.get_home_dir() + '/.local/share/icons'
        ];
        
        iconPaths.forEach(path => {
            if (GLib.file_test(path, GLib.FileTest.EXISTS)) {
                this.iconTheme.add_search_path(path);
                console.log(`🎨 Added icon path: ${path}`);
            }
        });
        
        console.log('🎨 GTK4 Icon theme initialized with automatic detection');
    }
    
    createDock() {
        // Main dock container
        const dockBox = new Gtk.Box({
            orientation: Gtk.Orientation.HORIZONTAL,
            css_classes: ['dock-container'],
            halign: Gtk.Align.CENTER,
            valign: Gtk.Align.CENTER
        });
        
        // App Launcher Button
        const launcherButton = this.createLauncherButton();
        dockBox.append(launcherButton);
        
        // Separator
        const separator = new Gtk.Separator({
            orientation: Gtk.Orientation.VERTICAL,
            css_classes: ['separator']
        });
        dockBox.append(separator);
        
        // Pinned Apps Container
        this.pinnedAppsBox = new Gtk.Box({
            orientation: Gtk.Orientation.HORIZONTAL,
            spacing: 4,
            halign: Gtk.Align.CENTER
        });
        dockBox.append(this.pinnedAppsBox);
        
        // Running Apps Container
        this.runningAppsBox = new Gtk.Box({
            orientation: Gtk.Orientation.HORIZONTAL,
            spacing: 4,
            halign: Gtk.Align.CENTER
        });
        dockBox.append(this.runningAppsBox);
        
        this.set_child(dockBox);
    }
    
    createLauncherButton() {
        const button = new Gtk.Button({
            css_classes: ['dock-item', 'launcher-button'],
            tooltip_text: 'Show Applications',
            width_request: 48,
            height_request: 48
        });
        
        // Try to load system icon
        let iconLoaded = false;
        try {
            const iconInfo = this.iconTheme.lookup_icon('view-grid-symbolic', null, 32, Gtk.IconLookupFlags.FORCE_SIZE);
            if (iconInfo) {
                const icon = new Gtk.Image({
                    gicon: iconInfo.load_icon(),
                    pixel_size: 28
                });
                button.set_child(icon);
                iconLoaded = true;
            }
        } catch (e) {
            console.log('Using fallback launcher icon');
        }
        
        // Fallback to text
        if (!iconLoaded) {
            const label = new Gtk.Label({
                label: '⚡'
            });
            button.set_child(label);
        }
        
        // Launch rofi on click
        button.connect('clicked', () => {
            this.launchApplication('rofi -show drun');
        });
        
        return button;
    }
    
    createDockItem(appInfo) {
        const button = new Gtk.Button({
            css_classes: ['dock-item'],
            tooltip_text: appInfo.get_name(),
            width_request: 48,
            height_request: 48
        });
        
        button.appInfo = appInfo;
        button.isRunning = false;
        button.windows = [];
        
        // Load application icon
        const icon = new Gtk.Image({
            gicon: appInfo.get_icon(),
            pixel_size: 32
        });
        
        // Icon container with running indicator
        const iconBox = new Gtk.Box({
            orientation: Gtk.Orientation.VERTICAL,
            valign: Gtk.Align.CENTER,
            halign: Gtk.Align.CENTER
        });
        iconBox.append(icon);
        
        // Running indicator
        const runningIndicator = new Gtk.Box({
            css_classes: ['running-indicator'],
            visible: false,
            halign: Gtk.Align.END,
            valign: Gtk.Align.END
        });
        iconBox.append(runningIndicator);
        
        button.runningIndicator = runningIndicator;
        button.set_child(iconBox);
        
        // Click handler
        button.connect('clicked', () => {
            if (button.isRunning && button.windows.length > 0) {
                this.focusWindow(button.windows[0]);
            } else {
                this.launchApp(appInfo);
            }
        });
        
        // Right-click to close
        const gesture = new Gtk.GestureClick();
        gesture.set_button(3);
        gesture.connect('pressed', () => {
            if (button.isRunning) {
                this.closeApp(button.windows[0]);
            }
        });
        button.add_controller(gesture);
        
        return button;
    }
    
    loadConfiguration() {
        // Default pinned apps
        const defaultApps = [
            'firefox',
            'kitty', 
            'nautilus',
            'code',
            'discord'
        ];
        
        this.loadPinnedApps(defaultApps);
    }
    
    loadPinnedApps(appIds) {
        appIds.forEach(appId => {
            try {
                let appInfo = null;
                
                // Try exact match first
                appInfo = GioUnix.DesktopAppInfo.new(appId + '.desktop');
                
                // If not found, try common names
                if (!appInfo) {
                    const commonNames = {
                        'firefox': 'org.mozilla.firefox',
                        'kitty': 'kitty',
                        'nautilus': 'org.gnome.Nautilus',
                        'code': 'code',
                        'discord': 'discord'
                    };
                    
                    const desktopId = commonNames[appId] || appId;
                    appInfo = GioUnix.DesktopAppInfo.new(desktopId + '.desktop');
                }
                
                if (appInfo) {
                    const dockItem = this.createDockItem(appInfo);
                    this.pinnedAppsBox.append(dockItem);
                    this.pinnedApps.push({
                        appId: appId,
                        appInfo: appInfo,
                        widget: dockItem
                    });
                    console.log(`📌 Loaded pinned app: ${appInfo.get_name()}`);
                }
            } catch (e) {
                console.error(`❌ Error loading app ${appId}:`, e);
            }
        });
        
        console.log(`📌 Loaded ${this.pinnedApps.length} pinned applications`);
    }
    
    startWindowMonitoring() {
        // Monitor running applications
        this.updateRunningApps();
        
        // Update every 2 seconds
        GLib.timeout_add_seconds(2000, null, () => {
            this.updateRunningApps();
            return true;
        });
        
        console.log('🪟 Started window monitoring');
    }
    
    updateRunningApps() {
        // Get running applications from Hyprland
        try {
            const proc = new Gio.Subprocess({
                argv: ['hyprctl', 'clients', '-j'],
                flags: Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE
            });
            
            proc.communicate_utf8_async(null, null, (source, result) => {
                try {
                    const [, stdout] = source.communicate_utf8_finish(result);
                    if (stdout) {
                        const clients = JSON.parse(stdout);
                        this.processRunningClients(clients);
                    }
                } catch (e) {
                    console.error('❌ Error parsing Hyprland clients:', e);
                }
            });
        } catch (e) {
            console.error('❌ Error getting Hyprland clients:', e);
        }
    }
    
    processRunningClients(clients) {
        // Clear previous running state
        this.pinnedApps.forEach(pinned => {
            pinned.widget.isRunning = false;
            pinned.widget.windows = [];
            pinned.widget.runningIndicator.visible = false;
            pinned.widget.remove_css_class('running');
        });
        
        // Clear running apps box
        while (this.runningAppsBox.get_first_child()) {
            this.runningAppsBox.remove(this.runningAppsBox.get_first_child());
        }
        
        this.runningApps = [];
        const processedClasses = new Set();
        
        clients.forEach(client => {
            const appClass = client.class.toLowerCase();
            
            // Check if it's a pinned app
            const pinnedApp = this.pinnedApps.find(p => 
                p.appInfo.get_executable().includes(appClass) ||
                p.appId.toLowerCase().includes(appClass)
            );
            
            if (pinnedApp) {
                pinnedApp.widget.isRunning = true;
                pinnedApp.widget.windows.push(client.address);
                pinnedApp.widget.runningIndicator.visible = true;
                pinnedApp.widget.add_css_class('running');
                processedClasses.add(appClass);
            } else if (!processedClasses.has(appClass)) {
                // Add to running apps if not pinned
                const dockItem = this.createRunningAppItem(client);
                this.runningAppsBox.append(dockItem);
                this.runningApps.push({
                    client: client,
                    widget: dockItem
                });
                processedClasses.add(appClass);
            }
        });
    }
    
    createRunningAppItem(client) {
        const button = new Gtk.Button({
            css_classes: ['dock-item', 'running'],
            tooltip_text: client.title || client.class,
            width_request: 48,
            height_request: 48
        });
        
        button.client = client;
        button.isRunning = true;
        
        // Try to find appropriate icon
        let icon = null;
        try {
            const appInfo = GioUnix.DesktopAppInfo.new(client.class.toLowerCase() + '.desktop');
            if (appInfo) {
                icon = new Gtk.Image({
                    gicon: appInfo.get_icon(),
                    pixel_size: 32
                });
            }
        } catch (e) {
            // Fallback icon
            icon = new Gtk.Image({
                icon_name: 'application-x-executable',
                pixel_size: 32
            });
        }
        
        const iconBox = new Gtk.Box({
            orientation: Gtk.Orientation.VERTICAL,
            valign: Gtk.Align.CENTER,
            halign: Gtk.Align.CENTER
        });
        iconBox.append(icon);
        
        // Running indicator
        const runningIndicator = new Gtk.Box({
            css_classes: ['running-indicator'],
            visible: true,
            halign: Gtk.Align.END,
            valign: Gtk.Align.END
        });
        iconBox.append(runningIndicator);
        
        button.set_child(iconBox);
        
        // Click to focus
        button.connect('clicked', () => {
            this.focusWindow(client.address);
        });
        
        // Right-click to close
        const gesture = new Gtk.GestureClick();
        gesture.set_button(3);
        gesture.connect('pressed', () => {
            this.closeWindow(client.address);
        });
        button.add_controller(gesture);
        
        return button;
    }
    
    launchApp(appInfo) {
        try {
            appInfo.launch([], null);
            console.log(`🚀 Launched: ${appInfo.get_name()}`);
        } catch (e) {
            console.error(`❌ Error launching app:`, e);
            // Fallback to command line
            const command = appInfo.get_executable();
            this.launchApplication(command);
        }
    }
    
    launchApplication(command) {
        try {
            const proc = new Gio.Subprocess({
                argv: command.split(' '),
                flags: Gio.SubprocessFlags.NONE
            });
            proc.init(null);
            console.log(`🚀 Launched: ${command}`);
        } catch (e) {
            console.error(`❌ Error launching command:`, e);
        }
    }
    
    focusWindow(address) {
        try {
            const proc = new Gio.Subprocess({
                argv: ['hyprctl', 'dispatch', 'focuswindow', 'address:' + address],
                flags: Gio.SubprocessFlags.NONE
            });
            proc.init(null);
            console.log(`🎯 Focused window: ${address}`);
        } catch (e) {
            console.error(`❌ Error focusing window:`, e);
        }
    }
    
    closeWindow(address) {
        try {
            const proc = new Gio.Subprocess({
                argv: ['hyprctl', 'dispatch', 'killwindow', 'address:' + address],
                flags: Gio.SubprocessFlags.NONE
            });
            proc.init(null);
            console.log(`🗑️ Closed window: ${address}`);
        } catch (e) {
            console.error(`❌ Error closing window:`, e);
        }
    }
});

// Application entry point
const app = new Gtk.Application({
    application_id: 'org.hyprcandy.dock'
});

app.connect('activate', () => {
    const dock = new HyprCandyDock(app);
    
    // Show dock
    dock.present();
    
    console.log('🍭 HyprCandy True Dock started!');
});

// Run the application
app.run(null);
