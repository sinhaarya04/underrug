# Underrug

A rug for your Mac desktop. Sweep your mess under it.

- **Drag** the rug to move it. **Drag an edge** to peel it back and peek at what's underneath; let go and it falls flat again.
- **Drag a corner dot** to rotate it (or scroll over it).
- The **Design** pill under the rug flips through the patterns: Persian, Kilim, Beni Ourain, Picnic Gingham, Sunset Stripes, or weave in your own image.
- **Hold ⌥** to see through it and click the files underneath.
- **Sweep Under the Rug** has Finder pile every desktop icon beneath the rug. Only icon positions change, never the files, and **Put the Icons Back** returns each one to where it was. If Finder's *Sort By* or *Use Stacks* is on, Finder keeps its own order; Underrug says so instead of pretending.
- **Size** goes from small to covering the whole desktop.

Everything else is in the menu bar icon, or right-click the rug.

## Build

```sh
./build.sh          # Command Line Tools are enough; outputs build/Underrug.app
open build/Underrug.app
```

The first sweep asks to let Underrug control Finder, which is how it moves icons.

`build/Underrug.app/Contents/MacOS/Underrug --snapshot out.png [--controls] [--fold] [--peek] [--swept] [--pattern kilim]` renders a frame offline over a stand-in desktop.

## Layout

- `Geometry.swift`: where the rug lies, and the fold a peel makes
- `Renderer.swift`: draws the rug, the turned-back flap and the controls (Core Graphics)
- `RugController.swift`: the overlay window, gestures, ⌥ peek and the menu
- `Patterns.swift`: the procedural rug textures
- `Desktop.swift`, `Sweeper.swift`: Finder icon positions, sweep and unsweep
