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

Each mode is a distinct **motion**, not just a color:

- **Breathing** — slow symmetric swell in/out. The calm, idle resting state.
- **Listening** — fast, shallow audio-meter shimmer dancing along the edges.
- **Thinking** — a bright comet of light orbiting the perimeter with a tail.
- **Speaking** — brightness waves radiating from the top edge, like sound.
- **Focus** — dead still and dim; quiet / do-not-disturb.

## Features

- **Full-screen edge glow** on every connected display (not per-window). No
  Accessibility permission needed.
- **Seam-free corners** — edges blend so corners bloom smoothly (no frame lines).
- **Gradient picker**: Ice Blue (default), Aurora, Sunset, Emerald, Magenta,
  Mono White. Each shows a live swatch. Color is independent of mode.
- **Animation Settings** panel (⌘,) with live sliders: breath speed, breath
  depth, thickness, intensity, and a breathing on/off toggle.
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
