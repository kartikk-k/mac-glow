import Cocoa
import AVFoundation

// MARK: - Audio level source
//
// Provides a smoothed 0..1 "loudness" level for audio-reactive modes. Tries the
// real microphone (asks permission on first use); if denied/unavailable, or when
// `simulate` is on, produces a lively synthetic level so the mode is always
// explorable.

final class AudioLevel {
    static let shared = AudioLevel()

    private let engine = AVAudioEngine()
    private var running = false
    private(set) var micAuthorized = false
    private(set) var micActive = false

    // Latest smoothed level (0..1), read by the render loop.
    private(set) var level: Double = 0
    private var raw: Double = 0

    // Synthetic level state (used for simulate / fallback).
    private var simClock: Double = 0

    // Start capturing. Returns immediately; permission resolves async.
    func startMic() {
        guard !running else { return }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.micAuthorized = granted
                if granted { self?.installTap() }
            }
        }
    }

    func stopMic() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        micActive = false
    }

    private func installTap() {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.channelCount > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let ch = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { let v = ch[i]; sum += v * v }
            let rms = n > 0 ? sqrt(sum / Float(n)) : 0
            // Map RMS to a perceptual 0..1 (rough, tuned for speech/music).
            let db = 20 * log10(max(1e-6, Double(rms)))          // ~ -60..0
            let norm = max(0, min(1, (db + 55) / 55))
            DispatchQueue.main.async { self.raw = norm }
        }
        do {
            try engine.start()
            running = true
            micActive = true
        } catch {
            running = false
            micActive = false
        }
    }

    // Called each frame. `simulate` forces the synthetic source.
    func tick(dt: Double, simulate: Bool) {
        let target: Double
        if simulate || !micActive {
            // Synthetic "speech-like" envelope: layered pulses with gaps.
            simClock += dt
            let s = simClock
            let syllable = pow(max(0, sin(s * 6.0)), 4)             // quick bursts
            let phrase = 0.5 + 0.5 * sin(s * 0.7)                   // rise/fall over phrases
            let gap = sin(s * 0.23) > -0.3 ? 1.0 : 0.15             // occasional pauses
            target = min(1, (0.15 + 0.85 * syllable) * phrase * gap)
        } else {
            target = raw
        }
        // Asymmetric smoothing: rise fast, fall slower — feels natural.
        let rise = 0.6, fall = 0.12
        let k = target > level ? rise : fall
        level += (target - level) * k
    }
}

// MARK: - Notch detection

enum Notch {
    // Returns the notch rect in the given screen's *view* coordinates (origin
    // bottom-left, matching the overlay), or a simulated top-center rect if the
    // display has no notch.
    static func rect(for screen: NSScreen, viewSize: CGSize) -> CGRect {
        let full = screen.frame
        let safeTopInset = screen.safeAreaInsets.top   // > 0 on notched Macs

        let notchWidth: CGFloat
        let notchHeight: CGFloat
        if safeTopInset > 1 {
            // Real notch: height ~ safe-area inset; width is not exposed by the
            // API, so use a typical notch aspect (~ 2.9x the height).
            notchHeight = safeTopInset
            notchWidth = safeTopInset * 2.9
        } else {
            // Simulated notch for non-notched displays.
            notchHeight = 34
            notchWidth = 180
        }
        // Center horizontally, hug the TOP. NOTE: the render buffer maps ny=0 to
        // the top of the screen, and NotchMode computes py = ny * height, so the
        // top of the screen is py≈0. Place the notch rect there.
        let x = (viewSize.width - notchWidth) / 2
        let y = 0.0
        _ = full
        return CGRect(x: x, y: y, width: notchWidth, height: notchHeight)
    }

    static func hasRealNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 1
    }
}
