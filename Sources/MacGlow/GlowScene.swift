import Cocoa
import QuartzCore

// MARK: - GPU glow scene
//
// A mode configures its visuals ONCE by building CALayers + CAAnimations into a
// GlowScene. The render server then animates them at 60fps at ~0% CPU — we don't
// push pixels per frame. Modes that need live data (audio) can update a single
// layer property per tick, which is still nearly free (no raster upload).

final class GlowScene {
    let root = CALayer()          // fills the whole screen; modes add sublayers
    let size: CGSize
    let palette: Palette
    let thickness: CGFloat
    let intensity: CGFloat

    // A reusable static edge-frame image for this palette/size (lazy).
    private(set) lazy var edgeFrame: CGImage? =
        GlowGeometry.edgeFrameImage(size: size, thickness: thickness,
                                    palette: palette, scale: 1)

    init(size: CGSize, palette: Palette, thickness: CGFloat, intensity: CGFloat) {
        self.size = size
        self.palette = palette
        self.thickness = thickness
        self.intensity = intensity
        root.frame = CGRect(origin: .zero, size: size)
        root.masksToBounds = false
        // Use top-left origin for ALL sublayer/path coordinates, so "top-right"
        // really is the top-right corner and paths aren't vertically flipped.
        root.isGeometryFlipped = true
    }

    // The perimeter path centered in the glow band.
    func perimeterPath() -> CGPath {
        GlowGeometry.perimeterPath(in: size, inset: thickness * 0.5)
    }

    // Exact corner points, in the root's (top-left origin) coordinate space.
    // 0 = top-right, 1 = bottom-right, 2 = bottom-left, 3 = top-left.
    func cornerPoint(_ corner: Int) -> CGPoint {
        let inset = thickness * 0.5
        let x0 = inset, x1 = size.width - inset
        let yTop = inset, yBot = size.height - inset   // top-left origin: y grows down
        switch corner {
        case 1: return CGPoint(x: x1, y: yBot)   // bottom-right
        case 2: return CGPoint(x: x0, y: yBot)   // bottom-left
        case 3: return CGPoint(x: x0, y: yTop)   // top-left
        default: return CGPoint(x: x1, y: yTop)  // top-right
        }
    }

    // Convenience: a full-screen layer showing the static edge frame.
    func makeEdgeFrameLayer() -> CALayer {
        let l = CALayer()
        l.frame = root.bounds
        l.contents = edgeFrame
        l.contentsGravity = .resize
        l.opacity = Float(intensity)
        return l
    }

    // A full-screen container clipped to the edge band, into which you can add a
    // moving/positioned highlight so it only ever shows *on the edge*, never as a
    // floating orb in the middle of the screen.
    func makeEdgeMaskedContainer() -> CALayer {
        let container = CALayer()
        container.frame = root.bounds
        container.masksToBounds = false
        let mask = CALayer()
        mask.frame = root.bounds
        mask.contents = edgeFrame        // alpha of the edge frame = the band shape
        mask.contentsGravity = .resize
        container.mask = mask
        return container
    }

    // Convenience: a soft round highlight sprite of a given on-screen diameter.
    // The source bitmap is small (soft blob upscales fine); the layer is sized to
    // the requested on-screen diameter.
    func makeBlobLayer(diameter: CGFloat, color: NSColor) -> CALayer {
        let l = CALayer()
        let img = GlowGeometry.blobImage(diameter: Int(min(160, diameter)), color: color)
        l.contents = img
        l.contentsGravity = .resize
        l.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        l.allowsEdgeAntialiasing = false
        l.allowsGroupOpacity = false
        return l
    }

    // Add a highlight blob that is CLIPPED TO THE EDGE BAND, so it reads as a
    // bright section of the glowing edge rather than a floating orb. Returns the
    // blob (add path/opacity animations to it) — its coordinates are the screen's.
    @discardableResult
    func addEdgeHighlight(diameter: CGFloat, color: NSColor, at point: CGPoint?) -> CALayer {
        let container = makeEdgeMaskedContainer()
        let blob = makeBlobLayer(diameter: diameter, color: color)
        if let p = point { blob.position = p }
        container.addSublayer(blob)
        root.addSublayer(container)
        return blob
    }
}

// A mode now builds a scene and, optionally, reacts to a per-tick live value.
protocol GlowSceneMode: AnyObject {
    var id: String { get }
    var name: String { get }
    var symbol: String { get }
    var colorOverride: String? { get }

    // Build all layers + animations into the scene. Called once when the mode
    // becomes active (or when geometry/palette changes).
    func build(_ scene: GlowScene)

    // Optional per-tick live update (audio level, etc.). Return false if the mode
    // needs no per-frame CPU at all (the common case) so the driver can idle.
    func needsLiveTick() -> Bool
    func liveTick(_ scene: GlowScene, dt: Double)

    // Prototyping controls for the Settings window.
    func controls() -> [ModeControl]
}

extension GlowSceneMode {
    var colorOverride: String? { nil }
    func needsLiveTick() -> Bool { false }
    func liveTick(_ scene: GlowScene, dt: Double) {}
    func controls() -> [ModeControl] { [] }
}
