# Quickshell & QML Reference

This document serves as a local reference (RAG) for Quickshell QML types, properties, signals, and methods used in this codebase.

## Quickshell Core Types

### `PanelWindow`
A window designed to be attached to one or more screen edges, commonly used to build bars, panels, docks, and desktop overlays.
- **`anchors`**: Controls attachment to screen edges.
  - `top`, `bottom`, `left`, `right` (boolean values).
  - Anchoring opposite edges (e.g. `left` and `right`) stretches the window across the screen.
- **`margins`**: Offsets the window from the screen edges.
  - `top`, `bottom`, `left`, `right` (integer values).
- **`exclusiveZone`**: Reserves space on the screen so that other maximized windows do not overlap it.
- **`exclusionMode`**: How the window behaves with respect to the exclusive zone:
  - `ExclusionMode.Normal`: Normal exclusive zone behavior.
  - `ExclusionMode.Ignore`: Ignore exclusive zone.
  - `ExclusionMode.Auto`: Auto determine.
- **`aboveWindows`**: Set to `true` to keep the panel above normal client windows.
- **`color`**: Sets the background color of the window. Can be `"transparent"`.
- **`focusable`**: Set to `false` for bars/docks that should not steal keyboard focus.
- **`WlrLayershell.layer`**: Specifies the Wayland layer:
  - `WlrLayer.Background`: Behind everything.
  - `WlrLayer.Bottom`: Above background, below normal windows.
  - `WlrLayer.Top`: Above normal windows, below overlay.
  - `WlrLayer.Overlay`: On top of everything.

### `Process`
Allows launching and interacting with external CLI processes.
- **`command`**: A list of strings representing the executable and arguments.
- **`running`**: A boolean value to start/stop the process or check if it's currently active.
- **`stdout`**: Assign a data parser (e.g., `SplitParser` or `StdioCollector`) to handle stdout stream.
- **`stderr`**: Assign a data parser to handle stderr stream.
- **`readOut()`**: Read standard output.
- **`readErr()`**: Read standard error.
- **`onRunningChanged`**: Signal triggered when the execution state changes.
- **`onExited`**: Signal triggered when the process exits.

### `FileView`
A utility type to read and watch files on the local filesystem.
- **`path`**: Absolute path to the file.
- **`watchChanges`**: Set to `true` to watch the file for changes on disk.
- **`onFileChanged`**: Signal handler invoked when the file changes.
- **`onLoaded`**: Signal handler invoked when the file has been initially loaded.
- **`text()`**: Returns the file content as a string.
- **`reload()`**: Reloads the file content.

### `SplitParser`
Parses a data stream by splitting it on a marker.
- **`splitMarker`**: The string delimiter (typically `"\n"`).
- **`onRead(line)`**: Signal triggered when a complete chunk is read.

### `StdioCollector`
Collects the entire data stream until execution finishes.
- **`text`**: The accumulated string from the stream.
- **`onStreamFinished`**: Signal handler invoked when the stream has closed.

### `Scope`
A utility type to hold custom properties or create isolated scopes.

---

## QtQuick Core Types

### `Rectangle`
A standard visual rectangle element.
- **`color`**: Fill color.
- **`border.color`**: Color of the border.
- **`border.width`**: Width of the border.
- **`radius`**: Corner radius. Set to half of the height/width for circular pills.
- **`topLeftRadius`, `topRightRadius`, `bottomLeftRadius`, `bottomRightRadius`**: Properties to control individual corner radii.

### `HoverHandler`
A handler that detects pointer (mouse) hover events.
- **`hovered`**: Boolean property indicating whether the pointer is over the parent item.
- **`onHoveredChanged`**: Signal handler triggered when the pointer enters or leaves the parent item.

### `Timer`
A component to trigger actions after a delay.
- **`interval`**: Delay in milliseconds.
- **`running`**: Starts or stops the timer.
- **`repeat`**: If `true`, fires repeatedly; if `false`, fires once.
- **`onTriggered`**: Signal handler invoked when the timer fires.

### `Canvas`
Allows dynamic drawing using a 2D context similar to HTML5 Canvas.
- **`paint`**: Signal emitted when drawing needs to happen.
- **`requestPaint()`**: Method to request redraw.
- **`getContext("2d")`**: Returns the drawing context.

### `Connections`
Declares connections to signals of objects defined outside the local scope.
- **`target`**: The source object.
- **`function on<SignalName>(...)`**: Handler syntax.

---

## Config & State Persistence
Settings are typically loaded and saved from `~/.config/hyprcandy/hyprcandy-bar.conf` using a backend settings model (e.g. `Config.qml` and bash commands in `ControlCenterPopup.qml`).
- Ini sections:
  - `[hyprland]`: General bar, auto-hide, layout, and visual options.
  - `[cc-cava-colors-v1]`: Visualizer color parameters.
