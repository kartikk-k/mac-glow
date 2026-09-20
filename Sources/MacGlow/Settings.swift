import Cocoa

// MARK: - Gradient palettes
//
// Each palette is an ordered list of colors sampled from the screen edge
// (index 0, most saturated) fading to transparent at the inner end.

struct Palette {
    let name: String
    let colors: [NSColor]

    // The core edge color, used e.g. for the menu swatch.
    var keyColor: NSColor { colors.first ?? .systemBlue }
}

enum Palettes {
    static let all: [Palette] = [
        Palette(name: "Ice Blue", colors: [
            NSColor(srgbRed: 0.55, green: 0.85, blue: 1.00, alpha: 1),
            NSColor(srgbRed: 0.30, green: 0.65, blue: 0.98, alpha: 1),
            NSColor(srgbRed: 0.20, green: 0.45, blue: 0.95, alpha: 1)
        ]),
        Palette(name: "Aurora", colors: [
            NSColor(srgbRed: 0.35, green: 1.00, blue: 0.80, alpha: 1),
            NSColor(srgbRed: 0.25, green: 0.75, blue: 0.95, alpha: 1),
            NSColor(srgbRed: 0.55, green: 0.40, blue: 0.95, alpha: 1)
        ]),
        Palette(name: "Sunset", colors: [
            NSColor(srgbRed: 1.00, green: 0.72, blue: 0.30, alpha: 1),
            NSColor(srgbRed: 1.00, green: 0.42, blue: 0.42, alpha: 1),
            NSColor(srgbRed: 0.85, green: 0.25, blue: 0.55, alpha: 1)
        ]),
        Palette(name: "Emerald", colors: [
            NSColor(srgbRed: 0.55, green: 1.00, blue: 0.70, alpha: 1),
            NSColor(srgbRed: 0.20, green: 0.85, blue: 0.55, alpha: 1),
            NSColor(srgbRed: 0.10, green: 0.60, blue: 0.45, alpha: 1)
        ]),
        Palette(name: "Magenta", colors: [
            NSColor(srgbRed: 1.00, green: 0.55, blue: 0.95, alpha: 1),
            NSColor(srgbRed: 0.85, green: 0.35, blue: 0.95, alpha: 1),
            NSColor(srgbRed: 0.55, green: 0.30, blue: 0.95, alpha: 1)
        ]),
        Palette(name: "Mono White", colors: [
            NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1),
            NSColor(srgbRed: 0.85, green: 0.90, blue: 1.00, alpha: 1),
            NSColor(srgbRed: 0.70, green: 0.80, blue: 0.95, alpha: 1)
        ])
    ]

    static func palette(named name: String) -> Palette {
        all.first { $0.name == name } ?? all[0]
    }
}

// MARK: - Ambient modes
//
// Every mode drives the SAME glow renderer — it only supplies a motion type
// plus a few parameters. Adding a mode is a few lines here, no new plumbing.
// This is the foundation for an "AI presence" layer: breathing when idle,
// alert when listening, an orbiting light when thinking, etc.

enum GlowMotion {
    case pulse      // slow symmetric in/out breathing
    case flicker    // fast shallow reactive jitter (alert / listening)
    case orbit      // a bright comet travels around the perimeter (working)
    case ripple     // brightness waves radiate around the edges (speaking)
    case steady     // no motion, static wash (focus / quiet)
}

struct GlowMode {
    let id: String
    let name: String
    let symbol: String          // SF Symbol for the menu
    let motion: GlowMotion
    let speed: Double           // seconds per cycle
    let depth: Double           // motion amount (expansion / travel intensity)
    let intensityScale: Double  // multiplies base intensity
    let colorOverride: String?  // palette name to force, or nil = use user's palette

    // Modes differ by MOTION first. Color is left to the user's palette by
    // default (colorOverride: nil) so the mode reads through its movement.

    static let breathing = GlowMode(
        id: "breathing", name: "Breathing", symbol: "wind",
        motion: .pulse, speed: 3.6, depth: 0.48, intensityScale: 1.0,
        colorOverride: nil)

    static let listening = GlowMode(
        id: "listening", name: "Listening", symbol: "waveform",
        motion: .flicker, speed: 0.5, depth: 0.5, intensityScale: 1.15,
        colorOverride: nil)

    static let thinking = GlowMode(
        id: "thinking", name: "Thinking", symbol: "sparkles",
        motion: .orbit, speed: 2.4, depth: 1.0, intensityScale: 1.1,
        colorOverride: nil)

    static let speaking = GlowMode(
        id: "speaking", name: "Speaking", symbol: "speaker.wave.2",
        motion: .ripple, speed: 1.8, depth: 1.0, intensityScale: 1.15,
        colorOverride: nil)

    static let focus = GlowMode(
        id: "focus", name: "Focus", symbol: "moon.stars",
        motion: .steady, speed: 1, depth: 0, intensityScale: 0.6,
        colorOverride: nil)

    static let all: [GlowMode] = [breathing, listening, thinking, speaking, focus]

    static func byID(_ id: String) -> GlowMode {
        all.first { $0.id == id } ?? breathing
    }
}

// MARK: - Shared settings (persisted, observable)

final class Settings {
    static let shared = Settings()

    static let didChange = Notification.Name("MacGlowSettingsDidChange")

    private let d = UserDefaults.standard
    private func post() { NotificationCenter.default.post(name: Settings.didChange, object: nil) }

    // Selected gradient palette name.
    var paletteName: String {
        get { d.string(forKey: "paletteName") ?? Palettes.all[0].name }
        set { d.set(newValue, forKey: "paletteName"); post() }
    }
    var palette: Palette { Palettes.palette(named: paletteName) }

    // Base thickness of the glow band, in points, before breathing.
    var thickness: Double {
        get { value("thickness", default: 62) }
        set { d.set(newValue, forKey: "thickness"); post() }
    }

    // Overall opacity multiplier (0...1).
    var intensity: Double {
        get { value("intensity", default: 0.4) }
        set { d.set(newValue, forKey: "intensity"); post() }
    }

    // Breathing on/off.
    var breathing: Bool {
        get { d.object(forKey: "breathing") == nil ? true : d.bool(forKey: "breathing") }
        set { d.set(newValue, forKey: "breathing"); post() }
    }

    // Seconds for one full breath in→out cycle.
    var breathSpeed: Double {
        get { value("breathSpeed", default: 3.6) }
        set { d.set(newValue, forKey: "breathSpeed"); post() }
    }

    // How much the glow expands at the peak of a breath, as a fraction of
    // base thickness (0 = no movement, 1 = doubles).
    var breathDepth: Double {
        get { value("breathDepth", default: 0.48) }
        set { d.set(newValue, forKey: "breathDepth"); post() }
    }

    // Selected ambient mode.
    var modeID: String {
        get { d.string(forKey: "modeID") ?? GlowMode.breathing.id }
        set { d.set(newValue, forKey: "modeID"); post() }
    }
    var mode: GlowMode { GlowMode.byID(modeID) }

    private func value(_ key: String, default def: Double) -> Double {
        d.object(forKey: key) == nil ? def : d.double(forKey: key)
    }
}
