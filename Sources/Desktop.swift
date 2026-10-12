import AppKit

struct DesktopItem: Equatable {
    var name: String
    var center: CGPoint  // AppKit screen points (origin bottom-left of the main screen)
}

/// Reads where Finder put each desktop icon, and watches ~/Desktop for changes.
final class DesktopScanner {
    static let rugFolder = "Under the Rug"
    private let queue = DispatchQueue(label: "underrug.scan")
    private var source: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var last: [DesktopItem] = []
    private(set) var usingFinder = true
    var onChange: (([DesktopItem]) -> Void)?
    let screenHeight: CGFloat

    init(screenHeight: CGFloat) { self.screenHeight = screenHeight }

    static var desktopURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop") }

    func start() {
        rescan()
        let fd = open(Self.desktopURL.path, O_EVTONLY)
        if fd >= 0 {
            let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            s.setEventHandler { [weak self] in
                // Finder places a new icon a moment after the file appears.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.rescan() }
            }
            s.setCancelHandler { close(fd) }
            s.resume()
            source = s
        }
        // Icons can also be rearranged by hand; positions are cheap to re-read.
        timer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in self?.rescan() }
    }

    func rescan() {
        let h = screenHeight
        queue.async { [weak self] in
            guard let self else { return }
            let items = Self.finderItems(screenHeight: h) ?? Self.fallbackItems(screenHeight: h)
            let viaFinder = Self.lastFinderOK
            DispatchQueue.main.async {
                self.usingFinder = viaFinder
                if items != self.last {
                    self.last = items
                    self.onChange?(items)
                }
            }
        }
    }

    private static var lastFinderOK = true

    static func finderItems(screenHeight: CGFloat) -> [DesktopItem]? {
        let src = "tell application \"Finder\" to get {name, desktop position} of every item of desktop"
        var err: NSDictionary?
        guard let script = NSAppleScript(source: src) else { return nil }
        let d = script.executeAndReturnError(&err)
        guard err == nil, d.numberOfItems == 2, let names = d.atIndex(1), let positions = d.atIndex(2) else {
            lastFinderOK = false
            return nil
        }
        var out = [DesktopItem]()
        let n = min(names.numberOfItems, positions.numberOfItems)
        if n > 0 {
            for k in 1...n {
                guard let name = names.atIndex(k)?.stringValue, let p = positions.atIndex(k), p.numberOfItems == 2 else { continue }
                let x = CGFloat(p.atIndex(1)!.int32Value), y = CGFloat(p.atIndex(2)!.int32Value)
                out.append(DesktopItem(name: name, center: CGPoint(x: x, y: screenHeight - y)))
            }
        }
        lastFinderOK = true
        return out
    }

    /// Without Finder access: assume the default layout, a column grid from the top-right corner.
    static func fallbackItems(screenHeight: CGFloat) -> [DesktopItem] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: desktopURL.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        let screenW = NSScreen.main?.frame.width ?? 1440
        let colW: CGFloat = 112, rowH: CGFloat = 112
        let rows = max(1, Int((screenHeight - 80) / rowH))
        return names.enumerated().map { k, name in
            let col = k / rows, row = k % rows
            return DesktopItem(name: name, center: CGPoint(x: screenW - 60 - CGFloat(col) * colW, y: screenHeight - 84 - CGFloat(row) * rowH))
        }
    }

    /// Move a desktop item (Finder coordinates are top-left based).
    static func place(_ name: String, at p: CGPoint, screenHeight: CGFloat) {
        let x = Int(p.x), y = Int(screenHeight - p.y)
        let safe = name.replacingOccurrences(of: "\"", with: "\\\"")
        let src = "tell application \"Finder\" to set desktop position of item \"\(safe)\" of desktop to {\(x), \(y)}"
        DispatchQueue.global().async { var e: NSDictionary?; _ = NSAppleScript(source: src)?.executeAndReturnError(&e) }
    }

    static func stampLumps(_ items: [DesktopItem], into field: Heightfield) {
        field.clear()
        let rugFolderCount = (try? FileManager.default.contentsOfDirectory(atPath: desktopURL.appendingPathComponent(rugFolder).path))?
            .reduce(0) { n, sub in n + ((try? FileManager.default.contentsOfDirectory(atPath: desktopURL.appendingPathComponent(rugFolder).appendingPathComponent(sub).path))?.count ?? 1) } ?? 0
        for it in items {
            let c = SIMD2<Float>(Float(it.center.x), Float(it.center.y))
            if it.name == rugFolder {
                // Everything you've swept away makes one satisfying lump.
                let h = min(30, 12 + 4 * log2(Float(1 + rugFolderCount)))
                field.stamp(center: c, half: SIMD2(28, 24), radius: 30, height: h)
            } else {
                // icon and label make one soft dome
                field.stamp(center: c + SIMD2(0, -10), half: SIMD2(14, 22), radius: 24, height: 13)
            }
        }
    }
}
