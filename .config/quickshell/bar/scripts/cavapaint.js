.pragma library

// Shared cava Canvas painter.
//
// Both bar/modules/Cava.qml (live, driven by cava's per-band signal) and the
// ControlCenter style picker (static preview) call paint() with the same code
// path, so a preset always looks identical in the bar and in its thumbnail.
//
//   ctx    : a Canvas 2D context (getContext("2d"))
//   style  : one of wave|mirror|spark|area|bars|dots|dotline|spiral
//   bands  : array of normalised amplitudes 0..1, one per frequency band
//   w, h   : paint area size in px
//   o      : { c0, c1, thickness, smooth }
//            c0/c1  CSS rgba colour strings (left/right of a horizontal ramp;
//                   pass the same value for a solid stroke)
//            thickness  stroke width / dot scale (px)
//            smooth     false -> straight segments, true -> quadratic smoothing

// A lively static signal for previews (n samples, 0..1).
function test(n) {
    var a = []
    for (var i = 0; i < n; i++) {
        var x = n > 1 ? i / (n - 1) : 0
        var v = 0.55 + 0.4 * Math.sin(x * Math.PI * 3.1) * Math.cos(x * Math.PI * 1.2)
        v *= 0.7 + 0.3 * Math.sin(x * Math.PI * 7 + 0.6)
        a.push(Math.max(0.08, Math.min(1, Math.abs(v))))
    }
    return a
}

function _grad(ctx, w, o) {
    var g = ctx.createLinearGradient(0, 0, w, 0)
    g.addColorStop(0, o.c0)
    g.addColorStop(1, o.c1 || o.c0)
    return g
}

// Trace a polyline through (xs[i], ys[i]) — smoothed via quadratic segments
// through midpoints, or straight when smooth is false.
function _trace(ctx, xs, ys, smooth) {
    var n = xs.length
    ctx.moveTo(xs[0], ys[0])
    if (!smooth || n < 3) {
        for (var i = 1; i < n; i++) ctx.lineTo(xs[i], ys[i])
        return
    }
    for (var i = 1; i < n - 1; i++) {
        var xc = (xs[i] + xs[i + 1]) / 2
        var yc = (ys[i] + ys[i + 1]) / 2
        ctx.quadraticCurveTo(xs[i], ys[i], xc, yc)
    }
    ctx.lineTo(xs[n - 1], ys[n - 1])
}

function paint(ctx, style, bands, w, h, o) {
    var n = bands.length
    if (n < 2) return
    o = o || {}
    var mid   = h / 2
    var amp   = mid * 0.9
    var step  = w / (n - 1)
    var lw    = o.thickness > 0 ? o.thickness : 2
    var smooth = o.smooth !== false

    var xs = [], yTop = [], yBot = []
    for (var i = 0; i < n; i++) {
        xs.push(i * step)
        yTop.push(mid - bands[i] * amp)
        yBot.push(mid + bands[i] * amp)
    }

    var grad = _grad(ctx, w, o)
    ctx.lineWidth   = lw
    ctx.lineJoin    = "round"
    ctx.lineCap     = "round"
    ctx.strokeStyle = grad
    ctx.fillStyle   = grad

    switch (style) {
        case "mirror": {
            // symmetric envelope + translucent fill between the two curves
            ctx.beginPath()
            _trace(ctx, xs, yTop, smooth)
            for (var i = n - 1; i >= 0; i--) ctx.lineTo(xs[i], yBot[i])
            ctx.closePath()
            ctx.globalAlpha = 0.28
            ctx.fill()
            ctx.globalAlpha = 1
            ctx.beginPath(); _trace(ctx, xs, yTop, smooth); ctx.stroke()
            ctx.beginPath(); _trace(ctx, xs, yBot, smooth); ctx.stroke()
            break
        }
        case "area": {
            // filled silhouette rising from the baseline
            ctx.beginPath()
            ctx.moveTo(xs[0], h)
            for (var i = 0; i < n; i++) ctx.lineTo(xs[i], h - bands[i] * (h - lw))
            ctx.lineTo(xs[n - 1], h)
            ctx.closePath()
            ctx.globalAlpha = 0.35
            ctx.fill()
            ctx.globalAlpha = 1
            ctx.beginPath()
            ctx.moveTo(xs[0], h - bands[0] * (h - lw))
            for (var i = 1; i < n; i++) ctx.lineTo(xs[i], h - bands[i] * (h - lw))
            ctx.stroke()
            break
        }
        case "bars": {
            // vertical bars from the floor
            var bw = Math.max(1, step * 0.62)
            for (var i = 0; i < n; i++) {
                var bh = bands[i] * (h - lw)
                ctx.fillRect(xs[i] - bw / 2, h - bh, bw, bh)
            }
            break
        }
        case "dots": {
            // LED dot-matrix columns
            var rows = Math.max(3, Math.floor(h / 4))
            var dy = h / rows
            var r = Math.max(0.8, Math.min(step, dy) * 0.3)
            for (var i = 0; i < n; i++) {
                var filled = Math.round(bands[i] * rows)
                for (var j = 0; j < filled; j++) {
                    var cy = h - (j + 0.5) * dy
                    ctx.beginPath()
                    ctx.arc(xs[i], cy, r, 0, Math.PI * 2)
                    ctx.fill()
                }
            }
            break
        }
        default: {
            // centred wave line (fallback)
            ctx.beginPath(); _trace(ctx, xs, yTop, smooth); ctx.stroke()
            break
        }
    }
}
