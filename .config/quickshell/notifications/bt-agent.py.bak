#!/usr/bin/env python3
"""
BlueZ Pairing + OBEX Agent for Quickshell
Handles incoming pair requests, PIN confirmations, and file transfer authorisation.
Events are written as JSON lines to stdout → QS reads via Process/SplitParser.
Commands are read from stdin (line by line) for QS to send responses.

Event format (stdout):  {"type":"pair_confirm","mac":"AA:BB..","name":"Device","passkey":"123456"}
                        {"type":"pair_pin","mac":"AA:BB..","name":"Device"}
                        {"type":"file_request","mac":"AA:BB..","name":"Device","filename":"photo.jpg","size":102400}
                        {"type":"pair_cancelled","mac":"AA:BB.."}
                        {"type":"agent_ready"}
                        {"type":"error","msg":"..."}

Command format (stdin): accept_pair AA:BB:CC:DD:EE:FF
                        reject_pair AA:BB:CC:DD:EE:FF
                        pin_pair   AA:BB:CC:DD:EE:FF 1234
                        accept_file AA:BB:CC:DD:EE:FF
                        reject_file AA:BB:CC:DD:EE:FF
"""

import sys
import os
import time
import json
import shutil
import threading
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

AGENT_PATH       = "/quickshell/bt/agent"
AGENT_IFACE      = "org.bluez.Agent1"
BLUEZ_SERVICE    = "org.bluez"
MANAGER_PATH     = "/org/bluez"          # AgentManager1 lives here, NOT at "/"
MANAGER_IFACE    = "org.bluez.AgentManager1"
OBEX_SERVICE     = "org.bluez.obex"
OBEX_AGENT_PATH  = "/quickshell/obex/agent"
OBEX_AGENT_IFACE = "org.bluez.obex.Agent1"
OBEX_MGR_IFACE   = "org.bluez.obex.AgentManager1"
OBEX_MGR_PATH    = "/org/bluez/obex"

PIDFILE = "/tmp/qs_bt_agent.pid"

def emit(obj):
    print(json.dumps(obj), flush=True)

def get_device_name(bus, mac):
    try:
        mgr = dbus.Interface(bus.get_object(BLUEZ_SERVICE, "/"), "org.freedesktop.DBus.ObjectManager")
        objects = mgr.GetManagedObjects()
        for path, ifaces in objects.items():
            if "org.bluez.Device1" in ifaces:
                props = ifaces["org.bluez.Device1"]
                addr = str(props.get("Address",""))
                if addr.upper() == mac.upper():
                    return str(props.get("Name", mac))
    except Exception:
        pass
    return mac

def mac_from_path(bus, path):
    """Extract MAC from a BlueZ device path like /org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"""
    try:
        obj = bus.get_object(BLUEZ_SERVICE, path)
        props = dbus.Interface(obj, "org.freedesktop.DBus.Properties")
        addr = str(props.Get("org.bluez.Device1", "Address"))
        name = str(props.Get("org.bluez.Device1", "Name")) if True else addr
        try:
            name = str(props.Get("org.bluez.Device1", "Name"))
        except Exception:
            name = addr
        return addr, name
    except Exception:
        # fallback: parse path
        part = path.split("/")[-1]  # dev_AA_BB_CC_DD_EE_FF
        mac = part.replace("dev_","").replace("_",":")
        return mac, mac


def _trust_device(bus, mac):
    """Set Trusted=True and AutoConnect=True on the BlueZ device object.

    This is the critical step for bidirectional connectivity: without it,
    a device that paired via an incoming request is 'Paired' but not
    'Trusted', so BlueZ refuses connection attempts initiated from the
    remote side. Setting Trusted also enables AutoConnect so BlueZ will
    reconnect the device automatically after suspend/resume.
    """
    try:
        mgr = dbus.Interface(bus.get_object(BLUEZ_SERVICE, "/"),
                             "org.freedesktop.DBus.ObjectManager")
        objects = mgr.GetManagedObjects()
        for path, ifaces in objects.items():
            if "org.bluez.Device1" not in ifaces:
                continue
            addr = str(ifaces["org.bluez.Device1"].get("Address", ""))
            if addr.upper() != mac.upper():
                continue
            dev_obj = bus.get_object(BLUEZ_SERVICE, path)
            props = dbus.Interface(dev_obj, "org.freedesktop.DBus.Properties")
            props.Set("org.bluez.Device1", "Trusted", dbus.Boolean(True))
            try:
                props.Set("org.bluez.Device1", "AutoConnect", dbus.Boolean(True))
            except Exception:
                pass  # AutoConnect not always writable; Trusted is sufficient
            emit({"type": "error", "msg": f"Trusted {mac}"})  # info log
            return
    except Exception as e:
        raise RuntimeError(f"_trust_device({mac}): {e}")

