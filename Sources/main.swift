import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: RugController?
    var status: NSStatusItem?

    func applicationDidFinishLaunching(_ note: Notification) {
        guard let screen = NSScreen.screens.first else { return }
        let c = RugController(screen: screen)
        controller = c
        c.show()
        let s = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        s.button?.image = Self.menuIcon()
        s.button?.toolTip = "Underrug"
        s.menu = c.menu()
        status = s
    }

    /// A tiny rug with fringe, drawn as a template image for the menu bar.
    static func menuIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 14), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let body = NSRect(x: 4, y: 2, width: 12, height: 10)
            NSBezierPath(roundedRect: body, xRadius: 1.5, yRadius: 1.5).stroke()
            NSBezierPath(rect: body.insetBy(dx: 3, dy: 3)).fill()
            for y in stride(from: 3.0, through: 11.0, by: 2.0) {
                NSBezierPath.strokeLine(from: NSPoint(x: 1, y: y), to: NSPoint(x: 4, y: y))
                NSBezierPath.strokeLine(from: NSPoint(x: 16, y: y), to: NSPoint(x: 19, y: y))
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

// MARK: offline renders for previews, testing and the app icon

func writePNG(_ img: NSImage, _ path: String) {
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

/// --snapshot out.png [--pattern kilim] [--fold] [--lifted] [--controls] [--peek] [--swept]:
/// render one frame over a stand-in desktop (wood floor, a handful of icons).
func snapshot(_ args: [String]) {
    let out = args.first { $0.hasSuffix(".png") } ?? "underrug.png"
    let size = CGSize(width: 1512, height: 982)
    let name = args.firstIndex(of: "--pattern").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    let pattern = Pattern(rawValue: name ?? "") ?? .anatolianRed
    let body = CGSize(width: 620, height: 620 / RugArt.aspect(pattern)), fringe: CGFloat = 26
    let rug = Placement(center: CGPoint(x: size.width * 0.48, y: size.height * 0.52), angle: -0.06,
                        size: CGSize(width: body.width + 2 * fringe, height: body.height), fringe: fringe)

    var frame = RugFrame(placement: rug, texture: RugArt.texture(pattern, body: body, fringe: fringe))
    if args.contains("--fold") {  // the bottom-right corner turned back toward the middle
        let c = CGPoint(x: rug.body.maxX, y: rug.body.minY)
        frame.fold = Fold(from: c, to: CGPoint(x: c.x - 300, y: c.y + 170))
    }
    if args.contains("--lifted") {  // turned most of the way back, showing the heap underneath
        let c = CGPoint(x: rug.body.maxX, y: rug.body.maxY)
        frame.fold = Fold(from: c, to: CGPoint(x: c.x - 760, y: c.y - 520))
    }
    if args.contains("--controls") {
        frame.controls = true
        frame.rotateTip = rug.corners[1]
    }
    if args.contains("--peek") { frame.opacity = 0.12; frame.optionBadge = true }

    var rng = SeededRNG(seed: 3)
    let icons = ["--swept", "--fold", "--peek", "--lifted"].contains(where: args.contains)
        ? Sweeper.pile(22, under: rug)
        : (0..<14).map { k in CGPoint(x: size.width - 70 - CGFloat(k / 7) * 100, y: size.height - 90 - CGFloat(k % 7) * 110) }

    let img = NSImage(size: size, flipped: false) { rect in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        woodFloor(ctx, rect, &rng)
        for c in icons { fakeIcon(ctx, c) }
        Renderer.draw(frame, in: ctx, bounds: rect)
        return true
    }
    writePNG(img, out)
    print("wrote \(out)")
}

private func woodFloor(_ ctx: CGContext, _ r: CGRect, _ rng: inout SeededRNG) {
    let rowH: CGFloat = 46
    var y = r.minY
    while y < r.maxY {
        var x = r.minX - CGFloat.random(in: 0...300, using: &rng)
        while x < r.maxX {
            let w = CGFloat.random(in: 220...460, using: &rng), t = CGFloat.random(in: 0...1, using: &rng)
            ctx.setFillColor(CGColor(red: 0.84 + 0.06 * t, green: 0.70 + 0.06 * t, blue: 0.52 + 0.05 * t, alpha: 1))
            ctx.fill(CGRect(x: x, y: y, width: w, height: rowH))
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.12))
            ctx.fill(CGRect(x: x, y: y, width: 1.5, height: rowH))
            x += w
        }
        ctx.fill(CGRect(x: r.minX, y: y, width: r.width, height: 1.5))
        y += rowH
    }
}

private func fakeIcon(_ ctx: CGContext, _ c: CGPoint) {
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.95))
    ctx.addPath(CGPath(roundedRect: CGRect(x: c.x - 20, y: c.y - 14, width: 40, height: 50), cornerWidth: 4, cornerHeight: 4, transform: nil))
    ctx.fillPath()
    ctx.setFillColor(CGColor(red: 0.15, green: 0.42, blue: 0.95, alpha: 1))
    ctx.addPath(CGPath(roundedRect: CGRect(x: c.x - 34, y: c.y - 34, width: 68, height: 15), cornerWidth: 4, cornerHeight: 4, transform: nil))
    ctx.fillPath()
}

/// --icon dir: render AppIcon.iconset PNGs.
func renderIcon(_ dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let a = RugArt.aspect(.anatolianRed)
    guard let tex = RugArt.texture(.anatolianRed, body: CGSize(width: 520, height: 520 / a), fringe: 30) else { return }
    for base in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = CGFloat(base * scale)
            let img = NSImage(size: NSSize(width: px, height: px), flipped: false) { r in
                let bg = NSBezierPath(roundedRect: r.insetBy(dx: px * 0.09, dy: px * 0.09), xRadius: px * 0.2, yRadius: px * 0.2)
                NSGradient(colors: [NSColor(calibratedRed: 0.80, green: 0.62, blue: 0.42, alpha: 1), NSColor(calibratedRed: 0.58, green: 0.40, blue: 0.25, alpha: 1)])!.draw(in: bg, angle: -90)
                guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
                ctx.saveGState()
                ctx.translateBy(x: r.midX, y: r.midY)
                ctx.rotate(by: -0.18)
                let w = px * 0.78, h = w * (520 / a) / 580
                ctx.setShadow(offset: CGSize(width: 0, height: -px * 0.02), blur: px * 0.04, color: NSColor(white: 0, alpha: 0.45).cgColor)
                ctx.draw(tex, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
                ctx.restoreGState()
                return true
            }
            writePNG(img, "\(dir)/icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png")
        }
    }
}

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "--snapshot" {
    _ = NSApplication.shared
    snapshot(Array(args.dropFirst()))
} else if args.first == "--icon", args.count > 1 {
    _ = NSApplication.shared
    renderIcon(args[1])
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
