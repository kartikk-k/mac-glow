import Cocoa
import QuartzCore

// MARK: - Scene-based modes (GPU-animated, ~0% CPU)
//
// Each mode builds CALayers + CAAnimations once. The render server animates them;
// we don't push pixels per frame. Only truly live modes (audio) tick a property.

enum SceneModes {
    static let all: [GlowSceneMode] = [
        BreathingSceneMode(),
        ScannerSceneMode(),
        NotificationSceneMode(),
        FocusSceneMode(),
        AudioSceneMode(),
        FlowSceneMode(),
        AssistantSceneMode(),
        PushToTalkSceneMode(),
        ConfirmationSceneMode(),
        NotchSceneMode()
    ]
}

// Shared helper: add a repeating, autoreversing opacity/scale pulse to a layer.
private func addPulse(to layer: CALayer, duration: Double, minOpacity: Float,
                      maxOpacity: Float, scale: Double) {
    let op = CABasicAnimation(keyPath: "opacity")
    op.fromValue = minOpacity; op.toValue = maxOpacity
    op.duration = duration
    op.autoreverses = true
    op.repeatCount = .infinity
    op.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(op, forKey: "pulseOpacity")

    if scale > 0 {
        let sc = CABasicAnimation(keyPath: "transform.scale")
        sc.fromValue = 1.0; sc.toValue = 1.0 + scale
        sc.duration = duration
        sc.autoreverses = true
        sc.repeatCount = .infinity
        sc.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(sc, forKey: "pulseScale")
    }
}

// Move a sprite layer around the perimeter path forever.
private func addPathTravel(to layer: CALayer, path: CGPath, duration: Double) {
    let a = CAKeyframeAnimation(keyPath: "position")
    a.path = path
    a.duration = duration
    a.repeatCount = .infinity
    a.calculationMode = .paced
    a.rotationMode = nil
    a.isRemovedOnCompletion = false
    layer.add(a, forKey: "travel")
}

// MARK: Breathing

final class BreathingSceneMode: GlowSceneMode {
    let id = "breathing", name = "Breathing", symbol = "wind"
    private let store = ModeStore("breathing")
    func build(_ scene: GlowScene) {
        let frame = scene.makeEdgeFrameLayer()
        scene.root.addSublayer(frame)
        let speed = store.double("speed", 5.0)
        let depth = store.double("depth", 0.10)
        addPulse(to: frame, duration: speed,
                 minOpacity: Float(scene.intensity) * 0.72,
                 maxOpacity: Float(scene.intensity),
                 scale: depth * 0.06)
    }
    func controls() -> [ModeControl] {
        [.label("A calm, symmetric swell — the idle resting state."),
         .slider(key: "speed", title: "Breath speed", min: 1, max: 15, def: 5.0,
                 format: { String(format: "%.1f s", $0) }),
         .slider(key: "depth", title: "Depth", min: 0, max: 1, def: 0.10,
                 format: { String(format: "%.0f%%", $0 * 100) })]
    }
}

// MARK: Scanner — a soft highlight glides around the edge over the ambient frame

final class ScannerSceneMode: GlowSceneMode {
    let id = "scanner", name = "Scanner", symbol = "dot.radiowaves.left.and.right"
    private let store = ModeStore("scanner")
    func build(_ scene: GlowScene) {
        // Faint ambient frame beneath.
        let frame = scene.makeEdgeFrameLayer()
        frame.opacity = Float(scene.intensity) * Float(store.double("floor", 0.30))
        scene.root.addSublayer(frame)

        // Traveling highlight, clipped to the edge band (never a floating orb).
        let dia = max(scene.size.width, scene.size.height) * store.double("width", 0.12) * 1.6
        let blob = scene.addEdgeHighlight(diameter: dia, color: scene.palette.keyColor, at: nil)
        blob.opacity = Float(scene.intensity)
        addPathTravel(to: blob, path: scene.perimeterPath(),
                      duration: store.double("speed", 6.0))
    }
    func controls() -> [ModeControl] {
        [.label("A soft bar sweeps calmly around the edge — the refined idea."),
         .slider(key: "speed", title: "Sweep speed", min: 2, max: 20, def: 6.0,
                 format: { String(format: "%.1f s / lap", $0) }),
         .slider(key: "width", title: "Highlight size", min: 0.05, max: 0.3, def: 0.12,
                 format: { String(format: "%.0f%%", $0 * 100) }),
         .slider(key: "floor", title: "Ambient floor", min: 0, max: 0.7, def: 0.30,
                 format: { String(format: "%.0f%%", $0 * 100) })]
    }
}

