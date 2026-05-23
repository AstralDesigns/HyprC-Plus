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
                        send_file AA:BB:CC:DD:EE:FF /path/to/file
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
    """Set Trusted=True and AutoConnect=True on the BlueZ device object."""
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
            return
    except Exception as e:
        emit({"type": "error", "msg": f"_trust_device({mac}): {e}"})

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
        self._known_cache_files = set()
        self._pending_file_moves = {}
        self._accepted_transfers = set()
        self._last_authorize_path = None
        self._monitored_transfers = {}
        super().__init__(bus, path)

    @dbus.service.method(OBEX_AGENT_IFACE, in_signature="o", out_signature="s",
                          async_callbacks=("reply_handler", "error_handler"))
    def AuthorizePush(self, transfer_path, reply_handler, error_handler):
        transfer_path_str = str(transfer_path)
        name = "unknown"
        size = 0
        mac = "unknown"
        device_name = "Unknown device"

        try:
            transfer_obj = self.bus.get_object(OBEX_SERVICE, transfer_path_str)
            transfer_props_iface = dbus.Interface(transfer_obj, "org.freedesktop.DBus.Properties")
            name = str(transfer_props_iface.Get("org.bluez.obex.Transfer1", "Name"))
            size = int(transfer_props_iface.Get("org.bluez.obex.Transfer1", "Size"))
            all_props = transfer_props_iface.GetAll("org.bluez.obex.Transfer1")
            session_path = str(all_props.get("Session", ""))
            if session_path:
                session_obj = self.bus.get_object(OBEX_SERVICE, session_path)
                session_props = dbus.Interface(session_obj, "org.freedesktop.DBus.Properties")
                mac = str(session_props.Get("org.bluez.obex.Session1", "Destination"))
                device_name = get_device_name(self.system_bus, mac)
        except Exception as e:
            emit({"type": "error", "msg": f"AuthorizePush property read failed: {e}"})

        dest_dir = f"{GLib.get_home_dir()}/.cache/obexd"
        os.makedirs(dest_dir, exist_ok=True)
        dest_path = f"{dest_dir}/{name}"
        final_path = f"{GLib.get_home_dir()}/Downloads/{name}"

        self._pending_file_moves[transfer_path_str] = {
            "obexd_path": dest_path,
            "final_path": final_path,
            "name": name, "mac": mac, "device_name": device_name,
            "expected_size": size
        }

        self._setup_transfer_monitoring(transfer_path_str)

        if self.auto_accept:
            reply_handler(dbus.String(dest_path))
            sz = (f"{size/1048576:.1f} MB" if size > 1048576
                  else f"{size//1024} KB" if size > 1024
                  else f"{size} B") if size else ""
            self._accepted_transfers.add(transfer_path_str)
            self._last_authorize_path = transfer_path_str
            emit({"type": "file_receiving", "mac": mac, "name": device_name,
                  "filename": name, "size": sz, "transfer": transfer_path_str})
        else:
            self._pending_transfers[transfer_path_str] = (reply_handler, error_handler, dest_path)
            self._last_authorize_path = transfer_path_str
            emit({"type": "file_request", "mac": mac, "name": device_name,
                  "filename": name, "size": size, "transfer": transfer_path_str})

    def _setup_transfer_monitoring(self, transfer_path_str):
        def on_props_changed(iface, changed, invalidated):
            if iface != "org.bluez.obex.Transfer1":
                return
            status = changed.get("Status")
            if not status:
                return
            if status == "complete":
                self._cleanup_transfer_monitoring(transfer_path_str)
                self._finalize_transfer(transfer_path_str)
            elif status == "error":
                self._cleanup_transfer_monitoring(transfer_path_str)
                self._pending_file_moves.pop(transfer_path_str, None)
                self._pending_transfers.pop(transfer_path_str, None)
                self._accepted_transfers.discard(transfer_path_str)
                emit({"type": "file_cancelled"})

        match = self.bus.add_signal_receiver(
            on_props_changed,
            signal_name="PropertiesChanged",
            dbus_interface="org.freedesktop.DBus.Properties",
            path=transfer_path_str
        )
        self._monitored_transfers[transfer_path_str] = match

    def _cleanup_transfer_monitoring(self, transfer_path_str):
        match = self._monitored_transfers.pop(transfer_path_str, None)
        if match:
            try:
                match.remove()
            except Exception:
                pass

    def respond_transfer(self, transfer_path, accept, dest=None):
        p = self._pending_transfers.pop(transfer_path, None)
        if not p:
            return False
        reply_h, error_h, default_dest = p
        if accept:
            self._accepted_transfers.add(transfer_path)
            reply_h(dbus.String(dest or default_dest))
        else:
            self._cleanup_transfer_monitoring(transfer_path)
            self._pending_file_moves.pop(transfer_path, None)
            self._accepted_transfers.discard(transfer_path)
            error_h(dbus.DBusException("org.bluez.obex.Error.Rejected"))
        return True

    def _finalize_transfer(self, transfer_path_str):
        info = self._pending_file_moves.get(transfer_path_str)
        if info:
            obexd_name = os.path.basename(info.get("obexd_path", ""))
            if obexd_name:
                self._known_cache_files.add(obexd_name)
        t = threading.Thread(
            target=self._finalize_transfer_worker,
            args=(transfer_path_str,), daemon=True)
        t.start()

    def _finalize_transfer_worker(self, transfer_path_str):
        if transfer_path_str not in self._pending_file_moves:
            return
        info = self._pending_file_moves.pop(transfer_path_str, None)
        if not info:
            return
        self._accepted_transfers.discard(transfer_path_str)
        obexd_path = info.get("obexd_path", "")
        final_path = info.get("final_path", "")
        name = info.get("name", "unknown")

        time.sleep(1.0)
        if not os.path.exists(obexd_path):
            return

        saved_size = os.path.getsize(obexd_path)
        if saved_size == 0:
            return

        dest_dir = os.path.dirname(final_path)
        os.makedirs(dest_dir, exist_ok=True)
        base, ext = os.path.splitext(name)
        actual_path = final_path
        counter = 1
        while os.path.exists(actual_path):
            actual_path = f"{dest_dir}/{base}({counter}){ext}"
            counter += 1

        try:
            shutil.copy2(obexd_path, actual_path)
            saved_size = os.path.getsize(actual_path)
            sz_str = (f"{saved_size/1048576:.1f} MB" if saved_size > 1048576
                      else f"{saved_size//1024} KB" if saved_size > 1024
                      else f"{saved_size} B")
            emit({"type": "file_saved", "mac": info.get("mac", ""),
                  "name": info.get("device_name", ""),
                  "filename": os.path.basename(actual_path), "size": sz_str})
        except Exception as e:
            emit({"type": "error", "msg": f"File save failed: {e}"})

    @dbus.service.method(OBEX_AGENT_IFACE, in_signature="", out_signature="")
    def Cancel(self):
        tp = self._last_authorize_path
        was_accepted = tp and tp in self._accepted_transfers
        if tp:
            self._cleanup_transfer_monitoring(tp)
            self._pending_file_moves.pop(tp, None)
            self._pending_transfers.pop(tp, None)
            self._accepted_transfers.discard(tp)
            self._last_authorize_path = None
        if not was_accepted:
            emit({"type":"file_cancelled"})

    @dbus.service.method(OBEX_AGENT_IFACE, in_signature="", out_signature="")
    def Release(self):
        pass


