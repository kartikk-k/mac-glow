import Cocoa

// MARK: - The mode renderers
//
// Each mode is small and self-contained. Where a mode reacts to a signal we
// don't have wired up yet (audio, notifications, assistant state), it exposes
// prototyping controls so you can drive it by hand from the Settings window.

// Registry of all modes, in menu order.
enum Modes {
    static let all: [GlowRenderer] = [
        BreathingMode(),
        ScannerMode(),
        ProgressMode(),
        NotificationMode(),
        FocusCornerMode(),
        AudioMode(),
        TypingMode(),
        AssistantMode(),
        PushToTalkMode(),
        ConfirmationMode(),
        NotchMode()
    ]
    static func by(id: String) -> GlowRenderer {
        all.first { $0.id == id } ?? all[0]
    }
}

// MARK: 0. Breathing (kept)

final class BreathingMode: GlowRenderer {
    let id = "breathing", name = "Breathing", symbol = "wind"
    private let store = ModeStore("breathing")

    func envelope(clock: Double) -> (thickness: Double, brightness: Double) {
        let speed = max(0.3, store.double("speed", 5.0))
        let depth = store.double("depth", 0.48)
        let e = sin(clock / speed * 2 * .pi) * 0.5 + 0.5
        return (1 + depth * e, 0.72 + 0.28 * e)
    }
    func output(_ s: GlowSample, clock: Double) -> GlowOutput { GlowOutput(1) }

    func controls() -> [ModeControl] {
        [
            .label("A calm, symmetric swell — the idle resting state."),
            .slider(key: "speed", title: "Breath speed", min: 1, max: 15, def: 5.0,
                    format: { String(format: "%.1f s", $0) }),
            .slider(key: "depth", title: "Expansion", min: 0, max: 1, def: 0.48,
                    format: { String(format: "%.0f%%", $0 * 100) })
        ]
    }
}

// MARK: 1. Scanner (the refined "thinking" — a soft bar sweeps the perimeter)

final class ScannerMode: GlowRenderer {
    let id = "scanner", name = "Scanner", symbol = "dot.radiowaves.left.and.right"
    private let store = ModeStore("scanner")
    private var pos = 0.0

    func update(dt: Double, clock: Double) {
        let speed = max(0.3, store.double("speed", 6.0))
        pos = (pos + dt / speed).truncatingRemainder(dividingBy: 1)
    }
    func output(_ s: GlowSample, clock: Double) -> GlowOutput {
        let width = store.double("width", 0.10)          // fraction of perimeter
        let floor = store.double("floor", 0.30)
        let d = Ease.loopDist(s.peri, pos)
        let sharp = 1.0 / max(0.001, width * width)
        let bar = exp(-d * d * sharp)
        return GlowOutput(floor + (1.1 - floor) * bar)
    }
    func controls() -> [ModeControl] {
        [
            .label("A soft bar sweeps calmly around the edge — refined Thinking."),
            .slider(key: "speed", title: "Sweep speed", min: 1, max: 20, def: 6.0,
                    format: { String(format: "%.1f s / lap", $0) }),
            .slider(key: "width", title: "Bar width", min: 0.03, max: 0.30, def: 0.10,
                    format: { String(format: "%.0f%%", $0 * 100) }),
            .slider(key: "floor", title: "Ambient floor", min: 0, max: 0.7, def: 0.30,
                    format: { String(format: "%.0f%%", $0 * 100) })
        ]
    }
}

// MARK: 2. Progress fill — light fills the perimeter 0→100%

final class ProgressMode: GlowRenderer {
    let id = "progress", name = "Progress", symbol = "circle.dotted"
    private let store = ModeStore("progress")
    private var auto = false
    private var autoValue = 0.0

    // The fill amount: the auto-run value while animating, else the slider.
    private var fill: Double { auto ? autoValue : store.double("value", 0.35) }

