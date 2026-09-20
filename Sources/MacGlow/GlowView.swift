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

        // Breathing phase for pulse/steady modes: eased sine (gentle at extremes).
        let breath: CGFloat = s.breathing
            ? CGFloat(sin(Double(phase) * 2 * .pi) * 0.5 + 0.5)
            : 0.5

        // Effective thickness expands with the breath (only for pulse motion).
        let base = CGFloat(s.thickness)
        let depth = CGFloat(s.breathDepth) * CGFloat(mode.depth)
        let thickness: CGFloat = (mode.motion == .pulse)
            ? base * (1 + depth * breath)
            : base

        // Brightness swells slightly on the inhale for pulse modes.
        let intensity = CGFloat(s.intensity) * CGFloat(mode.intensityScale)
        let pulseBright = (mode.motion == .pulse) ? (0.78 + 0.22 * breath) : 1.0
        let brightness = intensity * pulseBright

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
        let ph = Double(phase)                 // 0...1 per cycle
        let wD = Double(w - 1), hD = Double(h - 1)
        let cx = wD / 2, cy = hD / 2

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

                    // Perimeter position 0...1 (used by orbit/ripple/flicker).
                    // atan2 gives angle; map to a clockwise 0..1 starting at top.
                    let ang = atan2(Double(y) - cy, Double(x) - cx)
                    let peri = (ang / (2 * .pi)) + 0.5                    // 0...1

                    // --- Motion modulation ---
                    // Each mode has a DISTINCT motion signature, independent of color.
                    switch motion {
                    case .pulse, .steady:
                        break // handled via thickness/brightness already

                    case .flicker:
                        // "Listening": fast, tight audio-meter shimmer. Layered
                        // sines at different frequencies fake a live waveform that
                        // dances along the edges without expanding.
                        let p = ph * 2 * .pi
                        let s1 = sin(peri * 22 + p * 3)
                        let s2 = sin(peri * 47 - p * 5)
                        let s3 = sin(peri * 9  + p * 2)
                        let wave = (s1 * 0.5 + s2 * 0.3 + s3 * 0.2)       // -1...1
                        alpha *= (0.55 + 0.45 * (wave * 0.5 + 0.5))

                    case .orbit:
                        // "Thinking": a bright comet races around the perimeter,
                        // with a fading tail — reads as active processing.
                        var delta = abs(peri - ph)
                        delta = min(delta, 1 - delta)                     // wrap
                        let head = exp(-delta * delta * 90)               // tight head
                        var tail = ph - peri
                        if tail < 0 { tail += 1 }
                        let trail = exp(-tail * 6) * 0.55                 // trailing glow
                        // Keep a soft ambient floor so the frame stays present.
                        alpha *= (0.28 + 1.0 * head + trail)

                    case .ripple:
                        // "Speaking": waves radiate from the top-center down both
                        // sides, like sound emanating outward.
                        var d = abs(peri - 0.0)                          // dist from top
                        d = min(d, 1 - d)                                // 0 at top, .5 bottom
                        let wave = 0.5 + 0.5 * sin(d * 14 - ph * 2 * .pi)
                        alpha *= (0.4 + 0.6 * wave)
                    }

                    let a = alpha * Double(brightness)

                    // Sample the palette across the fade.
                    let scaled = t * Double(lastStop)
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
        // Pulse/steady use the user's breath speed; motion modes use the mode's.
        let speed: Double = (mode.motion == .pulse || mode.motion == .steady)
            ? max(0.3, s.breathSpeed)
            : max(0.3, mode.speed)
        let phase = CGFloat((elapsed.truncatingRemainder(dividingBy: speed)) / speed)
        for w in windows { w.glowView.phase = phase }
    }
}
