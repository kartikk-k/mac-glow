import Cocoa

// MARK: - Full-screen edge glow view
//
// Paints a gradient band that hugs the outer edge of the screen and fades
// inward to transparent. A breathing phase (0...1) drives expansion + brightness.

final class GlowView: NSView {
    var phase: CGFloat = 0 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var wantsUpdateLayer: Bool { false }

    // Reused low-res bitmap for the glow field (soft, so low res is invisible).
    private var maskBuffer: [UInt8] = []
    private var maskW = 0
    private var maskH = 0

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let s = Settings.shared
        let mode = s.mode
        let rect = bounds
        guard rect.width > 1, rect.height > 1 else { return }

        // A mode may force its own palette (e.g. Thinking = Aurora); otherwise
        // use the user's chosen palette.
        let palette = mode.colorOverride.map { Palettes.palette(named: $0) } ?? s.palette

        // A global "envelope" (0...1) drives whole-frame swell for the modes that
        // pulse the entire glow together: Breathing (smooth sine) and Heartbeat
        // (organic double-thump). Positional modes leave it at a steady mid value.
        let phD = Double(phase)
        var envelope = 0.5
        switch mode.motion {
        case .pulse:
            envelope = sin(phD * 2 * .pi) * 0.5 + 0.5
        case .heartbeat:
            envelope = heartbeatEnvelope(phD)
        default:
            envelope = 0.5
        }
        let env = CGFloat(s.breathing || mode.motion != .pulse ? envelope : 0.5)

        // Effective thickness expands with the envelope for pulse/heartbeat.
        let base = CGFloat(s.thickness)
        let depth = CGFloat(s.breathDepth) * CGFloat(mode.depth)
        let swells = (mode.motion == .pulse || mode.motion == .heartbeat)
        let thickness: CGFloat = swells ? base * (1 + depth * env) : base

        // Brightness swells with the envelope for pulse/heartbeat too.
        let intensity = CGFloat(s.intensity) * CGFloat(mode.intensityScale)
        let envBright = swells ? (0.72 + 0.28 * env) : 1.0
        let brightness = intensity * envBright

        // Render the glow as a per-pixel field into a low-res RGBA bitmap, then
        // let Core Graphics scale it up — the scaling itself adds smoothness.
        let scale = max(rect.width, rect.height) / 360.0
        let w = max(2, Int(rect.width / scale))
        let h = max(2, Int(rect.height / scale))
        let reach = max(1.0, thickness / scale)   // falloff distance in bitmap px

        if maskW != w || maskH != h {
            maskW = w; maskH = h
            maskBuffer = [UInt8](repeating: 0, count: w * h * 4)
        }

        // Flatten palette into RGB arrays for fast multi-stop interpolation.
        let stops = palette.colors.map { $0.usingColorSpace(.sRGB) ?? $0 }
        let cR = stops.map { $0.redComponent }
        let cG = stops.map { $0.greenComponent }
        let cB = stops.map { $0.blueComponent }
        let lastStop = stops.count - 1

        let motion = mode.motion
        let ph = phD                           // 0...1 per cycle