    func update(dt: Double, clock: Double) {
        if auto {
            let dur = max(1, store.double("duration", 8))
            autoValue += dt / dur
            if autoValue >= 1 { autoValue = 1; auto = false; store.setDouble("value", 1) }
        }
    }
    func output(_ s: GlowSample, clock: Double) -> GlowOutput {
        let v = fill
        let dim = store.double("trackDim", 0.12)
        // Perimeter runs 0..1 from top-left CW. Fill up to `v`.
        if s.peri <= v {
            let lead = Ease.smoothstep((v - s.peri) / 0.04)   // soft leading edge
            return GlowOutput(dim + (1.05 - dim) * max(0.5, lead))
        } else {
            return GlowOutput(dim)                            // faint unfilled track
        }
    }
    func controls() -> [ModeControl] {
        [
            .label("Light fills the perimeter to show progress on a long task."),
            .slider(key: "value", title: "Progress", min: 0, max: 1, def: 0.35,
                    format: { String(format: "%.0f%%", $0 * 100) }),
            .slider(key: "trackDim", title: "Unfilled track", min: 0, max: 0.4, def: 0.12,
                    format: { String(format: "%.0f%%", $0 * 100) }),
            .slider(key: "duration", title: "Auto-run time", min: 2, max: 30, def: 8,
                    format: { String(format: "%.0f s", $0) }),
            .button(title: "▶ Simulate 0 → 100%", action: { [weak self] in
                self?.autoValue = 0; self?.auto = true
            }),
            .button(title: "Reset", action: { [weak self] in
                self?.auto = false; self?.autoValue = 0; self?.store.setDouble("value", 0)
            })
        ]
    }
}

// MARK: 3. Notification origin — a bloom on the edge nearest a source

final class NotificationMode: GlowRenderer {
    let id = "notification", name = "Notification", symbol = "bell.badge"
    private let store = ModeStore("notification")
    // Active blooms: (perimeter position, age, ttl)
    private struct Bloom { var at: Double; var age: Double }
    private var blooms: [Bloom] = []

    func update(dt: Double, clock: Double) {
        let ttl = max(0.5, store.double("linger", 2.5))
        for i in blooms.indices { blooms[i].age += dt }
        blooms.removeAll { $0.age > ttl }
    }
    func fire(at peri: Double) { blooms.append(Bloom(at: peri, age: 0)) }

    func output(_ s: GlowSample, clock: Double) -> GlowOutput {
        let ttl = max(0.5, store.double("linger", 2.5))
        let spread = store.double("spread", 0.12)
        let floor = store.double("floor", 0.10)
        var glow = 0.0
        for b in blooms {
            let life = 1 - (b.age / ttl)                  // 1..0
            let pop = min(1, b.age / 0.15)                // quick attack
            let d = Ease.loopDist(s.peri, b.at)
            let sharp = 1.0 / max(0.001, spread * spread)
            glow = max(glow, exp(-d * d * sharp) * life * pop)
        }
        return GlowOutput(floor + 1.2 * glow)
    }
    func controls() -> [ModeControl] {
        [
            .label("A bloom appears on the edge nearest where an alert came from."),
            .slider(key: "spread", title: "Bloom size", min: 0.04, max: 0.3, def: 0.12,
                    format: { String(format: "%.0f%%", $0 * 100) }),
            .slider(key: "linger", title: "Linger", min: 0.5, max: 6, def: 2.5,
                    format: { String(format: "%.1f s", $0) }),
            .slider(key: "floor", title: "Ambient floor", min: 0, max: 0.4, def: 0.10,
                    format: { String(format: "%.0f%%", $0 * 100) }),
            .button(title: "Fire ▲ top-right", action: { [weak self] in self?.fire(at: 0.20) }),
            .button(title: "Fire ▼ bottom-right", action: { [weak self] in self?.fire(at: 0.40) }),
            .button(title: "Fire ▼ bottom-left", action: { [weak self] in self?.fire(at: 0.65) }),
            .button(title: "Fire ▲ top-left", action: { [weak self] in self?.fire(at: 0.95) })
        ]
    }
}

// MARK: 4. Focus corner — glow concentrates toward a region

final class FocusCornerMode: GlowRenderer {
    let id = "focus", name = "Focus Corner", symbol = "scope"
    private let store = ModeStore("focus")

