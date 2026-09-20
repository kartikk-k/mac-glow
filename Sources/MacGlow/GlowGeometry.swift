import Cocoa
import QuartzCore

// MARK: - Shared geometry + image helpers for the GPU glow
//
// The GPU glow is built from a few CALayers whose *contents* are rendered ONCE
// and then animated via cheap layer-property animations (position along a path,
// opacity, transform). These helpers produce those static images and the
// perimeter path the compositor animates sprites along.

enum GlowGeometry {

    // The rounded-rect path that hugs the screen edge, used to move a highlight
    // sprite around the perimeter and to stroke the progress fill.
    // Inset by half the band so the stroke sits centered in the glow band.
    static func perimeterPath(in size: CGSize, inset: CGFloat) -> CGPath {
        let r = CGRect(x: inset, y: inset,
                       width: max(1, size.width - inset * 2),
                       height: max(1, size.height - inset * 2))
        let radius = min(28, min(r.width, r.height) / 2)
        return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius,
                      transform: nil)
    }

    // A soft edge-frame glow image: full color at the outer edge fading inward,
    // seam-free corners. Rendered once; animated via opacity/scale afterwards.
    static func edgeFrameImage(size: CGSize, thickness: CGFloat,
                               palette: Palette, scale: CGFloat) -> CGImage? {
        // Render at a decent resolution so the gradient stays smooth; it's soft
        // and gets GPU-upscaled from here.
        let longEdge = max(size.width, size.height)
        let ds = max(1, longEdge / 700)              // downscale factor
        let w = max(2, Int(size.width / ds))
        let h = max(2, Int(size.height / ds))
        let reach = max(1.0, Double(thickness) / Double(ds))

        var px = [UInt8](repeating: 0, count: w * h * 4)
        // Single, clean color (the palette's key color) with a pure smooth alpha
        // falloff — no multi-stop color spread, which was causing visible bands
        // and stray hues (e.g. red in Sunset).
        let c = palette.keyColor.usingColorSpace(.sRGB) ?? palette.keyColor
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent

        // A soft, smooth inward falloff.
        func falloff(_ t: Double) -> Double { let e = 1 - (t*t*(3-2*t)); return e*e }

        px.withUnsafeMutableBufferPointer { buf in
            for y in 0..<h {
                let dyE = Double(min(y, h - 1 - y))
                let ey = falloff(min(1.0, dyE / reach))
                for x in 0..<w {
                    let dxE = Double(min(x, w - 1 - x))
                    let ex = falloff(min(1.0, dxE / reach))
                    let a = ex + ey - ex * ey       // seam-free corner blend
                    let idx = (y * w + x) * 4
                    buf[idx + 0] = UInt8(max(0, min(255, r * a * 255)))
                    buf[idx + 1] = UInt8(max(0, min(255, g * a * 255)))
                    buf[idx + 2] = UInt8(max(0, min(255, b * a * 255)))
                    buf[idx + 3] = UInt8(max(0, min(255, a * 255)))
                }
            }
        }
        return imageFrom(&px, w: w, h: h)
    }

    // A soft round highlight sprite (a radial blob) used as the traveling comet /
    // scanner head / notification bloom. Rendered once per color/size.
    static func blobImage(diameter: Int, color: NSColor, softness: Double = 2.6) -> CGImage? {
        let d = max(4, diameter)
        var px = [UInt8](repeating: 0, count: d * d * 4)
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        let cx = Double(d - 1) / 2, cy = cx
        let rad = Double(d) / 2
        px.withUnsafeMutableBufferPointer { buf in
            for y in 0..<d {
                for x in 0..<d {
                    let dx = (Double(x) - cx) / rad
                    let dy = (Double(y) - cy) / rad
                    let dist = min(1.0, sqrt(dx * dx + dy * dy))
                    let a = exp(-dist * dist * softness) * (1 - dist)
                    let idx = (y * d + x) * 4
                    buf[idx + 0] = UInt8(max(0, min(255, r * a * 255)))
                    buf[idx + 1] = UInt8(max(0, min(255, g * a * 255)))
                    buf[idx + 2] = UInt8(max(0, min(255, b * a * 255)))
                    buf[idx + 3] = UInt8(max(0, min(255, a * 255)))
                }
            }
        }
        return imageFrom(&px, w: d, h: d)
    }

    // The notch outline: a shape that hangs from the top edge with a flat top and
    // rounded bottom corners (the MacBook camera-notch silhouette). Given in a
    // top-left origin space, so y grows downward from the top edge (y=0).
    static func notchPath(rect: CGRect) -> CGPath {
        let r = min(rect.height * 0.55, rect.width * 0.18)   // bottom corner radius
        let p = CGMutablePath()
        let x0 = rect.minX, x1 = rect.maxX
        let yTop = rect.minY, yBot = rect.maxY
        p.move(to: CGPoint(x: x0, y: yTop))                  // top-left (at screen edge)
        p.addLine(to: CGPoint(x: x0, y: yBot - r))           // down left side
        p.addArc(tangent1End: CGPoint(x: x0, y: yBot),
                 tangent2End: CGPoint(x: x0 + r, y: yBot), radius: r)   // bottom-left round
        p.addLine(to: CGPoint(x: x1 - r, y: yBot))           // across the bottom
        p.addArc(tangent1End: CGPoint(x: x1, y: yBot),
                 tangent2End: CGPoint(x: x1, y: yBot - r), radius: r)   // bottom-right round
        p.addLine(to: CGPoint(x: x1, y: yTop))               // up right side
        return p
    }

    // A 4-point sparkle/star: a bright core with soft diagonal rays.
    static func starImage(diameter: Int, color: NSColor) -> CGImage? {
        let d = max(6, diameter)
        var px = [UInt8](repeating: 0, count: d * d * 4)
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        let cx = Double(d - 1) / 2, cy = cx
        let rad = Double(d) / 2
        px.withUnsafeMutableBufferPointer { buf in
            for y in 0..<d {
                for x in 0..<d {
                    let dx = (Double(x) - cx) / rad
                    let dy = (Double(y) - cy) / rad
                    let dist = sqrt(dx * dx + dy * dy)
                    // Bright round core.
                    let core = exp(-dist * dist * 9)
                    // Four-point rays: sharp along the axes.
                    let ax = exp(-pow(dx * 5, 2)) * exp(-pow(dy * 1.3, 2))
                    let ay = exp(-pow(dy * 5, 2)) * exp(-pow(dx * 1.3, 2))
                    let rays = (ax + ay) * max(0, 1 - dist)
                    let a = min(1.0, core + rays * 0.8)
                    let idx = (y * d + x) * 4
                    buf[idx + 0] = UInt8(max(0, min(255, r * a * 255)))
                    buf[idx + 1] = UInt8(max(0, min(255, g * a * 255)))
                    buf[idx + 2] = UInt8(max(0, min(255, b * a * 255)))
                    buf[idx + 3] = UInt8(max(0, min(255, a * 255)))
                }
            }
        }
        return imageFrom(&px, w: d, h: d)
    }

    // A small, crisp dot: a bright solid core with a tight soft rim (sharper than
    // the big soft blob — used for sparkle particles).
    static func dotImage(diameter: Int, color: NSColor) -> CGImage? {
        let d = max(4, diameter)
        var px = [UInt8](repeating: 0, count: d * d * 4)
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        let cx = Double(d - 1) / 2, cy = cx
        let rad = Double(d) / 2
        px.withUnsafeMutableBufferPointer { buf in
            for y in 0..<d {
                for x in 0..<d {
                    let dx = (Double(x) - cx) / rad
                    let dy = (Double(y) - cy) / rad
                    let dist = sqrt(dx * dx + dy * dy)
                    // Solid to ~55% radius, then a short sharp fade to the rim.
                    let a: Double
                    if dist < 0.55 { a = 1.0 }
                    else { a = max(0, 1 - (dist - 0.55) / 0.45) }
                    let aa = a * a          // sharpen the edge
                    let idx = (y * d + x) * 4
                    buf[idx + 0] = UInt8(max(0, min(255, r * aa * 255)))
                    buf[idx + 1] = UInt8(max(0, min(255, g * aa * 255)))
                    buf[idx + 2] = UInt8(max(0, min(255, b * aa * 255)))
                    buf[idx + 3] = UInt8(max(0, min(255, aa * 255)))
                }
            }
        }
        return imageFrom(&px, w: d, h: d)
    }

    private static func imageFrom(_ px: inout [UInt8], w: Int, h: Int) -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: w * 4, space: space, bitmapInfo: info,
                       provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }
}
