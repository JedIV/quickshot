import AppKit
import CoreServices
import ImageIO
import CoreText
import UniformTypeIdentifiers
import os

private let log = Logger(subsystem: "local.quickshot", category: "app")
private let ink: CGColor = CGColor(srgbRed: 0.98, green: 0.16, blue: 0.16, alpha: 1)

struct Mark {
    enum Kind { case arrow, box, text }
    var kind: Kind
    var start: CGPoint
    var end: CGPoint
    var width: CGFloat
    var text = ""
    var fontSize: CGFloat = 36
}

func textAttributes(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
    [.font: NSFont.systemFont(ofSize: size, weight: .semibold),
     .foregroundColor: NSColor(cgColor: ink)!]
}

func textFrame(_ mark: Mark, outline: Bool = false) -> (CTFrame, CGSize) {
    let font = CTFontCreateWithName(NSFont.systemFont(ofSize: mark.fontSize, weight: .semibold).fontName as CFString,
                                    mark.fontSize, nil)
    var attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink
    ]
    if outline {
        attributes[NSAttributedString.Key(kCTStrokeColorAttributeName as String)] = CGColor(gray: 1, alpha: 1)
        attributes[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = 6
    }
    let string = NSAttributedString(string: mark.text, attributes: attributes)
    let setter = CTFramesetterCreateWithAttributedString(string)
    let width = max(1, mark.end.x - mark.start.x)
    let measured = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil,
                        CGSize(width: width, height: .greatestFiniteMagnitude), nil)
    let size = CGSize(width: width, height: max(mark.fontSize * 1.3, ceil(measured.height) + 2))
    let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
    return (CTFramesetterCreateFrame(setter, CFRange(), path, nil), size)
}

func drawMarks(_ marks: [Mark], in c: CGContext) {
    c.setAllowsAntialiasing(true)
    c.setShouldAntialias(true)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    for m in marks {
        let p = CGMutablePath()
        switch m.kind {
        case .text:
            guard !m.text.isEmpty else { continue }
            let (frame, size) = textFrame(m)
            c.saveGState()
            c.translateBy(x: m.start.x, y: m.start.y + size.height)
            c.scaleBy(x: 1, y: -1)
            c.textMatrix = .identity
            CTFrameDraw(textFrame(m, outline: true).0, c)
            CTFrameDraw(frame, c)
            c.restoreGState()
            continue
        case .box:
            p.addRect(CGRect(x: min(m.start.x, m.end.x), y: min(m.start.y, m.end.y),
                             width: abs(m.end.x - m.start.x), height: abs(m.end.y - m.start.y)))
        case .arrow:
            let dx = m.end.x - m.start.x, dy = m.end.y - m.start.y
            let distance = hypot(dx, dy)
            guard distance > 0 else { continue }
            let length = min(m.width * 4.5, distance * 0.6)
            let ux = dx / distance, uy = dy / distance
            let base = CGPoint(x: m.end.x - ux * length, y: m.end.y - uy * length)
            let half = m.width / 2
            p.move(to: CGPoint(x: m.start.x - uy * half, y: m.start.y + ux * half))
            p.addLine(to: CGPoint(x: base.x - uy * half, y: base.y + ux * half))
            p.addLine(to: CGPoint(x: base.x - uy * length * 0.42, y: base.y + ux * length * 0.42))
            p.addLine(to: m.end)
            p.addLine(to: CGPoint(x: base.x + uy * length * 0.42, y: base.y - ux * length * 0.42))
            p.addLine(to: CGPoint(x: base.x + uy * half, y: base.y - ux * half))
            p.addLine(to: CGPoint(x: m.start.x + uy * half, y: m.start.y - ux * half))
            p.closeSubpath()
            c.addPath(p)
            c.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
            c.setLineWidth(m.width * 0.6)
            c.strokePath()
            c.addPath(p)
            c.setFillColor(ink)
            c.fillPath()
            continue
        }
        c.addPath(p)
        c.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
        c.setLineWidth(m.width * 1.6)
        c.strokePath()
        c.addPath(p)
        c.setStrokeColor(ink)
        c.setLineWidth(m.width)
        c.strokePath()
    }
}

