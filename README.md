# Mac Glow

An ambient glow that wraps your **entire screen** in a soft gradient of light
along the edges — an experiment in giving the Mac a peripheral "presence" layer.
The glow has **modes**, each with its own motion signature, so it can express
state (idle, listening, thinking, speaking) without a window. Prototype.

## The idea

The screen edge is always in your peripheral vision but never in the way — a
perfect ambient status channel. Mac Glow turns it into one. Today it's driven by
a menu picker; the modes are designed to eventually be driven by an assistant /
system events (mic active → Listening, model working → Thinking, etc.).

## Modes

Each mode is a self-contained renderer with its **own settings section** in the
Settings window. Modes that react to a real signal (audio, notifications, an
assistant, keystrokes) include prototyping controls so you can drive them by hand.

- **Breathing** — slow symmetric swell. The calm idle state.
- **Scanner** — a soft bar sweeps calmly around the perimeter (a gentle radar).
- **Progress** — light fills the perimeter 0→100% for a long task. Includes a
  "Simulate 0→100%" button and a manual progress slider.
- **Notification** — a bloom appears on the edge nearest where an alert came
  from. Fire buttons for each corner.
- **Focus Corner** — the glow gathers toward a chosen corner to pull your eye.
- **Audio Reactive** — pulses with your microphone (asks permission), or a
  built-in "Simulate audio" fallback.
- **Flow** — warmth builds as you type and fades on pause (warm palette).
- **Assistant** — three honest states: idle (breath) / working (sweep) /
  needs-you (calm attention pulses).
- **Push to Talk** — hold the button to listen, release to think, then settle.
- **Confirmation** — a soft green success swell, or amber attention pulses.
- **Notch Halo** — a glow hugging the camera notch (auto-detected; falls back to
  a simulated top-center notch on Macs without one).

All motion is calmly timed. Edges blend seam-free and the perimeter is a
continuous ray-cast coordinate, so corners never show wedge artifacts.

## Architecture

- `Modes.swift` — the `GlowRenderer` protocol + `ModeControl` (how a mode
  declares its own settings) + per-mode persisted `ModeStore`.
- `Renderers.swift` — all 11 modes, each ~20-40 lines.
- `GlowView.swift` — the shared per-pixel field (edge falloff, palette,
  perimeter) that drives whatever renderer is active.
- `SettingsWindow.swift` — rebuilds its lower section from the active mode's
  `controls()`, so each mode gets a tailored panel.
- `AudioLevel.swift` — mic level source (with simulate fallback) + notch detect.

Adding a new mode = one class in `Renderers.swift` + one line in the registry.

## Features

- **Full-screen edge glow** on every connected display (not per-window). No
  Accessibility permission needed.
- **Seam-free corners** — edges blend so corners bloom smoothly (no frame lines).
- **Gradient picker**: Ice Blue (default), Aurora, Sunset, Emerald, Magenta,
  Mono White. Each shows a live swatch. Color is independent of mode.
- **All-in-one Settings panel** (⌘,): glow on/off switch, mode picker, color
  picker, and live sliders for breath speed, depth, thickness, and intensity.
- Remembers your last on/off state, mode, palette, and settings across launches.
- Menu bar only (no dock icon); click-through overlay never steals focus.

## Ideas / roadmap

- Wire modes to real signals (mic, assistant activity, task progress).
- More ambient elements: glowing corner brackets, a perimeter progress ring,
  a notch halo, an edge waveform reactive to real audio.
- Per-mode color accents (success = green swell, error = red flashes).

## Build & run

```bash
./build-app.sh release
open MacGlow.app
```

Or during development:

```bash
swift run
```

Then click the ✨ in the menu bar → **Glow: On**.

## Where things live (`Sources/MacGlow/`)

- `main.swift` — menu bar app, gradient submenu, settings entry point.
- `GlowView.swift` — the full-screen edge-glow drawing + breathing loop +
  per-screen overlay windows.
- `SettingsWindow.swift` — the animation control panel (AppKit sliders).
- `Settings.swift` — palettes + persisted, observable settings.

## Tuning without the UI

Add a palette by appending to `Palettes.all` in `Settings.swift`. Adjust
defaults (thickness, speed, depth, intensity) in the same file.
