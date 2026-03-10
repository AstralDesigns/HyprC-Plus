#!/usr/bin/env gjs

imports.gi.versions.Gtk = '4.0';
imports.gi.versions.Gdk = '4.0';

const {Gtk, Gdk, Gio, GLib, GObject, GioUnix} = imports.gi;
const Gtk4LayerShell = imports.gi.Gtk4LayerShell;

// Check available functions
console.log("Available GTK4 Layer Shell functions:");
const functions = Object.getOwnPropertyNames(Gtk4LayerShell).filter(n => typeof Gtk4LayerShell[n] === 'function');
functions.forEach(f => console.log(`  ${f}`));
