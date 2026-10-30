import AppKit

enum Pattern: String, CaseIterable {
    case persian, kilim, beni, gingham, sunset, custom

    var title: String {
        switch self {
        case .persian: return "Persian"
        case .kilim: return "Kilim"
        case .beni: return "Beni Ourain"
        case .gingham: return "Picnic Gingham"
        case .sunset: return "Sunset Stripes"
        case .custom: return "Your Image…"
        }
    }
}

/// Procedural rug textures. Body sits between two fringe strips on the short (left/right) ends.
enum RugArt {
    static func texture(_ pattern: Pattern, body: CGSize, fringe: CGFloat, customImage: NSImage? = nil, seed: UInt64 = 7) -> CGImage? {
        let total = CGSize(width: body.width + 2 * fringe, height: body.height)
        let scale = min(2.0, 2048 / max(total.width, total.height))
        let pw = Int(total.width * scale), ph = Int(total.height * scale)
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        var rng = SeededRNG(seed: seed)
        let r = CGRect(x: fringe, y: 0, width: body.width, height: body.height)
        switch pattern {
        case .persian: persian(ctx, r, &rng)
        case .kilim: kilim(ctx, r, &rng)
        case .beni: beni(ctx, r, &rng)
        case .gingham: gingham(ctx, r)
        case .sunset: sunset(ctx, r, &rng)
        case .custom:
            if let img = customImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                ctx.saveGState(); ctx.clip(to: r)
                let a = CGFloat(img.width) / CGFloat(img.height), ra = r.width / r.height
                let d = a > ra ? CGSize(width: r.height * a, height: r.height) : CGSize(width: r.width, height: r.width / a)
                ctx.draw(img, in: CGRect(x: r.midX - d.width / 2, y: r.midY - d.height / 2, width: d.width, height: d.height))
                ctx.restoreGState()
            } else {
                persian(ctx, r, &rng)
            }
        }
        weave(ctx, r, &rng)
        fringes(ctx, r, fringe, &rng)
        return ctx.makeImage()
    }

    // MARK: patterns

    static func persian(_ c: CGContext, _ r: CGRect, _ rng: inout SeededRNG) {
        let navy = rgb(0.10, 0.13, 0.30), crimson = rgb(0.58, 0.09, 0.11), gold = rgb(0.86, 0.66, 0.30)
        let cream = rgb(0.93, 0.86, 0.72), rust = rgb(0.72, 0.30, 0.15), teal = rgb(0.13, 0.36, 0.40)
        fill(c, r, navy)
        let bw = min(r.width, r.height) * 0.13
        stroke(c, r.insetBy(dx: 4, dy: 4), gold, 1.4)
        // main border with a running flower-and-vine
        let mid = r.insetBy(dx: bw * 0.55, dy: bw * 0.55)
        c.setStrokeColor(gold); c.setLineWidth(1.6)
        let step = bw * 0.9
        for side in 0..<4 {
            let horizontal = side % 2 == 0
            let length = horizontal ? mid.width : mid.height
            var t: CGFloat = step / 2
            while t < length {
                let p: CGPoint
                switch side {
                case 0: p = CGPoint(x: mid.minX + t, y: mid.minY)
                case 1: p = CGPoint(x: mid.maxX, y: mid.minY + t)
                case 2: p = CGPoint(x: mid.maxX - t, y: mid.maxY)
                default: p = CGPoint(x: mid.minX, y: mid.maxY - t)
                }
                flower(c, p, bw * 0.28, petals: 6, crimson, cream, gold)
                t += step
            }
        }
        stroke(c, r.insetBy(dx: bw, dy: bw), cream, 2)
        stroke(c, r.insetBy(dx: bw + 4, dy: bw + 4), gold, 1.2)
        // field
        let field = r.insetBy(dx: bw + 7, dy: bw + 7)
        fill(c, field, crimson)
        c.saveGState(); c.clip(to: field)
        // repeating small motifs
        let gap: CGFloat = max(30, field.height / 7)
        var row = 0
        var y = field.minY + gap / 2
        while y < field.maxY {
            var x = field.minX + (row % 2 == 0 ? gap / 2 : gap)
            while x < field.maxX {
                diamond(c, CGPoint(x: x, y: y), gap * 0.16, row % 3 == 0 ? gold : rust)
                dot(c, CGPoint(x: x, y: y), gap * 0.05, cream)
                x += gap
            }
            y += gap * 0.6; row += 1
        }
        // corner spandrels
        let R = min(field.width, field.height) * 0.42
        for corner in [CGPoint(x: field.minX, y: field.minY), CGPoint(x: field.maxX, y: field.minY),
                       CGPoint(x: field.minX, y: field.maxY), CGPoint(x: field.maxX, y: field.maxY)] {
            star(c, corner, R, R * 0.8, 16, navy)
            star(c, corner, R * 0.86, R * 0.7, 16, teal)
            star(c, corner, R * 0.7, R * 0.58, 16, navy)
            for k in 0..<10 {
                let a = CGFloat(k) / 10 * .pi * 2
                flower(c, CGPoint(x: corner.x + cos(a) * R * 0.45, y: corner.y + sin(a) * R * 0.45), R * 0.07, petals: 5, crimson, cream, gold)
            }
        }
        // central medallion with pendants along the long axis
        let m = CGPoint(x: field.midX, y: field.midY)
        let M = min(field.width, field.height) * 0.36
        for dx in [-1.0, 1.0] {
            let pc = CGPoint(x: m.x + CGFloat(dx) * M * 1.25, y: m.y)
            diamond(c, pc, M * 0.32, navy); diamond(c, pc, M * 0.22, cream); diamond(c, pc, M * 0.12, crimson)
        }
        star(c, m, M, M * 0.84, 20, navy)
        star(c, m, M * 0.9, M * 0.76, 20, gold)
        star(c, m, M * 0.84, M * 0.7, 20, cream)
        ellipse(c, CGRect(x: m.x - M * 0.62, y: m.y - M * 0.62, width: M * 1.24, height: M * 1.24), crimson)
        for k in 0..<12 {
            let a = CGFloat(k) / 12 * .pi * 2
            flower(c, CGPoint(x: m.x + cos(a) * M * 0.44, y: m.y + sin(a) * M * 0.44), M * 0.09, petals: 6, navy, gold, cream)
        }
        star(c, m, M * 0.32, M * 0.22, 8, navy)
        flower(c, m, M * 0.2, petals: 8, gold, crimson, cream)
        c.restoreGState()
    }

    static func kilim(_ c: CGContext, _ r: CGRect, _ rng: inout SeededRNG) {
        let colors = [rgb(0.72, 0.30, 0.18), rgb(0.86, 0.63, 0.22), rgb(0.12, 0.40, 0.42), rgb(0.93, 0.88, 0.78), rgb(0.18, 0.16, 0.15), rgb(0.55, 0.20, 0.25)]
        fill(c, r, colors[3])
        var x = r.minX
        var k = 0
        while x < r.maxX {
            let w = CGFloat(Int.random(in: 26...64, using: &rng))
            let band = CGRect(x: x, y: r.minY, width: min(w, r.maxX - x), height: r.height)
            let a = colors[k % colors.count], b = colors[(k + 2) % colors.count]
            fill(c, band, a)
            switch k % 3 {
            case 0:  // stacked diamonds
                var y = r.minY
                while y < r.maxY { diamond(c, CGPoint(x: band.midX, y: y + band.width / 2), band.width * 0.42, b); diamond(c, CGPoint(x: band.midX, y: y + band.width / 2), band.width * 0.18, a); y += band.width }
            case 1:  // zigzag
                c.setFillColor(b)
                var y = r.minY
                let t = band.width / 2
                while y < r.maxY {
                    c.move(to: CGPoint(x: band.minX, y: y)); c.addLine(to: CGPoint(x: band.maxX, y: y + t)); c.addLine(to: CGPoint(x: band.minX, y: y + 2 * t)); c.closePath(); c.fillPath()
                    y += 2 * t
                }
            default:  // thin pinstripes
                for s in stride(from: band.minX + 4, to: band.maxX - 2, by: 7) { fill(c, CGRect(x: s, y: r.minY, width: 2.5, height: r.height), b) }
            }
            x += w; k += 1
        }
        stroke(c, r.insetBy(dx: 3, dy: 3), colors[4], 4)
    }

    static func beni(_ c: CGContext, _ r: CGRect, _ rng: inout SeededRNG) {
        fill(c, r, rgb(0.93, 0.90, 0.84))
        c.setLineCap(.round)
        for _ in 0..<Int(r.width * r.height / 18) {  // shaggy pile
            let p = CGPoint(x: .random(in: r.minX...r.maxX, using: &rng), y: .random(in: r.minY...r.maxY, using: &rng))
            let a = CGFloat.random(in: 0...(2 * .pi), using: &rng), l = CGFloat.random(in: 2...6, using: &rng)
            c.setStrokeColor(.random(in: 0...1, using: &rng) > 0.5 ? rgb(1, 1, 0.97, 0.25) : rgb(0.6, 0.55, 0.48, 0.12))
            c.setLineWidth(1)
            c.move(to: p); c.addLine(to: CGPoint(x: p.x + cos(a) * l, y: p.y + sin(a) * l)); c.strokePath()
        }
        // wobbly hand-knotted diamond lattice
        let d = max(60, r.height / 3.2)
        c.setStrokeColor(rgb(0.16, 0.15, 0.14, 0.92)); c.setLineWidth(3.4); c.setLineJoin(.round)
        for dir in [-1.0, 1.0] {
            var o = r.minX - r.height
            while o < r.maxX + r.height {
                var p = CGPoint(x: o, y: r.minY)
                c.move(to: p)
                while p.y < r.maxY {
                    p = CGPoint(x: p.x + CGFloat(dir) * d / 6 + .random(in: -1.6...1.6, using: &rng), y: p.y + d / 6)
                    c.addLine(to: p)
                }
                c.strokePath()
                o += d
            }
        }
    }

    static func gingham(_ c: CGContext, _ r: CGRect) {
        fill(c, r, rgb(0.98, 0.97, 0.95))
        let s: CGFloat = 26
        c.saveGState(); c.clip(to: r)
        for x in stride(from: r.minX, to: r.maxX, by: s * 2) { fill(c, CGRect(x: x, y: r.minY, width: s, height: r.height), rgb(0.80, 0.12, 0.14, 0.55)) }
        for y in stride(from: r.minY, to: r.maxY, by: s * 2) { fill(c, CGRect(x: r.minX, y: y, width: r.width, height: s), rgb(0.80, 0.12, 0.14, 0.55)) }
        c.restoreGState()
    }

    static func sunset(_ c: CGContext, _ r: CGRect, _ rng: inout SeededRNG) {
        let stops = [rgb(0.99, 0.80, 0.45), rgb(0.98, 0.58, 0.36), rgb(0.91, 0.36, 0.38), rgb(0.62, 0.24, 0.45), rgb(0.29, 0.18, 0.42), rgb(0.12, 0.13, 0.30)]
        let n = 18
        for k in 0..<n {
            let t = CGFloat(k) / CGFloat(n - 1)
            let col = lerp(stops, t)
            fill(c, CGRect(x: r.minX + CGFloat(k) * r.width / CGFloat(n), y: r.minY, width: r.width / CGFloat(n) + 1, height: r.height), col)
        }
        // a woven sun
        let m = CGPoint(x: r.midX, y: r.midY)
        let R = r.height * 0.28
        for i in 0..<6 { ellipse(c, CGRect(x: m.x - R + CGFloat(i) * 3, y: m.y - R + CGFloat(i) * 3, width: 2 * (R - CGFloat(i) * 3), height: 2 * (R - CGFloat(i) * 3)), i % 2 == 0 ? rgb(1, 0.88, 0.55) : rgb(0.99, 0.72, 0.40)) }
    }

    // MARK: texture finishing

    static func weave(_ c: CGContext, _ r: CGRect, _ rng: inout SeededRNG) {
        c.saveGState(); c.clip(to: r)
        for _ in 0..<Int(r.width * r.height / 40) {
            let p = CGPoint(x: .random(in: r.minX...r.maxX, using: &rng), y: .random(in: r.minY...r.maxY, using: &rng))
            c.setFillColor(.random(in: 0...1, using: &rng) > 0.5 ? rgb(0, 0, 0, 0.07) : rgb(1, 1, 1, 0.06))
            c.fill(CGRect(x: p.x, y: p.y, width: 1.2, height: 1.2))
        }
        c.restoreGState()
    }

    static func fringes(_ c: CGContext, _ r: CGRect, _ f: CGFloat, _ rng: inout SeededRNG) {
        guard f > 0 else { return }
        c.setLineCap(.round)
        var y = r.minY + 4
        var k = 0
        while y < r.maxY - 3 {
            for side in [-1.0, 1.0] {
                let edge = side < 0 ? r.minX : r.maxX
                let len = f * CGFloat.random(in: 0.72...0.98, using: &rng)
                let wob = CGFloat.random(in: -1.5...1.5, using: &rng)
                let shade = CGFloat.random(in: 0.86...0.97, using: &rng)
                c.setStrokeColor(rgb(shade, shade * 0.95, shade * 0.86))
                c.setLineWidth(1.7)
                c.move(to: CGPoint(x: edge, y: y))
                c.addQuadCurve(to: CGPoint(x: edge + CGFloat(side) * len, y: y + wob),
                               control: CGPoint(x: edge + CGFloat(side) * len * 0.5, y: y - wob))
                c.strokePath()
                if k % 4 == 0 {  // knots
                    c.setFillColor(rgb(0.78, 0.72, 0.62))
                    c.fill(CGRect(x: edge + CGFloat(side) * f * 0.22 - 2, y: y - 0.5, width: 4, height: 6))
                }
            }
            y += 3.1; k += 1
        }
        // woven end bands where the fringe starts
        fill(c, CGRect(x: r.minX, y: r.minY, width: 4, height: r.height), rgb(0.90, 0.85, 0.74))
        fill(c, CGRect(x: r.maxX - 4, y: r.minY, width: 4, height: r.height), rgb(0.90, 0.85, 0.74))
    }

    // MARK: drawing helpers

    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
    static func fill(_ c: CGContext, _ r: CGRect, _ col: CGColor) { c.setFillColor(col); c.fill(r) }
    static func stroke(_ c: CGContext, _ r: CGRect, _ col: CGColor, _ w: CGFloat) { c.setStrokeColor(col); c.setLineWidth(w); c.stroke(r) }
    static func ellipse(_ c: CGContext, _ r: CGRect, _ col: CGColor) { c.setFillColor(col); c.fillEllipse(in: r) }
    static func dot(_ c: CGContext, _ p: CGPoint, _ r: CGFloat, _ col: CGColor) { ellipse(c, CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r), col) }
    static func diamond(_ c: CGContext, _ p: CGPoint, _ r: CGFloat, _ col: CGColor) {
        c.setFillColor(col)
        c.move(to: CGPoint(x: p.x, y: p.y + r)); c.addLine(to: CGPoint(x: p.x + r * 0.7, y: p.y))
        c.addLine(to: CGPoint(x: p.x, y: p.y - r)); c.addLine(to: CGPoint(x: p.x - r * 0.7, y: p.y)); c.closePath(); c.fillPath()
    }
    static func star(_ c: CGContext, _ p: CGPoint, _ outer: CGFloat, _ inner: CGFloat, _ points: Int, _ col: CGColor) {
        c.setFillColor(col)
        for k in 0..<(points * 2) {
            let a = CGFloat(k) / CGFloat(points * 2) * .pi * 2
            let rr = k % 2 == 0 ? outer : inner
            let q = CGPoint(x: p.x + cos(a) * rr, y: p.y + sin(a) * rr)
            if k == 0 { c.move(to: q) } else { c.addLine(to: q) }
        }
        c.closePath(); c.fillPath()
    }
    static func flower(_ c: CGContext, _ p: CGPoint, _ r: CGFloat, petals: Int, _ a: CGColor, _ b: CGColor, _ center: CGColor) {
        for k in 0..<petals {
            let ang = CGFloat(k) / CGFloat(petals) * .pi * 2
            dot(c, CGPoint(x: p.x + cos(ang) * r * 0.6, y: p.y + sin(ang) * r * 0.6), r * 0.42, k % 2 == 0 ? a : b)
        }
        dot(c, p, r * 0.32, center)
    }
    static func lerp(_ stops: [CGColor], _ t: CGFloat) -> CGColor {
        let x = t * CGFloat(stops.count - 1)
        let i = min(Int(x), stops.count - 2), f = x - CGFloat(i)
        let a = stops[i].components!, b = stops[i + 1].components!
        return rgb(a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f)
    }
}

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}