func render(_ image: CGImage, marks: [Mark]) -> CGImage? {
    guard !marks.isEmpty else { return image }
    guard let c = CGContext(data: nil, width: image.width, height: image.height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    c.translateBy(x: 0, y: CGFloat(image.height))
    c.scaleBy(x: 1, y: -1)
    drawMarks(marks, in: c)
    return c.makeImage()
}

func png(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
}

final class InlineTextView: NSTextView {
    let typingHistory = UndoManager()
    var finish: (() -> Void)?
    var cancel: (() -> Void)?
    override var undoManager: UndoManager? { typingHistory }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancel?(); return }
        if event.modifierFlags.contains(.command), [36, 76].contains(event.keyCode) { finish?(); return }
        super.keyDown(with: event)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), [36, 76].contains(event.keyCode) { finish?(); return true }
        return super.performKeyEquivalent(with: event)
    }
}

final class Canvas: NSView, NSTextViewDelegate {
    let image: CGImage
    var marks: [Mark] = []
    var draft: Mark?
    private(set) var editor: InlineTextView?
    private var editingPoint = CGPoint.zero
    private var editingFontSize: CGFloat = 36
    private var editingIndex: Int?
    var changed: (() -> Void)?
    var copyImage: (() -> Void)?
    let history = UndoManager()
    override var undoManager: UndoManager? { history }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var imageRect: CGRect {
        let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        history.groupsByEvent = false
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.contentsScale = window?.backingScaleFactor ?? 2
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.contentsScale = window?.backingScaleFactor ?? 2
        needsDisplay = true
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil), r = imageRect
        let scale = CGFloat(image.width) / r.width
        return CGPoint(x: min(max(p.x - r.minX, 0), r.width) * scale,
                       y: min(max(p.y - r.minY, 0), r.height) * scale)
    }
    override func mouseDown(with event: NSEvent) {
        commitText()
        guard imageRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        window?.makeFirstResponder(self)
        let p = point(event)
        draft = Mark(kind: event.modifierFlags.contains(.shift) ? .box : .arrow,
                     start: p, end: p, width: 3 * CGFloat(image.width) / imageRect.width)
    }
    override func mouseDragged(with event: NSEvent) {
        guard draft != nil else { return }
        draft!.end = point(event)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard var mark = draft else { return }
        mark.end = point(event)
        draft = nil
        if hypot(mark.end.x - mark.start.x, mark.end.y - mark.start.y) > mark.width {
            replace(marks + [mark])
        } else if mark.kind == .arrow {
            beginText(at: mark.start)
        }
        needsDisplay = true
    }
    func beginText(at point: CGPoint) {
        commitText()
        guard imageRect.width > 0 && imageRect.height > 0 else { return }
        editingIndex = marks.indices.reversed().first {
            guard marks[$0].kind == .text else { return false }
            return CGRect(origin: marks[$0].start, size: textFrame(marks[$0]).1).contains(point)
        }
        let old = editingIndex.map { marks[$0] }
        editingPoint = old?.start ?? point
        editingFontSize = old?.fontSize ?? 18 * CGFloat(image.width) / imageRect.width
        let view = InlineTextView(frame: .zero)
        view.delegate = self
        view.drawsBackground = false
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.isContinuousSpellCheckingEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = false
        view.insertionPointColor = NSColor(cgColor: ink)!
        view.string = old?.text ?? ""
        view.finish = { [weak self] in self?.commitText() }
        view.cancel = { [weak self] in self?.cancelText() }
        editor = view
        addSubview(view)
        layoutEditor()
        window?.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        needsDisplay = true
    }
    override func layout() {
        super.layout()
        layoutEditor()
    }
    private func layoutEditor() {
        guard let editor else { return }
        let r = imageRect, scale = r.width / CGFloat(image.width)
        let origin = CGPoint(x: r.minX + editingPoint.x * scale, y: r.minY + editingPoint.y * scale)
        let size = editingFontSize * scale
        let width = max(1, r.maxX - origin.x)
        editor.frame = CGRect(origin: origin, size: CGSize(width: width, height: max(1, r.maxY - origin.y)))
        editor.font = NSFont.systemFont(ofSize: size, weight: .semibold)
        editor.textColor = NSColor(cgColor: ink)!
        editor.typingAttributes = textAttributes(size)
        if !editor.string.isEmpty {
            editor.textStorage?.setAttributes(textAttributes(size), range: NSRange(location: 0, length: (editor.string as NSString).length))
        }
        editor.textContainer?.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        if let manager = editor.layoutManager, let container = editor.textContainer {
            manager.ensureLayout(for: container)
            let height = max(size * 1.4, ceil(manager.usedRect(for: container).height) + 2)
            editor.setFrameSize(CGSize(width: width, height: min(height, max(1, r.maxY - origin.y))))
        }
    }
    func textDidChange(_ notification: Notification) { layoutEditor() }
    func commitText() {
        guard let editor else { return }
        let value = editor.string
        let index = editingIndex
        let point = editingPoint, size = editingFontSize
        editor.removeFromSuperview()
        self.editor = nil
        editingIndex = nil
        window?.makeFirstResponder(self)
        var next = marks
        if let index { next.remove(at: index) }
        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let mark = Mark(kind: .text, start: point,
                            end: CGPoint(x: CGFloat(image.width), y: CGFloat(image.height)),
                            width: 0, text: value, fontSize: size)
            if let index { next.insert(mark, at: index) } else { next.append(mark) }
        }
        if index != nil || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { replace(next) }
        needsDisplay = true
    }
    func cancelText() {
        editor?.removeFromSuperview()
        editor = nil
        editingIndex = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }
    func replace(_ next: [Mark]) {
        let old = marks
        let group = !history.isUndoing && !history.isRedoing
        if group { history.beginUndoGrouping() }
        history.registerUndo(withTarget: self) { $0.replace(old) }
        if group { history.endUndoGrouping() }
        marks = next
        needsDisplay = true
        changed?()
    }
    @objc func undo(_ sender: Any?) { history.undo() }
    @objc func redo(_ sender: Any?) { history.redo() }
    @objc func copy(_ sender: Any?) { copyImage?() }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "z": event.modifierFlags.contains(.shift) ? history.redo() : history.undo(); return
            case "c": copyImage?(); return
            case "w": window?.performClose(nil); return
            default: break
            }
        }
        if event.keyCode == 51, !marks.isEmpty { replace(Array(marks.dropLast())); return }
        super.keyDown(with: event)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        let r = imageRect
        c.saveGState()
        c.clip(to: r)
        c.translateBy(x: r.minX, y: r.minY)
        c.scaleBy(x: r.width / CGFloat(image.width), y: r.height / CGFloat(image.height))
        let visible = marks.enumerated().compactMap { $0.offset == editingIndex ? nil : $0.element }
        drawMarks(visible + (draft.map { [$0] } ?? []), in: c)
        c.restoreGState()
    }
}

