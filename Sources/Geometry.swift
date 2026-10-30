import CoreGraphics

/// Where the rug lies: `size` points (fringe included), centred on `center`, turned by `angle`.
/// Rug-local space has its origin at the centre with x along the long side.
struct Placement {
    var center: CGPoint
    var angle: CGFloat
    var size: CGSize
    var fringe: CGFloat

    var transform: CGAffineTransform { CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle) }
    var rect: CGRect { CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height) }
    /// The woven part, without the fringe on the short ends.
    var body: CGRect { rect.insetBy(dx: fringe, dy: 0) }

    func local(_ p: CGPoint) -> CGPoint { p.applying(transform.inverted()) }
    func screen(_ p: CGPoint) -> CGPoint { p.applying(transform) }
    func contains(_ p: CGPoint) -> Bool { rect.contains(local(p)) }

    /// Corners of the woven part, where the rotate handles sit.
    var corners: [CGPoint] {
        let b = body
        return [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY)].map(screen)
    }

    /// Screen-space bounding box.
    var frame: CGRect {
        let r = rect
        let pts = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                   CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)].map(screen)
        let xs = pts.map(\.x), ys = pts.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// How far a rug-local point is inside the woven edge (negative in the fringe or beyond).
    func inset(_ q: CGPoint) -> CGFloat {
        let b = body
        return min(q.x - b.minX, b.maxX - q.x, q.y - b.minY, b.maxY - q.y)
    }
}

/// A peel: the rug-local point `from` has been lifted to `to`. The rug folds along the
/// perpendicular bisector of the two, the way a corner of a real rug turns back on itself.
struct Fold {
    let from: CGPoint
    var to: CGPoint

    var depth: CGFloat { hypot(to.x - from.x, to.y - from.y) }
    /// A point on the crease.
    var mid: CGPoint { CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2) }
    /// Unit normal of the crease, pointing away from the turned-back part.
    var normal: CGVector {
        let l = max(depth, 1e-6)
        return CGVector(dx: (to.x - from.x) / l, dy: (to.y - from.y) / l)
    }

    /// Mirror across the crease: takes a point of the turned-back part to where it now lies.
    var reflection: CGAffineTransform {
        let n = normal, k = 2 * (mid.x * n.dx + mid.y * n.dy)
        return CGAffineTransform(a: 1 - 2 * n.dx * n.dx, b: -2 * n.dx * n.dy,
                                 c: -2 * n.dx * n.dy, d: 1 - 2 * n.dy * n.dy,
                                 tx: k * n.dx, ty: k * n.dy)
    }

    /// The half-plane that stays down (`lifted` false) or turns over (true), as a polygon
    /// big enough to cover any rug.
    func halfPlane(lifted: Bool) -> [CGPoint] {
        let s: CGFloat = lifted ? -1 : 1
        let n = CGVector(dx: normal.dx * s, dy: normal.dy * s), t = CGVector(dx: -n.dy, dy: n.dx)
        let m = mid, L: CGFloat = 100_000
        return [CGPoint(x: m.x + t.dx * L, y: m.y + t.dy * L),
                CGPoint(x: m.x + (t.dx + n.dx) * L, y: m.y + (t.dy + n.dy) * L),
                CGPoint(x: m.x + (n.dx - t.dx) * L, y: m.y + (n.dy - t.dy) * L),
                CGPoint(x: m.x - t.dx * L, y: m.y - t.dy * L)]
    }
}
