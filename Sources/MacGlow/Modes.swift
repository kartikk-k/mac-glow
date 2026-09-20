import Cocoa
import AVFoundation

// MARK: - Mode framework
//
// Every mode is a self-contained renderer. It receives a per-pixel sampling
// context and returns how bright that pixel should be (0...~1.6) plus an
// optional color shift. Shared machinery (edge falloff, palette, perimeter
// position) lives in GlowView; modes only express their *behavior*.
//
// Modes also declare their own settings (surfaced in the Settings window) and
// optional trigger buttons for prototyping (fire a notification, set a state…).

// Per-pixel input handed to a mode during rendering.
struct GlowSample {
    let peri: Double        // 0..1 position around the perimeter (top-left, CW)
    let edgeAlpha: Double   // base edge-falloff alpha at this pixel (0..1)
    let t: Double           // 0..1 depth into the band (0 = outer edge)
    let nx: Double          // normalized x (0..1) across the screen
    let ny: Double          // normalized y (0..1), 0 = bottom (Cocoa coords)
}

// What a mode returns per pixel.
struct GlowOutput {
    var alpha: Double        // multiplies edgeAlpha*brightness
    var colorShift: Double   // 0..1 offset into the palette (0 = default)
    init(_ a: Double, colorShift: Double = 0) { self.alpha = a; self.colorShift = colorShift }
}

// A UI control a mode wants in the Settings window.
enum ModeControl {
    case slider(key: String, title: String, min: Double, max: Double, def: Double, format: (Double) -> String)
    case toggle(key: String, title: String, def: Bool)
    case popup(key: String, title: String, options: [String], def: Int)
    case button(title: String, action: () -> Void)
    case momentary(title: String, down: () -> Void, up: () -> Void) // press-and-hold
    case label(String)
}

protocol GlowRenderer: AnyObject {
    var id: String { get }
    var name: String { get }
    var symbol: String { get }

    // Called once per frame before the pixel loop; advance animation state here.
    func update(dt: Double, clock: Double)

    // Per-pixel modulation.
    func output(_ s: GlowSample, clock: Double) -> GlowOutput

    // Whole-frame envelope (for modes that swell the entire glow, e.g. breathe).
    // Returns (thicknessScale, brightnessScale). Default: no swell.
    func envelope(clock: Double) -> (thickness: Double, brightness: Double)

    // A palette name to force, or nil to use the user's choice.
    var colorOverride: String? { get }

    // If true, the mode's `output.alpha` IS the final alpha (not multiplied by
    // the edge-falloff band) — for modes that paint independently, e.g. Notch.
    var paintsWholeScreen: Bool { get }

    // Custom settings/controls shown when this mode is active.
    func controls() -> [ModeControl]
}

extension GlowRenderer {
    func update(dt: Double, clock: Double) {}
    func envelope(clock: Double) -> (thickness: Double, brightness: Double) { (1, 1) }
    var colorOverride: String? { nil }
    var paintsWholeScreen: Bool { false }
    func controls() -> [ModeControl] { [] }
}

// Small persistent per-mode settings helper (namespaced UserDefaults).
final class ModeStore {
    let ns: String
    private let d = UserDefaults.standard
    init(_ ns: String) { self.ns = ns }
    private func k(_ key: String) -> String { "mode.\(ns).\(key)" }

    func double(_ key: String, _ def: Double) -> Double {
        d.object(forKey: k(key)) == nil ? def : d.double(forKey: k(key))
    }
    func setDouble(_ key: String, _ v: Double) { d.set(v, forKey: k(key)); notify() }

    func bool(_ key: String, _ def: Bool) -> Bool {
        d.object(forKey: k(key)) == nil ? def : d.bool(forKey: k(key))
    }
    func setBool(_ key: String, _ v: Bool) { d.set(v, forKey: k(key)); notify() }

    func string(_ key: String, _ def: String) -> String {
        d.string(forKey: k(key)) ?? def
    }
    func setString(_ key: String, _ v: String) { d.set(v, forKey: k(key)); notify() }

    private func notify() {
        NotificationCenter.default.post(name: Settings.didChange, object: nil)
    }
}

// MARK: - Easing helpers shared by modes

enum Ease {
    static func smoothstep(_ x: Double) -> Double {
        let t = max(0, min(1, x)); return t * t * (3 - 2 * t)
    }
    // Distance around a 0..1 loop.
    static func loopDist(_ a: Double, _ b: Double) -> Double {
        var d = abs(a - b); d = min(d, 1 - d); return d
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
