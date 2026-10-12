import Foundation
import simd

/// Height of whatever lies under the rug (desktop icons), sampled on a coarse grid in screen points.
final class Heightfield {
    let cell: Float
    let w: Int, h: Int
    private(set) var data: [Float]

    init(width: Float, height: Float, cell: Float = 6) {
        self.cell = cell
        w = Int(width / cell) + 2
        h = Int(height / cell) + 2
        data = [Float](repeating: 0, count: w * h)
    }

    func clear() { data = [Float](repeating: 0, count: w * h) }

    @inline(__always) func sample(_ x: Float, _ y: Float) -> Float {
        let fx = x / cell, fy = y / cell
        let ix = Int(fx.rounded(.down)), iy = Int(fy.rounded(.down))
        guard ix >= 0, iy >= 0, ix < w - 1, iy < h - 1 else { return 0 }
        let tx = fx - Float(ix), ty = fy - Float(iy)
        let i = iy * w + ix
        let a = data[i], b = data[i + 1], c = data[i + w], d = data[i + w + 1]
        return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
    }

    /// A soft rounded box: flat-ish top of `half` size, shoulders falling off over `radius`.
    func stamp(center: SIMD2<Float>, half: SIMD2<Float>, radius: Float, height: Float) {
        let lo = (center - half - radius) / cell, hi = (center + half + radius) / cell
        let x0 = max(0, Int(lo.x)), y0 = max(0, Int(lo.y))
        let x1 = min(w - 1, Int(hi.x) + 1), y1 = min(h - 1, Int(hi.y) + 1)
        guard x0 <= x1, y0 <= y1 else { return }
        for iy in y0...y1 {
            for ix in x0...x1 {
                let p = SIMD2<Float>(Float(ix), Float(iy)) * cell
                let q = abs(p - center) - half
                let outside = simd_length(simd_max(q, .zero))
                let inside = min(max(q.x, q.y), 0)  // <= 0 inside the box
                var v: Float
                if outside > 0 {
                    let t = min(outside / radius, 1)
                    v = height * (1 - t * t * (3 - 2 * t))
                } else {
                    // gentle dome on top so lumps read as soft, not flat plateaus
                    let depth = min(-inside / max(min(half.x, half.y), 1), 1)
                    v = height * (0.88 + 0.12 * depth)
                }
                let i = iy * w + ix
                if v > data[i] { data[i] = v }
            }
        }
    }
}

struct Constraint {
    var a: Int32
    var b: Int32
    var rest: Float
    var k: Float
}

/// Verlet cloth: a grid of particles held together by distance constraints, resting on the heightfield.
final class Cloth {
    private(set) var nx = 0, ny = 0
    private(set) var size = SIMD2<Float>(0, 0)
    var pos = [SIMD3<Float>]()
    var prev = [SIMD3<Float>]()
    private var cons = [Constraint]()
    private var locked = [Bool]()
    private var weight = [Float]()

    let ground: Heightfield
    var bounds: SIMD2<Float>

    var gravity: Float = -2600
    var damping: Float = 0.985
    var friction: Float = 0.42
    var bend: Float = 0.3
    var iterations = 12
    let lift: Float = 36

    private var grabSet: [(Int, SIMD2<Float>)] = []
    private var target: SIMD2<Float>?
    private var lastTarget: SIMD2<Float>?
    private var targetVel = SIMD2<Float>(0, 0)
    var isGrabbing: Bool { target != nil }

    init(ground: Heightfield, bounds: SIMD2<Float>) {
        self.ground = ground
        self.bounds = bounds
    }

    var count: Int { pos.count }