    // Target perimeter center per corner choice.
    private func target() -> Double {
        switch Int(store.double("corner", 0)) {
        case 1: return 0.375   // bottom-right
        case 2: return 0.625   // bottom-left
        case 3: return 0.875   // top-left
        default: return 0.125  // top-right
        }
    }
    func output(_ s: GlowSample, clock: Double) -> GlowOutput {
        let width = store.double("width", 0.22)
        let floor = store.double("floor", 0.06)
        let d = Ease.loopDist(s.peri, target())
        let sharp = 1.0 / max(0.001, width * width)
        let g = exp(-d * d * sharp)
        // Gentle shimmer so it feels alive.
        let breathe = 0.9 + 0.1 * sin(clock * 1.5)
        return GlowOutput((floor + (1.05 - floor) * g) * breathe)
    }
    func controls() -> [ModeControl] {
        [
            .label("The glow gathers toward a corner to pull your eye there."),
            .popup(key: "corner", title: "Corner",
                   options: ["Top-right", "Bottom-right", "Bottom-left", "Top-left"], def: 0),
            .slider(key: "width", title: "Concentration", min: 0.08, max: 0.4, def: 0.22,
                    format: { String(format: "%.0f%%", $0 * 100) }),
            .slider(key: "floor", title: "Rest of frame", min: 0, max: 0.4, def: 0.06,
                    format: { String(format: "%.0f%%", $0 * 100) })
        ]
    }
}

// MARK: 5. Audio-reactive — the glow pulses with real (or simulated) audio

final class AudioMode: GlowRenderer {
    let id = "audio", name = "Audio Reactive", symbol = "waveform.circle"
    private let store = ModeStore("audio")

    func update(dt: Double, clock: Double) {
        let sim = store.bool("simulate", false)
        if !sim { AudioLevel.shared.startMic() }
        AudioLevel.shared.tick(dt: dt, simulate: sim)
    }
    func envelope(clock: Double) -> (thickness: Double, brightness: Double) {
        let lvl = AudioLevel.shared.level
        let react = store.double("react", 0.8)
        return (1 + lvl * react * 0.6, 0.35 + lvl * (0.4 + react * 0.5))
    }
    func output(_ s: GlowSample, clock: Double) -> GlowOutput {
        // A subtle standing waveform around the edge, scaled by level.
        let lvl = AudioLevel.shared.level
        let wob = 0.85 + 0.15 * sin(s.peri * 40 + clock * 6) * lvl
        return GlowOutput(max(0.15, wob))
    }
    func controls() -> [ModeControl] {
        let mic = AudioLevel.shared.micActive
        return [
            .label(mic ? "Reacting to your microphone." :
                         "Enable the mic, or turn on Simulate to preview."),
            .toggle(key: "simulate", title: "Simulate audio (no mic)", def: false),
            .slider(key: "react", title: "Reactivity", min: 0.1, max: 1.5, def: 0.8,
                    format: { String(format: "%.0f%%", $0 / 1.5 * 100) })
        ]
    }
}

// MARK: 6. Typing / flow — warmth builds as you type, fades on pause

final class TypingMode: GlowRenderer {
    let id = "typing", name = "Flow", symbol = "keyboard"
    private let store = ModeStore("typing")
    private var flow = 0.0

    // Called by the app when a keystroke is observed (or simulated).
    func bump() { flow = min(1, flow + store.double("perKey", 0.06)) }

    func update(dt: Double, clock: Double) {
        let decay = max(0.05, store.double("decay", 0.4))
        flow = max(0, flow - dt * decay)
        if store.bool("autoType", false) {
            // Simulate a burst of typing.
            if sin(clock * 8) > 0.6 { bump() }
        }
    }
    func envelope(clock: Double) -> (thickness: Double, brightness: Double) {
        (1 + flow * 0.4, 0.3 + flow * 0.7)
    }
    func output(_ s: GlowSample, clock: Double) -> GlowOutput {
        // Warmth pools toward the bottom edge (near the keyboard).
        // Buffer ny=0 is the TOP, so the bottom is ny→1.
        let bottomBias = s.ny                  // 1 at bottom, 0 at top
        let g = 0.4 + 0.6 * (0.5 + 0.5 * bottomBias) * (0.3 + 0.7 * flow)
        return GlowOutput(g, colorShift: flow * 0.4)
    }
    var colorOverride: String? { "Sunset" }   // warm palette suits "flow"
    func controls() -> [ModeControl] {
        [
            .label("Warmth builds as you type and fades when you pause."),
            .toggle(key: "autoType", title: "Simulate typing", def: false),
            .slider(key: "perKey", title: "Build per keystroke", min: 0.02, max: 0.2, def: 0.06,
                    format: { String(format: "%.0f%%", $0 * 100) }),
            .slider(key: "decay", title: "Fade speed", min: 0.1, max: 1.5, def: 0.4,
                    format: { String(format: "%.1f / s", $0) }),
            .button(title: "Tap (simulate keystroke)", action: { [weak self] in self?.bump() })
        ]
    }
}

