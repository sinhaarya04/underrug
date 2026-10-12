# Underrug

A rug for your Mac desktop. It lies over your icons, drapes into soft lumps wherever files sit underneath, and moves like real cloth when you drag it.

- **Drag** to move it, **scroll** over it to rotate, **double-click** to shake it out.
- **Hold ⌥** to see through it and click the files underneath.
- **Rug designs:** Persian, Kilim, Beni Ourain, Picnic Gingham, Sunset Stripes, or weave in your own image.
- **Size** (small to covering the whole desktop) and **fabric** (heavy wool, cotton, silk) change how it drapes.
- **Sweep Under the Rug** moves the desktop clutter into `~/Desktop/Under the Rug/<date>`. That folder sits under the rug as one lump that grows with what you've swept. **Unsweep** puts everything back.
- The physics sleeps once the rug settles, so it idles under 1% CPU.

Everything is in the menu bar icon, or right-click the rug.

## Build

```sh
./build.sh          # Command Line Tools are enough; outputs build/Underrug.app
open build/Underrug.app
```

On first launch macOS asks to let Underrug control Finder. Finder is where it reads your icon positions; without access it guesses a default grid.

`build/Underrug.app/Contents/MacOS/Underrug --snapshot out.png [--drag] [--pattern kilim]` renders a frame offline against your real desktop layout.
