# Mac Glow

A menu bar app that wraps your **entire screen** in a soft, breathing gradient
glow along the edges. Pick a color palette, tune the animation, toggle on/off —
all from the menu bar. A concept sketch.

## Features

- **Full-screen edge glow** on every connected display (not per-window). No
  Accessibility permission needed.
- **Gradient picker** in the menu bar: Ice Blue (default), Aurora, Sunset,
  Emerald, Magenta, Mono White. Each shows a live swatch.
- **Breathing animation** — the glow gently expands/contracts and brightens.
- **Animation Settings** panel (⌘,) with live sliders:
  - Breath speed (seconds per breath)
  - Breath depth (how far it expands)
  - Thickness (base band width)
  - Intensity (overall opacity)
  - Breathing on/off
- Remembers your last on/off state, palette, and settings across launches.
- Menu bar only (no dock icon); click-through overlay never steals focus.

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