class QuickshellBTAgent(dbus.service.Object):
    def __init__(self, bus, path):
        self.bus = bus
        self._pending = {}   # mac → (reply_handler, error_handler, kind)
        self._lock = threading.Lock()
        super().__init__(bus, path)

    def _store_pending(self, mac, reply_h, error_h, kind):
        with self._lock:
            self._pending[mac] = (reply_h, error_h, kind)

    def _pop_pending(self, mac):
        with self._lock:
            return self._pending.pop(mac, None)

    def respond(self, mac, accept, pin=None):
        p = self._pop_pending(mac)
        if not p:
            return False
        reply_h, error_h, kind = p
        if not accept:
            error_h(dbus.DBusException("org.bluez.Error.Rejected: Rejected by user"))
            return True
        if kind == "confirm" or kind == "authorize":
            reply_h()
        elif kind == "pin":
            reply_h(dbus.String(pin or "0000"))
        elif kind == "passkey":
            reply_h(dbus.UInt32(int(pin or "0")))
        # Trust + enable AutoConnect so the device can reconnect from either side.
        # Without this, the remote device is paired but not trusted, so BlueZ
        # won't let it initiate connections back to the desktop.
        if accept:
            try:
                _trust_device(self.bus, mac)
            except Exception as e:
                emit({"type": "error", "msg": f"trust failed: {e}"})
        return True

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="s", async_callbacks=("reply_handler","error_handler"))
    def RequestPinCode(self, device, reply_handler, error_handler):
        mac, name = mac_from_path(self.bus, str(device))
        self._store_pending(mac, reply_handler, error_handler, "pin")
        emit({"type":"pair_pin","mac":mac,"name":name})

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="u", async_callbacks=("reply_handler","error_handler"))
    def RequestPasskey(self, device, reply_handler, error_handler):
        mac, name = mac_from_path(self.bus, str(device))
        self._store_pending(mac, reply_handler, error_handler, "passkey")
        emit({"type":"pair_pin","mac":mac,"name":name,"needs_passkey":True})

    @dbus.service.method(AGENT_IFACE, in_signature="ou", out_signature="", async_callbacks=("reply_handler","error_handler"))
    def RequestConfirmation(self, device, passkey, reply_handler, error_handler):
        mac, name = mac_from_path(self.bus, str(device))
        self._store_pending(mac, reply_handler, error_handler, "confirm")
        pk = "%06d" % int(passkey)
        emit({"type":"pair_confirm","mac":mac,"name":name,"passkey":pk})

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="", async_callbacks=("reply_handler","error_handler"))
    def RequestAuthorization(self, device, reply_handler, error_handler):
        mac, name = mac_from_path(self.bus, str(device))
        self._store_pending(mac, reply_handler, error_handler, "authorize")
        emit({"type":"pair_authorize","mac":mac,"name":name})

    @dbus.service.method(AGENT_IFACE, in_signature="os", out_signature="", async_callbacks=("reply_handler","error_handler"))
    def AuthorizeService(self, device, uuid, reply_handler, error_handler):
        # Auto-authorize service connections for already-paired devices
        reply_handler()

    @dbus.service.method(AGENT_IFACE, in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        mac, name = mac_from_path(self.bus, str(device))
        emit({"type":"display_pin","mac":mac,"name":name,"pin":str(pincode)})

    @dbus.service.method(AGENT_IFACE, in_signature="ouu", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        mac, name = mac_from_path(self.bus, str(device))
        emit({"type":"display_pin","mac":mac,"name":name,"pin":"%06d" % int(passkey)})

    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Cancel(self):
        # BlueZ calls Cancel when the remote side aborts pairing.
        # Emit with the first pending MAC if we have one, else null.
        with self._lock:
            mac = next(iter(self._pending), None)
            if mac:
                self._pending.pop(mac, None)
        emit({"type": "pair_cancelled", "mac": mac})

    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Release(self):
        pass


class QuickshellObexAgent(dbus.service.Object):
    def __init__(self, bus, system_bus, path, bt_agent):
        self.bus = bus
        self.system_bus = system_bus
        self.bt_agent = bt_agent
        self.auto_accept = False
        self._pending_transfers = {}
        self._known_cache_files = set()  # Track files already in obexd cache
        self._pending_file_moves = {}
        self._accepted_transfers = set()
        self._last_authorize_path = None
        self._known_sessions = set()
        super().__init__(bus, path)

    @dbus.service.method(OBEX_AGENT_IFACE, in_signature="o", out_signature="s",
                          async_callbacks=("reply_handler", "error_handler"))
    def AuthorizePush(self, transfer_path, reply_handler, error_handler):
        """Authorize an incoming OBEX file push."""
        transfer_path_str = str(transfer_path)
        emit({"type": "error", "msg": f"AuthorizePush called: {transfer_path_str}"})
        name = "unknown"
        size = 0
        mac = "unknown"
        device_name = "Unknown device"

        # Query the Transfer object for Name and Size, and Session for MAC
        try:
            transfer_obj = self.bus.get_object(OBEX_SERVICE, transfer_path_str)
            transfer_props_iface = dbus.Interface(transfer_obj, "org.freedesktop.DBus.Properties")
            name = str(transfer_props_iface.Get("org.bluez.obex.Transfer1", "Name"))
            size = int(transfer_props_iface.Get("org.bluez.obex.Transfer1", "Size"))
            # Get Session path from transfer properties to find the device MAC
            all_props = transfer_props_iface.GetAll("org.bluez.obex.Transfer1")
            session_path = str(all_props.get("Session", ""))
            if session_path:
                session_obj = self.bus.get_object(OBEX_SERVICE, session_path)
                session_props = dbus.Interface(session_obj, "org.freedesktop.DBus.Properties")
                mac = str(session_props.Get("org.bluez.obex.Session1", "Destination"))
                device_name = get_device_name(self.system_bus, mac)
        except Exception:
            pass

        dest_dir = f"{GLib.get_home_dir()}/.cache/obexd"
        # Ensure the destination directory exists
        os.makedirs(dest_dir, exist_ok=True)
        # obexd can only write to its own cache directory due to daemon security
        # restrictions. We return a path there, then copy to ~/Downloads after.
        dest_path = f"{dest_dir}/{name}"
        final_path = f"{GLib.get_home_dir()}/Downloads/{name}"

        if self.auto_accept:
            # Receive Files mode: accept immediately without prompting
            reply_handler(dbus.String(dest_path))
            sz = (f"{size/1048576:.1f} MB" if size > 1048576
                  else f"{size//1024} KB" if size > 1024
                  else f"{size} B") if size else ""
            # Store for post-transfer file finalization
            self._pending_file_moves[transfer_path_str] = {
                "obexd_path": dest_path,
                "final_path": final_path,
                "name": name, "mac": mac, "device_name": device_name,
                "expected_size": size}
            self._accepted_transfers.add(transfer_path_str)  # Auto-accepted = accepted
            self._last_authorize_path = transfer_path_str
            emit({"type": "file_receiving", "mac": mac, "name": device_name,
                  "filename": name, "size": sz, "transfer": transfer_path_str})
        else:
            # Prompt mode: hold the D-Bus reply and ask QML via notification toast
            self._pending_transfers[transfer_path_str] = (reply_handler, error_handler, dest_path)
            # Store for post-transfer file finalization
            self._pending_file_moves[transfer_path_str] = {
                "obexd_path": dest_path,
                "final_path": final_path,
                "name": name, "mac": mac, "device_name": device_name,
                "expected_size": size}
            self._last_authorize_path = transfer_path_str
            emit({"type": "file_request", "mac": mac, "name": device_name,
                  "filename": name, "size": size, "transfer": transfer_path_str})

    def respond_transfer(self, transfer_path, accept, dest=None):
        p = self._pending_transfers.pop(transfer_path, None)
        if not p:
            return False
        reply_h, error_h, default_dest = p
        if accept:
            # Mark as explicitly accepted so Cancel() doesn't report it
            self._accepted_transfers.add(transfer_path)
            reply_h(dbus.String(dest or default_dest))
        else:
            error_h(dbus.DBusException("org.bluez.obex.Error.Rejected"))
        return True

    def _finalize_transfer(self, transfer_path_str):
        """Copy a completed OBEX transfer from ~/.cache/obexd/ to ~/Downloads/.

        Runs in a background thread to avoid blocking the GLib main loop
        (which handles D-Bus callbacks for other transfers).
        """
        emit({"type": "error", "msg": f"_finalize_transfer called for: {transfer_path_str}"})
        # Guard against double-finalization (race from session monitor)
        if transfer_path_str not in self._pending_file_moves:
            emit({"type": "error", "msg": f"_finalize_transfer: {transfer_path_str} not in pending, skipping"})
            return
        info = self._pending_file_moves.pop(transfer_path_str, None)
        if not info:
            emit({"type": "error", "msg": f"_finalize_transfer: info is None for {transfer_path_str}, skipping"})
            return
        # Clean up accepted set
        self._accepted_transfers.discard(transfer_path_str)
        obexd_path = info.get("obexd_path", "")
        final_path = info.get("final_path", "")
        name = info.get("name", "unknown")
        expected_size = info.get("expected_size", 0)

        emit({"type": "error", "msg": f"Finalizing: name={name} obexd={obexd_path} final={final_path}"})

        # Wait for obexd to finish writing the file in its cache
        for attempt in range(40):  # up to 20 seconds
            time.sleep(0.5)
            exists = os.path.exists(obexd_path)
            sz = os.path.getsize(obexd_path) if exists else -1
            if attempt % 8 == 0:  # Log every 4 seconds
                emit({"type": "error", "msg": f"  attempt {attempt}: exists={exists} size={sz}"})
            if exists:
                if expected_size > 0 and sz >= expected_size:
                    time.sleep(0.5)  # brief flush wait
                    emit({"type": "error", "msg": f"  File reached expected size {sz} >= {expected_size}"})
                    break
                elif expected_size == 0 and sz > 0:
                    # No expected size — wait for stability
                    stable = 0
                    for _ in range(6):
                        time.sleep(0.5)
                        new_sz = os.path.getsize(obexd_path)
                        if new_sz == sz and sz > 0:
                            stable += 1
                        else:
                            sz = new_sz
                            stable = 0
                    emit({"type": "error", "msg": f"  File stabilized at size {sz}"})
                    break

        if not os.path.exists(obexd_path):
            emit({"type": "error", "msg": f"OBEX cache file not found: {obexd_path}"})
            # List what IS in the cache dir
            try:
                cached = os.listdir(os.path.dirname(obexd_path))
                emit({"type": "error", "msg": f"Cache dir contents: {cached}"})
            except Exception:
                pass
            return

        obexd_size = os.path.getsize(obexd_path)
        emit({"type": "error", "msg": f"OBEX cache file size: {obexd_size} bytes"})
        if obexd_size == 0:
            emit({"type": "error", "msg": f"OBEX cache file is empty: {name}"})
            return

        # Handle filename collisions in Downloads
        dest_dir = os.path.dirname(final_path)
        os.makedirs(dest_dir, exist_ok=True)
        base, ext = os.path.splitext(name)
        actual_path = final_path
        counter = 1
        while os.path.exists(actual_path):
            actual_path = f"{dest_dir}/{base}({counter}){ext}"
            counter += 1

        emit({"type": "error", "msg": f"Copying {obexd_path} -> {actual_path}"})
        try:
            shutil.copy2(obexd_path, actual_path)
            saved_size = os.path.getsize(actual_path)
            if saved_size == 0:
                os.unlink(actual_path)
                emit({"type": "error", "msg": f"Failed to save file (empty copy): {name}"})
                return
            sz_str = (f"{saved_size/1048576:.1f} MB" if saved_size > 1048576
                      else f"{saved_size//1024} KB" if saved_size > 1024
                      else f"{saved_size} B")
            emit({"type": "file_saved", "mac": info.get("mac", ""),
                  "name": info.get("device_name", ""),
                  "filename": os.path.basename(actual_path), "size": sz_str})
            emit({"type": "error", "msg": f"SUCCESS: saved {actual_path} ({sz_str})"})
        except Exception as e:
            emit({"type": "error", "msg": f"Failed to save file: {e}"})

    @dbus.service.method(OBEX_AGENT_IFACE, in_signature="", out_signature="")
    def Cancel(self):
        # Cancel is called when the remote side aborts or the transfer errors out.
        # If the last transfer we were authorizing was already accepted (either
        # via auto_accept or manual accept), don't emit "cancelled" — the
        # session monitor will handle the file move instead.
        tp = self._last_authorize_path
        was_accepted = tp and tp in self._accepted_transfers
        # Clean up pending state for this transfer
        if tp:
            self._pending_file_moves.pop(tp, None)
            self._pending_transfers.pop(tp, None)
            self._accepted_transfers.discard(tp)
            self._last_authorize_path = None
        if not was_accepted:
            emit({"type":"file_cancelled"})

    @dbus.service.method(OBEX_AGENT_IFACE, in_signature="", out_signature="")
    def Release(self):
        pass


def kill_previous_instance():
    """Kill any previous bt-agent.py process and clean up its D-Bus registrations.

    Called at startup so a clean bar restart evicts stale agents that
    still hold the BlueZ / OBEX registrations from crashed processes,
    preventing AlreadyExists and UnknownMethod errors.
    """
    # First try to kill the PID-recorded process
    try:
        with open(PIDFILE, "r") as f:
            old_pid = int(f.read().strip())
        if old_pid != os.getpid():
            try:
                os.kill(old_pid, 15)   # SIGTERM
                time.sleep(0.3)
                try:
                    os.kill(old_pid, 9)  # SIGKILL if still alive
                except ProcessLookupError:
                    pass
            except ProcessLookupError:
                pass  # already gone
    except (FileNotFoundError, ValueError):
        pass

    # Then try to unregister any agents at our known D-Bus paths.
    # These will fail silently if no agents are registered, which is fine.
    try:
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        sys_bus = dbus.SystemBus()
        try:
            sys_bus.call_blocking(BLUEZ_SERVICE, MANAGER_PATH,
                MANAGER_IFACE, 'UnregisterAgent', 'o',
                [dbus.ObjectPath(AGENT_PATH)])
        except Exception:
            pass
        ses_bus = dbus.SessionBus()
        try:
            ses_bus.call_blocking(OBEX_SERVICE, OBEX_MGR_PATH,
                OBEX_MGR_IFACE, 'UnregisterAgent', 'o',
                [dbus.ObjectPath(OBEX_AGENT_PATH)])
        except Exception:
            pass
        time.sleep(0.2)  # let BlueZ/OBEX notice the disconnects
    except Exception:
        pass  # D-Bus not available yet — not fatal

def write_pidfile():
    try:
        with open(PIDFILE, "w") as f:
            f.write(str(os.getpid()))
    except Exception as e:
        emit({"type": "error", "msg": f"pidfile write failed: {e}"})

def remove_pidfile():
    try:
        os.unlink(PIDFILE)
    except FileNotFoundError:
        pass


def stdin_reader(loop, bt_agent, obex_agent):
    """Read commands from the persistent fifo in a background thread.

    Each QML send is a short-lived `printf ... >> /tmp/qs_bt_cmd` process.
    When that process exits it is the last writer, so the fifo delivers
    EOF to us.  We must NOT exit on EOF — loop back and reopen so the
    GLib mainloop and D-Bus agent registration stay alive indefinitely.

    Extra command:
        set_auto_accept 1   — auto-accept incoming files (Receive Files mode)
        set_auto_accept 0   — prompt user via notification toast (default)
    """
    FIFO = "/tmp/qs_bt_cmd"
    import fcntl as _fcntl
    while True:
        try:
            fd = os.open(FIFO, os.O_RDONLY | os.O_NONBLOCK)
            flags = _fcntl.fcntl(fd, _fcntl.F_GETFL)
            _fcntl.fcntl(fd, _fcntl.F_SETFL, flags & ~os.O_NONBLOCK)
            with os.fdopen(fd, "r") as fh:
                for raw in fh:
                    line = raw.strip()
                    if not line:
                        continue
                    parts = line.split()
                    cmd = parts[0] if parts else ""
                    try:
                        if cmd == "accept_pair" and len(parts) >= 2:
                            bt_agent.respond(parts[1], True)
                        elif cmd == "reject_pair" and len(parts) >= 2:
                            bt_agent.respond(parts[1], False)
                        elif cmd == "pin_pair" and len(parts) >= 3:
                            bt_agent.respond(parts[1], True, pin=parts[2])
                        elif cmd == "accept_file" and len(parts) >= 2:
                            obex_agent.respond_transfer(parts[1], True)
                        elif cmd == "reject_file" and len(parts) >= 2:
                            obex_agent.respond_transfer(parts[1], False)
                        elif cmd == "file_transfer_completed" and len(parts) >= 2:
                            # Called by QML when OBEX session is removed (transfer done)
                            obex_agent._move_obex_file(parts[1])
                        elif cmd == "set_auto_accept" and len(parts) >= 2:
                            obex_agent.auto_accept = (parts[1] == "1")
                            emit({"type": "auto_accept",
                                  "enabled": obex_agent.auto_accept})
                            emit({"type": "error", "msg": f"auto_accept set to {obex_agent.auto_accept}"})
                        elif cmd == "quit":
                            loop.quit()
                            return
                    except Exception as ex:
                        emit({"type": "error", "msg": str(ex)})
            # EOF — last writer closed the fifo; sleep briefly before
            # reopening so we don't spin at 100% CPU while idle.
            time.sleep(0.25)
        except Exception as ex:
            emit({"type": "error", "msg": f"stdin_reader reopen: {ex}"})
            time.sleep(1)


def main():
    # ── Singleton: evict any stale previous instance ──────────────────────
    kill_previous_instance()
    write_pidfile()

    # ── Ensure the command FIFO exists ──────────────────────────────────────
    FIFO = "/tmp/qs_bt_cmd"
    try:
        if not os.path.exists(FIFO) or not os.path.exists(FIFO):
            # Could be a regular file left over from a crash — force it to a FIFO
            try:
                if os.path.isfile(FIFO) or os.path.islink(FIFO):
                    os.unlink(FIFO)
                os.mkfifo(FIFO)
            except FileExistsError:
                # Race: another process created it between our checks
                if os.path.isfile(FIFO):
                    os.unlink(FIFO)
                    os.mkfifo(FIFO)
    except Exception as e:
        # Non-fatal: the QML side might create it; we'll just wait for it
        emit({"type": "error", "msg": f"FIFO creation warning: {e}"})

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    system_bus = dbus.SystemBus()
    session_bus = dbus.SessionBus()

    # ── BT pairing agent on system bus ────────────────────────────────────
    bt_agent = QuickshellBTAgent(system_bus, AGENT_PATH)
    try:
        # BlueZ AgentManager1 doesn't expose introspection data, so dbus-python
        # can't auto-detect method signatures.  We must use call_blocking
        # with explicit signature strings.
        # RegisterAgent(in o agent, in s capability)
        try:
            system_bus.call_blocking(BLUEZ_SERVICE, MANAGER_PATH,
                MANAGER_IFACE, 'UnregisterAgent', 'o',
                [dbus.ObjectPath(AGENT_PATH)])
        except Exception:
            pass
        system_bus.call_blocking(BLUEZ_SERVICE, MANAGER_PATH,
            MANAGER_IFACE, 'RegisterAgent', 'os',
            [dbus.ObjectPath(AGENT_PATH), "DisplayYesNo"])
        system_bus.call_blocking(BLUEZ_SERVICE, MANAGER_PATH,
            MANAGER_IFACE, 'RequestDefaultAgent', 'o',
            [dbus.ObjectPath(AGENT_PATH)])
        emit({"type": "error", "msg": "BT agent registered as default"})
    except Exception as e:
        emit({"type": "error", "msg": f"BT agent register failed: {e}"})

    # ── OBEX agent on session bus ──────────────────────────────────────────
    obex_agent = QuickshellObexAgent(session_bus, system_bus, OBEX_AGENT_PATH, bt_agent)
    try:
        # OBEX AgentManager1 also lacks introspection data — use call_blocking
        try:
            session_bus.call_blocking(OBEX_SERVICE, OBEX_MGR_PATH,
                OBEX_MGR_IFACE, 'UnregisterAgent', 'o',
                [dbus.ObjectPath(OBEX_AGENT_PATH)])
        except Exception:
            pass
        session_bus.call_blocking(OBEX_SERVICE, OBEX_MGR_PATH,
            OBEX_MGR_IFACE, 'RegisterAgent', 'o',
            [dbus.ObjectPath(OBEX_AGENT_PATH)])
        emit({"type": "error", "msg": "OBEX agent registered"})
    except Exception as e:
        emit({"type": "error", "msg": f"OBEX agent register failed: {e}"})

    # ── Make adapter discoverable and pairable ────────────────────────────
    try:
        obj_mgr = dbus.Interface(
            system_bus.get_object(BLUEZ_SERVICE, "/"), "org.freedesktop.DBus.ObjectManager")
        for path, ifaces in obj_mgr.GetManagedObjects().items():
            if "org.bluez.Adapter1" in ifaces:
                props = dbus.Interface(
                    system_bus.get_object(BLUEZ_SERVICE, path),
                    "org.freedesktop.DBus.Properties")
                props.Set("org.bluez.Adapter1", "Discoverable",        dbus.Boolean(True))
                props.Set("org.bluez.Adapter1", "Pairable",            dbus.Boolean(True))
                props.Set("org.bluez.Adapter1", "DiscoverableTimeout", dbus.UInt32(0))
    except Exception as e:
        emit({"type": "error", "msg": f"Discoverable set failed: {e}"})

    emit({"type": "agent_ready"})

    loop = GLib.MainLoop()
    t = threading.Thread(
        target=stdin_reader, args=(loop, bt_agent, obex_agent), daemon=True)
    t.start()

    # ── OBEX cache directory monitor ───────────────────────────────────────
    def obex_cache_monitor():
        """Watch ~/.cache/obexd/ for new files and copy them to ~/Downloads/.

        Android often sends multiple files in a single OBEX session, so
        AuthorizePush is only called once.  Instead of tracking individual
        transfers, we watch the cache directory for new files.
        """
        cache_dir = f"{GLib.get_home_dir()}/.cache/obexd"
        dest_dir = f"{GLib.get_home_dir()}/Downloads"
        os.makedirs(cache_dir, exist_ok=True)
        os.makedirs(dest_dir, exist_ok=True)

        # Build initial set of known files
        try:
            obex_agent._known_cache_files = set(os.listdir(cache_dir))
        except Exception:
            obex_agent._known_cache_files = set()

        while True:
            time.sleep(1.0)
            try:
                current_files = set(os.listdir(cache_dir))
            except Exception:
                continue

            # Find new files that appeared since last check
            new_files = current_files - obex_agent._known_cache_files
            for filename in new_files:
                cache_path = os.path.join(cache_dir, filename)
                # Skip if it's a directory or doesn't exist yet
                if not os.path.isfile(cache_path):
                    continue
                # Wait for the file to be fully written
                time.sleep(0.5)
                try:
                    file_size = os.path.getsize(cache_path)
                except OSError:
                    continue

                # Handle filename collisions in Downloads
                dest_path = os.path.join(dest_dir, filename)
                base, ext = os.path.splitext(filename)
                counter = 1
                while os.path.exists(dest_path):
                    dest_path = os.path.join(dest_dir, f"{base}({counter}){ext}")
                    counter += 1

                try:
                    shutil.copy2(cache_path, dest_path)
                    saved_size = os.path.getsize(dest_path)
                    sz_str = (f"{saved_size/1048576:.1f} MB" if saved_size > 1048576
                              else f"{saved_size//1024} KB" if saved_size > 1024
                              else f"{saved_size} B")
                    emit({"type": "file_saved", "mac": "",
                          "name": "Bluetooth",
                          "filename": os.path.basename(dest_path), "size": sz_str})
                except Exception as e:
                    emit({"type": "error", "msg": f"Failed to save {filename}: {e}"})

            obex_agent._known_cache_files = current_files

    monitor_thread = threading.Thread(target=obex_cache_monitor, daemon=True)
    monitor_thread.start()
    try:
        loop.run()
    except KeyboardInterrupt:
        pass
    finally:
        remove_pidfile()

if __name__ == "__main__":
    main()