// MARK: Notification — a bloom on the nearest edge (positioned along perimeter)

final class NotificationSceneMode: GlowSceneMode {
    let id = "notification", name = "Notification", symbol = "bell.badge"
    private let store = ModeStore("notification")
    private weak var scene: GlowScene?

    func build(_ scene: GlowScene) {
        self.scene = scene
        let frame = scene.makeEdgeFrameLayer()
        frame.opacity = Float(scene.intensity) * Float(store.double("floor", 0.10))
        scene.root.addSublayer(frame)
    }

    // Fire a transient bloom at a named corner (0=TR,1=BR,2=BL,3=TL).
    func fire(corner: Int) {
        guard let scene else { return }
        let pt = scene.cornerPoint(corner)
        let dia = max(scene.size.width, scene.size.height) * store.double("spread", 0.12) * 2.4
        let blob = scene.addEdgeHighlight(diameter: dia, color: scene.palette.keyColor, at: pt)
        blob.opacity = 0

        let ttl = store.double("linger", 2.5)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, Float(scene.intensity) * 1.2, 0]
        fade.keyTimes = [0, 0.12, 1]
        fade.duration = ttl
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.isRemovedOnCompletion = true
        blob.add(fade, forKey: "bloom")
        DispatchQueue.main.asyncAfter(deadline: .now() + ttl) { [weak blob] in
            blob?.superlayer?.removeFromSuperlayer()   // remove the masked container
        }
    }

    func controls() -> [ModeControl] {
        [.label("A bloom appears on the edge nearest where an alert came from."),
         .slider(key: "spread", title: "Bloom size", min: 0.04, max: 0.3, def: 0.12,
                 format: { String(format: "%.0f%%", $0 * 100) }),
         .slider(key: "linger", title: "Linger", min: 0.5, max: 6, def: 2.5,
                 format: { String(format: "%.1f s", $0) }),
         .slider(key: "floor", title: "Ambient floor", min: 0, max: 0.4, def: 0.10,
                 format: { String(format: "%.0f%%", $0 * 100) }),
         .button(title: "Fire ▲ top-right", action: { [weak self] in self?.fire(corner: 0) }),
         .button(title: "Fire ▼ bottom-right", action: { [weak self] in self?.fire(corner: 1) }),
         .button(title: "Fire ▼ bottom-left", action: { [weak self] in self?.fire(corner: 2) }),
         .button(title: "Fire ▲ top-left", action: { [weak self] in self?.fire(corner: 3) })]
    }
}

// MARK: Focus corner — a static bloom gathered at a corner

