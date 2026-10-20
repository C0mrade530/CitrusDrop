import AppKit

final class WheelPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class DropWheel: NSView {
    var operations: [Operation] = [] { didSet { accessibleSectors = operations.indices.map { WheelSector(wheel:self,index:$0) } } }
    private var accessibleSectors: [WheelSector] = []
    var files: [URL] = []
    var mode = 0
    var selected = -1
    var onDrop: ((Operation, [URL]) -> Void)?
    var onDismiss: (() -> Void)?
    var onModeChange: ((Int) -> Void)?
    private let outer: CGFloat = 154
    private let inner: CGFloat = 60
    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func accessibilityChildren() -> [Any]? { accessibleSectors }
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(L.t("Меню файлов", "File wheel"))
    }
    required init?(coder: NSCoder) { fatalError() }
    var center: NSPoint { NSPoint(x: bounds.midX, y: bounds.midY) }
    func selection(at point: NSPoint) -> Int {
        let dx = point.x - center.x, dy = point.y - center.y
        let radius = hypot(dx, dy)
        guard radius >= inner, radius <= outer + 8, !operations.isEmpty else { return -1 }
        var angle = atan2(dx, dy)
        if angle < 0 { angle += 2 * .pi }
        return Int((angle + .pi / CGFloat(operations.count)).truncatingRemainder(dividingBy: 2 * .pi) / (2 * .pi / CGFloat(operations.count)))
    }
    override func draw(_ dirtyRect: NSRect) {
        guard !operations.isEmpty else { return }
        NSColor(calibratedRed:0.055,green:0.071,blue:0.094,alpha:0.99).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 9, dy: 9)).fill()
        let step = 360.0 / CGFloat(operations.count)
        for (index, operation) in operations.enumerated() {
            let start = 90 - CGFloat(index) * step + step / 2 - 0.5
            let end = start - step + 1
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: outer, startAngle: start, endAngle: end, clockwise: true)
            path.appendArc(withCenter: center, radius: inner, startAngle: end, endAngle: start, clockwise: false)
            path.close()
            let active = selected == index
            (active ? NSColor.systemOrange : NSColor(calibratedRed:0.10,green:0.13,blue:0.17,alpha:1)).setFill(); path.fill()
            let radians = (90 - CGFloat(index) * step) * .pi / 180
            let position = NSPoint(x: center.x + cos(radians) * 107, y: center.y + sin(radians) * 107)
            let color = active ? NSColor.black : NSColor.labelColor
            if mode != 0, let image = NSImage(systemSymbolName: operation.symbol, accessibilityDescription: L.operation(operation)) {
                let rect = NSRect(x: position.x - 9, y: position.y + 3, width: 18, height: 18)
                image.withSymbolConfiguration(.init(pointSize: 16, weight: .medium).applying(.init(paletteColors:[color])))?.draw(in: rect)
            }
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byWordWrapping
            let title = L.operation(operation)
            title.draw(in: NSRect(x: position.x - 50,y: position.y - (mode == 0 ? 10 : 25),width: 100,height: 27), withAttributes: [.font:NSFont.systemFont(ofSize: mode == 0 ? 14 : 10, weight:.semibold), .foregroundColor:color,.paragraphStyle:paragraph])
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let heading = mode == 0 ? L.t("Формат","Format") : mode == 1 ? L.t("Инструменты","Tools") : L.t("Действия","Actions")
        heading.draw(in: NSRect(x: center.x - 57,y: center.y + 2,width: 114,height: 20), withAttributes:[.font:NSFont.systemFont(ofSize:12, weight:.semibold),.foregroundColor:NSColor.labelColor,.paragraphStyle:paragraph])
        L.t("\(files.count) файл(а)","\(files.count) file(s)").draw(in:NSRect(x:center.x-55,y:center.y-19,width:110,height:18),withAttributes:[.font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor.secondaryLabelColor,.paragraphStyle:paragraph])
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        selected = selection(at: convert(sender.draggingLocation, from:nil)); needsDisplay = true
        return selected >= 0 ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { selected = -1; needsDisplay = true }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { selected >= 0 }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = (sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL]) ?? []
        guard selected >= 0, selected < operations.count, !urls.isEmpty else { return false }
        let operation = operations[selected]
        // Do not run work inside the source application's drag callback.
        DispatchQueue.main.async { self.onDrop?(operation, urls) }
        return true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect:bounds,options:[.activeAlways,.mouseMoved,.inVisibleRect],owner:self))
    }
    override func mouseMoved(with event: NSEvent) { selected = selection(at:convert(event.locationInWindow,from:nil)); needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        selected = selection(at:convert(event.locationInWindow,from:nil))
        if selected >= 0, selected < operations.count { onDrop?(operations[selected],files) }
    }
    override func flagsChanged(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { onModeChange?(2) }
        else if event.modifierFlags.contains(.command) { onModeChange?(1) }
        else if event.modifierFlags.contains(.shift) { onModeChange?(0) }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDismiss?(); return }
        if event.keyCode == 124 || event.keyCode == 125 { selected = (selected + 1) % max(1, operations.count) }
        else if event.keyCode == 123 || event.keyCode == 126 { selected = (selected + operations.count - 1) % max(1,operations.count) }
        else if event.keyCode == 36, selected >= 0, selected < operations.count { onDrop?(operations[selected], files) }
        needsDisplay = true
    }
}

