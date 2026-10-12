import AppKit
import SceneKit
import ServiceManagement

enum RugSize: String, CaseIterable {
    case small, medium, large, cover
    var title: String { ["small": "Small", "medium": "Medium", "large": "Large", "cover": "Cover the Desktop"][rawValue]! }
    func points(for screen: CGSize) -> SIMD2<Float> {
        switch self {
        case .small: return SIMD2(420, 270)
        case .medium: return SIMD2(620, 400)
        case .large: return SIMD2(860, 540)
        case .cover: return SIMD2(Float(screen.width) * 0.86, Float(screen.height) * 0.80)
        }
    }
}

enum Feel: String, CaseIterable {
    case heavy, normal, silky
    var title: String { ["heavy": "Heavy Wool", "normal": "Cotton", "silky": "Silk"][rawValue]! }
    var friction: Float { [0.58, 0.42, 0.16][Feel.allCases.firstIndex(of: self)!] }
    var bend: Float { [0.6, 0.45, 0.2][Feel.allCases.firstIndex(of: self)!] }
    var damping: Float { [0.98, 0.985, 0.992][Feel.allCases.firstIndex(of: self)!] }
}

/// The window floats just above the desktop icons and below every app window. It only takes the
/// mouse while the pointer is over the rug, so the rest of the desktop still works.
final class RugPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class RugView: SCNView {
    weak var controller: RugController?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private func pt(_ e: NSEvent) -> SIMD2<Float> { let p = convert(e.locationInWindow, from: nil); return SIMD2(Float(p.x), Float(p.y)) }
    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2 { controller?.shake(); return }
        controller?.grab(pt(e))
    }
    override func mouseDragged(with e: NSEvent) { controller?.drag(pt(e)) }
    override func mouseUp(with e: NSEvent) { controller?.drop() }
    override func scrollWheel(with e: NSEvent) { controller?.spin(Float(e.scrollingDeltaY) * (e.hasPreciseScrollingDeltas ? 0.004 : 0.04)) }
    override func rightMouseDown(with e: NSEvent) { if let m = controller?.menu() { NSMenu.popUpContextMenu(m, with: e, for: self) } }
}

final class RugController: NSObject, NSMenuDelegate {
    let screen: NSScreen
    let window: RugPanel
    let view: RugView
    let field: Heightfield
    let cloth: Cloth
    let rugScene: RugScene
    let scanner: DesktopScanner
    private var stepTimer: Timer?
    private var pollTimer: Timer?
    private var stillFrames = 0
    private var awake = true
    private var peeking = false
    private var hovering = false
    private var items: [DesktopItem] = []
    private let d = UserDefaults.standard

    var pattern: Pattern { get { Pattern(rawValue: d.string(forKey: "pattern") ?? "") ?? .persian } set { d.set(newValue.rawValue, forKey: "pattern") } }
    var rugSize: RugSize { get { RugSize(rawValue: d.string(forKey: "size") ?? "") ?? .medium } set { d.set(newValue.rawValue, forKey: "size") } }
    var feel: Feel { get { Feel(rawValue: d.string(forKey: "feel") ?? "") ?? .normal } set { d.set(newValue.rawValue, forKey: "feel") } }
    var visible: Bool { get { d.object(forKey: "visible") as? Bool ?? true } set { d.set(newValue, forKey: "visible") } }

