import AppKit
import ServiceManagement

enum RugSize: String, CaseIterable {
    case small, medium, large, huge, cover
    var title: String { ["small": "Small", "medium": "Medium", "large": "Large", "huge": "Extra Large", "cover": "Cover the Desktop"][rawValue]! }
    /// The woven part; the fringe is added on the short ends.
    func body(for screen: CGSize) -> CGSize {
        switch self {
        case .small: return CGSize(width: 420, height: 270)
        case .medium: return CGSize(width: 620, height: 400)
        case .large: return CGSize(width: 860, height: 540)
        case .huge: return CGSize(width: 1100, height: 700)
        case .cover: return CGSize(width: screen.width * 0.86, height: screen.height * 0.80)
        }
    }
}

/// The window floats just above the desktop icons and below every app window. It only takes the
/// mouse while the pointer is over the rug or its controls, so the rest of the desktop still works.
final class RugPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class RugView: NSView {
    weak var controller: RugController?
    var rugFrame: RugFrame? { didSet { needsDisplay = true } }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirty: NSRect) {
        guard let f = rugFrame, let ctx = NSGraphicsContext.current?.cgContext else { return }
        Renderer.draw(f, in: ctx, bounds: bounds)
    }
    private func pt(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }
    override func mouseDown(with e: NSEvent) { controller?.press(pt(e), e) }
    override func mouseDragged(with e: NSEvent) { controller?.drag(pt(e)) }
    override func mouseUp(with e: NSEvent) { controller?.release() }
    override func magnify(with e: NSEvent) { controller?.zoom(e.magnification, ended: e.phase == .ended || e.phase == .cancelled) }
    override func scrollWheel(with e: NSEvent) { controller?.spin(e.scrollingDeltaY * (e.hasPreciseScrollingDeltas ? 0.004 : 0.04)) }
    override func rightMouseDown(with e: NSEvent) { if let m = controller?.menu() { NSMenu.popUpContextMenu(m, with: e, for: self) } }

    // Desktop icons dragged from Finder and dropped on the rug go under it. The drop answers
    // .generic, never .move, so Finder leaves the files where they are; only the icons move.
    private func droppedNames(_ info: NSDraggingInfo) -> [String] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return Finder.onDesktop(urls)
    }
    private func dropTarget(_ info: NSDraggingInfo) -> NSDragOperation {
        let p = convert(info.draggingLocation, from: nil)
        return controller?.acceptsDrop(at: p) == true && !droppedNames(info).isEmpty ? .generic : []
    }
    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation { dropTarget(info) }
    override func draggingUpdated(_ info: NSDraggingInfo) -> NSDragOperation { dropTarget(info) }
    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        let names = droppedNames(info)
        guard !names.isEmpty else { return false }
        // Finder snaps the icons back first; sweep a beat later so ours is the last word.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.controller?.sweep(only: Set(names)) }
        return true
    }
}

final class RugController: NSObject, NSMenuDelegate {
    private enum Gesture {
        case move(offset: CGVector)
        case rotate(angle: CGFloat, bearing: CGFloat)
        case peel
    }

    /// Grabbing this close to the woven edge (or anywhere on the fringe) peels instead of moving.
    private static let peelBand: CGFloat = 34

    let screen: NSScreen
    let window: RugPanel
    let view: RugView
    private var placement: Placement
    private var texture: CGImage?
    private var fold: Fold?
    private var unfolding: (from: CGPoint, start: TimeInterval)?
    private var gesture: Gesture?
    private var opacity: CGFloat = 1
    private var peeking = false
    private var lastOver: TimeInterval = 0
    private var cursor: NSCursor?
    private var chrome: (controls: Bool, tip: CGPoint?) = (false, nil)
    private var animator: Timer?
    private var poller: Timer?
    private var sweeping = false
    private var customImage: NSImage?
    private let d = UserDefaults.standard

    var pattern: Pattern { get { Pattern(rawValue: d.string(forKey: "pattern") ?? "") ?? .anatolianRed } set { d.set(newValue.rawValue, forKey: "pattern") } }
    var rugSize: RugSize { get { RugSize(rawValue: d.string(forKey: "size") ?? "") ?? .medium } set { d.set(newValue.rawValue, forKey: "size") } }
    /// Pinch, Bigger and Smaller stretch the chosen size by this much.
    var scale: CGFloat { get { CGFloat(d.object(forKey: "scale") as? Double ?? 1) } set { d.set(Double(newValue), forKey: "scale") } }
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
        view.wantsLayer = true
        view.layerContentsRedrawPolicy = .onSetNeedsDisplay
        view.registerForDraggedTypes([.fileURL])
        window.contentView = view