    func build(center: SIMD2<Float>, size: SIMD2<Float>, angle: Float, dropHeight: Float) {
        self.size = size
        let maxCells: Float = 90
        let spacing = max(6.5, max(size.x, size.y) / maxCells)
        nx = max(4, Int((size.x / spacing).rounded()) + 1)
        ny = max(4, Int((size.y / spacing).rounded()) + 1)
        let sx = size.x / Float(nx - 1), sy = size.y / Float(ny - 1)
        let c = cos(angle), s = sin(angle)
        pos.removeAll(keepingCapacity: true)
        for j in 0..<ny {
            for i in 0..<nx {
                let lx = Float(i) * sx - size.x / 2, ly = Float(j) * sy - size.y / 2
                let x = center.x + lx * c - ly * s, y = center.y + lx * s + ly * c
                pos.append(SIMD3(x, y, dropHeight + Float.random(in: 0...1.5)))
            }
        }
        prev = pos
        locked = [Bool](repeating: false, count: pos.count)
        weight = [Float](repeating: 1, count: pos.count)
        cons.removeAll(keepingCapacity: true)
        func add(_ a: Int, _ b: Int, _ k: Float) {
            let d = SIMD2(pos[a].x - pos[b].x, pos[a].y - pos[b].y)
            cons.append(Constraint(a: Int32(a), b: Int32(b), rest: simd_length(d), k: k))
        }
        for j in 0..<ny {
            for i in 0..<nx {
                let p = j * nx + i
                if i + 1 < nx { add(p, p + 1, 1) }
                if j + 1 < ny { add(p, p + nx, 1) }
                if i + 1 < nx, j + 1 < ny { add(p, p + nx + 1, 0.9); add(p + 1, p + nx, 0.9) }
                if i + 2 < nx { add(p, p + 2, bend) }
                if j + 2 < ny { add(p, p + 2 * nx, bend) }
            }
        }
        // Order constraints in independent colour groups (no shared particle within a group): the
        // solver's updates no longer wait on each other, which makes it about 6x faster.
        var used = [UInt64](repeating: 0, count: pos.count)
        var color = [Int](repeating: 0, count: cons.count)
        for (k, c) in cons.enumerated() {
            let col = (~(used[Int(c.a)] | used[Int(c.b)])).trailingZeroBitCount
            color[k] = col
            used[Int(c.a)] |= 1 << UInt64(col)
            used[Int(c.b)] |= 1 << UInt64(col)
        }
        cons = zip(cons, color).sorted { $0.1 < $1.1 }.map { $0.0 }
        grabSet = []
        target = nil
    }

    func setBend(_ k: Float) {
        bend = k
        let stride2 = 2
        for idx in cons.indices {
            let d = Int(cons[idx].b - cons[idx].a)
            if d == stride2 || d == 2 * nx { cons[idx].k = k }
        }
    }

    func step(_ dt: Float) {
        if let t = target {
            targetVel = t - (lastTarget ?? t)
            lastTarget = t
        }
        let dt2 = dt * dt
        let n = pos.count
        let fr = 1 - friction
        pos.withUnsafeMutableBufferPointer { P in
            prev.withUnsafeMutableBufferPointer { Q in
                for i in 0..<n {
                    var p = P[i]
                    var v = (p - Q[i]) * damping
                    if p.z <= ground.sample(p.x, p.y) + 0.9 { v.x *= fr; v.y *= fr }
                    Q[i] = p
                    p += v
                    p.z += gravity * dt2
                    P[i] = p
                }
            }
        }
        for k in 0..<iterations {
            solveConstraints()
            applyGrab()
            collide()
            if k == iterations / 2 { selfCollide() }
        }
        selfCollide()
        collide()
    }

    // MARK: self-collision

    private var hashHeads = [Int32]()
    private var hashNext = [Int32]()
    private let thickness: Float = 4

