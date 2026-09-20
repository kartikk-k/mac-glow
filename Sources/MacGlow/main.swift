import Cocoa

// MARK: - Menu bar app
//
// Full-screen edge glow with a breathing animation. Toggle on/off, pick a
// gradient palette, and open a settings panel to tune the animation.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let manager = GlowManager()
    private lazy var settingsWC = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu bar only, no dock icon

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles",
                                   accessibilityDescription: "Glow")
        }
        // Let the settings window drive the glow directly.
        settingsWC.isGlowOn = { [weak self] in self?.manager.isEnabled ?? false }
        settingsWC.setGlowOn = { [weak self] on in self?.setGlow(on) }

        rebuildMenu()

        // Restore the last on/off state across launches.
        if UserDefaults.standard.bool(forKey: "glowEnabled") {
            manager.setEnabled(true)
            rebuildMenu()
        }
    }

    // Single place that flips the glow and keeps everything in sync.
    private func setGlow(_ on: Bool) {
        manager.setEnabled(on)
        UserDefaults.standard.set(on, forKey: "glowEnabled")
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: manager.isEnabled ? "Glow: On" : "Glow: Off",
            action: #selector(toggleGlow), keyEquivalent: "")
        toggle.target = self
        toggle.state = manager.isEnabled ? .on : .off
        menu.addItem(toggle)

        menu.addItem(.separator())

        // Mode submenu — the ambient "AI presence" states.
        let modeItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        let currentMode = Settings.shared.modeID
        for mode in GlowMode.all {
            let item = NSMenuItem(title: mode.name,
                                  action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.id
            item.image = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: mode.name)
            item.state = mode.id == currentMode ? .on : .off
            modeMenu.addItem(item)
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        // Gradient submenu with color-swatch icons.
        let gradientItem = NSMenuItem(title: "Gradient", action: nil, keyEquivalent: "")
        let gradientMenu = NSMenu()
        let current = Settings.shared.paletteName
        for palette in Palettes.all {
            let item = NSMenuItem(title: palette.name,
                                  action: #selector(selectPalette(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = palette.name
            item.image = swatch(for: palette)
            item.state = palette.name == current ? .on : .off
            gradientMenu.addItem(item)
        }
        gradientItem.submenu = gradientMenu
        menu.addItem(gradientItem)

        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // A small horizontal gradient swatch preview for a palette.
    private func swatch(for palette: Palette) -> NSImage {
        let size = NSSize(width: 28, height: 14)
        let image = NSImage(size: size)
        image.lockFocus()
        let colors = palette.colors.map { $0.withAlphaComponent(1).cgColor }
        let gradient = NSGradient(colors: palette.colors)
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 0)
        _ = colors
        NSColor.white.withAlphaComponent(0.25).setStroke()
        let border = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size),
                                  xRadius: 3, yRadius: 3)
        border.stroke()
        image.unlockFocus()
        return image
    }

    @objc private func toggleGlow() {
        setGlow(!manager.isEnabled)
    }

    @objc private func selectPalette(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        Settings.shared.paletteName = name
        rebuildMenu()
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Settings.shared.modeID = id
        rebuildMenu()
    }

    @objc private func openSettings() {
        settingsWC.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
