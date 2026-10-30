import AppKit

/// Real rugs, photographed by The Metropolitan Museum of Art and released into the public domain
/// (Open Access, CC0). Each photo is cropped to the woven field and turned landscape, so the warp
/// ends, where the fringe goes, are on the left and right. Sources are in CREDITS.md.
enum Pattern: String, CaseIterable {
    case anatolianRed, persianMedallion, cairoMedallion, chineseGold, cairoGarden, anatolianGold, ivoryField, prayerRug, custom

    var title: String {
        switch self {
        case .anatolianRed: return "Anatolian Red"
        case .persianMedallion: return "Persian Medallion"
        case .cairoMedallion: return "Cairo Medallion"
        case .chineseGold: return "Chinese Gold"
        case .cairoGarden: return "Cairo Garden"
        case .anatolianGold: return "Anatolian Gold"
        case .ivoryField: return "Ivory Field"
        case .prayerRug: return "Prayer Rug"
        case .custom: return "Your Image…"
        }
    }

    /// Where and when it was woven, per the Met.
    var origin: String {
        switch self {
        case .anatolianRed: return "Turkey, 18th century"
        case .persianMedallion: return "Iran, second half 16th century"
        case .cairoMedallion: return "Egypt, ca. 1550"
        case .chineseGold: return "China, late 18th–19th century"
        case .cairoGarden: return "Egypt, 17th century"
        case .anatolianGold: return "Turkey, 17th century"
        case .ivoryField: return "Turkey, 18th century"
        case .prayerRug: return "Turkey, 1774"
        case .custom: return ""
        }
    }

    /// The Met object ID, which is also the photo's file name in Resources/Rugs.
    var metID: Int? {
        switch self {
        case .anatolianRed: return 452567
        case .persianMedallion: return 446954
        case .cairoMedallion: return 452309
        case .chineseGold: return 42748
        case .cairoGarden: return 446957
        case .anatolianGold: return 447544
        case .ivoryField: return 452569
        case .prayerRug: return 451690
        case .custom: return nil
        }
    }
}

enum RugArt {
    private static var photos: [Int: CGImage] = [:]

    static func photo(_ pattern: Pattern, customImage: NSImage? = nil) -> CGImage? {
        guard let id = pattern.metID else { return customImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
        if let p = photos[id] { return p }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Rugs/\(id).jpg"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        photos[id] = img
        return img
    }

    /// Width over height of the woven part, so the rug keeps the real one's proportions.
    static func aspect(_ pattern: Pattern, customImage: NSImage? = nil) -> CGFloat {
        guard let p = photo(pattern, customImage: customImage), p.height > 0 else { return 1.55 }
        return min(max(CGFloat(p.width) / CGFloat(p.height), 1.15), 2.2)
    }

    /// The rug as one image: the photo across `body`, with a strip of fringe on each short end.
    static func texture(_ pattern: Pattern, body: CGSize, fringe: CGFloat, customImage: NSImage? = nil, seed: UInt64 = 7) -> CGImage? {
        let total = CGSize(width: body.width + 2 * fringe, height: body.height)
        let scale = min(2.0, 3072 / max(total.width, total.height))  // stays sharp on Retina up to ~1500 pt
        let pw = Int(total.width * scale), ph = Int(total.height * scale)
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.interpolationQuality = .high
        let r = CGRect(x: fringe, y: 0, width: body.width, height: body.height)
        if let img = photo(pattern, customImage: customImage) ?? photo(.anatolianRed) {
            // fill, cropping whatever doesn't fit (only a custom image is ever far off)
            ctx.saveGState(); ctx.clip(to: r)
            let a = CGFloat(img.width) / CGFloat(img.height), ra = r.width / r.height
            let d = a > ra ? CGSize(width: r.height * a, height: r.height) : CGSize(width: r.width, height: r.width / a)
            ctx.draw(img, in: CGRect(x: r.midX - d.width / 2, y: r.midY - d.height / 2, width: d.width, height: d.height))
            ctx.restoreGState()
        }
        var rng = SeededRNG(seed: seed)
        fringes(ctx, r, fringe, &rng)
        return ctx.makeImage()
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
                let shade = CGFloat.random(in: 0.80...0.93, using: &rng)
                c.setStrokeColor(rgb(shade, shade * 0.94, shade * 0.84))
                c.setLineWidth(1.7)
                c.move(to: CGPoint(x: edge, y: y))
                c.addQuadCurve(to: CGPoint(x: edge + CGFloat(side) * len, y: y + wob),
                               control: CGPoint(x: edge + CGFloat(side) * len * 0.5, y: y - wob))
                c.strokePath()
                if k % 4 == 0 {  // knots
                    c.setFillColor(rgb(0.74, 0.68, 0.58))
                    c.fill(CGRect(x: edge + CGFloat(side) * f * 0.22 - 2, y: y - 0.5, width: 4, height: 6))
                }
            }
            y += 3.1; k += 1
        }
        // woven end bands where the fringe starts
        c.setFillColor(rgb(0.86, 0.81, 0.70))
        c.fill(CGRect(x: r.minX - 1, y: r.minY, width: 4, height: r.height))
        c.fill(CGRect(x: r.maxX - 3, y: r.minY, width: 4, height: r.height))
    }

    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
}

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}
