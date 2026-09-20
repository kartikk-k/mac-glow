import Cocoa
import QuartzCore

// MARK: - Sparkle particles
//
// A global overlay of little twinkling sparkles scattered within the glow's edge
// band. Each sparkle is a small star sprite that fades in, pulses, and fades out
// at a random spot, then relocates — all GPU-animated (CAAnimationGroup), so the
// overlay stays essentially free on the CPU.

enum Sparkles {

    // Build a container of sparkle layers over the edge band and add it to `root`.
    // `seed` varies placement between screens without needing Math.random at runtime.
    static func makeLayer(size: CGSize, thickness: CGFloat, palette: Palette,
                          density: Double, sizeScale: Double, speed: Double,
                          intensity: CGFloat) -> CALayer {
        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: size)
        container.masksToBounds = false

        // Count scales with density and the screen's perimeter length.
        let perim = 2 * (size.width + size.height)
        let count = max(4, Int(perim / 90 * (0.3 + density)))

        // Small, crisp dots — much smaller than the glow.
        let baseDia = 3.0 + sizeScale * 6.0           // sprite diameter in pt (~3–9)
        let dot = GlowGeometry.dotImage(diameter: max(12, Int(baseDia * 4)),
                                        color: palette.keyColor)

        // Deterministic pseudo-random (no Math.random needed; stable per build).
        var s: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> Double {
            s ^= s << 13; s ^= s >> 7; s ^= s << 17
            return Double(s % 10_000) / 10_000.0
        }

        // Sparkles hug the OUTER edge in a shallow band, always much thinner than
        // the glow: at most ~22px, and never more than a quarter of the glow.
        let band = min(Double(thickness) * 0.25, 22.0)
        // A small margin so dots sit right on the screen border, not off-screen.
        let margin = 2.0
        for _ in 0..<count {
            let edge = Int(rnd() * 4)
            let along = rnd()
            var pt = CGPoint.zero
            let depth = margin + rnd() * band          // shallow, near the edge
            switch edge {
            case 0: pt = CGPoint(x: along * size.width, y: depth)                       // top
            case 1: pt = CGPoint(x: size.width - depth, y: along * size.height)         // right
            case 2: pt = CGPoint(x: along * size.width, y: size.height - depth)         // bottom
            default: pt = CGPoint(x: depth, y: along * size.height)                     // left
            }

            let scale = 0.6 + rnd() * 0.7              // subtle size variety
            let sprite = CALayer()
            sprite.contents = dot
            let d = baseDia * scale
            sprite.bounds = CGRect(x: 0, y: 0, width: d, height: d)
            sprite.position = pt
            sprite.opacity = 0
            sprite.allowsEdgeAntialiasing = false
            container.addSublayer(sprite)

            // Twinkle: fade in, hold briefly, fade out — repeat forever, with a
            // random phase (via timeOffset) so they don't blink in unison.
            let cycle = (2.5 + rnd() * 4.0) / max(0.15, speed)
            let phase = rnd() * cycle
            let peak = Float(min(1.0, 0.7 + 0.5 * Double(intensity)))   // stay bright

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, peak, peak, 0]
            fade.keyTimes = [0, 0.25, 0.5, 1]
            fade.duration = cycle
            fade.repeatCount = .infinity
            fade.timeOffset = phase
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            let twinkle = CABasicAnimation(keyPath: "transform.scale")
            twinkle.fromValue = 0.7
            twinkle.toValue = 1.25
            twinkle.duration = cycle
            twinkle.autoreverses = true
            twinkle.repeatCount = .infinity
            twinkle.timeOffset = phase

            sprite.add(fade, forKey: "twinkleFade")
            sprite.add(twinkle, forKey: "twinkleScale")
        }
        return container
    }
}
