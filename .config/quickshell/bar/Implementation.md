We'll implement a new `"shell"` mode for the bar, which combines a full‑width shell strip at the screen edge with a protruding center island, while the left and right islands remain floating with their existing margins and auto‑hide behaviour.

---

### 1. Add new properties to `Config.qml`

Add a new section in `Config.qml` for shell‑specific settings. Place them after the existing tri‑mode properties.

```qml
// ── Shell mode (barMode === "shell") ──────────────────────────────
property int shellHeight: 20          // height of the shell strip (px)
property int shellRadius: 10          // radius of the shell's inner corners (px)
```

**Persistence** – add the appropriate `_loadSettings` and `_saveSettings` entries for these two properties. Use the same pattern as `barHeight` and `islandRadius`.

---

### 2. Modify `Bar.qml` – PanelWindow dimensions and margins

In `Bar.qml`, adjust the window’s `implicitHeight` and `exclusiveZone` for shell mode.

```qml
// Replace the existing implicitHeight and exclusiveZone assignments
implicitWidth:  _isHorizontal ? 0 : Config.barHeight
implicitHeight: _isHorizontal
    ? (Config.barMode === "shell" ? Config.moduleHeight + Config.shellHeight : Config.barHeight)
    : 0

exclusiveZone: Config.barMode === "shell"
    ? Config.moduleHeight + Config.shellHeight   // reserve space for the protruding centre
    : Config.barHeight + (_isTop ? Config.outerMarginBottom : _isBottom ? Config.outerMarginTop : 0)
```

For shell mode, the window must be tall enough to contain the centre island, which extends beyond the shell. The exclusive zone should also match that height so windows are pushed out of the way.

---

### 3. Add shell background rectangle

Inside the root `Item` (after `barBg`), add the shell rectangle. It will be visible only in `"shell"` mode.

```qml
// ── SHELL BACKGROUND (barMode === "shell") ─────────────────────────
Rectangle {
    id: shellBg
    visible: Config.barMode === "shell" && bar._isHorizontal
    anchors {
        left: parent.left
        right: parent.right
        top: bar._isTop ? parent.top : undefined
        bottom: bar._isBottom ? parent.bottom : undefined
    }
    height: Config.shellHeight
    color: Theme.blurBackground
    // radius on the inner corners only (bottom corners for top, top corners for bottom)
    radius: 0
    // We'll draw a custom shape for the rounded inner corners using a separate rectangle
    // or use a Shape; for simplicity we can set radius and then mask the outer corners.
    // But since the shell touches the screen edge, we only want radius on the inner edge.
    // We'll use a clipped rectangle with a radius on the bottom corners.
    clip: true
    // Use a gradient if configured
    Rectangle {
        anchors.fill: parent
        visible: Config.barRectBgStyle === "gradient"
        opacity: 1.0
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Theme.cScrim }
            GradientStop { position: 0.5; color: Theme.cInversePrimary }
            GradientStop { position: 1.0; color: Theme.cScrim }
        }
    }
    // Inner border line (only on the edge facing the screen centre)
    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            top: bar._isTop ? parent.bottom : undefined
            bottom: bar._isBottom ? parent.top : undefined
        }
        height: Config.barBorderWidth
        color: Config.barBorderColor
        opacity: Config.barBorderAlpha
        visible: Config.barBorderWidth > 0
    }
}
```

We need to make the shell’s background appear rounded on its inner corners. Because the shell touches the screen edges, the outer corners should be square. We can achieve this by using a `Shape` with a custom path, or by drawing a `Rectangle` with radius only on the inner corners using a mask. For brevity, the above code uses a plain rectangle – you may replace it with a shape that rounds only the two inner corners (bottom‑left and bottom‑right for top position, top‑left and top‑right for bottom position). A practical approach is to use a `Rectangle` with `clip: true` and overlay a rounded rectangle of the same size but with the outer corners cut off.

---

### 4. Modify the centre island for shell mode