final class FocusSceneMode: GlowSceneMode {
    let id = "focus", name = "Focus Corner", symbol = "scope"
    private let store = ModeStore("focus")
    func build(_ scene: GlowScene) {
        let frame = scene.makeEdgeFrameLayer()
        frame.opacity = Float(scene.intensity) * Float(store.double("floor", 0.06))
        scene.root.addSublayer(frame)

        let idx = min(3, max(0, Int(store.double("corner", 0))))
        let pt = scene.cornerPoint(idx)
        let dia = max(scene.size.width, scene.size.height) * store.double("width", 0.22) * 2.4
        let blob = scene.addEdgeHighlight(diameter: dia, color: scene.palette.keyColor, at: pt)
        blob.opacity = Float(scene.intensity)
    }
    func controls() -> [ModeControl] {
        [.label("The glow gathers toward a corner to pull your eye there."),
         .popup(key: "corner", title: "Corner",
                options: ["Top-right", "Bottom-right", "Bottom-left", "Top-left"], def: 0),
         .slider(key: "width", title: "Concentration", min: 0.08, max: 0.4, def: 0.22,
                 format: { String(format: "%.0f%%", $0 * 100) }),
         .slider(key: "floor", title: "Rest of frame", min: 0, max: 0.4, def: 0.06,
                 format: { String(format: "%.0f%%", $0 * 100) })]
    }
}

// MARK: Audio reactive — the one live mode; scales the frame to audio level

final class AudioSceneMode: GlowSceneMode {
    let id = "audio", name = "Audio Reactive", symbol = "waveform.circle"
    private let store = ModeStore("audio")
    private weak var frame: CALayer?

    func build(_ scene: GlowScene) {
        let f = scene.makeEdgeFrameLayer()
        f.opacity = Float(scene.intensity) * 0.35
        scene.root.addSublayer(f)
        frame = f
        if !store.bool("simulate", true) { AudioLevel.shared.startMic() }
    }
    func needsLiveTick() -> Bool { true }
    func liveTick(_ scene: GlowScene, dt: Double) {
        let sim = store.bool("simulate", true)
        if !sim { AudioLevel.shared.startMic() }
        AudioLevel.shared.tick(dt: dt, simulate: sim)
        let lvl = AudioLevel.shared.level
        let react = store.double("react", 0.8)
        guard let frame else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame.opacity = Float(scene.intensity) * Float(0.35 + lvl * (0.4 + react * 0.5))
        let s = 1 + lvl * react * 0.05
        frame.transform = CATransform3DMakeScale(CGFloat(s), CGFloat(s), 1)
        CATransaction.commit()
    }
    func controls() -> [ModeControl] {
        [.label(AudioLevel.shared.micActive ? "Reacting to your microphone." :
                    "Enable the mic, or turn on Simulate to preview."),
         .toggle(key: "simulate", title: "Simulate audio (no mic)", def: false),
         .slider(key: "react", title: "Reactivity", min: 0.1, max: 1.5, def: 0.8,
                 format: { String(format: "%.0f%%", $0 / 1.5 * 100) })]
    }
}

// MARK: Flow — warm bottom-weighted glow that pulses gently (typing metaphor)

final class FlowSceneMode: GlowSceneMode {
    let id = "flow", name = "Flow", symbol = "keyboard"
    private let store = ModeStore("flow")
    var colorOverride: String? { "Sunset" }
    func build(_ scene: GlowScene) {
        let frame = scene.makeEdgeFrameLayer()
        // Bias brightness toward the bottom with a gradient mask.
        let grad = CAGradientLayer()
        grad.frame = scene.root.bounds
        grad.colors = [NSColor(white: 1, alpha: 1).cgColor, NSColor(white: 1, alpha: 0.35).cgColor]
        grad.startPoint = CGPoint(x: 0.5, y: 1)   // bottom (flipped view: y=1 bottom)
        grad.endPoint = CGPoint(x: 0.5, y: 0)
        frame.mask = grad
        scene.root.addSublayer(frame)
        addPulse(to: frame, duration: 3.5,
                 minOpacity: Float(scene.intensity) * 0.7,
                 maxOpacity: Float(scene.intensity), scale: 0)
    }
    func controls() -> [ModeControl] {
        [.label("A warm, bottom-weighted glow — a calm 'in flow' presence.")]
    }
}

// MARK: Assistant — idle / working / needs, each a distinct scene

