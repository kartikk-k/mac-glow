import Cocoa

// MARK: - Full-screen edge glow view (mode-driven)
//
// Paints a per-pixel glow field. The active GlowRenderer decides how each pixel
// behaves; this view supplies the shared machinery: edge falloff, palette
// sampling, and a continuous perimeter coordinate.

final class GlowView: NSView {
    // Advanced by the manager each frame.
    var clock: Double = 0 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // Reused low-res bitmap (the glow is soft, so low res is invisible).
    private var maskBuffer: [UInt8] = []
    private var maskW = 0
    private var maskH = 0

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let s = Settings.shared
        let mode = s.renderer
        let rect = bounds
        guard rect.width > 1, rect.height > 1 else { return }

        // Notch mode needs its rect in view space, refreshed each frame.
        if let notch = mode as? NotchMode {
            if let scr = window?.screen {
                notch.notchRect = Notch.rect(for: scr, viewSize: rect.size)
                notch.hasReal = Notch.hasRealNotch(scr)
            }
            notch.viewSize = rect.size
        }

        // Palette (mode may override).
        let palette = mode.colorOverride.map { Palettes.palette(named: $0) } ?? s.palette

        // Whole-frame envelope (breathing swell, audio swell, etc.).
        let env = mode.envelope(clock: clock)
        let base = CGFloat(s.thickness)
        let depth = CGFloat(s.breathDepth)
        let thickness = base * CGFloat(env.thickness) * (s.breathing ? 1 : 1)
        let intensity = CGFloat(s.intensity)
        let brightness = intensity * CGFloat(env.brightness)

        // Low-res bitmap sizing.
        let scale = max(rect.width, rect.height) / 360.0
        let w = max(2, Int(rect.width / scale))
        let h = max(2, Int(rect.height / scale))
        let reach = max(1.0, thickness / scale)

        if maskW != w || maskH != h {
            maskW = w; maskH = h
            maskBuffer = [UInt8](repeating: 0, count: w * h * 4)
        }

        // Palette RGB arrays.
        let stops = palette.colors.map { $0.usingColorSpace(.sRGB) ?? $0 }
        let cR = stops.map { $0.redComponent }
        let cG = stops.map { $0.greenComponent }
        let cB = stops.map { $0.blueComponent }
        let lastStop = stops.count - 1

        let wholeScreen = mode.paintsWholeScreen
        let clk = clock

        maskBuffer.withUnsafeMutableBufferPointer { buf in
            for y in 0..<h {
                let dyEdge = Double(min(y, h - 1 - y))
                let ny = Double(y) / Double(h - 1)
                for x in 0..<w {
                    let dxEdge = Double(min(x, w - 1 - x))
                    let nx = Double(x) / Double(w - 1)

                    // Seam-free edge falloff (screen blend of the two axes).
                    let tx = min(1.0, dxEdge / reach)
                    let ty = min(1.0, dyEdge / reach)
                    let ex = falloff(tx)
                    let ey = falloff(ty)
                    let edgeAlpha = ex + ey - ex * ey
                    let t = min(tx, ty)

                    let peri = perimeterPosition(x: x, y: y, w: w, h: h)

                    let sample = GlowSample(peri: peri, edgeAlpha: edgeAlpha,
                                            t: t, nx: nx, ny: ny)
                    let out = mode.output(sample, clock: clk)

                    let a: Double
                    if wholeScreen {
                        a = out.alpha * Double(brightness)
                    } else {
                        a = edgeAlpha * out.alpha * Double(brightness)
                    }

                    // Palette sample (+ optional per-pixel color shift).
                    let tc = min(1.0, t + out.colorShift * 0.6)
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
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(maskBuffer) as CFData),
              let image = CGImage(
                width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: w * 4, space: space, bitmapInfo: bitmapInfo,
                provider: provider, decode: nil, shouldInterpolate: true,
                intent: .defaultIntent) else { return }

        ctx.interpolationQuality = .high
        ctx.draw(image, in: rect)
    }

    @inline(__always)
    private func falloff(_ t: Double) -> Double {
        let e = 1.0 - (t * t * (3 - 2 * t))
        return e * e
    }

    // Continuous 0..1 perimeter position (ray-cast from center → no corner seam).
    @inline(__always)
    private func perimeterPosition(x: Int, y: Int, w: Int, h: Int) -> Double {
        let W = Double(w - 1), H = Double(h - 1)
        let cx = W / 2, cy = H / 2
        var dx = Double(x) - cx
        var dy = Double(y) - cy
        if dx == 0 && dy == 0 { dx = 1e-6 }
        let tx = dx != 0 ? cx / abs(dx) : .greatestFiniteMagnitude
        let ty = dy != 0 ? cy / abs(dy) : .greatestFiniteMagnitude
        let t = min(tx, ty)
        let ex = cx + dx * t
        let ey = cy + dy * t
        let perim = 2 * (W + H)
        let eps = 0.5
        var sPos: Double
        if ey <= eps {                 // top: left→right
            sPos = ex
        } else if ex >= W - eps {      // right: top→bottom
            sPos = W + ey
        } else if ey >= H - eps {      // bottom: right→left
            sPos = W + H + (W - ex)
        } else {                       // left: bottom→top
            sPos = 2 * W + H + (H - ey)
        }
        return (sPos / perim).truncatingRemainder(dividingBy: 1)
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
        level = .init(Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        setFrame(screen.frame, display: true)
        contentView = glowView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Manager: one window per screen + a shared animation clock

final class GlowManager {
    private var windows: [GlowWindow] = []
    private var timer: Timer?
    private var clock: Double = 0
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
        clock = 0
        timer?.invalidate()
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
        let dt = 1.0 / 60.0
        clock += dt
        // Advance the active mode's animation state, then redraw.
        Settings.shared.renderer.update(dt: dt, clock: clock)
        for w in windows { w.glowView.clock = clock }
    }
}
