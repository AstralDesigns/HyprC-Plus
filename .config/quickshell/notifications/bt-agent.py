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
import threading
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

AGENT_PATH      = "/quickshell/bt/agent"
AGENT_IFACE     = "org.bluez.Agent1"
BLUEZ_SERVICE   = "org.bluez"
MANAGER_PATH    = "/"
MANAGER_IFACE   = "org.bluez.AgentManager1"
OBEX_SERVICE    = "org.bluez.obex"
OBEX_AGENT_PATH = "/quickshell/obex/agent"
OBEX_AGENT_IFACE= "org.bluez.obex.Agent1"
OBEX_MGR_IFACE  = "org.bluez.obex.AgentManager1"
OBEX_MGR_PATH   = "/org/bluez/obex"

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

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="")
    def DisplayPinCode(self, device, pincode):
        mac, name = mac_from_path(self.bus, str(device))
        emit({"type":"display_pin","mac":mac,"name":name,"pin":str(pincode)})

    @dbus.service.method(AGENT_IFACE, in_signature="ou", out_signature="")
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
    def __init__(self, bus, path, bt_agent):
        self.bus = bus
        self.bt_agent = bt_agent  # share pending dict
        self._pending_transfers = {}  # transfer_path → (reply_h, error_h, info)
        super().__init__(bus, path)

    @dbus.service.method(OBEX_AGENT_IFACE, in_signature="oa{sv}", out_signature="s",
                          async_callbacks=("reply_handler","error_handler"))
    def AuthorizePush(self, transfer_path, transfer_props, reply_handler, error_handler):
        name     = str(transfer_props.get("Name","unknown"))
        size     = int(transfer_props.get("Size", 0))
        # Get the remote device MAC from the session
        mac  = "unknown"
        device_name = "Unknown device"
        try:
            session_path = str(transfer_props.get("Session",""))
            if session_path:
                obj = self.bus.get_object(OBEX_SERVICE, session_path)
                props = dbus.Interface(obj, "org.freedesktop.DBus.Properties")
                dest = str(props.Get("org.bluez.obex.Session1","Destination"))
                mac = dest
                device_name = get_device_name(
                    dbus.SystemBus(), mac)
        except Exception as e:
            pass
        dest_path = f"{GLib.get_home_dir()}/Downloads/{name}"
        self._pending_transfers[str(transfer_path)] = (reply_handler, error_handler, dest_path)
        emit({"type":"file_request","mac":mac,"name":device_name,
              "filename":name,"size":size,"transfer":str(transfer_path)})

    def respond_transfer(self, transfer_path, accept, dest=None):
        p = self._pending_transfers.pop(transfer_path, None)
        if not p:
            return False
        reply_h, error_h, default_dest = p
        if accept:
            reply_h(dbus.String(dest or default_dest))
        else:
            error_h(dbus.DBusException("org.bluez.obex.Error.Rejected"))
        return True

    @dbus.service.method(OBEX_AGENT_IFACE, in_signature="", out_signature="")
    def Cancel(self):
        emit({"type":"file_cancelled"})

    @dbus.service.method(OBEX_AGENT_IFACE, in_signature="", out_signature="")
    def Release(self):
        pass


def stdin_reader(loop, bt_agent, obex_agent):
    """Read commands from the persistent fifo in a background thread.

    Each QML send is a short-lived `echo >> /tmp/qs_bt_cmd` process.
    When that process exits it is the last writer, so the fifo delivers
    EOF to us.  We must NOT exit on EOF — loop back and reopen so the
    GLib mainloop and D-Bus agent registration stay alive indefinitely.
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
                        elif cmd == "quit":
                            loop.quit()
                            return
                    except Exception as ex:
                        emit({"type":"error","msg":str(ex)})
            # EOF — last writer closed, loop back and reopen
        except Exception as ex:
            emit({"type":"error","msg":f"stdin_reader reopen: {ex}"})
            time.sleep(1)


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    system_bus = dbus.SystemBus()
    session_bus = dbus.SessionBus()

    # BT pairing agent on system bus
    bt_agent = QuickshellBTAgent(system_bus, AGENT_PATH)
    try:
        mgr_obj = system_bus.get_object(BLUEZ_SERVICE, MANAGER_PATH)
        agent_mgr = dbus.Interface(mgr_obj, MANAGER_IFACE)
        # Unregister any stale registration from a previous run first
        try:
            agent_mgr.UnregisterAgent(AGENT_PATH)
        except Exception:
            pass
        agent_mgr.RegisterAgent(AGENT_PATH, "DisplayYesNo")
        agent_mgr.RequestDefaultAgent(AGENT_PATH)
        emit({"type":"error","msg":"BT agent registered as default"})
    except Exception as e:
        emit({"type":"error","msg":f"BT agent register failed: {e}"})

    # OBEX agent on session bus
    obex_agent = QuickshellObexAgent(session_bus, OBEX_AGENT_PATH, bt_agent)
    try:
        obex_obj = session_bus.get_object(OBEX_SERVICE, OBEX_MGR_PATH)
        obex_mgr = dbus.Interface(obex_obj, OBEX_MGR_IFACE)
        obex_mgr.RegisterAgent(OBEX_AGENT_PATH)
    except Exception as e:
        emit({"type":"error","msg":f"OBEX agent register failed: {e}"})

    # Make sure bluetooth is discoverable
    try:
        mgr_obj2 = system_bus.get_object(BLUEZ_SERVICE, MANAGER_PATH)
        obj_mgr = dbus.Interface(mgr_obj2, "org.freedesktop.DBus.ObjectManager")
        objects = obj_mgr.GetManagedObjects()
        for path, ifaces in objects.items():
            if "org.bluez.Adapter1" in ifaces:
                adapter = dbus.Interface(
                    system_bus.get_object(BLUEZ_SERVICE, path),
                    "org.freedesktop.DBus.Properties")
                adapter.Set("org.bluez.Adapter1", "Discoverable", dbus.Boolean(True))
                adapter.Set("org.bluez.Adapter1", "Pairable", dbus.Boolean(True))
                adapter.Set("org.bluez.Adapter1", "DiscoverableTimeout", dbus.UInt32(0))
    except Exception as e:
        emit({"type":"error","msg":f"Discoverable set failed: {e}"})

    emit({"type":"agent_ready"})

    loop = GLib.MainLoop()
    t = threading.Thread(target=stdin_reader, args=(loop, bt_agent, obex_agent), daemon=True)
    t.start()
    try:
        loop.run()
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    main()