final class AssistantSceneMode: GlowSceneMode {
    let id = "assistant", name = "Assistant", symbol = "sparkles"
    private let store = ModeStore("assistant")
    func build(_ scene: GlowScene) {
        let state = Int(store.double("state", 0))
        switch state {
        case 1: // working — traveling highlight
            let frame = scene.makeEdgeFrameLayer(); frame.opacity = Float(scene.intensity) * 0.3
            scene.root.addSublayer(frame)
            let dia = max(scene.size.width, scene.size.height) * 0.20
            let blob = scene.addEdgeHighlight(diameter: dia, color: scene.palette.keyColor, at: nil)
            blob.opacity = Float(scene.intensity)
            addPathTravel(to: blob, path: scene.perimeterPath(), duration: 3.0)
        case 2: // needs you — calm attention pulses
            let frame = scene.makeEdgeFrameLayer()
            scene.root.addSublayer(frame)
            let a = CAKeyframeAnimation(keyPath: "opacity")
            a.values = [Float(scene.intensity)*0.4, Float(scene.intensity), Float(scene.intensity)*0.4,
                        Float(scene.intensity), Float(scene.intensity)*0.4]
            a.keyTimes = [0, 0.1, 0.25, 0.35, 1]
            a.duration = 2.2; a.repeatCount = .infinity
            frame.add(a, forKey: "attn")
        default: // idle — breathe
            let frame = scene.makeEdgeFrameLayer()
            scene.root.addSublayer(frame)
            addPulse(to: frame, duration: 5.0,
                     minOpacity: Float(scene.intensity)*0.6,
                     maxOpacity: Float(scene.intensity), scale: 0.04)
        }
    }
    var colorOverride: String? {
        Int(store.double("state", 0)) == 2 ? "Sunset" : nil
    }
    func controls() -> [ModeControl] {
        [.label("Three honest states an assistant would actually need."),
         .popup(key: "state", title: "State", options: ["Idle", "Working", "Needs you"], def: 0),
         .label("idle = breath · working = sweep · needs = attention pulses")]
    }
}

// MARK: Push to talk — hold to listen (audio), release to think, then settle

final class PushToTalkSceneMode: GlowSceneMode {
    let id = "ptt", name = "Push to Talk", symbol = "mic.circle"
    private let store = ModeStore("ptt")
    private weak var scene: GlowScene?
    private weak var frame: CALayer?
    private var listening = false

    func build(_ scene: GlowScene) {
        self.scene = scene
        let f = scene.makeEdgeFrameLayer()
        f.opacity = Float(scene.intensity) * 0.4
        scene.root.addSublayer(f)
        frame = f
        addPulse(to: f, duration: 5.0,
                 minOpacity: Float(scene.intensity)*0.3,
                 maxOpacity: Float(scene.intensity)*0.55, scale: 0)
    }
    func needsLiveTick() -> Bool { listening }
    func liveTick(_ scene: GlowScene, dt: Double) {
        AudioLevel.shared.tick(dt: dt, simulate: store.bool("simulate", true))
        guard let frame else { return }
        let lvl = AudioLevel.shared.level
        CATransaction.begin(); CATransaction.setDisableActions(true)
        frame.opacity = Float(scene.intensity) * Float(0.5 + lvl * 0.5)
        CATransaction.commit()
    }
    func hold() {
        listening = true
        frame?.removeAnimation(forKey: "pulseOpacity")
        if !store.bool("simulate", true) { AudioLevel.shared.startMic() }
        store.poke()   // wake the live timer
    }
    func release() {
        listening = false
        guard let scene, let frame else { return }
        // Think: a quick sweep, then settle back to idle pulse.
        let dia = max(scene.size.width, scene.size.height) * 0.20
        let blob = scene.addEdgeHighlight(diameter: dia, color: scene.palette.keyColor, at: nil)
        blob.opacity = Float(scene.intensity)
        addPathTravel(to: blob, path: scene.perimeterPath(),
                      duration: store.double("thinkTime", 1.6))
        let think = store.double("thinkTime", 1.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + think) { [weak self, weak blob] in
            blob?.superlayer?.removeFromSuperlayer()
            if let f = self?.frame {
                addPulse(to: f, duration: 5.0,
                         minOpacity: Float((self?.scene?.intensity ?? 1))*0.3,
                         maxOpacity: Float((self?.scene?.intensity ?? 1))*0.55, scale: 0)
            }
            self?.store.poke()
        }
    }
    var colorOverride: String? { "Aurora" }
    func controls() -> [ModeControl] {
        [.label("Hold to listen, release to think, then it settles."),
         .toggle(key: "simulate", title: "Simulate audio (no mic)", def: false),
         .slider(key: "thinkTime", title: "Think duration", min: 0.4, max: 4, def: 1.6,
                 format: { String(format: "%.1f s", $0) }),
         .momentary(title: "🎙 Hold to talk",
                    down: { [weak self] in self?.hold() },
                    up: { [weak self] in self?.release() })]
    }
}