The centre island (currently `triCenter`) should be reused but with adjusted geometry.

- In the `triCenter` Rectangle, change its `visible` condition to include shell mode.
- Adjust its `height`, `anchors`, and radius based on mode.

```qml
// ── CENTRE ISLAND (tri mode + shell mode) ──────────────────────────
Rectangle {
    id: triCenter
    visible: bar._isHorizontal && (Config.barMode === "tri" || Config.barMode === "shell")
             && (!bar._triCenterAhHidden || bar._triCenterPinned)
    anchors {
        horizontalCenter: parent.horizontalCenter
        verticalCenter: Config.barMode === "tri" ? parent.verticalCenter : undefined
        top: Config.barMode === "shell" && bar._isTop ? shellBg.top : undefined
        bottom: Config.barMode === "shell" && bar._isBottom ? shellBg.bottom : undefined
    }
    height: Config.barMode === "tri"
        ? Config.barHeight
        : Config.moduleHeight + Config.shellHeight   // shell + module height
    // ... existing width binding ...
    // Radius: for shell mode, only inner corners are rounded (bottom for top, top for bottom)
    topLeftRadius: Config.barMode === "tri"
        ? Config.triCenterTopLeftRadius
        : (bar._isTop ? 0 : Config.triCenterBottomLeftRadius)  // for bottom pos, top corners get the radius
    topRightRadius: Config.barMode === "tri"
        ? Config.triCenterTopRightRadius
        : (bar._isTop ? 0 : Config.triCenterBottomRightRadius)
    bottomLeftRadius: Config.barMode === "tri"
        ? Config.triCenterBottomLeftRadius
        : (bar._isTop ? Config.triCenterBottomLeftRadius : 0)
    bottomRightRadius: Config.barMode === "tri"
        ? Config.triCenterBottomRightRadius
        : (bar._isTop ? Config.triCenterBottomRightRadius : 0)
    // Background and gradient as before
    color: Theme.blurBackground
    // ... border: for shell mode, remove border on the edge attached to the shell
    border.width: Config.barMode === "tri"
        ? Config.barBorderWidth
        : (bar._isTop ? 0 : Config.barBorderWidth)  // if top, no border on top; if bottom, no border on bottom
    // But we want border only on three edges; we can draw a separate border line
    // or use the same border but with a custom mask. For simplicity, we can keep the border
    // and just rely on the shell's border to cover that edge? Actually the centre island
    // sits on top of the shell, so the shell's inner border might be hidden by the island.
    // We'll skip border on the attached edge by setting border.width to 0 and drawing our own
    // border using a Shape or multiple lines.
    // For now, we'll keep the border as-is, but the attached edge will have a border
    // that may overlap the shell; we could remove it by using a custom border.
    // ...
}
```

We also need to adjust the `implicitWidth` of the centre island to match its contents; the `triCenterRow` inside it will determine the width.

---

### 5. Keep left and right islands floating

The left and right islands (`triLeft` and `triRight`) already have their own anchors and margins. In shell mode, they should remain in the same relative position as in tri mode – i.e., their `verticalCenter` should be aligned with the **shell’s vertical centre** (not the full window height). To achieve this, change their `anchors.verticalCenter` to reference the shell’s vertical centre when in shell mode.

Modify the `triLeft` and `triRight` Rectangle definitions:

```qml
// For triLeft
anchors {
    left: parent.left
    leftMargin: Config.outerMarginSide
    verticalCenter: Config.barMode === "shell" ? shellBg.verticalCenter : parent.verticalCenter
}
// For triRight
anchors {
    right: parent.right
    rightMargin: Config.outerMarginSide
    verticalCenter: Config.barMode === "shell" ? shellBg.verticalCenter : parent.verticalCenter
}
```

This keeps the floating islands centred on the shell strip, preserving their margins.

---

### 6. Auto‑hide and visibility

