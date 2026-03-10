#!/usr/bin/env gjs

imports.gi.versions.Gtk = '4.0';
imports.gi.versions.Gdk = '4.0';

const {Gtk, Gdk, Gio, GLib, GObject, GioUnix} = imports.gi;

// Check available imports
console.log("Available layer shell imports:");
try {
    const GtkLayerShell = imports.gi.GtkLayerShell;
    console.log("  GtkLayerShell: Available");
} catch (e) {
    console.log("  GtkLayerShell: Not available");
}

try {
    const Gtk4LayerShell = imports.gi.Gtk4LayerShell;
    console.log("  Gtk4LayerShell: Available");
} catch (e) {
    console.log("  Gtk4LayerShell: Not available");
}

// Check all GI imports
const gi = imports.gi;
console.log("All available imports containing 'layer':");
Object.keys(gi).filter(n => n.toLowerCase().includes('layer')).forEach(n => console.log(`  ${n}`));