final class FileDropView: NSView {
    var onFiles: (([URL]) -> Void)?
    var mode = 0 { didSet { refreshDescription() } }
    var fileCount = 0 { didSet { refreshDescription() } }
    private var heading: String { [L.t("Сменить формат","Convert to a new format"),L.t("Сжатие и обработка","Compress and edit"),L.t("Действия с файлами","Manage your files")][mode] }
    private var detail: String { [L.t("Фото, видео, аудио, PDF и офисные документы","Images, video, audio, PDF and Office documents"),L.t("Сжатие, размер, обрезка, поворот и метаданные","Compression, resize, crop, rotation and metadata"),L.t("Копирование, перемещение, AirDrop и просмотр","Copy, move, AirDrop and preview")][mode] }
    private var invitation: String { fileCount == 0 ? L.t("Перетащите файлы сюда или выберите их ниже","Drop files here or choose them below") : L.t("Выберите операцию ниже · можно выбрать другие файлы","Choose an operation below · drop to select other files") }
    private func refreshDescription() { setAccessibilityLabel("\(heading). \(detail). \(invitation)"); needsDisplay = true }
    private var hovering = false
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]); wantsLayer = true; setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel(L.t("Область для файлов","File drop area")) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 3,dy: 3)
        (hovering ? NSColor.systemOrange.withAlphaComponent(0.15) : NSColor(calibratedRed:0.075,green:0.098,blue:0.13,alpha:1)).setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14); path.fill()
        (hovering ? NSColor.systemOrange : NSColor(calibratedRed:0.19,green:0.24,blue:0.30,alpha:1)).setStroke(); path.lineWidth = 1; path.stroke()
        NSImage(systemSymbolName:["arrow.triangle.2.circlepath","slider.horizontal.3","folder"][mode],accessibilityDescription:nil)?.withSymbolConfiguration(.init(paletteColors:[.systemOrange]))?.draw(in:NSRect(x:bounds.midX-16,y:bounds.midY+30,width:32,height:32))
        let style = NSMutableParagraphStyle(); style.alignment = .center
        heading.draw(in:NSRect(x:20,y:bounds.midY-2,width:bounds.width-40,height:24),withAttributes:[.font:NSFont.systemFont(ofSize:18,weight:.medium),.foregroundColor:NSColor.labelColor,.paragraphStyle:style])
        detail.draw(in:NSRect(x:20,y:bounds.midY-29,width:bounds.width-40,height:20),withAttributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.secondaryLabelColor,.paragraphStyle:style])
        invitation.draw(in:NSRect(x:20,y:bounds.midY-53,width:bounds.width-40,height:18),withAttributes:[.font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor.secondaryLabelColor,.paragraphStyle:style])
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { hovering = true; needsDisplay = true; return .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { hovering = false; needsDisplay = true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hovering = false; needsDisplay = true
        let files = sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL] ?? []
        onFiles?(files); return !files.isEmpty
    }
}

final class WheelSector: NSAccessibilityElement {
    weak var wheel: DropWheel?
    let index: Int
    init(wheel: DropWheel, index: Int) {
        self.wheel = wheel; self.index = index; super.init()
        setAccessibilityRole(.button); setAccessibilityEnabled(true); setAccessibilityLabel(L.operation(wheel.operations[index])); setAccessibilityParent(wheel)
    }
    override func accessibilityFrame() -> NSRect {
        guard let wheel, let window = wheel.window else { return .zero }
        let angle = (90 - CGFloat(index) * 360 / CGFloat(max(1,wheel.operations.count))) * .pi / 180
        let rect = NSRect(x:wheel.bounds.midX + cos(angle)*107-36,y:wheel.bounds.midY + sin(angle)*107-20,width:72,height:40)
        return window.convertToScreen(wheel.convert(rect,to:nil))
    }
    override func accessibilityPerformPress() -> Bool {
        guard let wheel, wheel.operations.indices.contains(index) else { return false }
        wheel.onDrop?(wheel.operations[index],wheel.files); return true
    }
}