        let saved = CGPoint(x: d.double(forKey: "cx"), y: d.double(forKey: "cy"))
        placement = Placement(center: saved.x > 0 ? saved : CGPoint(x: f.width * 0.42, y: f.height * 0.45),
                              angle: CGFloat(d.object(forKey: "angle") as? Double ?? -0.06), size: .zero, fringe: 0)
        super.init()
        view.controller = self
        restyle()
        placement.center = clamped(placement.center)
    }

    func show() {
        if visible { window.orderFront(nil) }
        poller = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(poller!, forMode: .common)
    }

    // MARK: drawing

    /// The chosen size, shaped like the real rug: the preset is a box the rug fits inside.
    private var baseBody: CGSize {
        let box = rugSize.body(for: screen.frame.size), a = RugArt.aspect(pattern, customImage: customImage)
        return box.width / box.height > a ? CGSize(width: box.height * a, height: box.height) : CGSize(width: box.width, height: box.width / a)
    }

    /// The woven part: the chosen size times `scale`, never smaller than a bath mat or bigger than the screen.
    private func bodySize(_ s: CGFloat) -> CGSize {
        let base = baseBody, room = screen.frame.size
        let k = min(max(s, 220 / base.width), room.width * 0.95 / base.width, room.height * 0.92 / base.height)
        return CGSize(width: base.width * k, height: base.height * k)
    }

    private func fit(_ body: CGSize) {
        let fringe = min(26, body.height * 0.07)
        placement.size = CGSize(width: body.width + 2 * fringe, height: body.height)
        placement.fringe = fringe
    }

    /// Rebuild the texture after the design or size changes.
    private func restyle() {
        customImage = pattern == .custom ? d.string(forKey: "customImage").flatMap(NSImage.init(contentsOfFile:)) : nil
        let body = bodySize(scale)
        fit(body)
        texture = RugArt.texture(pattern, body: body, fringe: placement.fringe, customImage: customImage)
        render()
    }

    private func render() {
        view.rugFrame = RugFrame(placement: placement, texture: texture, fold: fold, opacity: opacity,
                                 controls: chrome.controls, rotateTip: chrome.tip, optionBadge: peeking)
    }

    /// Runs at 60 Hz only while something is easing: the ⌥ fade or a peel springing back flat.
    private func animate() {
        guard animator == nil else { return }
        animator = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(animator!, forMode: .common)
    }

    private func step() {
        var busy = false
        let target: CGFloat = peeking ? 0.12 : 1
        if abs(opacity - target) > 0.01 { opacity += (target - opacity) * 0.3; busy = true } else { opacity = target }
        if let u = unfolding, var f = fold {
            let t = min((ProcessInfo.processInfo.systemUptime - u.start) / 0.32, 1), e = 1 - pow(1 - t, 3)
            f.to = CGPoint(x: u.from.x + (f.from.x - u.from.x) * e, y: u.from.y + (f.from.y - u.from.y) * e)
            if t < 1 { fold = f; busy = true } else { fold = nil; unfolding = nil }
        }
        render()
        if !busy { animator?.invalidate(); animator = nil }
    }

    // MARK: pointer

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    /// The controls stay up for a moment after the pointer leaves, so it can travel from the rug to the pill.
    private var controlsUp: Bool { gesture != nil || now - lastOver < 0.8 }

    private func onHandle(_ p: CGPoint) -> Bool {
        controlsUp && placement.corners.contains { hypot($0.x - p.x, $0.y - p.y) <= Renderer.handleHit }
    }

    private func onPill(_ p: CGPoint) -> Bool { controlsUp && Renderer.pill(for: placement).contains(p) }

    /// Take the mouse only over the rug and its controls, and fade the rug while ⌥ is held.
    private func poll() {
        guard visible else { return }
        let m = NSEvent.mouseLocation
        let p = CGPoint(x: m.x - screen.frame.minX, y: m.y - screen.frame.minY)
        let alt = NSEvent.modifierFlags.contains(.option)
        if alt != peeking { peeking = alt; animate() }

        let handle = !peeking && onHandle(p), pill = !peeking && onPill(p), rug = !peeking && placement.contains(p)
        let over = gesture != nil || handle || pill || rug
        if over { lastOver = now }
        if window.ignoresMouseEvents == over { window.ignoresMouseEvents = !over }

        // a button held with no gesture of ours is a drag from Finder: leave its cursor alone
        let theirs = gesture == nil && NSEvent.pressedMouseButtons != 0
        let c: NSCursor? = gesture != nil ? .closedHand : handle || pill ? .arrow : rug ? .openHand : nil
        if c !== cursor && !theirs { (c ?? .arrow).set(); cursor = c }

        let rotating: Bool
        if case .rotate = gesture { rotating = true } else { rotating = false }
        let next = (controls: controlsUp && !peeking, tip: handle && gesture == nil || rotating ? p : nil)
        if next.controls != chrome.controls || next.tip != chrome.tip {
            chrome = next
            render()
        }
    }

    func press(_ p: CGPoint, _ e: NSEvent) {
        if onPill(p) { pillClick(p, e); return }
        if onHandle(p) {
            gesture = .rotate(angle: placement.angle, bearing: atan2(p.y - placement.center.y, p.x - placement.center.x))
        } else if placement.contains(p) {
            let q = placement.local(p)
            if placement.inset(q) < Self.peelBand {
                fold = Fold(from: q, to: q)
                unfolding = nil
                gesture = .peel
            } else {
                gesture = .move(offset: CGVector(dx: placement.center.x - p.x, dy: placement.center.y - p.y))
            }
        } else { return }
        NSCursor.closedHand.set(); cursor = .closedHand
        render()
    }

    func drag(_ p: CGPoint) {
        switch gesture {
        case .move(let o):
            placement.center = clamped(CGPoint(x: p.x + o.dx, y: p.y + o.dy))
        case .rotate(let a, let b):
            placement.angle = a + atan2(p.y - placement.center.y, p.x - placement.center.x) - b
            chrome.tip = p
        case .peel:
            fold?.to = placement.local(p)
        case nil:
            return
        }
        render()
    }

    func release() {
        if case .peel = gesture, let f = fold {
            unfolding = (f.to, now)
            animate()
        }
        gesture = nil
        save()
        render()
    }

    /// Pinch over the rug to resize it. Mid-pinch the old texture just stretches; it's rewoven at the new size when the pinch ends.
    func zoom(_ m: CGFloat, ended: Bool) {
        guard gesture == nil else { return }
        resize(to: scale * (1 + m), final: ended)
    }

    private func resize(to s: CGFloat, final: Bool) {
        let body = bodySize(s)
        scale = body.width / baseBody.width
        if final { restyle() } else { fit(body) }
        placement.center = clamped(placement.center)
        if final { save() }
        render()
    }

    func spin(_ a: CGFloat) {
        guard gesture == nil else { return }
        placement.angle += a
        save()
        render()
    }

    func acceptsDrop(at p: CGPoint) -> Bool { visible && !peeking && !sweeping && placement.contains(p) }

    private func clamped(_ c: CGPoint) -> CGPoint {
        let b = view.bounds.insetBy(dx: 40, dy: 40)
        return CGPoint(x: min(max(c.x, b.minX), b.maxX), y: min(max(c.y, b.minY), b.maxY))
    }

    private func save() {
        d.set(Double(placement.center.x), forKey: "cx")
        d.set(Double(placement.center.y), forKey: "cy")
        d.set(Double(placement.angle), forKey: "angle")
    }

    // MARK: design pill

    private func pillClick(_ p: CGPoint, _ e: NSEvent) {
        let r = Renderer.pill(for: placement)
        if p.x < r.minX + 32 { cycle(-1) } else if p.x > r.maxX - 32 { cycle(1) } else {
            NSMenu.popUpContextMenu(designMenu(), with: e, for: view)
        }
    }

    private func cycle(_ by: Int) {
        let all = Pattern.allCases.filter { $0 != .custom }
        let i = all.firstIndex(of: pattern) ?? 0
        pattern = all[(i + by + all.count) % all.count]
        restyle()
    }

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

    private func designMenu() -> NSMenu {
        let m = NSMenu()
        for p in Pattern.allCases {
            let i = item(p.title, #selector(choosePattern(_:)), on: p == pattern, obj: p.rawValue)
            if !p.origin.isEmpty { i.toolTip = p.origin }
            if #available(macOS 14.4, *), !p.origin.isEmpty { i.subtitle = p.origin }
            m.addItem(i)
        }
        m.addItem(.separator())
        let credit = NSMenuItem(title: "Rugs from The Met's Open Access collection", action: nil, keyEquivalent: "")
        credit.isEnabled = false
        m.addItem(credit)
        return m
    }

    private func populate(_ m: NSMenu) {
        m.removeAllItems()
        m.addItem(item(visible ? "Hide Rug" : "Show Rug", #selector(toggle)))
        m.addItem(.separator())
        let di = NSMenuItem(title: "Design", action: nil, keyEquivalent: ""); di.submenu = designMenu(); m.addItem(di)
        let sz = NSMenu()
        let stretched = abs(scale - 1) > 0.01
        for s in RugSize.allCases { sz.addItem(item(s.title, #selector(chooseSize(_:)), on: s == rugSize && !stretched, obj: s.rawValue)) }
        sz.addItem(.separator())
        sz.addItem(item("Bigger", #selector(bigger), "="))
        sz.addItem(item("Smaller", #selector(smaller), "-"))
        if stretched { sz.addItem(item("Back to \(rugSize.title)", #selector(unstretch))) }
        let hint = NSMenuItem(title: "Or pinch on the trackpad over the rug", action: nil, keyEquivalent: ""); hint.isEnabled = false
        sz.addItem(hint)
        let si = NSMenuItem(title: "Size", action: nil, keyEquivalent: ""); si.submenu = sz; m.addItem(si)
        m.addItem(item("Straighten", #selector(straighten)))
        m.addItem(.separator())
        // The sweep itself goes through Finder; the count is only for the title.
        let n = Finder.desktopCount
        let sweepTitle = sweeping ? "Sweeping…"
            : n == nil ? "Sweep All Icons Under the Rug"
            : n! > 0 ? "Sweep \(n!) Icon\(n == 1 ? "" : "s") Under the Rug" : "Desktop Is Already Clean"
        m.addItem(item(sweepTitle, n != 0 && !sweeping ? #selector(sweepAll) : nil))
        m.addItem(item("Sweep Selected Icons Under the Rug", sweeping ? nil : #selector(sweepSelection)))
        if Sweeper.canUnsweep { m.addItem(item("Put the Icons Back", sweeping ? nil : #selector(unsweep))) }
        m.addItem(.separator())
        let tip = NSMenuItem(title: "Drag to move · drag an edge to peek under · drag a corner dot to rotate · hold ⌥ to see through · drop icons on it to sweep them",
                             action: nil, keyEquivalent: "")
        tip.isEnabled = false
        m.addItem(tip)
        m.addItem(.separator())
        m.addItem(item("Open at Login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))
        m.addItem(item("Quit Underrug", #selector(quit), "q"))
    }

    @objc private func toggle() {
        visible.toggle()
        if visible { window.orderFront(nil) } else { window.orderOut(nil) }
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
        restyle()
    }

    @objc private func chooseSize(_ s: NSMenuItem) {
        guard let v = RugSize(rawValue: s.representedObject as? String ?? "") else { return }
        rugSize = v
        resize(to: 1, final: true)
    }

    @objc private func bigger() { resize(to: scale * 1.15, final: true) }
    @objc private func smaller() { resize(to: scale / 1.15, final: true) }
    @objc private func unstretch() { resize(to: 1, final: true) }

    @objc private func straighten() {
        placement.angle = 0
        save()
        render()
    }

    @objc private func sweepAll() { sweep(only: nil) }

    @objc private func sweepSelection() {
        sweeping = true
        DispatchQueue.global(qos: .userInitiated).async {
            let names = Finder.selection()
            DispatchQueue.main.async {
                self.sweeping = false
                guard let names else { self.askFinderAccess(); return }
                if names.isEmpty { self.info("Select some icons on the desktop first, then sweep them. Or drag them straight onto the rug.") }
                else { self.sweep(only: Set(names)) }
            }
        }
    }

    /// Everything on the desktop, or just these icons (a Finder selection or a drop on the rug).
    func sweep(only names: Set<String>?) {
        guard !sweeping else { return }
        sweeping = true
        let rug = placement, h = screen.frame.height
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Sweeper.sweep(under: rug, screenHeight: h, only: names)
            DispatchQueue.main.async {
                self.sweeping = false
                switch r {
                case .swept: break
                case .nothingToSweep: self.info(names == nil ? "Your desktop is already clean." : "None of those are on the desktop.")
                case .noFinderAccess: self.askFinderAccess()
                case .finderSorts:
                    self.info("Finder is keeping your desktop sorted, so it put the icons straight back. Right-click the desktop, set Sort By to None and turn off Use Stacks, then sweep again.")
                }
            }
        }
    }

    @objc private func unsweep() {
        sweeping = true
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Sweeper.unsweep()
            DispatchQueue.main.async {
                self.sweeping = false
                guard let r else { self.askFinderAccess(); return }
                if r.missing > 0 { self.info("Put back \(r.restored) icon\(r.restored == 1 ? "" : "s"). \(r.missing) are no longer on the desktop.") }
            }
        }
    }

    private func askFinderAccess() {
        info("Underrug needs permission to move icons in Finder. Turn on Finder under Underrug in Privacy & Security ▸ Automation, then try again.")
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    private func info(_ s: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = "Underrug"; a.informativeText = s; a.runModal()
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