    init(screen: NSScreen) {
        self.screen = screen
        let f = screen.frame
        window = RugPanel(contentRect: f, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.setFrame(f, display: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false

        view = RugView(frame: NSRect(origin: .zero, size: f.size))
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.wantsLayer = true
        view.layer?.isOpaque = false
        window.contentView = view

        field = Heightfield(width: Float(f.width), height: Float(f.height))
        cloth = Cloth(ground: field, bounds: SIMD2(Float(f.width), Float(f.height)))
        rugScene = RugScene(size: f.size)
        scanner = DesktopScanner(screenHeight: f.height)
        super.init()
        view.controller = self
        view.scene = rugScene.scene
        view.pointOfView = rugScene.camera
        view.isPlaying = false
        view.rendersContinuously = false

        applyFeel()
        buildRug(drop: true)
        scanner.onChange = { [weak self] items in
            guard let self else { return }
            self.items = items
            DesktopScanner.stampLumps(items, into: self.field)
            self.wake()
        }
        scanner.start()
    }

    func show() {
        if visible { window.orderFront(nil) }
        stepTimer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(stepTimer!, forMode: .common)
        pollTimer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    // MARK: rug lifecycle

    func buildRug(drop: Bool, center: SIMD2<Float>? = nil, angle: Float? = nil) {
        let s = rugSize.points(for: screen.frame.size)
        let fringe: Float = min(26, s.y * 0.07)
        let total = SIMD2(s.x + 2 * fringe, s.y)
        let saved = SIMD2(Float(d.double(forKey: "cx")), Float(d.double(forKey: "cy")))
        let sc = SIMD2(Float(screen.frame.width), Float(screen.frame.height))
        var c = center ?? (saved.x > 0 ? saved : SIMD2(sc.x * 0.42, sc.y * 0.45))
        c = simd_clamp(c, total * 0.3, sc - total * 0.3)
        let a = angle ?? (d.object(forKey: "angle") as? Double).map { Float($0) } ?? -0.06
        cloth.build(center: c, size: total, angle: a, dropHeight: drop ? 70 : 2)
        var custom: NSImage?
        if pattern == .custom, let path = d.string(forKey: "customImage") { custom = NSImage(contentsOfFile: path) }
        rugScene.setTexture(RugArt.texture(pattern, body: CGSize(width: CGFloat(s.x), height: CGFloat(s.y)), fringe: CGFloat(fringe), customImage: custom), rugSize: total)
        rugScene.update(cloth)
        wake()
    }

    private func applyFeel() {
        cloth.friction = feel.friction
        cloth.damping = feel.damping
        cloth.setBend(feel.bend)
    }

    private func wake() {
        if !awake { view.preferredFramesPerSecond = 60 }
        awake = true
        stillFrames = 0
    }

    private func tick() {
        guard awake, visible else { return }
        cloth.step(1.0 / 120)
        cloth.step(1.0 / 120)
        rugScene.update(cloth)
        if !cloth.isGrabbing && cloth.motion < 0.02 {
            stillFrames += 1
            if stillFrames > 45 {  // settled: stop simulating and redrawing until something changes
                awake = false
                view.preferredFramesPerSecond = 1
                save()
            }
        } else {
            stillFrames = 0
        }
    }

    private func save() {
        let c = cloth.centroid
        d.set(Double(c.x), forKey: "cx"); d.set(Double(c.y), forKey: "cy"); d.set(Double(cloth.angle), forKey: "angle")
    }

    /// Track the pointer: take mouse events only over the rug, and fade it while ⌥ is held.
    private func poll() {
        guard visible else { return }
        let m = NSEvent.mouseLocation
        let p = SIMD2(Float(m.x - screen.frame.minX), Float(m.y - screen.frame.minY))
        let alt = NSEvent.modifierFlags.contains(.option)
        if alt != peeking {
            peeking = alt
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                window.animator().alphaValue = alt ? 0.14 : 1
            }
        }
        let over = cloth.isGrabbing || (!peeking && cloth.contains(p))
        if window.ignoresMouseEvents == over { window.ignoresMouseEvents = !over }
        if over != hovering {
            hovering = over
            (over ? NSCursor.openHand : NSCursor.arrow).set()
        }
    }

    // MARK: interaction

    func grab(_ p: SIMD2<Float>) { cloth.grab(at: p); NSCursor.closedHand.set(); wake() }
    func drag(_ p: SIMD2<Float>) { cloth.moveGrab(to: p); wake() }
    func drop() { cloth.release(); NSCursor.openHand.set(); wake() }
    func spin(_ a: Float) { guard !cloth.isGrabbing else { return }; cloth.rotate(by: a); wake() }
    func shake() { cloth.shake(); wake() }

    // MARK: menu

    func menu() -> NSMenu {
        let m = NSMenu()
        m.delegate = self
        populate(m)
        return m
    }

    func menuNeedsUpdate(_ menu: NSMenu) { populate(menu) }

    private func item(_ title: String, _ sel: Selector?, _ key: String = "", on: Bool = false, obj: Any? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        i.state = on ? .on : .off
        i.representedObject = obj
        return i
    }

    private func populate(_ m: NSMenu) {
        m.removeAllItems()
        m.addItem(item(visible ? "Hide Rug" : "Show Rug", #selector(toggle)))
        m.addItem(.separator())
        let pat = NSMenu()
        for p in Pattern.allCases { pat.addItem(item(p.title, #selector(choosePattern(_:)), on: p == pattern, obj: p.rawValue)) }
        let pi = NSMenuItem(title: "Rug", action: nil, keyEquivalent: ""); pi.submenu = pat; m.addItem(pi)
        let sz = NSMenu()
        for s in RugSize.allCases { sz.addItem(item(s.title, #selector(chooseSize(_:)), on: s == rugSize, obj: s.rawValue)) }
        let si = NSMenuItem(title: "Size", action: nil, keyEquivalent: ""); si.submenu = sz; m.addItem(si)
        let fl = NSMenu()
        for f in Feel.allCases { fl.addItem(item(f.title, #selector(chooseFeel(_:)), on: f == feel, obj: f.rawValue)) }
        let fi = NSMenuItem(title: "Fabric", action: nil, keyEquivalent: ""); fi.submenu = fl; m.addItem(fi)
        m.addItem(item("Shake It Out", #selector(shakeAction)))
        m.addItem(item("Straighten", #selector(straighten)))
        m.addItem(.separator())
        let n = Sweeper.candidates().count
        m.addItem(item(n > 0 ? "Sweep \(n) Item\(n == 1 ? "" : "s") Under the Rug…" : "Desktop Is Already Clean", n > 0 ? #selector(sweep) : nil))
        if Sweeper.canUnsweep { m.addItem(item("Unsweep Last Sweep", #selector(unsweep))) }
        m.addItem(.separator())
        let tip = NSMenuItem(title: "Drag to move · scroll to rotate · double-click to shake · hold ⌥ to peek", action: nil, keyEquivalent: "")
        tip.isEnabled = false
        m.addItem(tip)
        if !scanner.usingFinder {
            let w = NSMenuItem(title: "Allow Finder access in System Settings to drape over icons exactly", action: #selector(openAutomation), keyEquivalent: "")
            w.target = self
            m.addItem(w)
        }
        m.addItem(.separator())
        m.addItem(item("Open at Login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))
        m.addItem(item("Quit Underrug", #selector(quit), "q"))
    }

    @objc private func toggle() {
        visible.toggle()
        if visible { window.orderFront(nil); buildRug(drop: true, center: cloth.centroid, angle: cloth.angle) } else { window.orderOut(nil) }
    }

    @objc private func choosePattern(_ s: NSMenuItem) {
        guard let p = Pattern(rawValue: s.representedObject as? String ?? "") else { return }
        if p == .custom {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.message = "Choose an image to weave into your rug"
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let url = panel.url else { return }
            d.set(url.path, forKey: "customImage")
        }
        pattern = p
        buildRug(drop: true, center: cloth.centroid, angle: cloth.angle)
    }

    @objc private func chooseSize(_ s: NSMenuItem) {
        guard let v = RugSize(rawValue: s.representedObject as? String ?? "") else { return }
        rugSize = v
        buildRug(drop: true, center: cloth.centroid, angle: cloth.angle)
    }

    @objc private func chooseFeel(_ s: NSMenuItem) {
        guard let v = Feel(rawValue: s.representedObject as? String ?? "") else { return }
        feel = v
        applyFeel()
        wake()
    }

    @objc private func shakeAction() { shake() }
    @objc private func straighten() { buildRug(drop: true, center: cloth.centroid, angle: 0) }

    @objc private func sweep() {
        let n = Sweeper.candidates().count
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Sweep \(n) item\(n == 1 ? "" : "s") under the rug?"
        a.informativeText = "They'll move into a dated folder inside “\(DesktopScanner.rugFolder)” on your Desktop, which hides under the rug. Nothing is deleted, and Unsweep puts everything back."
        a.addButton(withTitle: "Sweep")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let r = Sweeper.sweep()
        let c = cloth.centroid
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            DesktopScanner.place(DesktopScanner.rugFolder, at: CGPoint(x: CGFloat(c.x), y: CGFloat(c.y)), screenHeight: self.screen.frame.height)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.scanner.rescan() }
        }
        if !r.failed.isEmpty { info("Swept \(r.moved). Couldn't move: \(r.failed.prefix(5).joined(separator: ", "))") }
    }

    @objc private func unsweep() {
        let r = Sweeper.unsweepLast()
        scanner.rescan()
        if !r.skipped.isEmpty { info("Put back \(r.restored). Left in place (a file with that name already exists, or it was moved): \(r.skipped.prefix(5).joined(separator: ", "))") }
    }

    private func info(_ s: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = "Underrug"; a.informativeText = s; a.runModal()
    }

    @objc private func openAutomation() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            info("macOS didn't allow that: \(error.localizedDescription). Move Underrug to Applications and try again.")
        }
    }

    @objc private func quit() { save(); NSApp.terminate(nil) }
}
