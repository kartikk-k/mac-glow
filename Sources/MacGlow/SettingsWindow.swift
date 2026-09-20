import Cocoa

// MARK: - Control panel
//
// Top section is shared (glow switch, mode picker, color, global sliders). Below
// it, a per-mode section rebuilds itself from the selected mode's controls() so
// each prototype gets its own tailored settings and trigger buttons.

final class SettingsWindowController: NSWindowController {
    private let s = Settings.shared

    var isGlowOn: () -> Bool = { false }
    var setGlowOn: (Bool) -> Void = { _ in }

    private var glowSwitch: NSSwitch!
    private var modePopup: NSPopUpButton!
    private var palettePopup: NSPopUpButton!
    private var displayPopup: NSPopUpButton!
    private var particlesCheck: NSButton!
    private var rootStack: NSStackView!
    private var modeSection: NSStackView!

    // Live-updating value labels for global sliders.
    private var globalRows: [(slider: NSSlider, label: NSTextField, format: (Double) -> String)] = []
    // Value labels for the current mode's sliders.
    private var modeRows: [(slider: NSSlider, label: NSTextField, format: (Double) -> String)] = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Mac Glow"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        buildUI()
        window.center()
    }

    // MARK: build

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc

        rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 14
        rootStack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: doc.topAnchor),
            rootStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            rootStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.widthAnchor)
        ])

        buildSharedSection()
        modeSection = NSStackView()
        modeSection.orientation = .vertical
        modeSection.alignment = .leading
        modeSection.spacing = 12
        rootStack.addArrangedSubview(modeSection)
        rebuildModeSection()
    }

    private func buildSharedSection() {
        // Glow switch.
        let glowRow = NSStackView()
        glowRow.orientation = .horizontal
        let glowLabel = NSTextField(labelWithString: "Glow")
        glowLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        glowSwitch = NSSwitch()
        glowSwitch.state = isGlowOn() ? .on : .off
        glowSwitch.target = self
        glowSwitch.action = #selector(glowToggled)
        glowRow.addArrangedSubview(glowLabel)
        glowRow.addArrangedSubview(NSView())
        glowRow.addArrangedSubview(glowSwitch)
        addFullWidth(glowRow, to: rootStack)

        rootStack.addArrangedSubview(separator())

        modePopup = labeledPopup(title: "Mode",
                                 items: s.allModes.map { $0.name },
                                 selected: s.sceneMode.name,
                                 action: #selector(modeChanged))
        palettePopup = labeledPopup(title: "Color",
                                    items: Palettes.all.map { $0.name },
                                    selected: s.paletteName,
                                    action: #selector(paletteChanged))
        displayPopup = labeledPopup(title: "Display",
                                    items: ["Primary only", "All displays"],
                                    selected: s.displayTarget == 0 ? "Primary only" : "All displays",
                                    action: #selector(displayChanged))

        rootStack.addArrangedSubview(separator())

        let hdr = NSTextField(labelWithString: "GLOW")
        hdr.font = .systemFont(ofSize: 10, weight: .bold)
        hdr.textColor = .tertiaryLabelColor
        rootStack.addArrangedSubview(hdr)

        addGlobalSlider("Thickness", min: 20, max: 240,
                        get: { self.s.thickness }, set: { self.s.thickness = $0 }) {
            String(format: "%.0f px", $0) }
        addGlobalSlider("Intensity", min: 0.1, max: 1.0,
                        get: { self.s.intensity }, set: { self.s.intensity = $0 }) {
            String(format: "%.0f%%", $0 * 100) }

        rootStack.addArrangedSubview(separator())
        let pHdr = NSTextField(labelWithString: "PARTICLES")
        pHdr.font = .systemFont(ofSize: 10, weight: .bold)
        pHdr.textColor = .tertiaryLabelColor
        rootStack.addArrangedSubview(pHdr)

        particlesCheck = NSButton(checkboxWithTitle: "Sparkle particles",
                                  target: self, action: #selector(particlesToggled))
        particlesCheck.state = s.particles ? .on : .off
        rootStack.addArrangedSubview(particlesCheck)

        addGlobalSlider("Density", min: 0, max: 1,
                        get: { self.s.particleDensity }, set: { self.s.particleDensity = $0 }) {
            String(format: "%.0f%%", $0 * 100) }
        addGlobalSlider("Particle size", min: 0, max: 1,
                        get: { self.s.particleSize }, set: { self.s.particleSize = $0 }) {
            String(format: "%.0f%%", $0 * 100) }
        addGlobalSlider("Twinkle speed", min: 0.15, max: 1.5,
                        get: { self.s.particleSpeed }, set: { self.s.particleSpeed = $0 }) {
            String(format: "%.0f%%", $0 / 1.5 * 100) }
    }

    @objc private func particlesToggled() {
        s.particles = particlesCheck.state == .on
    }

    // Rebuild the per-mode section from the active mode's controls().
    func rebuildModeSection() {
        guard let modeSection else { return }
        modeSection.arrangedSubviews.forEach { $0.removeFromSuperview() }
        modeRows.removeAll()

        let mode = s.sceneMode
        let store = ModeStore(mode.id)

        modeSection.addArrangedSubview(separator())
        let title = NSTextField(labelWithString: mode.name.uppercased())
        title.font = .systemFont(ofSize: 10, weight: .bold)
        title.textColor = .tertiaryLabelColor
        modeSection.addArrangedSubview(title)

        for control in mode.controls() {
            switch control {
            case .label(let text):
                let l = NSTextField(wrappingLabelWithString: text)
                l.font = .systemFont(ofSize: 11)
                l.textColor = .secondaryLabelColor
                l.preferredMaxLayoutWidth = 340
                addFullWidth(l, to: modeSection)

            case .slider(let key, let t, let mn, let mx, let def, let fmt):
                addModeSlider(store: store, key: key, title: t, min: mn, max: mx, def: def, format: fmt)

            case .toggle(let key, let t, let def):
                let btn = NSButton(checkboxWithTitle: t, target: self, action: #selector(modeToggle(_:)))
                btn.state = store.bool(key, def) ? .on : .off
                btn.identifier = NSUserInterfaceItemIdentifier("\(mode.id)|\(key)")
                modeSection.addArrangedSubview(btn)

            case .popup(let key, let t, let options, let def):
                let p = labeledPopup(title: t, items: options,
                                     selected: options[safe: Int(store.double(key, Double(def)))] ?? options.first ?? "",
                                     action: #selector(modePopupChanged(_:)),
                                     addTo: modeSection)
                p.identifier = NSUserInterfaceItemIdentifier("\(mode.id)|\(key)")

            case .button(let t, let action):
                let b = ClosureButton(title: t) { action() }
                addFullWidth(b, to: modeSection)

            case .momentary(let t, let down, let up):
                let b = HoldButton(title: t, onDown: down, onUp: up)
                addFullWidth(b, to: modeSection)
            }
        }
        window?.layoutIfNeeded()
    }

    // MARK: builders

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: 360).isActive = true
        return line
    }

    private func addFullWidth(_ v: NSView, to stack: NSStackView) {
        v.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(v)
        v.widthAnchor.constraint(equalToConstant: 360).isActive = true
    }

    private func labeledPopup(title: String, items: [String], selected: String,
                              action: Selector, addTo: NSStackView? = nil) -> NSPopUpButton {
        let row = NSStackView()
        row.orientation = .horizontal
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: items)
        popup.selectItem(withTitle: selected)
        popup.target = self
        popup.action = action
        row.addArrangedSubview(label)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(popup)
        addFullWidth(row, to: addTo ?? rootStack)
        popup.widthAnchor.constraint(equalToConstant: 200).isActive = true
        return popup
    }

    private func addGlobalSlider(_ title: String, min: Double, max: Double,
                                 get: @escaping () -> Double, set: @escaping (Double) -> Void,
                                 format: @escaping (Double) -> String) {
        let (group, slider, valueLabel) = sliderGroup(title: title, min: min, max: max,
                                                       value: get(), format: format)
        slider.target = self
        slider.action = #selector(globalSliderChanged(_:))
        slider.tag = globalRows.count
        addFullWidth(group, to: rootStack)
        globalRows.append((slider, valueLabel, format))
        // Store setter alongside via associated tag order.
        globalSetters.append(set)
    }
    private var globalSetters: [(Double) -> Void] = []

    private func addModeSlider(store: ModeStore, key: String, title: String,
                               min: Double, max: Double, def: Double,
                               format: @escaping (Double) -> String) {
        let (group, slider, valueLabel) = sliderGroup(title: title, min: min, max: max,
                                                      value: store.double(key, def),
                                                      format: format)
        slider.target = self
        slider.action = #selector(modeSliderChanged(_:))
        slider.identifier = NSUserInterfaceItemIdentifier("\(store.ns)|\(key)")
        slider.tag = modeRows.count
        addFullWidth(group, to: modeSection)
        modeRows.append((slider, valueLabel, format))
    }

    private func sliderGroup(title: String, min: Double, max: Double, value: Double,
                             format: @escaping (Double) -> String)
        -> (NSStackView, NSSlider, NSTextField) {
        let header = NSStackView()
        header.orientation = .horizontal
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        let valueLabel = NSTextField(labelWithString: format(value))
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(NSView())
        header.addArrangedSubview(valueLabel)
        header.translatesAutoresizingMaskIntoConstraints = false

        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: nil, action: nil)
        slider.isContinuous = true

        let group = NSStackView(views: [header, slider])
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 4
        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalToConstant: 360),
            slider.widthAnchor.constraint(equalToConstant: 360)
        ])
        return (group, slider, valueLabel)
    }

    // MARK: actions

    @objc private func glowToggled() { setGlowOn(glowSwitch.state == .on) }

    @objc private func modeChanged() {
        guard let name = modePopup.titleOfSelectedItem,
              let mode = s.allModes.first(where: { $0.name == name }) else { return }
        s.modeID = mode.id
        rebuildModeSection()
    }

    @objc private func paletteChanged() {
        guard let name = palettePopup.titleOfSelectedItem else { return }
        s.paletteName = name
    }

    @objc private func displayChanged() {
        s.displayTarget = displayPopup.indexOfSelectedItem
    }

    @objc private func globalSliderChanged(_ sender: NSSlider) {
        let v = sender.doubleValue
        globalSetters[sender.tag](v)
        let row = globalRows[sender.tag]
        row.label.stringValue = row.format(v)
    }

    @objc private func modeSliderChanged(_ sender: NSSlider) {
        guard let id = sender.identifier?.rawValue else { return }
        let parts = id.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        ModeStore(parts[0]).setDouble(parts[1], sender.doubleValue)
        let row = modeRows[sender.tag]
        row.label.stringValue = row.format(sender.doubleValue)
    }

    @objc private func modeToggle(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        let parts = id.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        ModeStore(parts[0]).setBool(parts[1], sender.state == .on)
    }

    @objc private func modePopupChanged(_ sender: NSPopUpButton) {
        guard let id = sender.identifier?.rawValue else { return }
        let parts = id.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        ModeStore(parts[0]).setDouble(parts[1], Double(sender.indexOfSelectedItem))
    }

    private func syncControls() {
        glowSwitch?.state = isGlowOn() ? .on : .off
        modePopup?.selectItem(withTitle: s.sceneMode.name)
        palettePopup?.selectItem(withTitle: s.paletteName)
    }

    func show() {
        syncControls()
        rebuildModeSection()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Small button helpers

final class ClosureButton: NSButton {
    private let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        target = self
        action = #selector(fire)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}

// Press-and-hold button for push-to-talk.
final class HoldButton: NSButton {
    private let onDown: () -> Void
    private let onUp: () -> Void
    init(title: String, onDown: @escaping () -> Void, onUp: @escaping () -> Void) {
        self.onDown = onDown; self.onUp = onUp
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) {
        highlight(true); onDown()
        // Block until mouse up so it's a true hold.
        var holding = true
        while holding {
            guard let e = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) else { break }
            if e.type == .leftMouseUp { holding = false }
        }
        onUp(); highlight(false)
    }
}