    /// Keep folded layers stacked instead of passing through each other. Particles from parts of the
    /// rug that are far apart in the weave but close in space are pushed apart vertically; the one
    /// that was already higher stays on top, so a fold always lies over the rug, never inside it.
    private func selfCollide() {
        let n = pos.count
        let cell = max(size.x / Float(nx - 1), 4) * 1.5
        let r = cell * 1.45, r2 = r * r
        let gw = Int(bounds.x / cell) + 2, gh = Int(bounds.y / cell) + 2
        if hashHeads.count != gw * gh { hashHeads = [Int32](repeating: -1, count: gw * gh) } else {
            for i in hashHeads.indices { hashHeads[i] = -1 }
        }
        if hashNext.count != n { hashNext = [Int32](repeating: -1, count: n) }
        let P = pos.withUnsafeMutableBufferPointer { $0.baseAddress! }
        let Q = prev.withUnsafeBufferPointer { $0.baseAddress! }
        for i in 0..<n {
            let cx = min(max(Int(P[i].x / cell), 0), gw - 1), cy = min(max(Int(P[i].y / cell), 0), gh - 1)
            let h = cy * gw + cx
            hashNext[i] = hashHeads[h]
            hashHeads[h] = Int32(i)
        }
        for i in 0..<n {
            let pi = P[i]
            let ii = i % nx, ij = i / nx
            let cx = min(max(Int(pi.x / cell), 0), gw - 1), cy = min(max(Int(pi.y / cell), 0), gh - 1)
            for dy in -1...1 {
                let yy = cy + dy
                if yy < 0 || yy >= gh { continue }
                for dx in -1...1 {
                    let xx = cx + dx
                    if xx < 0 || xx >= gw { continue }
                    var j = Int(hashHeads[yy * gw + xx])
                    while j >= 0 {
                        defer { j = Int(hashNext[j]) }
                        if j <= i { continue }
                        // neighbours in the weave are held by constraints already
                        let ji = j % nx, jj = j / nx
                        if abs(ji - ii) <= 3 && abs(jj - ij) <= 3 { continue }
                        let pj = P[j]
                        let dxy = SIMD2(pj.x - pi.x, pj.y - pi.y)
                        if simd_length_squared(dxy) >= r2 { continue }
                        let dz = pj.z - pi.z
                        if abs(dz) >= thickness { continue }
                        // who belongs on top: the higher one, judged by last frame to stay consistent
                        let jOnTop = (Q[j].z + pj.z) >= (Q[i].z + pi.z)
                        let push = (thickness - abs(dz)) * 0.5
                        if jOnTop {
                            P[j].z += push; P[i].z -= push
                        } else {
                            P[i].z += push; P[j].z -= push
                        }
                    }
                }
            }
        }
    }

    private func solveConstraints() {
        // Branch-free: each end moves in proportion to its weight (0 when held by the mouse).
        let base = pos.withUnsafeMutableBufferPointer { $0.baseAddress! }
        let wt = weight.withUnsafeBufferPointer { $0.baseAddress! }
        cons.withUnsafeBufferPointer { C in
            for c in C {
                let a = Int(c.a), b = Int(c.b)
                let pa = base[a], pb = base[b]
                let d = pb - pa
                let len2 = simd_length_squared(d)
                let wa = wt[a], wb = wt[b], ws = wa + wb
                if len2 < 1e-10 || ws == 0 { continue }
                let len = len2.squareRoot()
                let s = (len - c.rest) / len * c.k / ws
                base[a] = pa + d * (s * wa)
                base[b] = pb - d * (s * wb)
            }
        }
    }

    private func collide() {
        let W = bounds.x, H = bounds.y
        pos.withUnsafeMutableBufferPointer { P in
            for i in 0..<P.count {
                var p = P[i]
                let g = ground.sample(p.x, p.y) + 0.5
                if p.z < g { p.z = g }
                p.x = min(max(p.x, 0), W)
                p.y = min(max(p.y, 0), H)
                P[i] = p
            }
        }
    }

    private func applyGrab() {
        guard let t = target else { return }
        for (i, off) in grabSet {
            pos[i] = SIMD3(t.x + off.x, t.y + off.y, lift - simd_length(off) * 0.35)
        }
    }

    // MARK: interaction

    func nearest(to p: SIMD2<Float>) -> Int {
        var best = 0, bd = Float.greatestFiniteMagnitude
        for i in pos.indices {
            let d = simd_length_squared(SIMD2(pos[i].x, pos[i].y) - p)
            if d < bd { bd = d; best = i }
        }
        return best
    }

    func grab(at p: SIMD2<Float>) {
        let g = nearest(to: p)
        let sx = size.x / Float(nx - 1)
        let r = sx * 1.4
        let gp = SIMD2(pos[g].x, pos[g].y)
        grabSet = pos.indices.compactMap { i in
            let q = SIMD2(pos[i].x, pos[i].y)
            return simd_length(q - gp) <= r ? (i, q - gp) : nil
        }
        for (i, _) in grabSet { locked[i] = true; weight[i] = 0 }
        target = p
        lastTarget = p
        targetVel = .zero
    }

    func moveGrab(to p: SIMD2<Float>) {
        if target != nil { target = p }
    }