        maskBuffer.withUnsafeMutableBufferPointer { buf in
            for y in 0..<h {
                let dyEdge = Double(min(y, h - 1 - y))
                for x in 0..<w {
                    let dxEdge = Double(min(x, w - 1 - x))

                    // --- Corner-seam-free falloff ---
                    // Instead of a hard min() (which creases along the 45° line),
                    // fade each axis independently and combine with a "screen"
                    // blend. Corners then bloom smoothly with no visible seam.
                    let tx = min(1.0, dxEdge / reach)
                    let ty = min(1.0, dyEdge / reach)
                    let ex = falloff(tx)
                    let ey = falloff(ty)
                    var alpha = ex + ey - ex * ey    // screen blend of the two edges

                    // Distance used for color sampling (nearest edge still fine here).
                    let t = min(tx, ty)

                    // Perimeter position measured by arc length so a comet travels
                    // at constant visual speed on every edge (atan2 alone would
                    // speed up on the short edges). peri is 0..1 clockwise from
                    // the top-left, weighted by the actual edge lengths.
                    let peri = perimeterPosition(x: x, y: y, w: w, h: h)

                    // Extra color offset for the drift mode (set below).
                    var colorShift = 0.0

                    // --- Motion modulation ---
                    // Each mode has a DISTINCT, calmly-timed motion signature.
                    switch motion {
                    case .pulse, .heartbeat:
                        break // whole-frame envelope handled above

                    case .comet:
                        // The winner: one bright comet glides around with a long,
                        // soft tail. Slow `speed` keeps it calm, not frantic.
                        alpha *= cometGlow(peri: peri, head: ph,
                                           headSharp: 55, tailLen: 4.0,
                                           floor: 0.26, tailWeight: 0.6)

                    case .dualComet:
                        // Two comets chasing on opposite sides of the frame.
                        let g1 = cometGlow(peri: peri, head: ph,
                                           headSharp: 55, tailLen: 4.0,
                                           floor: 0.0, tailWeight: 0.55)
                        let g2 = cometGlow(peri: peri, head: ph + 0.5,
                                           headSharp: 55, tailLen: 4.0,
                                           floor: 0.0, tailWeight: 0.55)
                        alpha *= (0.22 + max(g1, g2))

                    case .drift:
                        // Aurora: the light slowly breathes in soft, wide lobes
                        // that drift around the frame, and the color itself shifts.
                        let lobe = 0.5 + 0.5 * sin((peri * 2 - ph) * 2 * .pi)
                        let lobe2 = 0.5 + 0.5 * sin((peri * 3 + ph) * 2 * .pi)
                        alpha *= (0.45 + 0.55 * (lobe * 0.6 + lobe2 * 0.4))
                        colorShift = 0.5 + 0.5 * sin((peri - ph) * 2 * .pi)

                    case .scanner:
                        // A soft, wide bar sweeps calmly around the perimeter —
                        // symmetric (no tail), like a gentle radar.
                        var d = abs(peri - ph)
                        d = min(d, 1 - d)                                // wrap
                        let bar = exp(-d * d * 30)                       // soft wide bar
                        alpha *= (0.30 + 0.95 * bar)
                    }

                    let a = alpha * Double(brightness)

                    // Sample the palette across the fade (plus any drift offset).
                    let tc = min(1.0, t + colorShift * 0.6)
                    let scaled = tc * Double(lastStop)
                    let si = min(Int(scaled), max(0, lastStop - 1))
                    let sf = scaled - Double(si)
                    let r = cR[si] + (cR[si + 1] - cR[si]) * sf
                    let g = cG[si] + (cG[si + 1] - cG[si]) * sf
                    let b = cB[si] + (cB[si + 1] - cB[si]) * sf

                    let idx = (y * w + x) * 4
                    buf[idx + 0] = UInt8(max(0, min(255, r * a * 255)))
                    buf[idx + 1] = UInt8(max(0, min(255, g * a * 255)))
                    buf[idx + 2] = UInt8(max(0, min(255, b * a * 255)))
                    buf[idx + 3] = UInt8(max(0, min(255, a * 255)))
                }
            }
        }

