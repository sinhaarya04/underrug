import AppKit
import SceneKit

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
        let img = NSImage(size: NSSize(width: 20, height: 14), flipped: false) { r in
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
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

/// --snapshot out.png [--drag] [--pattern kilim]: simulate on the real desktop layout and render one frame.
func snapshot(_ args: [String]) {
    let out = args.first { $0.hasSuffix(".png") } ?? "underrug.png"
    let size = NSScreen.main?.frame.size ?? CGSize(width: 1512, height: 982)
    if let i = args.firstIndex(of: "--pattern"), i + 1 < args.count { UserDefaults.standard.set(args[i + 1], forKey: "pattern") }
    let field = Heightfield(width: Float(size.width), height: Float(size.height))
    let items = DesktopScanner.finderItems(screenHeight: size.height) ?? DesktopScanner.fallbackItems(screenHeight: size.height)
    DesktopScanner.stampLumps(items, into: field)
    let cloth = Cloth(ground: field, bounds: SIMD2(Float(size.width), Float(size.height)))
    let pattern = Pattern(rawValue: UserDefaults.standard.string(forKey: "pattern") ?? "") ?? .persian
    let body = SIMD2<Float>(620, 400), fringe: Float = 26
    let total = SIMD2(body.x + 2 * fringe, body.y)
    // put the rug over the busiest part of the desktop so the lumps show
    var c = SIMD2<Float>(Float(size.width) * 0.62, Float(size.height) * 0.52)
    if !items.isEmpty {
        let xs = items.map { Float($0.center.x) }.sorted(), ys = items.map { Float($0.center.y) }.sorted()
        c = SIMD2(xs[xs.count / 2], ys[ys.count / 2])
        c = simd_clamp(c, total * 0.5, SIMD2(Float(size.width), Float(size.height)) - total * 0.5)
    }
    cloth.build(center: c, size: total, angle: -0.07, dropHeight: 70)
    cloth.setBend(0.45)
    for _ in 0..<360 { cloth.step(1.0 / 120) }
    if ProcessInfo.processInfo.environment["UNDERRUG_DEBUG"] != nil {
        let zs = cloth.pos.map { $0.z }
        let gs = cloth.pos.map { field.sample($0.x, $0.y) }
        for k in 0..<6 { for _ in 0..<120 { cloth.step(1.0 / 120) }; print("after", 360 + (k + 1) * 120, "steps motion", cloth.motion) }
        let t0 = Date(); for _ in 0..<120 { cloth.step(1.0 / 120) }; print("120 steps", Date().timeIntervalSince(t0), "s")
        print("z min", zs.min()!, "max", zs.max()!, "ground max under rug", gs.max()!, "field max", field.data.max()!, "grid", cloth.nx, cloth.ny)
    }
    if args.contains("--drag") {
        let corner = cloth.pos[cloth.nx * (cloth.ny - 1)]
        var p = SIMD2(corner.x + 10, corner.y - 10)
        cloth.grab(at: p)
        for k in 0..<120 { p += SIMD2(1.6, -0.9) * (k < 90 ? 1 : 0); cloth.moveGrab(to: p); cloth.step(1.0 / 120) }
    }
    let rs = RugScene(size: size)
    rs.setTexture(RugArt.texture(pattern, body: CGSize(width: CGFloat(body.x), height: CGFloat(body.y)), fringe: CGFloat(fringe)), rugSize: total)
    rs.update(cloth)
    let r = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    r.scene = rs.scene
    r.pointOfView = rs.camera
    let rug = r.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    // composite over a stand-in desktop: wallpaper gradient plus a dot per icon, to check alignment
    let final = NSImage(size: size, flipped: false) { rect in
        NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.30, blue: 0.45, alpha: 1), NSColor(calibratedRed: 0.42, green: 0.32, blue: 0.48, alpha: 1)])!.draw(in: rect, angle: 70)
        for it in items {
            NSColor(white: 1, alpha: 0.55).setFill()
            NSBezierPath(roundedRect: NSRect(x: it.center.x - 22, y: it.center.y - 22, width: 44, height: 44), xRadius: 8, yRadius: 8).fill()
            NSColor(white: 1, alpha: 0.3).setFill()
            NSBezierPath(roundedRect: NSRect(x: it.center.x - 30, y: it.center.y - 50, width: 60, height: 10), xRadius: 3, yRadius: 3).fill()
        }
        rug.draw(in: rect)
        return true
    }
    writePNG(final, out)
    print("wrote \(out) with \(items.count) desktop items")
}

/// --icon dir: render AppIcon.iconset PNGs.
func renderIcon(_ dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    guard let tex = RugArt.texture(.persian, body: CGSize(width: 520, height: 340), fringe: 30) else { return }
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
                let w = px * 0.78, h = w * 340 / 580
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
