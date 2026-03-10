#!/usr/bin/env gjs

imports.gi.versions.Gtk = '4.0';
imports.gi.versions.Gdk = '4.0';

const {Gtk, Gdk, Gio, GLib, GObject, Pango, cairo} = imports.gi;

// GNOME-like GTK4 Dock with Full Features
const HyprCandyDock = GObject.registerClass({
    GTypeName: 'HyprCandyDock',
    Properties: {
        'auto-hide': GObject.ParamSpec.boolean('auto-hide', 'Auto Hide', 'Automatically hide dock', GObject.ParamFlags.READWRITE, false),
        'dock-size': GObject.ParamSpec.int('dock-size', 'Dock Size', 'Size of dock icons', GObject.ParamFlags.READWRITE, 32, 128, 48),
        'opacity': GObject.ParamSpec.double('opacity', 'Opacity', 'Dock opacity', GObject.ParamFlags.READWRITE, 0.3, 1.0, 0.9),
        'position': GObject.ParamSpec.string('position', 'Position', 'Dock position', GObject.ParamFlags.READWRITE, 'bottom')
    }
}, class extends Gtk.Window {
    constructor() {
        super({
            title: 'HyprCandy Dock',
            decorated: false,
            resizable: false,
            default_width: 400,
            default_height: 80
        });
        
        // Properties
        this.autoHide = false;
        this.dockSize = 48;
        this.opacity = 0.9;
        this.position = 'bottom';
        
        // State
        this.pinnedApps = [];
        this.runningApps = [];
        this.isHovered = false;
        this.isHidden = false;
        
        this.setupWindow();
        this.setupStyle();
        this.setupIconTheme();
        this.createDock();
        this.loadConfiguration();
        this.startWindowMonitoring();
    }
    
    setupWindow() {
        // Configure window for dock behavior
        // Note: In GTK4, window hints are set differently
        
        // Make window always on top
        this.set_keep_above(true);
        
        // Set up screen geometry
        const display = Gdk.Display.get_default();
        const surface = this.get_surface();
        const monitor = display.get_monitor_at_surface(surface);
        const geometry = monitor.get_geometry();
        
        // Position dock at bottom center
        const dockWidth = Math.min(800, geometry.width * 0.8);
        const dockHeight = 80;
        
        this.set_default_size(dockWidth, dockHeight);
        
        // Center horizontally at bottom
        this.move(
            geometry.x + (geometry.width - dockWidth) / 2,
            geometry.y + geometry.height - dockHeight - 20
        );
        
        // Set up auto-hide behavior
        this.setupAutoHide();
    }
    
    setupStyle() {
        // Modern GNOME-like styling with animations
        const cssProvider = new Gtk.CssProvider();
        cssProvider.load_from_data(`
            window {
                background: rgba(26, 26, 26, 0.9);
                border-radius: 25px;
                border: 1px solid rgba(255, 255, 255, 0.1);
                box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
                backdrop-filter: blur(20px);
                transition: all 300ms cubic-bezier(0.4, 0.0, 0.2, 1);
            }
            
            .dock-container {
                background: transparent;
                border-radius: 20px;
                padding: 8px 16px;
                spacing: 4px;
            }
            
            .dock-item {
                background: transparent;
                border-radius: 14px;
                padding: 8px;
                margin: 2px;
                transition: all 200ms cubic-bezier(0.4, 0.0, 0.2, 1);
                min-width: 48px;
                min-height: 48px;
            }
            
            .dock-item:hover {
                background: rgba(255, 255, 255, 0.1);
                transform: scale(1.1);
                box-shadow: 0 4px 16px rgba(0, 0, 0, 0.2);
            }
            
            .dock-item.running {
                background: rgba(74, 159, 191, 0.2);
                border: 2px solid rgba(74, 159, 191, 0.6);
            }
            
            .dock-item.running:hover {
                background: rgba(74, 159, 191, 0.3);
                border-color: rgba(74, 159, 191, 0.8);
            }
            
            .dock-icon {
                transition: all 200ms ease;
            }
            
            .running-indicator {
                background: linear-gradient(45deg, #4CAF50, #45a049);
                border-radius: 50%;
                width: 8px;
                height: 8px;
                box-shadow: 0 2px 4px rgba(76, 175, 80, 0.4);
                animation: pulse 2s infinite;
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
            
            .tooltip {
                background: rgba(0, 0, 0, 0.9);
                color: white;
                border-radius: 8px;
                padding: 6px 12px;
                font-size: 13px;
                font-weight: 500;
                box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
                margin: 8px;
            }
            
            @keyframes pulse {
                0% { opacity: 1; transform: scale(1); }
                50% { opacity: 0.7; transform: scale(0.9); }
                100% { opacity: 1; transform: scale(1); }
            }
            
            .drag-hover {
                background: rgba(255, 255, 255, 0.2);
                border: 2px dashed rgba(255, 255, 255, 0.4);
            }
        `);
        
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
            '/usr/share/icons/Papirus-Dark',
            '/usr/share/icons/Adwaita',
            '/usr/share/icons/Adwaita-dark',
            '/usr/share/icons/breeze',
            '/usr/share/icons/breeze-dark',
            '/usr/share/icons/Flat-Remix-Blue-Dark',
            '/usr/share/icons/Tela',
            '/usr/share/icons/Tela-dark',
            GLib.get_home_dir() + '/.local/share/icons',
            GLib.get_home_dir() + '/.icons'
        ];
        
        iconPaths.forEach(path => {
            if (GLib.file_test(path, GLib.FileTest.EXISTS)) {
                this.iconTheme.add_search_path(path);
                console.log(`🎨 Added icon path: ${path}`);
            }
        });
        
        console.log('🎨 GTK4 Icon theme initialized with comprehensive detection');
    }
    
    createDock() {
        // Main dock container
        const dockBox = new Gtk.Box({
            orientation: Gtk.Orientation.HORIZONTAL,
            css_classes: ['dock-container'],
            halign: Gtk.Align.CENTER,
            valign: Gtk.Align.CENTER
        });
        
        // App Launcher Button (Show Applications)
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
        
        // Running Apps Container (for unpinned running apps)
        this.runningAppsBox = new Gtk.Box({
            orientation: Gtk.Orientation.HORIZONTAL,
            spacing: 4,
            halign: Gtk.Align.CENTER
        });
        dockBox.append(this.runningAppsBox);
        
        this.set_child(dockBox);
        
        // Set up drag and drop
        this.setupDragAndDrop();
    }
    
    createLauncherButton() {
        const button = new Gtk.Button({
            css_classes: ['dock-item', 'launcher-button'],
            tooltip_text: 'Show Applications',
            width_request: 48,
            height_request: 48
        });
        
        // Create icon
        const iconBox = new Gtk.Box({
            orientation: Gtk.Orientation.VERTICAL,
            valign: Gtk.Align.CENTER,
            halign: Gtk.Align.CENTER
        });
        
        // Try to load system "show-apps" icon
        let iconLoaded = false;
        try {
            const iconInfo = this.iconTheme.lookup_icon('view-grid-symbolic', null, 32, Gtk.IconLookupFlags.FORCE_SIZE);
            if (iconInfo) {
                const icon = new Gtk.Image({
                    gicon: iconInfo.load_icon(),
                    pixel_size: 28,
                    css_classes: ['dock-icon']
                });
                iconBox.append(icon);
                iconLoaded = true;
            }
        } catch (e) {
            console.log('Using fallback launcher icon');
        }
        
        // Fallback to text launcher
        if (!iconLoaded) {
            const launcherIcon = new Gtk.Label({
                label: '⚡',
                css_classes: ['dock-icon']
            });
            launcherIcon.get_style_context().add_provider(
                new Gtk.CssProvider(),
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
            iconBox.append(launcherIcon);
        }
        
        button.set_child(iconBox);
        
        // Launch rofi on click
        button.connect('clicked', () => {
            this.launchApplication('rofi -show drun -theme ~/.config/rofi/launcher.rasi');
        });
        
        return button;
    }
    
    createDockItem(appInfo) {
        const button = new Gtk.Button({
            css_classes: ['dock-item'],
            tooltip_text: appInfo.get_name(),
            width_request: this.dockSize,
            height_request: this.dockSize
        });
        
        button.appInfo = appInfo;
        button.isRunning = false;
        button.windows = [];
        
        // Icon container
        const iconBox = new Gtk.Box({
            orientation: Gtk.Orientation.VERTICAL,
            valign: Gtk.Align.CENTER,
            halign: Gtk.Align.CENTER
        });
        
        // Load application icon
        const icon = new Gtk.Image({
            gicon: appInfo.get_icon(),
            pixel_size: this.dockSize - 16,
            css_classes: ['dock-icon']
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
        button.icon = icon;
        
        // Click handler
        button.connect('clicked', () => {
            if (button.isRunning && button.windows.length > 0) {
                // Focus existing window
                this.focusWindow(button.windows[0]);
            } else {
                // Launch new instance
                this.launchApp(appInfo);
            }
        });
        
        // Right-click context menu
        const gesture = new Gtk.GestureClick();
        gesture.set_button(3); // Right click
        gesture.connect('pressed', (gesture, n_press, x, y) => {
            if (n_press === 1) {
                this.showContextMenu(button, x, y);
            }
        });
        button.add_controller(gesture);
        
        // Hover effects
        const hoverController = new Gtk.EventControllerMotion();
        hoverController.connect('enter', () => {
            this.isHovered = true;
            if (this.autoHide && this.isHidden) {
                this.showDock();
            }
        });
        hoverController.connect('leave', () => {
            this.isHovered = false;
            if (this.autoHide) {
                this.hideDockTimeout();
            }
        });
        button.add_controller(hoverController);
        
        return button;
    }
    
    loadConfiguration() {
        // Load pinned apps configuration
        const configPath = GLib.get_home_dir() + '/.config/hyprcandy/dock-config.json';
        
        try {
            const file = Gio.File.new_for_path(configPath);
            if (file.query_exists(null)) {
                const [success, contents] = file.load_contents(null);
                if (success) {
                    const config = JSON.parse(contents);
                    this.loadPinnedApps(config.pinnedApps || []);
                    this.autoHide = config.autoHide || false;
                    this.dockSize = config.dockSize || 48;
                    this.opacity = config.opacity || 0.9;
                    console.log('📋 Dock configuration loaded');
                }
            } else {
                // Create default configuration
                this.createDefaultConfiguration();
            }
        } catch (e) {
            console.error('❌ Error loading dock configuration:', e);
            this.createDefaultConfiguration();
        }
    }
    
    createDefaultConfiguration() {
        // Default pinned apps
        const defaultApps = [
            'firefox',
            'kitty',
            'nautilus',
            'org.gnome.Nautilus',
            'code',
            'discord',
            'org.mozilla.firefox'
        ];
        
        this.loadPinnedApps(defaultApps);
        this.saveConfiguration();
    }
    
    loadPinnedApps(appIds) {
        // Clear existing pinned apps
        while (this.pinnedAppsBox.get_first_child()) {
            this.pinnedAppsBox.remove(this.pinnedAppsBox.get_first_child());
        }
        
        this.pinnedApps = [];
        
        appIds.forEach(appId => {
            try {
                // Try to find .desktop file
                let appInfo = null;
                
                // Try exact match first
                appInfo = Gio.DesktopAppInfo.new(appId + '.desktop');
                
                // If not found, try common names
                if (!appInfo) {
                    const commonNames = {
                        'firefox': 'org.mozilla.firefox',
                        'kitty': 'kitty',
                        'nautilus': 'org.gnome.Nautilus',
                        'code': 'code',
                        'discord': 'discord',
                        'files': 'org.gnome.Nautilus'
                    };
                    
                    const desktopId = commonNames[appId] || appId;
                    appInfo = Gio.DesktopAppInfo.new(desktopId + '.desktop');
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
        // Monitor running applications using Hyprland IPC
        this.updateRunningApps();
        
        // Update every 2 seconds
        GLib.timeout_add_seconds(2000, () => {
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
            } else if (client.workspace.id === this.getCurrentWorkspace()) {
                // Add to running apps if not pinned and on current workspace
                if (!processedClasses.has(appClass)) {
                    const dockItem = this.createRunningAppItem(client);
                    this.runningAppsBox.append(dockItem);
                    this.runningApps.push({
                        client: client,
                        widget: dockItem
                    });
                    processedClasses.add(appClass);
                }
            }
        });
    }
    
    createRunningAppItem(client) {
        // Create a dock item for running app that's not pinned
        const button = new Gtk.Button({
            css_classes: ['dock-item', 'running'],
            tooltip_text: client.title || client.class,
            width_request: this.dockSize,
            height_request: this.dockSize
        });
        
        button.client = client;
        button.isRunning = true;
        
        // Try to find appropriate icon
        let icon = null;
        try {
            const appInfo = Gio.DesktopAppInfo.new(client.class.toLowerCase() + '.desktop');
            if (appInfo) {
                icon = new Gtk.Image({
                    gicon: appInfo.get_icon(),
                    pixel_size: this.dockSize - 16,
                    css_classes: ['dock-icon']
                });
            }
        } catch (e) {
            // Fallback icon
            icon = new Gtk.Image({
                icon_name: 'application-x-executable',
                pixel_size: this.dockSize - 16,
                css_classes: ['dock-icon']
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
    
    getCurrentWorkspace() {
        // Get current workspace from Hyprland
        try {
            const proc = new Gio.Subprocess({
                argv: ['hyprctl', 'activeworkspace', '-j'],
                flags: Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE
            });
            
            const [, stdout] = proc.communicate_utf8(null, null);
            if (stdout) {
                const workspace = JSON.parse(stdout);
                return workspace.id;
            }
        } catch (e) {
            console.error('❌ Error getting current workspace:', e);
        }
        return 1;
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
    
    setupAutoHide() {
        // Auto-hide functionality
        const motionController = new Gtk.EventControllerMotion();
        motionController.connect('enter', () => {
            if (this.autoHide && this.isHidden) {
                this.showDock();
            }
        });
        motionController.connect('leave', () => {
            if (this.autoHide && !this.isHovered) {
                this.hideDockTimeout();
            }
        });
        this.add_controller(motionController);
    }
    
    hideDockTimeout() {
        if (this.hideTimeoutId) {
            GLib.source_remove(this.hideTimeoutId);
        }
        
        this.hideTimeoutId = GLib.timeout_add(500, () => {
            if (!this.isHovered && this.autoHide) {
                this.hideDock();
            }
            this.hideTimeoutId = null;
            return false;
        });
    }
    
    hideDock() {
        if (!this.isHidden) {
            this.isHidden = true;
            // Slide down animation
            const currentY = this.get_allocation().y;
            this.move(this.get_allocation().x, currentY + 100);
            this.set_opacity(0.3);
        }
    }
    
    showDock() {
        if (this.isHidden) {
            this.isHidden = false;
            // Slide up animation
            const display = Gdk.Display.get_default();
            const monitor = display.get_monitor_at_surface(this.get_surface());
            const geometry = monitor.get_geometry();
            
            this.move(this.get_allocation().x, geometry.y + geometry.height - 100);
            this.set_opacity(this.opacity);
        }
    }
    
    setupDragAndDrop() {
        // Set up drag source for dock items
        this.pinnedApps.forEach(pinned => {
            const dragSource = new Gtk.DragSource();
            dragSource.set_actions(Gdk.DragAction.MOVE);
            
            dragSource.connect('prepare', (source, x, y) => {
                const content = new Gdk.ContentProvider();
                content.set_value(pinned.appId);
                return content;
            });
            
            pinned.widget.add_controller(dragSource);
        });
        
        // Set up drop target for reordering
        const dropTarget = new Gtk.DropTarget({
            actions: Gdk.DragAction.MOVE
        });
        
        dropTarget.set_gtype(GType.STRING);
        
        dropTarget.connect('drop', (target, value, x, y) => {
            console.log(`🔄 Dropped app: ${value}`);
            // Handle reordering logic here
            return true;
        });
        
        this.pinnedAppsBox.add_controller(dropTarget);
    }
    
    showContextMenu(dockItem, x, y) {
        // Create context menu for dock items
        const menu = new Gtk.PopoverMenu();
        menu.set_parent(dockItem);
        
        const menuModel = Gio.Menu.new();
        
        if (dockItem.isRunning) {
            // Add running app options
            const newWindow = Gio.MenuItem.new('New Window', 'app.new-window');
            menuModel.append_item(newWindow);
            
            const close = Gio.MenuItem.new('Close', 'app.close');
            menuModel.append_item(close);
        } else {
            // Add pinned app options
            const launch = Gio.MenuItem.new('Launch', 'app.launch');
            menuModel.append_item(launch);
        }
        
        const separator = Gio.MenuItem.new_separator();
        menuModel.append_item(separator);
        
        const unpin = Gio.MenuItem.new('Unpin from Dock', 'app.unpin');
        menuModel.append_item(unpin);
        
        menu.set_menu_model(menuModel);
        menu.popup();
    }
    
    saveConfiguration() {
        const config = {
            pinnedApps: this.pinnedApps.map(p => p.appId),
            autoHide: this.autoHide,
            dockSize: this.dockSize,
            opacity: this.opacity,
            position: this.position
        };
        
        const configPath = GLib.get_home_dir() + '/.config/hyprcandy/dock-config.json';
        const configDir = GLib.get_home_dir() + '/.config/hyprcandy';
        
        // Ensure config directory exists
        GLib.mkdir_with_parents(configDir, 0o755);
        
        try {
            const file = Gio.File.new_for_path(configPath);
            file.replace_contents(
                JSON.stringify(config, null, 2),
                null,
                false,
                Gio.FileCreateFlags.NONE,
                null
            );
            console.log('💾 Dock configuration saved');
        } catch (e) {
            console.error('❌ Error saving configuration:', e);
        }
    }
});

// Application entry point
const app = new Gtk.Application({
    application_id: 'org.hyprcandy.dock'
});

app.connect('activate', () => {
    const dock = new HyprCandyDock();
    app.add_window(dock);
    
    // Show dock
    dock.present();
    
    console.log('🍭 HyprCandy GTK4 Dock started with GNOME-like features!');
});

// Run the application
app.run(null);
