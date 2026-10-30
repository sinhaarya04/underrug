import AppKit

/// One frame of the overlay: the rug, its turned-back flap if it's being peeled, and the
/// controls that show while the pointer is over it.
struct RugFrame {
    var placement: Placement
    var texture: CGImage?
    var fold: Fold?
    var opacity: CGFloat = 1
    var controls = false        // corner handles + Design pill
    var rotateTip: CGPoint?     // "Drag to rotate" beside the pointer
    var optionBadge = false     // ⌥ key at the bottom of the screen while peeking through
}

enum Renderer {
    static let handleRadius: CGFloat = 5
    static let handleHit: CGFloat = 13

    static func pill(for p: Placement) -> CGRect {
        let f = p.frame
        return CGRect(x: (f.midX - 62).rounded(), y: (f.minY - 42).rounded(), width: 124, height: 28)
    }

    static func badge(in bounds: CGRect) -> CGRect {
        CGRect(x: (bounds.midX - 27).rounded(), y: 38, width: 54, height: 54)
    }

    static func draw(_ f: RugFrame, in ctx: CGContext, bounds: CGRect) {
        if f.opacity > 0.005, let tex = f.texture { rug(f, tex, ctx) }
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        if f.controls && f.opacity > 0.5 { controls(f.placement, ctx) }
        if let t = f.rotateTip { tip("Drag to rotate", at: t, ctx) }
        if f.optionBadge { optionKey(in: bounds, ctx) }
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: rug

    private static func rug(_ f: RugFrame, _ tex: CGImage, _ ctx: CGContext) {
        let p = f.placement
        ctx.saveGState()
        ctx.setAlpha(f.opacity)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)

        // what still lies flat, with its shadow on the floor
        ctx.saveGState()
        ctx.concatenate(p.transform)
        if let fold = f.fold { clip(ctx, fold.halfPlane(lifted: false)) }
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -5), blur: 16, color: CGColor(gray: 0, alpha: 0.38))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(p.body)  // only casts the shadow; the texture covers it
        ctx.restoreGState()
        ctx.draw(tex, in: p.rect)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.16))
        ctx.setLineWidth(2)
        ctx.stroke(p.body.insetBy(dx: 1, dy: 1))
        ctx.restoreGState()

        // the turned-back flap: the rug's underside, mirrored over the crease, casting a shadow
        if let fold = f.fold, fold.depth > 1 {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: CGColor(gray: 0, alpha: 0.45))
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.concatenate(p.transform)
            ctx.concatenate(fold.reflection)
            clip(ctx, fold.halfPlane(lifted: true))
            ctx.draw(tex, in: p.rect)
            // the back of a rug shows the same pattern, flatter and darker
            ctx.setBlendMode(.sourceAtop)
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.30))
            ctx.fill(p.rect)
            // light catching the rounded crease
            let n = fold.normal, m = fold.mid, w = min(56, fold.depth / 2)
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [CGColor(gray: 1, alpha: 0.24), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: m, end: CGPoint(x: m.x - n.dx * w, y: m.y - n.dy * w), options: [])
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }

        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    private static func clip(_ ctx: CGContext, _ poly: [CGPoint]) {
        ctx.beginPath()
        ctx.addLines(between: poly)
        ctx.closePath()
        ctx.clip()
    }

    // MARK: controls

    private static func controls(_ p: Placement, _ ctx: CGContext) {
        for c in p.corners {
            let r = CGRect(x: c.x - handleRadius, y: c.y - handleRadius, width: 2 * handleRadius, height: 2 * handleRadius)
            ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: CGColor(gray: 0, alpha: 0.4))
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: r)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.25))
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: r)
        }
        let r = pill(for: p)
        let path = CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.78))
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: CGColor(gray: 0, alpha: 0.22))
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.1))
        ctx.strokePath()
        let ink = NSColor(white: 0.12, alpha: 0.8)
        text("‹", in: CGRect(x: r.minX + 6, y: r.minY, width: 22, height: r.height), size: 17, ink)
        text("Design", in: r, size: 12, ink, weight: .medium)
        text("›", in: CGRect(x: r.maxX - 28, y: r.minY, width: 22, height: r.height), size: 17, ink)
    }

    private static func tip(_ s: String, at p: CGPoint, _ ctx: CGContext) {
        let r = CGRect(x: p.x + 14, y: p.y - 34, width: 104, height: 22)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 5, cornerHeight: 5, transform: nil))
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 0.85))
        ctx.fillPath()
        text(s, in: r, size: 11, .white)
    }

    private static func optionKey(in bounds: CGRect, _ ctx: CGContext) {
        let r = badge(in: bounds)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 12, cornerHeight: 12, transform: nil))
        ctx.setFillColor(CGColor(gray: 0.12, alpha: 0.78))
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 10, color: CGColor(gray: 0, alpha: 0.3))
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        text("⌥", in: r, size: 26, .white)
    }

    private static func text(_ s: String, in r: CGRect, size: CGFloat, _ color: NSColor, weight: NSFont.Weight = .regular) {
        let a = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
        let sz = a.size()
        a.draw(at: CGPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2))
    }
}
