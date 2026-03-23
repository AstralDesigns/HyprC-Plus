#!/usr/bin/env gjs

imports.gi.versions.Gtk = '4.0';
imports.gi.versions.Gdk = '4.0';

const {Gtk, Gdk, Gio, GLib, GObject, GioUnix} = imports.gi;
const Gtk4LayerShell = imports.gi.Gtk4LayerShell;

// Check available constants
console.log("Available GTK4 Layer Shell constants:");
console.log("Layer constants:");
console.log("  BOTTOM:", Gtk4LayerShell.Layer.BOTTOM);
console.log("  TOP:", Gtk4LayerShell.Layer.TOP);
console.log("  OVERLAY:", Gtk4LayerShell.Layer.OVERLAY);

console.log("Edge constants:");
console.log("  BOTTOM:", Gtk4LayerShell.Edge.BOTTOM);
console.log("  TOP:", Gtk4LayerShell.Edge.TOP);
console.log("  LEFT:", Gtk4LayerShell.Edge.LEFT);
console.log("  RIGHT:", Gtk4LayerShell.Edge.RIGHT);

console.log("KeyboardMode constants:");
console.log("  NONE:", Gtk4LayerShell.KeyboardMode.NONE);
console.log("  ON_DEMAND:", Gtk4LayerShell.KeyboardMode.ON_DEMAND);
