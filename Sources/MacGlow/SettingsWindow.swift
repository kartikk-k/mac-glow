import Cocoa

// MARK: - Animation & appearance control panel

final class SettingsWindowController: NSWindowController {
    private let s = Settings.shared

    // Keep references so callbacks can read/update them.
    private var breathingCheck: NSButton!
    private var rows: [(slider: NSSlider, label: NSTextField, format: (Double) -> String)] = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Glow Settings"
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

        // Breathing toggle.
        breathingCheck = NSButton(checkboxWithTitle: "Breathing animation",
                                  target: self, action: #selector(breathingToggled))
        breathingCheck.state = s.breathing ? .on : .off
        stack.addArrangedSubview(breathingCheck)

        // Sliders.
        addSlider(to: stack, title: "Breath speed", min: 1, max: 15,
                  value: s.breathSpeed, tag: 0) { String(format: "%.1f s / breath", $0) }
        addSlider(to: stack, title: "Breath depth (expansion)", min: 0, max: 1,
                  value: s.breathDepth, tag: 1) { String(format: "%.0f%%", $0 * 100) }
        addSlider(to: stack, title: "Thickness", min: 20, max: 240,
                  value: s.thickness, tag: 2) { String(format: "%.0f px", $0) }
        addSlider(to: stack, title: "Intensity", min: 0.1, max: 1.0,
                  value: s.intensity, tag: 3) { String(format: "%.0f%%", $0 * 100) }
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
        header.addArrangedSubview(NSView()) // spacer
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
            header.widthAnchor.constraint(equalToConstant: 320),
            slider.widthAnchor.constraint(equalToConstant: 320)
        ])

        rows.append((slider, valueLabel, format))
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

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
