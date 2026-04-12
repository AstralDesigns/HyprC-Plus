//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QS_NO_RELOAD_POPUP=1

import "./modules/overview/"
import "./services/"
import "./common/"
import "./common/functions/"
import "./common/widgets/"

import QtQuick
import Quickshell
import Quickshell.Hyprland

ShellRoot {
    Overview {}
}
