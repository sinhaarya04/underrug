# Contributing to Underrug

Thanks for wanting to help! Underrug is a small, single-purpose app, and the bar for changes is that the rug still
feels like a rug: it lies flat, peels back like fabric, and never touches your files.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Quick guide

- **Found a bug?** Search [the issues](https://github.com/sinhaarya04/underrug/issues) first, then open a
  [bug report](https://github.com/sinhaarya04/underrug/issues/new?template=bug_report.yml). Include your macOS version
  and whether Finder's *Sort By* or *Use Stacks* is on; most sweep problems come down to one of those.
- **Have an idea?** Open a [feature request](https://github.com/sinhaarya04/underrug/issues/new?template=feature_request.yml)
  before writing code, so we can agree on the shape of it.
- **Want to add a rug design?** See [Adding a rug](#adding-a-rug). These are the easiest first contributions.
- **Security issue?** Don't open an issue; see [SECURITY.md](SECURITY.md).

## Working on the code

You need macOS 13 or later and Apple's Command Line Tools (`xcode-select --install`). There is no Xcode project and
there are no dependencies.

```sh
git clone https://github.com/sinhaarya04/underrug.git && cd underrug
./build.sh                 # builds build/Underrug.app (universal: Apple silicon and Intel)
open build/Underrug.app
```

Quit it from the menu bar icon (or `pkill -f Underrug.app`) before running a new build.

### Seeing your change without touching your desktop

`--snapshot` renders one frame over a stand-in desktop (wood floor, a few icons) and writes a PNG. It's the quickest
way to check drawing changes, and screenshots from it are welcome in PRs.

```sh
APP=build/Underrug.app/Contents/MacOS/Underrug
$APP --snapshot out.png --controls             # corner dots, Design pill, rotate tip
$APP --snapshot out.png --fold                 # a corner peeled back
$APP --snapshot out.png --lifted               # peeled most of the way, showing a swept heap
$APP --snapshot out.png --peek                 # holding ⌥
$APP --snapshot out.png --pattern prayerRug    # any Pattern case name
```

### Code structure

| File | What it does |
|---|---|
| `Sources/Geometry.swift` | Where the rug lies (`Placement`) and the fold a peel makes (`Fold`) |
| `Sources/Renderer.swift` | Draws the rug, the turned-back flap and the controls with Core Graphics |
| `Sources/RugController.swift` | The overlay window, gestures (move, rotate, peel, pinch), ⌥ peek, drag and drop, menus |
| `Sources/Patterns.swift` | The rug designs, loading their photos, and the drawn fringe |
| `Sources/Desktop.swift` | Asking Finder for icon positions and the current selection, and moving icons |
| `Sources/Sweeper.swift` | Sweep and unsweep: the heap layout and the saved original positions |
| `Sources/main.swift` | App entry, menu bar icon, `--snapshot` and `--icon` |

### Ground rules

- **Never move, rename or delete a user's files.** Sweeping only changes icon positions through Finder, and every
  sweep must be undoable with *Put the Icons Back*.
- **No network access.** Underrug works entirely offline.
- **Keep it light.** The app should idle at ~0% CPU; animate only while something is moving.
- Match the surrounding style: small types, short comments that explain *why*, no new dependencies.

## Adding a rug

Designs are photographs of real rugs that are in the public domain. The Met's
[Open Access collection](https://www.metmuseum.org/art/collection/search?showOnly=openAccess) is a good source.

1. Pick a carpet whose photo is straight-on, complete (all four borders) and clearly rectangular (wider than about
   1.35 : 1). Check the object page says **Public Domain**.
2. Download the full-size image and crop it:
   ```sh
   swiftc -O scripts/crop-rug.swift -o /tmp/crop-rug
   /tmp/crop-rug path/to/download.jpg Rugs/<objectID>.jpg 2200
   ```
   Open the result and make sure no backdrop or real fringe is left at the edges.
3. Add a case to `Pattern` in `Sources/Patterns.swift` (title, origin, Met ID) and a row to [CREDITS.md](CREDITS.md).
4. Render it with `--snapshot out.png --pattern <case>` and attach the image to your PR.

## Pull requests

- Keep each PR to one change, and describe how you tested it (a snapshot or a short screen recording is ideal).
- `./build.sh` must succeed with no warnings; CI builds every PR.
- Add a line to the *Unreleased* section of [CHANGELOG.md](CHANGELOG.md) for anything a user would notice.
- Be ready to iterate on review comments.
