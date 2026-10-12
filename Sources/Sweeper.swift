import Foundation

/// "Sweep under the rug": move loose desktop items into ~/Desktop/Under the Rug/<date>, with undo.
enum Sweeper {
    struct Move: Codable { var from: String; var to: String }
    struct Sweep: Codable { var at: Date; var folder: String; var moves: [Move] }

    static var manifestURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Underrug")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sweeps.json")
    }

    static func loadSweeps() -> [Sweep] {
        guard let d = try? Data(contentsOf: manifestURL) else { return [] }
        return (try? JSONDecoder().decode([Sweep].self, from: d)) ?? []
    }

    static func saveSweeps(_ s: [Sweep]) {
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: manifestURL, options: .atomic) }
    }

    static func candidates() -> [URL] {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: DesktopScanner.desktopURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return items.filter { $0.lastPathComponent != DesktopScanner.rugFolder }
    }

    /// Returns how many items moved and any that couldn't be.
    static func sweep() -> (moved: Int, failed: [String]) {
        let fm = FileManager.default
        let items = candidates()
        guard !items.isEmpty else { return (0, []) }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm"
        let dest = DesktopScanner.desktopURL.appendingPathComponent(DesktopScanner.rugFolder).appendingPathComponent(f.string(from: Date()))
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
        var moves = [Move](), failed = [String]()
        for src in items {
            let to = dest.appendingPathComponent(src.lastPathComponent)
            do {
                try fm.moveItem(at: src, to: to)
                moves.append(Move(from: src.path, to: to.path))
            } catch {
                failed.append(src.lastPathComponent)
            }
        }
        var all = loadSweeps()
        all.append(Sweep(at: Date(), folder: dest.path, moves: moves))
        saveSweeps(all)
        return (moves.count, failed)
    }

    static var canUnsweep: Bool { !loadSweeps().isEmpty }

    static func unsweepLast() -> (restored: Int, skipped: [String]) {
        var all = loadSweeps()
        guard let last = all.popLast() else { return (0, []) }
        let fm = FileManager.default
        var restored = 0, skipped = [String]()
        for m in last.moves {
            if fm.fileExists(atPath: m.from) || !fm.fileExists(atPath: m.to) {
                skipped.append((m.from as NSString).lastPathComponent)
                continue
            }
            do { try fm.moveItem(atPath: m.to, toPath: m.from); restored += 1 } catch { skipped.append((m.from as NSString).lastPathComponent) }
        }
        if let left = try? fm.contentsOfDirectory(atPath: last.folder), left.filter({ !$0.hasPrefix(".") }).isEmpty {
            try? fm.removeItem(atPath: last.folder)
            let root = DesktopScanner.desktopURL.appendingPathComponent(DesktopScanner.rugFolder).path
            if let r = try? fm.contentsOfDirectory(atPath: root), r.filter({ !$0.hasPrefix(".") }).isEmpty { try? fm.removeItem(atPath: root) }
        }
        if skipped.isEmpty || restored > 0 { saveSweeps(all) }
        return (restored, skipped)
    }
}