final class ImageHost: NSView {
    let picture = NSImageView()
    let canvas: Canvas
    override var isFlipped: Bool { true }
    init(image: CGImage, canvas: Canvas) {
        self.canvas = canvas
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        picture.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        picture.imageScaling = .scaleAxesIndependently
        picture.wantsLayer = true
        addSubview(picture)
        addSubview(canvas)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        canvas.frame = bounds
        picture.frame = canvas.imageRect
        canvas.needsDisplay = true
        window?.invalidateCursorRects(for: canvas)
    }
}

final class Shot: NSObject, NSWindowDelegate {
    let image: CGImage
    let canvas: Canvas
    let window: NSWindow
    var generation = 0
    var cached: Data?
    var cachedGeneration = -1
    let encoder = DispatchQueue(label: "local.quickshot.encode", qos: .userInitiated)
    var closed: (() -> Void)?
    init(image: CGImage, originalPNG: Data?, screen: NSScreen) {
        self.image = image
        canvas = Canvas(image: image)
        let natural = NSSize(width: CGFloat(image.width) / screen.backingScaleFactor,
                             height: CGFloat(image.height) / screen.backingScaleFactor)
        let available = screen.visibleFrame.size
        let fit = min(1, available.width * 0.9 / natural.width, (available.height * 0.9 - 28) / natural.height)
        let size = NSSize(width: max(140, natural.width * fit), height: max(70, natural.height * fit))
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.titleVisibility = .hidden
        window.title = ""
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 140, height: 70)
        window.contentView = ImageHost(image: image, canvas: canvas)
        window.contentView?.needsLayout = true
        window.contentView?.layoutSubtreeIfNeeded()
        window.delegate = self
        window.center()
        window.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - window.frame.width / 2,
                                      y: screen.visibleFrame.midY - window.frame.height / 2))
        canvas.changed = { [weak self] in self?.prepareCopy() }
        canvas.copyImage = { [weak self] in self?.copy() }
        if let data = originalPNG { cached = data; cachedGeneration = 0 }
        window.makeFirstResponder(canvas)
    }
    func show() {
        NSApp.unhideWithoutActivation()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
    }
    func prepareCopy() {
        generation += 1
        let version = generation, marks = canvas.marks, image = self.image
        encoder.async { [weak self] in
            guard let rendered = render(image, marks: marks), let data = png(rendered) else { return }
            DispatchQueue.main.async {
                guard let self, self.generation == version else { return }
                self.cached = data
                self.cachedGeneration = version
            }
        }
    }
    @discardableResult func copy() -> Bool {
        canvas.commitText()
        let data: Data?
        if cachedGeneration == generation { data = cached }
        else { data = render(image, marks: canvas.marks).flatMap(png) }
        guard let data else { NSSound.beep(); return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setData(data, forType: .png)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { copy() }
    func windowWillClose(_ notification: Notification) { closed?() }
}

final class ScreenshotWatcher {
    let folder: URL
    let queue = DispatchQueue(label: "local.quickshot.watch", qos: .userInitiated)
    var stream: FSEventStreamRef?
    var pending = Set<String>()
    var opened = Set<String>()
    let received: (CGImage, Data?) -> Void
    init(folder: URL, received: @escaping (CGImage, Data?) -> Void) {
        self.folder = folder
        self.received = received
    }
    func start() {
        if let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) {
            opened = Set(files.map { folder.appendingPathComponent($0).path })
        }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<ScreenshotWatcher>.fromOpaque(info).takeUnretainedValue()
            let names = unsafeBitCast(paths, to: NSArray.self) as! [String]
            for path in names.prefix(count) { watcher.changed(path) }
        }
        stream = FSEventStreamCreate(nil, callback, &context, [folder.path] as CFArray,
                                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.01,
                                    FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes |
                                        kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer))
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }
    func changed(_ path: String) {
        guard ["png", "jpg", "jpeg", "tiff", "heic"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()),
              !opened.contains(path), !pending.contains(path) else { return }
        pending.insert(path)
        load(path, attempt: 0)
    }
    func load(_ path: String, attempt: Int) {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
           CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete {
            pending.remove(path)
            opened.insert(path)
            let original = URL(fileURLWithPath: path).pathExtension.lowercased() == "png" ? data : nil
            DispatchQueue.main.async { [received] in received(image, original) }
        } else if attempt < 200 {
            queue.asyncAfter(deadline: .now() + .milliseconds(10)) { [weak self] in self?.load(path, attempt: attempt + 1) }
        } else { pending.remove(path) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var watcher: ScreenshotWatcher?
    var shots: [Shot] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Quickshot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let file = NSMenuItem()
        menu.addItem(file)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.submenu = fileMenu
        let edit = NSMenuItem()
        menu.addItem(edit)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: #selector(Canvas.undo(_:)), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: #selector(Canvas.redo(_:)), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(withTitle: "Copy", action: #selector(Canvas.copy(_:)), keyEquivalent: "c")
        edit.submenu = editMenu
        NSApp.mainMenu = menu
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Quickshot", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        watcher = ScreenshotWatcher(folder: folder) { [weak self] image, data in self?.show(image, data: data) }
        watcher?.start()
        log.info("Ready")
    }
    func show(_ image: CGImage, data: Data?) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let shot = Shot(image: image, originalPNG: data, screen: screen)
        shots.append(shot)
        shot.closed = { [weak self, weak shot] in
            guard let shot else { return }
            self?.shots.removeAll { $0 === shot }
            if self?.shots.isEmpty == true { NSApp.hide(nil) }
        }
        shot.show()
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let data = try? Data(contentsOf: url),
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return }
                DispatchQueue.main.async { self?.show(image, data: url.pathExtension.lowercased() == "png" ? data : nil) }
            }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let key = shots.first(where: { $0.window.isKeyWindow }) ?? shots.last, !key.copy() { return .terminateCancel }
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

