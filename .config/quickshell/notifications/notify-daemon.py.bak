#!/usr/bin/env python3
"""
org.freedesktop.Notifications DBus service for Quickshell.
Claims the well-known name so swaync/dunst are not needed.
Emits JSON lines to stdout for QS to consume.

Ensure this starts before swaync or kill swaync first:
  exec-once = pkill -x swaync; sleep 0.2; qs -c ~/.config/quickshell/notifications
"""

import sys
import json
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

NOTIF_IFACE   = "org.freedesktop.Notifications"
NOTIF_PATH    = "/org/freedesktop/Notifications"
DBUS_NAME     = "org.freedesktop.Notifications"

def emit(obj):
    print(json.dumps(obj), flush=True)

URGENCY_MAP = {0: "low", 1: "normal", 2: "critical"}

class NotificationService(dbus.service.Object):
    def __init__(self, bus):
        self.bus = bus
        self._id_counter = 1
        super().__init__(bus, NOTIF_PATH)

    @dbus.service.method(NOTIF_IFACE,
                         in_signature="susssasa{sv}i",
                         out_signature="u")
    def Notify(self, app_name, replaces_id, app_icon,
               summary, body, actions, hints, expire_timeout):
        nid = int(replaces_id) if replaces_id else self._id_counter
        if not replaces_id:
            self._id_counter += 1

        urgency = URGENCY_MAP.get(int(hints.get("urgency", 1)), "normal")
        category = str(hints.get("category", ""))

        action_list = []
        it = iter(actions)
        for key in it:
            label = next(it, "")
            action_list.append({"key": str(key), "label": str(label)})

        emit({
            "type":     "notify",
            "id":       nid,
            "app_name": str(app_name),
            "icon":     str(app_icon),
            "summary":  str(summary),
            "body":     str(body),
            "urgency":  urgency,
            "category": category,
            "actions":  action_list,
            "timeout":  int(expire_timeout)
        })
        return dbus.UInt32(nid)

    @dbus.service.method(NOTIF_IFACE, in_signature="u", out_signature="")
    def CloseNotification(self, nid):
        emit({"type": "close", "id": int(nid)})
        self.NotificationClosed(dbus.UInt32(nid), dbus.UInt32(3))

    @dbus.service.method(NOTIF_IFACE, in_signature="", out_signature="ssss")
    def GetServerInformation(self):
        return ("quickshell-notif", "quickshell", "1.0", "1.2")

    @dbus.service.method(NOTIF_IFACE, in_signature="", out_signature="as")
    def GetCapabilities(self):
        return ["body", "body-markup", "actions", "persistence", "icon-static"]

    @dbus.service.signal(NOTIF_IFACE, signature="uu")
    def NotificationClosed(self, nid, reason):
        pass

    @dbus.service.signal(NOTIF_IFACE, signature="us")
    def ActionInvoked(self, nid, action_key):
        pass


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    session_bus = dbus.SessionBus()

    try:
        name = dbus.service.BusName(DBUS_NAME, session_bus,
                                     allow_replacement=True,
                                     replace_existing=True,
                                     do_not_queue=True)
    except dbus.exceptions.NameExistsException:
        emit({"type": "error", "msg": "Could not claim org.freedesktop.Notifications"})
        sys.exit(1)

    svc = NotificationService(session_bus)
    

    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    main()
