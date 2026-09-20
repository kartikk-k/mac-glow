import Cocoa
import QuartzCore

// MARK: - GPU glow host view
//
// Hosts a GlowScene (CALayers + CAAnimations). Animation runs on the render
// server at ~0% CPU. We only rebuild the scene when the mode / palette / size
// changes, and (for a couple of live modes) push one cheap property per tick.

final class GlowView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var scene: GlowScene?
    private var builtKey = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }
    required init?(coder: NSCoder) { fatalError() }

    // Rebuild the scene for the current mode/palette/size if anything changed.
    func rebuildIfNeeded(force: Bool = false) {
        let s = Settings.shared
        let mode = s.sceneMode
        let palette = mode.colorOverride.map { Palettes.palette(named: $0) } ?? s.palette
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }

        let pKey = s.particles
            ? "P\(String(format: "%.2f", s.particleDensity))\(String(format: "%.2f", s.particleSize))\(String(format: "%.2f", s.particleSpeed))"
            : "P0"
        let key = "\(mode.id)|\(palette.name)|\(Int(s.thickness))|\(Int(size.width))x\(Int(size.height))|\(String(format: "%.2f", s.intensity))|\(pKey)"
        if key == builtKey && !force { return }
        builtKey = key

        let newScene = GlowScene(size: size, palette: palette,
                                 thickness: CGFloat(s.thickness),
                                 intensity: CGFloat(s.intensity))
        // Notch geometry.
        if let notch = mode as? NotchSceneMode, let scr = window?.screen {
            notch.notchRect = Notch.rect(for: scr, viewSize: size)
            notch.hasReal = Notch.hasRealNotch(scr)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        mode.build(newScene)
        // Sparkle particles overlay (global, on top of any mode).
        if s.particles {
            let sparkles = Sparkles.makeLayer(
                size: size, thickness: CGFloat(s.thickness), palette: palette,
                density: s.particleDensity, sizeScale: s.particleSize,
                speed: s.particleSpeed, intensity: CGFloat(s.intensity))
            newScene.root.addSublayer(sparkles)
        }
        layer?.addSublayer(newScene.root)
        CATransaction.commit()

        scene = newScene
    }

    func liveTick(dt: Double) {
        guard let scene else { return }
        Settings.shared.sceneMode.liveTick(scene, dt: dt)
    }

    var currentModeNeedsTick: Bool { Settings.shared.sceneMode.needsLiveTick() }
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

// MARK: - Manager
//
// Builds scenes and only runs a light timer for the few modes that need live
// per-tick data (e.g. audio). Everything else animates purely on the GPU.

final class GlowManager {
    private var windows: [GlowWindow] = []
    private var liveTimer: Timer?
    private(set) var isEnabled = false

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: Settings.didChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuildScreens),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuildScreens),
            name: Settings.displaysChanged, object: nil)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            rebuildScreens()
            updateLiveTimer()
        } else {
            stopLiveTimer()
            windows.forEach { $0.orderOut(nil) }
            windows.removeAll()
        }
    }

    @objc private func rebuildScreens() {
        guard isEnabled else { return }
        windows.forEach { $0.orderOut(nil) }
        windows = Settings.shared.targetScreens.map { screen in
            let win = GlowWindow(screen: screen)
            win.orderFront(nil)
            win.glowView.rebuildIfNeeded(force: true)
            return win
        }
        updateLiveTimer()
    }

    @objc private func settingsChanged() {
        guard isEnabled else { return }
        // Force a rebuild: per-mode slider values aren't in the cache key, so a
        // mode's own control changes must always re-run its scene build.
        windows.forEach { $0.glowView.rebuildIfNeeded(force: true) }
        updateLiveTimer()
    }

    // Only run a timer if the active mode needs live per-frame data.
    private func updateLiveTimer() {
        let needs = windows.first?.glowView.currentModeNeedsTick ?? false
        if needs { startLiveTimer() } else { stopLiveTimer() }
    }

    private func startLiveTimer() {
        guard liveTimer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.windows.forEach { $0.glowView.liveTick(dt: 1.0 / 30.0) }
        }
        RunLoop.main.add(t, forMode: .common)
        liveTimer = t
    }

    private func stopLiveTimer() {
        liveTimer?.invalidate()
        liveTimer = nil
    }
}