    func release() {
        guard target != nil else { return }
        let v = SIMD3(targetVel.x, targetVel.y, 0) * 0.7
        for (i, _) in grabSet {
            locked[i] = false
            weight[i] = 1
            prev[i] = pos[i] - v
        }
        grabSet = []
        target = nil
        lastTarget = nil
    }

    func rotate(by a: Float) {
        let c = centroid
        let cs = cos(a), sn = sin(a)
        func r(_ p: SIMD3<Float>) -> SIMD3<Float> {
            let d = SIMD2(p.x, p.y) - c
            return SIMD3(c.x + d.x * cs - d.y * sn, c.y + d.x * sn + d.y * cs, p.z)
        }
        for i in pos.indices { pos[i] = r(pos[i]); prev[i] = r(prev[i]) }
    }

    /// Shake it out: a travelling wave lifts the rug, then it settles flatter.
    func shake() {
        for j in 0..<ny {
            for i in 0..<nx {
                let k = j * nx + i
                let u = Float(i) / Float(nx - 1), v = Float(j) / Float(ny - 1)
                let up = 7 * sin(Float.pi * u) * (0.6 + 0.4 * sin(Float.pi * v)) + 3 * sin(u * 3 * .pi)
                prev[k].z = pos[k].z - up
            }
        }
    }

    /// Where every particle would sit if the rug lay perfectly flat and square at its current spot.
    func formTargets() -> [SIMD2<Float>] {
        let c = centroid, a = angle
        let cs = cos(a), sn = sin(a)
        let sx = size.x / Float(nx - 1), sy = size.y / Float(ny - 1)
        var out = [SIMD2<Float>]()
        out.reserveCapacity(pos.count)
        for j in 0..<ny {
            for i in 0..<nx {
                let lx = Float(i) * sx - size.x / 2, ly = Float(j) * sy - size.y / 2
                out.append(SIMD2(c.x + lx * cs - ly * sn, c.y + lx * sn + ly * cs))
            }
        }
        return out
    }

    /// Firm up, frame t in 0...1: glide every particle from `start` to its flat spot, arcing up a little
    /// mid-way (a fold can only open by lifting). Velocities are zeroed so it lands softly.
    func form(from start: [SIMD3<Float>], to targets: [SIMD2<Float>], t: Float) {
        guard start.count == pos.count, targets.count == pos.count else { return }
        let e = t * t * (3 - 2 * t)
        let arc = sin(t * .pi) * 18
        for i in pos.indices {
            let s = start[i]
            let xy = SIMD2(s.x, s.y) + (targets[i] - SIMD2(s.x, s.y)) * e
            let z = max(ground.sample(xy.x, xy.y) + 0.5, s.z * (1 - e) + arc + 2 * e)
            pos[i] = SIMD3(xy.x, xy.y, z)
            prev[i] = pos[i]
        }
    }

    var centroid: SIMD2<Float> {
        guard !pos.isEmpty else { return .zero }
        var s = SIMD2<Float>(0, 0)
        for p in pos { s += SIMD2(p.x, p.y) }
        return s / Float(pos.count)
    }

    var angle: Float {
        guard nx > 1 else { return 0 }
        let mid = (ny / 2) * nx
        let a = pos[mid], b = pos[mid + nx - 1]
        return atan2(b.y - a.y, b.x - a.x)
    }

    var motion: Float {
        var m: Float = 0
        for i in pos.indices { m = max(m, simd_length(pos[i] - prev[i])) }
        return m
    }

    /// Rug outline, counter-clockwise, in screen points.
    func outline() -> [SIMD2<Float>] {
        var o = [SIMD2<Float>]()
        func add(_ i: Int, _ j: Int) { let p = pos[j * nx + i]; o.append(SIMD2(p.x, p.y)) }
        for i in 0..<nx { add(i, 0) }
        for j in 1..<ny { add(nx - 1, j) }
        for i in stride(from: nx - 2, through: 0, by: -1) { add(i, ny - 1) }
        for j in stride(from: ny - 2, through: 1, by: -1) { add(0, j) }
        return o
    }

    func contains(_ p: SIMD2<Float>) -> Bool {
        let poly = outline()
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
}