// MARK: 7. Assistant states — idle / working / needs-you

final class AssistantMode: GlowRenderer {
    let id = "assistant", name = "Assistant", symbol = "sparkles"
    private let store = ModeStore("assistant")
    private var pos = 0.0

    // Popup stores an index; map it to a state name.
    private var state: String {
        ["idle", "working", "needs"][safe: Int(store.double("state", 0))] ?? "idle"
    }

    func update(dt: Double, clock: Double) {
        pos = (pos + dt / 4.0).truncatingRemainder(dividingBy: 1)  // working sweep
    }
    func envelope(clock: Double) -> (thickness: Double, brightness: Double) {
        switch state {
        case "idle":
            let e = sin(clock / 5 * 2 * .pi) * 0.5 + 0.5
            return (1 + 0.35 * e, 0.6 + 0.3 * e)
        case "needs":
            // Two calm attention pulses, never a panic flash.
            let p = clock.truncatingRemainder(dividingBy: 2.2)
            let a = exp(-pow((p - 0.2) / 0.18, 2)) + exp(-pow((p - 0.6) / 0.18, 2))
            return (1, 0.5 + 0.8 * min(1, a))
        default: return (1, 1)
        }
    }
    func output(_ s: GlowSample, clock: Double) -> GlowOutput {
        switch state {
        case "working":
            let d = Ease.loopDist(s.peri, pos)
            return GlowOutput(0.3 + 0.9 * exp(-d * d * 120))
        case "needs":
            return GlowOutput(1)
        default:
            return GlowOutput(1)
        }
    }
    var colorOverride: String? {
        switch state {
        case "needs": return "Sunset"     // warm = attention (not alarming red)
        default: return nil
        }
    }
    func controls() -> [ModeControl] {
        [
            .label("Three honest states an assistant would actually need."),
            .popup(key: "state", title: "State", options: ["Idle", "Working", "Needs you"], def: 0),
            .label("idle = calm breath · working = sweep · needs = attention pulses")
        ]
    }
}

// MARK: 8. Push-to-talk halo — hold to listen, release to think, then settle

final class PushToTalkMode: GlowRenderer {
    let id = "ptt", name = "Push to Talk", symbol = "mic.circle"
    private let store = ModeStore("ptt")
    // Phases: idle → listening (held) → thinking (after release) → settle → idle
    private enum P { case idle, listening, thinking, settle }
    private var phase: P = .idle
    private var t = 0.0
    private var pos = 0.0

    func hold() {
        phase = .listening; t = 0
        if !store.bool("simulate", false) { AudioLevel.shared.startMic() }
    }
    func release() { phase = .thinking; t = 0 }

    func update(dt: Double, clock: Double) {
        t += dt
        pos = (pos + dt / 2.0).truncatingRemainder(dividingBy: 1)
        AudioLevel.shared.tick(dt: dt, simulate: store.bool("simulate", false))
        switch phase {
        case .thinking: if t > max(0.8, store.double("thinkTime", 1.6)) { phase = .settle; t = 0 }
        case .settle: if t > 0.9 { phase = .idle; t = 0 }
        default: break
        }
    }
    func envelope(clock: Double) -> (thickness: Double, brightness: Double) {
        switch phase {
        case .idle:
            let e = sin(clock / 5 * 2 * .pi) * 0.5 + 0.5
            return (1 + 0.2 * e, 0.4 + 0.2 * e)
        case .listening:
            let lvl = AudioLevel.shared.level
            return (1 + lvl * 0.6, 0.5 + lvl * 0.5)
        case .thinking: return (1, 0.9)
        case .settle:
            let s = 1 - Ease.smoothstep(t / 0.9)
            return (1, 0.4 + 0.6 * s)
        }
    }
    func output(_ s: GlowSample, clock: Double) -> GlowOutput {
        switch phase {
        case .thinking:
            let d = Ease.loopDist(s.peri, pos)
            return GlowOutput(0.3 + 0.9 * exp(-d * d * 120))
        case .listening:
            let lvl = AudioLevel.shared.level
            return GlowOutput(max(0.4, 0.7 + 0.3 * sin(s.peri * 30 + clock * 8) * lvl))
        default:
            return GlowOutput(1)
        }
    }
    var colorOverride: String? { "Aurora" }
    func controls() -> [ModeControl] {
        [
            .label("Hold to listen, release to think, then it settles."),
            .toggle(key: "simulate", title: "Simulate audio (no mic)", def: false),
            .slider(key: "thinkTime", title: "Think duration", min: 0.4, max: 4, def: 1.6,
                    format: { String(format: "%.1f s", $0) }),
            .momentary(title: "🎙 Hold to talk",
                       down: { [weak self] in self?.hold() },
                       up: { [weak self] in self?.release() })
        ]
    }
}