        let space = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(maskBuffer) as CFData),
              let image = CGImage(
                width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: w * 4, space: space, bitmapInfo: bitmapInfo,
                provider: provider, decode: nil, shouldInterpolate: true,
                intent: .defaultIntent) else { return }

        ctx.interpolationQuality = .high
        ctx.draw(image, in: rect)
    }

    // Per-axis edge falloff: 1 at the edge (t=0) easing to 0 at reach (t=1).
    // smoothstep squared gives a natural, soft tail.
    @inline(__always)
    private func falloff(_ t: Double) -> Double {
        let e = 1.0 - (t * t * (3 - 2 * t))
        return e * e
    }

    // A comet: a bright head at `head` with a soft trailing tail, wrapping the
    // perimeter. Returns a 0..~1.6 glow factor (floor + head + tail).
    @inline(__always)
    private func cometGlow(peri: Double, head: Double, headSharp: Double,
                           tailLen: Double, floor: Double, tailWeight: Double) -> Double {
        var delta = abs(peri - head.truncatingRemainder(dividingBy: 1))
        delta = min(delta, 1 - delta)                       // wrap-around distance
        let headGlow = exp(-delta * delta * headSharp)      // bright, tight head
        // Trailing tail: measure how far `peri` lags *behind* the head.
        var lag = head.truncatingRemainder(dividingBy: 1) - peri
        if lag < 0 { lag += 1 }
        let tail = exp(-lag * tailLen) * tailWeight
        return floor + headGlow + tail
    }

    // Organic heartbeat envelope over one cycle (0..1): a strong "lub", a quick
    // softer "dub", then rest. Reads as alive, distinct from a smooth breath.
    @inline(__always)
    private func heartbeatEnvelope(_ p: Double) -> Double {
        func thump(_ x: Double, _ center: Double, _ width: Double) -> Double {
            let d = (x - center) / width
            return exp(-d * d)
        }
        let lub = thump(p, 0.10, 0.05)          // first, strongest beat
        let dub = thump(p, 0.28, 0.06) * 0.7    // second, softer beat
        return min(1.0, lub + dub)              // long quiet rest fills the remainder
    }

    // Perimeter position 0..1, measured by arc length (so travel speed is
    // constant on every edge). Walks clockwise from the top-left corner.
    @inline(__always)
    // Map a pixel to a continuous 0..1 position around the rectangle perimeter
    // by casting a ray from the center through the pixel and finding where it
    // exits the rectangle, then measuring that exit point's arc length. This is
    // continuous everywhere (no corner snap → no wedge artifact) and travels at
    // roughly constant visual speed along each edge.
    private func perimeterPosition(x: Int, y: Int, w: Int, h: Int) -> Double {
        let W = Double(w - 1), H = Double(h - 1)
        let cx = W / 2, cy = H / 2
        var dx = Double(x) - cx
        var dy = Double(y) - cy
        if dx == 0 && dy == 0 { dx = 1e-6 }

        // Find t so the ray (cx,cy)+t*(dx,dy) hits the rectangle border.
        let tx = dx != 0 ? cx / abs(dx) : .greatestFiniteMagnitude
        let ty = dy != 0 ? cy / abs(dy) : .greatestFiniteMagnitude
        let t = min(tx, ty)
        let ex = cx + dx * t          // exit point on the border
        let ey = cy + dy * t

        // Arc length of the exit point, walking clockwise from the top-left.
        let perim = 2 * (W + H)
        let eps = 0.5
        var s: Double
        if ey <= eps {                // top edge: left→right
            s = ex
        } else if ex >= W - eps {     // right edge: top→bottom
            s = W + ey
        } else if ey >= H - eps {     // bottom edge: right→left
            s = W + H + (W - ex)
        } else {                      // left edge: bottom→top
            s = 2 * W + H + (H - ey)
        }
        return (s / perim).truncatingRemainder(dividingBy: 1)
    }
}

// MARK: - One overlay window per screen

final class GlowWindow: NSWindow {
    let glowView = GlowView()

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .init(Int(CGShieldingWindowLevel()))    // above normal windows
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        setFrame(screen.frame, display: true)
        contentView = glowView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Manager: one window per screen, a breathing animation loop

final class GlowManager {
    private var windows: [GlowWindow] = []
    private var timer: Timer?
    private var startDate: TimeInterval = 0
    private var elapsed: TimeInterval = 0
    private(set) var isEnabled = false

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh),
            name: Settings.didChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuildScreens),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            rebuildScreens()
            startLoop()
        } else {
            stopLoop()
            windows.forEach { $0.orderOut(nil) }
            windows.removeAll()
        }
    }

    @objc private func rebuildScreens() {
        guard isEnabled else { return }
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { screen in
            let w = GlowWindow(screen: screen)
            w.orderFront(nil)
            return w
        }
    }

    @objc private func refresh() {
        windows.forEach { $0.glowView.needsDisplay = true }
    }

    private func startLoop() {
        elapsed = 0
        timer?.invalidate()
        // ~60fps breathing animation.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
    }

    private func stopLoop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        elapsed += 1.0 / 60.0
        let s = Settings.shared
        let mode = s.mode
        // Breathing (pulse) respects the user's Breath speed slider; every other
        // mode uses its own calmly-tuned speed.
        let speed: Double = (mode.motion == .pulse)
            ? max(0.3, s.breathSpeed)
            : max(0.3, mode.speed)
        let phase = CGFloat((elapsed.truncatingRemainder(dividingBy: speed)) / speed)
        for w in windows { w.glowView.phase = phase }
    }
}