if CommandLine.arguments.contains("--quit-running") {
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: "local.quickshot")
        .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    for application in running { application.terminate() }
    let deadline = Date(timeIntervalSinceNow: 5)
    while running.contains(where: { !$0.isTerminated }) && Date() < deadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }
    if running.contains(where: { !$0.isTerminated }) {
        fputs("Quickshot could not finish closing; update cancelled.\n", stderr)
        exit(1)
    }
} else if CommandLine.arguments.contains("--self-test") {
    // Exercise the actual drag handlers, undo, image-coordinate mapping and renderer.
    _ = NSApplication.shared
    let testOutput = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QUICKSHOT_TEST_OUTPUT"] ??
                         FileManager.default.temporaryDirectory.appendingPathComponent("quickshot-tests").path,
                         isDirectory: true)
    try! FileManager.default.createDirectory(at: testOutput, withIntermediateDirectories: true)
    let context = CGContext(data: nil, width: 320, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
    let image = context.makeImage()!
    let marks = [Mark(kind: .arrow, start: CGPoint(x: 25, y: 30), end: CGPoint(x: 150, y: 80), width: 4),
                 Mark(kind: .box, start: CGPoint(x: 180, y: 40), end: CGPoint(x: 290, y: 150), width: 4)]
    let output = render(image, marks: marks)!
    let data = png(output)!
    let path = testOutput.appendingPathComponent("self-test.png")
    try! data.write(to: path)
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    precondition(decoded.width == 320 && decoded.height == 200)
    let pixels = output.dataProvider!.data! as Data
    precondition(pixels.contains { $0 < 150 })
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let canvas = Canvas(image: image)
    window.contentView = canvas
    canvas.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
    func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat, shift: Bool = false) -> NSEvent {
        let point = canvas.convert(NSPoint(x: x, y: y), to: nil)
        return NSEvent.mouseEvent(with: type, location: point, modifierFlags: shift ? [.shift] : [],
                                  timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                  eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    canvas.mouseDown(with: event(.leftMouseDown, 50, 60))
    canvas.mouseDragged(with: event(.leftMouseDragged, 300, 160))
    canvas.mouseUp(with: event(.leftMouseUp, 300, 160))
    precondition(canvas.marks.count == 1)
    precondition(canvas.marks[0].start == CGPoint(x: 25, y: 30))
    precondition(canvas.marks[0].end == CGPoint(x: 150, y: 80))
    canvas.mouseDown(with: event(.leftMouseDown, 360, 80, shift: true))
    canvas.mouseDragged(with: event(.leftMouseDragged, 580, 300, shift: true))
    canvas.mouseUp(with: event(.leftMouseUp, 580, 300, shift: true))
    precondition(canvas.marks.count == 2 && canvas.marks[1].kind == .box)
    canvas.history.undo()
    precondition(canvas.marks.count == 1)
    canvas.history.redo()
    precondition(canvas.marks.count == 2)
    // A click starts text; an empty click and Escape do not leave annotations.
    canvas.mouseDown(with: event(.leftMouseDown, 80, 220))
    canvas.mouseUp(with: event(.leftMouseUp, 80, 220))
    precondition(canvas.editor != nil && canvas.marks.count == 2)
    canvas.editor!.string = "A note\nSecond line"
    canvas.commitText()
    precondition(canvas.editor == nil && canvas.marks.count == 3)
    precondition(canvas.marks.last!.kind == .text && canvas.marks.last!.text == "A note\nSecond line")
    precondition(canvas.marks.last!.start == CGPoint(x: 40, y: 110))
    canvas.history.undo()
    precondition(canvas.marks.count == 2)
    canvas.history.redo()
    precondition(canvas.marks.count == 3)
    canvas.beginText(at: CGPoint(x: 45, y: 115))
    precondition(canvas.editor!.string == "A note\nSecond line")
    canvas.editor!.string = "Edited"
    canvas.commitText()
    precondition(canvas.marks.count == 3 && canvas.marks.last!.text == "Edited")
    canvas.beginText(at: CGPoint(x: 45, y: 115))
    canvas.editor!.string = ""
    canvas.commitText()
    precondition(canvas.marks.count == 2)
    canvas.history.undo()
    precondition(canvas.marks.last!.text == "Edited")
    canvas.beginText(at: CGPoint(x: 250, y: 170))
    canvas.editor!.string = "Cancelled"
    canvas.cancelText()
    precondition(canvas.marks.count == 3 && canvas.editor == nil)
    canvas.beginText(at: CGPoint(x: 250, y: 170))
    canvas.commitText()
    precondition(canvas.marks.count == 3)
    // Export actual glyphs at the image's original resolution, in the same coordinates.
    let textMark = Mark(kind: .text, start: CGPoint(x: 30, y: 25), end: CGPoint(x: 300, y: 190),
                        width: 0, text: "Hello\nRetina", fontSize: 30)
    let textImage = render(image, marks: [textMark])!
    try! png(textImage)!.write(to: testOutput.appendingPathComponent("text-test.png"))
    let textPixels = textImage.dataProvider!.data! as Data
    var redRows: [Int] = []
    for y in 0..<textImage.height {
        for x in 0..<textImage.width {
            let offset = y * textImage.bytesPerRow + x * 4
            if textPixels[offset] > 180 && textPixels[offset + 1] < 150 && textPixels[offset + 2] < 150 {
                redRows.append(y)
            }
        }
    }
    precondition(redRows.count > 100 && redRows.min()! >= 25 && redRows.max()! < 115)
    // Closing/copying must include text that is still being edited, without changing the user's clipboard.
    let pb = NSPasteboard.general
    let savedItems = (pb.pasteboardItems ?? []).map { item -> NSPasteboardItem in
        let saved = NSPasteboardItem()
        for type in item.types { if let data = item.data(forType: type) { saved.setData(data, forType: type) } }
        return saved
    }
    let shot = Shot(image: image, originalPNG: png(image), screen: NSScreen.main!)
    shot.canvas.beginText(at: CGPoint(x: 25, y: 25))
    shot.canvas.editor!.string = "Text on close"
    precondition(shot.windowShouldClose(shot.window))
    let writtenCount = pb.changeCount
    let copied = pb.data(forType: .png)!
    precondition(shot.canvas.editor == nil && shot.canvas.marks.last!.text == "Text on close")
    precondition(copied != png(image)!)
    try! copied.write(to: testOutput.appendingPathComponent("text-on-close.png"))
    if pb.changeCount == writtenCount {
        pb.clearContents()
        if !savedItems.isEmpty { pb.writeObjects(savedItems) }
    }
    let full = CGContext(data: nil, width: 1280, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    full.setFillColor(CGColor(gray: 1, alpha: 1))
    full.fill(CGRect(x: 0, y: 0, width: 1280, height: 800))
    let fixture = full.makeImage()!
    try! png(fixture)!.write(to: testOutput.appendingPathComponent("input.png"))
    let start = CFAbsoluteTimeGetCurrent()
    let sharp = render(fixture, marks: [Mark(kind: .arrow, start: CGPoint(x: 100, y: 100),
                      end: CGPoint(x: 650, y: 350), width: 6),
                      Mark(kind: .box, start: CGPoint(x: 800, y: 180), end: CGPoint(x: 1150, y: 650), width: 6)])!
    try! png(sharp)!.write(to: testOutput.appendingPathComponent("retina-test.png"))
    print("Arrows, boxes, click-to-type, text editing/deletion/cancellation, undo/redo, Retina export and text-on-close clipboard checks passed")
    print("1280x800 render + PNG: \(Int((CFAbsoluteTimeGetCurrent() - start) * 1000)) ms")
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
