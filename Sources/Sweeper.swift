import Foundation

/// "Sweep under the rug": Finder piles the desktop icons under the rug. Only their positions
/// change, never the files, and the old spots are saved so Unsweep puts every icon back.
enum Sweeper {
    struct Saved: Codable { var at: Date; var spots: [String: CGPoint] }

    enum Outcome { case swept(Int), nothingToSweep, noFinderAccess, finderSorts }

    static var savedURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Underrug")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("swept.json")
    }

    static func load() -> Saved? {
        guard let d = try? Data(contentsOf: savedURL) else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: d)
    }

    static var canUnsweep: Bool { load() != nil }

    /// Slow (it talks to Finder): call off the main thread.
    static func sweep(under rug: Placement, screenHeight: CGFloat) -> Outcome {
        guard let icons = Finder.icons() else { return .noFinderAccess }
        guard !icons.isEmpty else { return .nothingToSweep }
        let targets = pile(icons.count, under: rug).map { CGPoint(x: $0.x, y: screenHeight - $0.y) }

        // an icon swept twice keeps the spot it had before the first sweep
        let before = load()
        var saved = before ?? Saved(at: Date(), spots: [:])
        for i in icons where saved.spots[i.name] == nil { saved.spots[i.name] = i.position }
        if let d = try? JSONEncoder().encode(saved) { try? d.write(to: savedURL, options: .atomic) }

        Finder.move(zip(icons, targets).map { ($0.name, $1) })

        // With Sort By on, Finder keeps its own order and ignores where we put things.
        let now = Dictionary((Finder.icons() ?? []).map { ($0.name, $0.position) }, uniquingKeysWith: { a, _ in a })
        let landed = zip(icons, targets).filter { i, t in now[i.name].map { hypot($0.x - t.x, $0.y - t.y) < 48 } ?? false }.count
        if landed * 2 < icons.count {
            if before == nil { try? FileManager.default.removeItem(at: savedURL) }
            return .finderSorts
        }
        return .swept(icons.count)
    }

    /// Returns how many icons went back and how many have since gone missing; nil without Finder access.
    static func unsweep() -> (restored: Int, missing: Int)? {
        guard let saved = load() else { return (0, 0) }
        guard let icons = Finder.icons() else { return nil }
        let present = Set(icons.map(\.name))
        let moves = saved.spots.filter { present.contains($0.key) }.map { (name: $0.key, to: $0.value) }
        Finder.move(moves)
        try? FileManager.default.removeItem(at: savedURL)
        return (moves.count, saved.spots.count - moves.count)
    }

    /// Screen points (bottom-left origin) for `n` icons, scattered in a loose grid under the rug.
    static func pile(_ n: Int, under rug: Placement) -> [CGPoint] {
        // icons are ~64 pt with a label below; keep them clear of the edges
        let inner = rug.body.insetBy(dx: min(46, rug.body.width / 4), dy: min(46, rug.body.height / 4))
        let cols = max(1, Int((Double(n) * Double(inner.width / inner.height)).squareRoot().rounded(.up)))
        let rows = max(1, (n + cols - 1) / cols)
        let sx = inner.width / CGFloat(cols), sy = inner.height / CGFloat(rows)
        var rng = SeededRNG(seed: UInt64(n))
        return (0..<n).map { k in
            let j = min(sx, sy) * 0.3
            let q = CGPoint(x: inner.minX + (CGFloat(k % cols) + 0.5) * sx + .random(in: -j...j, using: &rng),
                            y: inner.maxY - (CGFloat(k / cols) + 0.5) * sy + .random(in: -j...j, using: &rng))
            return rug.screen(q)
        }
    }
}