def send_file_dbus(session_bus, mac, file_path):
    """Outbound file send using BlueZ OBEX client D-Bus interface."""
    if not os.path.exists(file_path):
        emit({"type": "file_send_error", "filename": os.path.basename(file_path), "msg": "Local file not found"})
        return

    filename = os.path.basename(file_path)
    emit({"type": "file_send_started", "mac": mac, "filename": filename})

    try:
        obex_client = session_bus.get_object(OBEX_SERVICE, "/org/bluez/obex")
        client_mgr = dbus.Interface(obex_client, "org.bluez.obex.Client1")
        
        # Create session with retry logic for device wake-up
        session_path = None
        for attempt in range(1, 4):
            try:
                session_path = client_mgr.CreateSession(mac, {"Target": dbus.String("opp")})
                break
            except Exception as e:
                if attempt < 3:
                    emit({"type": "file_send_retrying", "mac": mac, "filename": filename, 
                          "attempt": attempt, "max": 3, "msg": "Waking up device..."})
                    time.sleep(2)
                else:
                    raise e
        
        session_obj = session_bus.get_object(OBEX_SERVICE, session_path)
        opp = dbus.Interface(session_obj, "org.bluez.obex.ObjectPush1")
        transfer_path, props = opp.SendFile(file_path)
        transfer_path_str = str(transfer_path)
        
        def on_send_props_changed(iface, changed, invalidated):
            if iface != "org.bluez.obex.Transfer1":
                return
            status = changed.get("Status")
            if not status:
                return
            if status == "complete":
                send_match.remove()
                emit({"type": "file_sent", "mac": mac, "filename": filename})
                try:
                    client_mgr.RemoveSession(session_path)
                except Exception:
                    pass
            elif status == "error":
                send_match.remove()
                emit({"type": "file_send_error", "mac": mac, "filename": filename, "msg": "Remote device rejected or error"})
                try:
                    client_mgr.RemoveSession(session_path)
                except Exception:
                    pass

        send_match = session_bus.add_signal_receiver(
            on_send_props_changed,
            signal_name="PropertiesChanged",
            dbus_interface="org.freedesktop.DBus.Properties",
            path=transfer_path_str
        )
    except Exception as e:
        emit({"type": "file_send_error", "mac": mac, "filename": filename, "msg": str(e)})


