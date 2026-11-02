# HyprCandy Greeter themes

Each immediate subdirectory here is one SDDM theme (e.g. `hyprcandy-1`).
The installer symlinks every subdirectory into `/usr/share/sddm/themes/`
and SDDM picks the active one via `/etc/sddm.conf.d/hyprcandy.conf`
(`Current=<dir-name>`, switchable from the Control Center → Greeter →
Themes tab).

A theme directory must contain:

- `metadata.desktop` — with `MainScript=Main.qml`, `ConfigFile=theme.conf`,
  and a unique `Theme-Id` matching the directory name
- `Main.qml` — Qt6 QML entry point (SDDM 0.20+; use `QtQuick.Effects`
  MultiEffect, not QtGraphicalEffects)
- `theme.conf` — editable keys surfaced by the CC Greeter → Edit tab
  (`HeaderText`, `FormPosition`, `BlurRadius`, `RoundCorners`,
  `InterfaceShadowSize`, `Font`, `MainColor`, `AccentColor`,
  `BackgroundColor`, `Background`, `ScreenWidth`, `ScreenHeight`)

Colors come from the shared runtime directory: matugen and wallust write
`Appearance.colors.qml` / `Appearance.wallust.qml` into this folder on
every wallpaper change, and `greeter-sync.sh` mirrors them to
`/usr/share/sddm/themes/hyprcandy-shared/` (alongside `Backgrounds/`
which holds the current greeter wallpaper). Themes reach them with
`import "../hyprcandy-shared"` + the `Theme.qml` bridge pattern from
`hyprcandy-1`.

Community themes: drop a new directory with the three required files in
place — it is auto-linked on the next `Candy_Update.sh` / install run.
