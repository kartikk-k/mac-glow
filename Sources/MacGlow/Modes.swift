import Cocoa
import AVFoundation

// MARK: - Mode framework (GPU scene-based)
//
// Modes build CALayer scenes (see GlowScene / GlowSceneMode) that animate on the
// render server at ~0% CPU. This file holds the shared bits: the settings-control
// declarations, the per-mode persistent store, and small easing helpers.

// A UI control a mode wants in the Settings window.
enum ModeControl {
    case slider(key: String, title: String, min: Double, max: Double, def: Double, format: (Double) -> String)
    case toggle(key: String, title: String, def: Bool)
    case popup(key: String, title: String, options: [String], def: Int)
    case button(title: String, action: () -> Void)
    case momentary(title: String, down: () -> Void, up: () -> Void) // press-and-hold
    case label(String)
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

    // Wake the render loop (for trigger buttons that change animation state
    // without touching a stored value, e.g. "Fire notification", "Simulate").
    func poke() { notify() }
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