def stdin_reader(loop, bt_agent, obex_agent, session_bus):
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
                    if not line: continue
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
                        elif cmd == "set_auto_accept" and len(parts) >= 2:
                            obex_agent.auto_accept = (parts[1] == "1")
                            emit({"type": "auto_accept", "enabled": obex_agent.auto_accept})
                        elif cmd == "send_file" and len(parts) >= 3:
                            mac = parts[1]
                            file_path = " ".join(parts[2:])
                            t = threading.Thread(target=send_file_dbus, args=(session_bus, mac, file_path), daemon=True)
                            t.start()
                        elif cmd == "quit":
                            loop.quit()
                            return
                    except Exception as ex:
                        emit({"type": "error", "msg": str(ex)})
            time.sleep(0.25)
        except Exception:
            time.sleep(1)


def main():
    # Kill previous instance
    try:
        if os.path.exists(PIDFILE):
            with open(PIDFILE, "r") as f:
                old_pid = int(f.read().strip())
            os.kill(old_pid, 15)
            time.sleep(0.3)
    except Exception: pass
    
    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    system_bus = dbus.SystemBus()
    session_bus = dbus.SessionBus()

    bt_agent = QuickshellBTAgent(system_bus, AGENT_PATH)
    try:
        mgr = dbus.Interface(system_bus.get_object(BLUEZ_SERVICE, MANAGER_PATH), MANAGER_IFACE)
        try: mgr.UnregisterAgent(dbus.ObjectPath(AGENT_PATH))
        except: pass
        mgr.RegisterAgent(dbus.ObjectPath(AGENT_PATH), "DisplayYesNo")
        mgr.RequestDefaultAgent(dbus.ObjectPath(AGENT_PATH))
    except Exception as e:
        emit({"type": "error", "msg": f"BT agent register failed: {e}"})

    obex_agent = QuickshellObexAgent(session_bus, system_bus, OBEX_AGENT_PATH, bt_agent)
    try:
        omgr = dbus.Interface(session_bus.get_object(OBEX_SERVICE, OBEX_MGR_PATH), OBEX_MGR_IFACE)
        try: omgr.UnregisterAgent(dbus.ObjectPath(OBEX_AGENT_PATH))
        except: pass
        omgr.RegisterAgent(dbus.ObjectPath(OBEX_AGENT_PATH))
    except Exception as e:
        emit({"type": "error", "msg": f"OBEX agent register failed: {e}"})

    emit({"type": "agent_ready"})

    loop = GLib.MainLoop()
    t = threading.Thread(target=stdin_reader, args=(loop, bt_agent, obex_agent, session_bus), daemon=True)
    t.start()
    
    try:
        loop.run()
    except KeyboardInterrupt:
        pass
    finally:
        if os.path.exists(PIDFILE): os.unlink(PIDFILE)

if __name__ == "__main__":
    main()