// MARK: Confirmation — success swell / attention pulses

final class ConfirmationSceneMode: GlowSceneMode {
    let id = "confirm", name = "Confirmation", symbol = "checkmark.seal"
    private let store = ModeStore("confirm")
    private weak var scene: GlowScene?

    func build(_ scene: GlowScene) {
        self.scene = scene
        let frame = scene.makeEdgeFrameLayer()
        frame.opacity = Float(scene.intensity) * 0.3
        scene.root.addSublayer(frame)
    }
    private func flash(color: String, values: [Float], keyTimes: [NSNumber], dur: Double) {
        guard let scene else { return }
        let pal = Palettes.palette(named: color)
        let layer = GlowGeometry.edgeFrameImage(size: scene.size, thickness: scene.thickness,
                                                palette: pal, scale: 1)
        let l = CALayer(); l.frame = scene.root.bounds; l.contents = layer
        l.contentsGravity = .resize; l.opacity = 0
        scene.root.addSublayer(l)
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = values; a.keyTimes = keyTimes; a.duration = dur
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        a.isRemovedOnCompletion = true
        l.add(a, forKey: "flash")
        DispatchQueue.main.asyncAfter(deadline: .now() + dur) { [weak l] in l?.removeFromSuperlayer() }
    }
    func success() {
        flash(color: "Emerald",
              values: [0, Float(scene?.intensity ?? 1) * 1.1, 0],
              keyTimes: [0, 0.25, 1], dur: 1.8)
    }
    func attention() {
        // Same calm single swell as success — just amber instead of green.
        flash(color: "Sunset",
              values: [0, Float(scene?.intensity ?? 1) * 1.1, 0],
              keyTimes: [0, 0.25, 1], dur: 1.8)
    }
    func controls() -> [ModeControl] {
        [.label("A quiet yes / heads-up you feel, not a red panic."),
         .button(title: "✓ Success (green swell)", action: { [weak self] in self?.success() }),
         .button(title: "! Attention (amber pulses)", action: { [weak self] in self?.attention() })]
    }
}

// MARK: Notch halo — a glow tracing the actual notch silhouette
//
// Reworked from scratch: an accurate notch-shaped outline at the top-center,
// with a soft glow hugging its shape. Fully independent of the global glow
// thickness — its own controls size the notch and the halo.

final class NotchSceneMode: GlowSceneMode {
    let id = "notch", name = "Notch Halo", symbol = "rectangle.topthird.inset.filled"
    private let store = ModeStore("notch")
    var notchRect: CGRect = .zero      // detected notch (or .zero if none)
    var hasReal = false

