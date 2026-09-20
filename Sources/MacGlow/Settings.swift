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

// Modes are now full renderer objects (see Modes.swift / Renderers.swift).

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

    // Live renderer instances, created once so animation state + trigger
    // buttons persist. `renderer` returns the currently-selected one.
    private lazy var renderers: [GlowRenderer] = Modes.all

    var modeID: String {
        get { d.string(forKey: "modeID") ?? renderers[0].id }
        set { d.set(newValue, forKey: "modeID"); post() }
    }
    var allModes: [GlowRenderer] { renderers }
    var renderer: GlowRenderer {
        renderers.first { $0.id == modeID } ?? renderers[0]
    }

    private func value(_ key: String, default def: Double) -> Double {
        d.object(forKey: key) == nil ? def : d.double(forKey: key)
    }
}
