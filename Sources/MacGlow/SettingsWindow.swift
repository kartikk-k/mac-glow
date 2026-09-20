import Cocoa

// MARK: - Control panel: glow toggle, mode picker, appearance + animation sliders

final class SettingsWindowController: NSWindowController {
    private let s = Settings.shared

    // Wired up by the app delegate so the window can drive the actual glow.
    var isGlowOn: () -> Bool = { false }
    var setGlowOn: (Bool) -> Void = { _ in }

    private var glowSwitch: NSSwitch!
    private var modePopup: NSPopUpButton!
    private var palettePopup: NSPopUpButton!
    private var breathingCheck: NSButton!
    private var rows: [(slider: NSSlider, label: NSTextField, format: (Double) -> String)] = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Mac Glow"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        buildUI()
        window.center()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        // --- Glow on/off switch ---
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
        glowRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(glowRow)
        glowRow.widthAnchor.constraint(equalToConstant: 340).isActive = true

        stack.addArrangedSubview(separator())

        // --- Mode picker ---
        modePopup = labeledPopup(in: stack, title: "Mode",
                                 items: GlowMode.all.map { $0.name },
                                 selected: s.mode.name,
                                 action: #selector(modeChanged))

        // --- Palette picker ---
        palettePopup = labeledPopup(in: stack, title: "Color",
                                    items: Palettes.all.map { $0.name },
                                    selected: s.paletteName,
                                    action: #selector(paletteChanged))

        stack.addArrangedSubview(separator())

        // --- Animation sliders ---
        breathingCheck = NSButton(checkboxWithTitle: "Breathing swell (Breathing mode)",
                                  target: self, action: #selector(breathingToggled))
        breathingCheck.state = s.breathing ? .on : .off
        stack.addArrangedSubview(breathingCheck)

        addSlider(to: stack, title: "Breath speed", min: 1, max: 15,
                  value: s.breathSpeed, tag: 0) { String(format: "%.1f s / breath", $0) }
        addSlider(to: stack, title: "Breath depth (expansion)", min: 0, max: 1,
                  value: s.breathDepth, tag: 1) { String(format: "%.0f%%", $0 * 100) }
        addSlider(to: stack, title: "Thickness", min: 20, max: 240,
                  value: s.thickness, tag: 2) { String(format: "%.0f px", $0) }
        addSlider(to: stack, title: "Intensity", min: 0.1, max: 1.0,
                  value: s.intensity, tag: 3) { String(format: "%.0f%%", $0 * 100) }
    }

    // MARK: builders

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: 340).isActive = true
        return line
    }

    private func labeledPopup(in stack: NSStackView, title: String,
                              items: [String], selected: String,
                              action: Selector) -> NSPopUpButton {
        let row = NSStackView()
        row.orientation = .horizontal
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: items)
        popup.selectItem(withTitle: selected)
        popup.target = self
        popup.action = action

        row.addArrangedSubview(label)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(popup)
        row.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(row)
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: 340),
            popup.widthAnchor.constraint(equalToConstant: 200)
        ])
        return popup
    }

    private func addSlider(to stack: NSStackView, title: String,
                           min: Double, max: Double, value: Double, tag: Int,
                           format: @escaping (Double) -> String) {
        let header = NSStackView()
        header.orientation = .horizontal
        header.distribution = .fill
        header.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)

        let valueLabel = NSTextField(labelWithString: format(value))
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right

        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(NSView())
        header.addArrangedSubview(valueLabel)

        let slider = NSSlider(value: value, minValue: min, maxValue: max,
                              target: self, action: #selector(sliderChanged(_:)))
        slider.tag = tag
        slider.isContinuous = true

        let group = NSStackView(views: [header, slider])
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 4
        group.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(group)

        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalToConstant: 340),
            slider.widthAnchor.constraint(equalToConstant: 340)
        ])

        rows.append((slider, valueLabel, format))
    }

    // MARK: actions

    @objc private func glowToggled() {
        setGlowOn(glowSwitch.state == .on)
    }

    @objc private func modeChanged() {
        guard let name = modePopup.titleOfSelectedItem,
              let mode = GlowMode.all.first(where: { $0.name == name }) else { return }
        s.modeID = mode.id
    }

    @objc private func paletteChanged() {
        guard let name = palettePopup.titleOfSelectedItem else { return }
        s.paletteName = name
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let v = sender.doubleValue
        switch sender.tag {
        case 0: s.breathSpeed = v
        case 1: s.breathDepth = v
        case 2: s.thickness = v
        case 3: s.intensity = v
        default: break
        }
        let row = rows[sender.tag]
        row.label.stringValue = row.format(v)
    }

    @objc private func breathingToggled() {
        s.breathing = breathingCheck.state == .on
    }

    // Refresh controls from current state (e.g. when reopened or toggled elsewhere).
    private func syncControls() {
        glowSwitch?.state = isGlowOn() ? .on : .off
        modePopup?.selectItem(withTitle: s.mode.name)
        palettePopup?.selectItem(withTitle: s.paletteName)
    }

    func show() {
        syncControls()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