    func build(_ scene: GlowScene) {
        // Notch dimensions: use the detected notch on real hardware; otherwise a
        // sensible simulated size. Both are adjustable via the mode's own sliders,
        // so the global Thickness slider has NO effect here.
        let widthScale = store.double("width", 1.0)
        let heightScale = store.double("height", 1.0)
        let baseW: CGFloat = hasReal && notchRect.width > 0 ? notchRect.width : 190
        let baseH: CGFloat = hasReal && notchRect.height > 0 ? notchRect.height : 36
        let nw = baseW * widthScale
        let nh = baseH * heightScale
        let rect = CGRect(x: (scene.size.width - nw) / 2, y: 0, width: nw, height: nh)
        let path = GlowGeometry.notchPath(rect: rect)

        let halo = CGFloat(store.double("halo", 40))
        let color = scene.palette.keyColor

        // 1) Soft outer glow: a blurred stroke tracing the notch silhouette.
        let glow = CAShapeLayer()
        glow.path = path
        glow.fillColor = NSColor.clear.cgColor
        glow.strokeColor = color.cgColor
        glow.lineWidth = 3
        glow.lineJoin = .round
        glow.opacity = Float(scene.intensity)
        if let blur = CIFilter(name: "CIGaussianBlur",
                               parameters: [kCIInputRadiusKey: max(4, halo)]) {
            glow.filters = [blur]
        }
        scene.root.addSublayer(glow)

        // 2) Crisp inner outline so the notch shape reads clearly.
        let line = CAShapeLayer()
        line.path = path
        line.fillColor = NSColor.clear.cgColor
        line.strokeColor = color.cgColor
        line.lineWidth = 2
        line.lineJoin = .round
        line.opacity = Float(scene.intensity) * 0.9
        scene.root.addSublayer(line)

        // Gentle breathing on the whole halo (opacity only — no size jitter, so
        // it never drifts off the notch).
        for layer in [glow, line] {
            addPulse(to: layer, duration: store.double("speed", 4),
                     minOpacity: layer.opacity * 0.6, maxOpacity: layer.opacity, scale: 0)
        }
    }

    func controls() -> [ModeControl] {
        [.label(hasReal ? "Tracing your Mac's real notch." :
                    "No notch on this display — tracing a simulated top-center notch."),
         .slider(key: "halo", title: "Halo softness", min: 6, max: 90, def: 40,
                 format: { String(format: "%.0f px", $0) }),
         .slider(key: "width", title: "Notch width", min: 0.5, max: 1.6, def: 1.0,
                 format: { String(format: "%.0f%%", $0 * 100) }),
         .slider(key: "height", title: "Notch height", min: 0.5, max: 2.0, def: 1.0,
                 format: { String(format: "%.0f%%", $0 * 100) }),
         .slider(key: "speed", title: "Breath speed", min: 1, max: 10, def: 4,
                 format: { String(format: "%.1f s", $0) })]
    }
}

// MARK: - Path point helper

func pointOnPath(_ path: CGPath, at frac: Double) -> CGPoint {
    // Sample the path into points, then pick by fractional arc length.
    var pts: [CGPoint] = []
    path.applyWithBlock { el in
        let e = el.pointee
        switch e.type {
        case .moveToPoint, .addLineToPoint:
            pts.append(e.points[0])
        case .addQuadCurveToPoint:
            pts.append(e.points[1])
        case .addCurveToPoint:
            pts.append(e.points[2])
        default: break
        }
    }
    guard pts.count > 1 else { return pts.first ?? .zero }
    // Cumulative lengths.
    var lens: [CGFloat] = [0]
    for i in 1..<pts.count {
        let d = hypot(pts[i].x - pts[i-1].x, pts[i].y - pts[i-1].y)
        lens.append(lens[i-1] + d)
    }
    let total = lens.last ?? 1
    let target = CGFloat(frac.truncatingRemainder(dividingBy: 1)) * total
    for i in 1..<lens.count where lens[i] >= target {
        let seg = lens[i] - lens[i-1]
        let f = seg > 0 ? (target - lens[i-1]) / seg : 0
        return CGPoint(x: pts[i-1].x + (pts[i].x - pts[i-1].x) * f,
                       y: pts[i-1].y + (pts[i].y - pts[i-1].y) * f)
    }
    return pts.last ?? .zero
}