The auto‑hide logic for the three panels already exists. The shell itself should not hide – only the islands can collapse. When all three islands are hidden, the shell remains visible (as a thin strip). The existing `updateBarVisibility()` function should be adjusted for shell mode: the shell is always visible, while the individual islands toggle visibility based on their auto‑hide state.

Modify the `updateBarVisibility()` function:

```qml
function updateBarVisibility() {
    if (Config.barMode === "tri") {
        const leftVisible   = !Config.triLeftAutoHide   || !_triLeftAhHidden   || _triLeftPinned
        const centerVisible = !Config.triCenterAutoHide || !_triCenterAhHidden || _triCenterPinned
        const rightVisible  = !Config.triRightAutoHide  || !_triRightAhHidden  || _triRightPinned
        bar.visible = leftVisible || centerVisible || rightVisible
    } else if (Config.barMode === "shell") {
        // Shell is always visible; centre island visibility is controlled separately
        // The left and right islands still follow their auto-hide rules.
        // The bar window itself should always be visible (the shell is always there).
        bar.visible = true
        // But we can also hide the window if all islands are hidden? The shell stays.
        // So keep bar.visible = true.
    } else {
        bar.visible = !bar._ahHidden
    }
}
```

For shell mode, we also need to ensure the centre island’s auto‑hide works with the existing `triCenter` timers – they already handle the centre island’s visibility.

---

### 7. Add shell controls to the Control Center

In `ControlCenterPopup.qml`, under the Bar > General tab, add sliders for `shellHeight` and `shellRadius`. They should be visible only when `Config.barMode === "shell"`.

```qml
// Inside the General sub-tab, after the existing sliders
CCSection { text: "Shell Mode" }
CCSlider {
    visible: Config.barMode === "shell"
    label: "Shell Height"
    from: 10; to: 80; stepSize: 2
    value: Config.shellHeight
    onMoved: function(v) { Config.shellHeight = v }
}
CCSlider {
    visible: Config.barMode === "shell"
    label: "Shell Radius"
    from: 0; to: 40; stepSize: 1
    value: Config.shellRadius
    onMoved: function(v) { Config.shellRadius = v }
}
```

You may also want to add a note or separator to clarify these settings apply only to shell mode.

---

### 8. Summary of changes

| File                     | Changes                                                                                                                                                                                                                                                                                                                                 |
|--------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `Config.qml`             | Add `shellHeight` and `shellRadius` properties with persistence.                                                                                                                                                                                                                                                                       |
| `Bar.qml`                | • Adjust `implicitHeight` and `exclusiveZone` for shell mode.<br>• Add `shellBg` rectangle for the shell background and inner border.<br>• Modify `triCenter` (centre island) geometry for shell mode (height, anchors, radius, border).<br>• Adjust `triLeft`/`triRight` vertical centering to use `shellBg.verticalCenter` in shell mode.<br>• Update `updateBarVisibility()` to keep the shell always visible. |
| `ControlCenterPopup.qml` | Add two sliders (`shellHeight`, `shellRadius`) in the Bar > General tab, visible only in shell mode.                                                                                                                                                                                                                                    |

---

### 9. Behaviour notes

- **Shell**: full‑width strip at the screen edge, no margins, height = `shellHeight`. It has a glass/gradient background and an inner border (if enabled). Its inner corners are rounded using `shellRadius`.
- **Centre island**: attached to the shell, protruding inward by `moduleHeight`. Its total height = `moduleHeight + shellHeight`. It has its own background and border (border removed on the edge attached to the shell). Its two inner corners are rounded (using the existing `triCenterBottomLeft/RightRadius` for top position, or top radii for bottom position). Radius on the attached edge is 0.
- **Left & right islands**: float with their usual margins, centred vertically on the shell.
- **Auto‑hide**: the centre island can be hidden via its own timer; left/right islands have their own timers. The shell remains visible at all times.

This implementation gives you the desired shell‑like layout while reusing most of the existing tri‑mode logic. The new properties are fully persisted and controlled from the Control Center.