// MARK: 9. Confirmation flash — success / attention swells

final class ConfirmationMode: GlowRenderer {
    let id = "confirm", name = "Confirmation", symbol = "checkmark.seal"
    private let store = ModeStore("confirm")
    private enum Kind { case none, success, attention }
    private var kind: Kind = .none
    private var t = 0.0

    func success() { kind = .success; t = 0 }
    func attention() { kind = .attention; t = 0 }

    func update(dt: Double, clock: Double) {
        if kind != .none { t += dt; if t > 2.4 { kind = .none } }
    }
    func envelope(clock: Double) -> (thickness: Double, brightness: Double) {
        switch kind {
        case .success:
            // One soft swell that settles.
            let a = t < 0.4 ? Ease.smoothstep(t / 0.4) : (1 - Ease.smoothstep((t - 0.4) / 1.6))
            return (1 + 0.4 * a, 0.4 + 0.9 * a)
        case .attention:
            // Two calm amber pulses.
            let p = t.truncatingRemainder(dividingBy: 1.0)
            let a = exp(-pow((p - 0.15) / 0.1, 2)) + exp(-pow((p - 0.5) / 0.1, 2))
            return (1, 0.4 + 0.9 * min(1, a))
        case .none:
            let e = sin(clock / 5 * 2 * .pi) * 0.5 + 0.5
            return (1, 0.3 + 0.2 * e)
        }
    }
    func output(_ s: GlowSample, clock: Double) -> GlowOutput { GlowOutput(1) }
    var colorOverride: String? {
        switch kind {
        case .success: return "Emerald"
        case .attention: return "Sunset"
        case .none: return nil
        }
    }
    func controls() -> [ModeControl] {
        [
            .label("A quiet yes / heads-up you feel, not a red panic."),
            .button(title: "✓ Success (green swell)", action: { [weak self] in self?.success() }),
            .button(title: "! Attention (amber pulses)", action: { [weak self] in self?.attention() })
        ]
    }
}

// MARK: 10. Notch halo — glow hugging the camera notch

final class NotchMode: GlowRenderer {
    let id = "notch", name = "Notch Halo", symbol = "rectangle.topthird.inset.filled"
    private let store = ModeStore("notch")
    // Set each frame by the view (view-space rect + size).
    var notchRect: CGRect = .zero
    var viewSize: CGSize = .zero
    var hasReal = false

    func envelope(clock: Double) -> (thickness: Double, brightness: Double) {
        // Notch halo ignores the edge band entirely; handled in output via ny/nx.
        (1, 1)
    }
    func output(_ s: GlowSample, clock: Double) -> GlowOutput {
        guard viewSize.width > 0, notchRect.width > 0 else { return GlowOutput(0) }
        // Pixel position in view space.
        let px = s.nx * viewSize.width
        let py = s.ny * viewSize.height
        // Distance to the notch rectangle (0 inside, grows outside).
        let dx = max(notchRect.minX - px, 0, px - notchRect.maxX)
        let dy = max(notchRect.minY - py, 0, py - notchRect.maxY)
        let dist = sqrt(dx * dx + dy * dy)
        let reach = store.double("reach", 60)
        let breathe = 0.85 + 0.15 * sin(clock / max(0.5, store.double("speed", 3)) * 2 * .pi)
        let g = exp(-(dist / reach) * (dist / reach) * 2.5)
        return GlowOutput(g * breathe)
    }
    // Notch mode paints independent of the edge band.
    var paintsWholeScreen: Bool { true }
    func controls() -> [ModeControl] {
        [
            .label(hasReal ? "Hugging your Mac's real notch." :
                             "No notch detected — showing a simulated top-center notch."),
            .slider(key: "reach", title: "Halo size", min: 20, max: 160, def: 60,
                    format: { String(format: "%.0f px", $0) }),
            .slider(key: "speed", title: "Breath speed", min: 1, max: 10, def: 3,
                    format: { String(format: "%.1f s", $0) })
        ]
    }
}
