import Foundation

/// Finder's view of the desktop. Positions are Finder's: points from the top-left of the main screen.
enum Finder {
    struct Icon { var name: String; var position: CGPoint }

    static var desktopURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop") }

    /// Cheap count for menu titles; doesn't need Finder.
    static var desktopCount: Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: desktopURL.path)) ?? []).filter { !$0.hasPrefix(".") }.count
    }

    /// Every desktop icon, or nil when Underrug isn't allowed to ask Finder.
    static func icons() -> [Icon]? {
        let src = "tell application \"Finder\" to get {name, desktop position} of every item of desktop"
        var err: NSDictionary?
        guard let d = NSAppleScript(source: src)?.executeAndReturnError(&err), err == nil,
              d.numberOfItems == 2, let names = d.atIndex(1), let spots = d.atIndex(2) else { return nil }
        var out = [Icon]()
        let n = min(names.numberOfItems, spots.numberOfItems)
        guard n > 0 else { return out }
        for k in 1...n {
            guard let name = names.atIndex(k)?.stringValue, let p = spots.atIndex(k), p.numberOfItems == 2,
                  let x = p.atIndex(1)?.int32Value, let y = p.atIndex(2)?.int32Value else { continue }
            out.append(Icon(name: name, position: CGPoint(x: CGFloat(x), y: CGFloat(y))))
        }
        return out
    }

    /// Move icons in one Finder round trip. A name that has gone missing is skipped, not fatal.
    static func move(_ spots: [(name: String, to: CGPoint)]) {
        guard !spots.isEmpty else { return }
        var src = "tell application \"Finder\"\n"
        for s in spots {
            let safe = s.name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            src += "try\nset desktop position of item \"\(safe)\" of desktop to {\(Int(s.to.x)), \(Int(s.to.y))}\nend try\n"
        }
        src += "end tell"
        var err: NSDictionary?
        _ = NSAppleScript(source: src)?.executeAndReturnError(&err)
    }
}
