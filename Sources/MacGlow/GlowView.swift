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
        let palette = s.palette
        let rect = bounds
        guard rect.width > 1, rect.height > 1 else { return }

        // Breathing: eased sine so it pauses gently at the extremes.
        let breath: CGFloat = s.breathing
            ? CGFloat(sin(Double(phase) * 2 * .pi) * 0.5 + 0.5)
            : 0.5

        // Effective thickness expands with the breath.
        let base = CGFloat(s.thickness)
        let depth = CGFloat(s.breathDepth)
        let thickness = base * (1 + depth * breath)

        // Brightness swells slightly on the inhale.
        let intensity = CGFloat(s.intensity)
        let brightness = intensity * (0.78 + 0.22 * breath)

        // Render the glow as a per-pixel field into a low-res RGBA bitmap, then
        // let Core Graphics scale it up — the scaling itself adds smoothness.
        // Downscale so the longest edge is ~360px; the glow is soft enough that
        // this is imperceptible but keeps 60fps cheap.
        let scale = max(rect.width, rect.height) / 360.0
        let w = max(2, Int(rect.width / scale))
        let h = max(2, Int(rect.height / scale))
        let reach = max(1.0, thickness / scale)   // falloff distance in bitmap px

        if maskW != w || maskH != h {
            maskW = w; maskH = h
            maskBuffer = [UInt8](repeating: 0, count: w * h * 4)
        }

        // Pre-sample the palette into edge (outer) and mid RGB for interpolation.
        let stops = palette.colors.map { $0.usingColorSpace(.sRGB) ?? $0 }
        // Flatten palette into RGB arrays for fast multi-stop interpolation.
        let cR = stops.map { $0.redComponent }
        let cG = stops.map { $0.greenComponent }
        let cB = stops.map { $0.blueComponent }
        let lastStop = stops.count - 1

        maskBuffer.withUnsafeMutableBufferPointer { buf in
            for y in 0..<h {
                // distance (in px) from nearest horizontal edge
                let dyEdge = Double(min(y, h - 1 - y))
                for x in 0..<w {
                    let dxEdge = Double(min(x, w - 1 - x))
                    // Distance to nearest edge. Using min() gives a natural,
                    // rounded corner bloom (corners are near two edges).
                    let d = min(dxEdge, dyEdge)

                    // Normalized position across the falloff: 0 at edge, 1 at reach.
                    let t = min(1.0, d / reach)

                    // smoothstep for an organic, non-linear fade (soft ease-out).
                    // Full glow at the edge, tapering gently to nothing inward.
                    let e = 1.0 - (t * t * (3 - 2 * t))   // 1 at edge -> 0 at reach
                    let alpha = e * e                     // extra falloff = softer tail

                    let a = alpha * Double(brightness)
                    // Sample the full palette across the fade: edge color at the
                    // outside (t=0), last color deepest inward (t=1).
                    let scaled = t * Double(lastStop)
                    let si = min(Int(scaled), max(0, lastStop - 1))
                    let sf = scaled - Double(si)
                    let r = cR[si] + (cR[si + 1] - cR[si]) * sf
                    let g = cG[si] + (cG[si + 1] - cG[si]) * sf
                    let b = cB[si] + (cB[si + 1] - cB[si]) * sf

                    let idx = (y * w + x) * 4
                    // Premultiplied alpha.
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
        let speed = max(0.3, Settings.shared.breathSpeed)
        let phase = CGFloat((elapsed.truncatingRemainder(dividingBy: speed)) / speed)
        for w in windows { w.glowView.phase = phase }
    }
}
