import AppKit
import Carbon

/// Reads only Finder's selection, through the public Apple Events interface.
/// macOS owns the Automation consent prompt; no Accessibility event tap is used.
enum FinderSelection {
    static func requestPermission(_ completion: @escaping (OSStatus) -> Void) {
        DispatchQueue.global(qos:.userInitiated).async {
            let target = NSAppleEventDescriptor(bundleIdentifier:"com.apple.finder")
            let status = AEDeterminePermissionToAutomateTarget(target.aeDesc,typeWildCard,typeWildCard,true)
            DispatchQueue.main.async { completion(status) }
        }
    }
    static func read() throws -> [URL] {
        let source = """
        with timeout of 5 seconds
            tell application "Finder"
                set selectedItems to selection
                set paths to {}
                repeat with selectedItem in selectedItems
                    set end of paths to POSIX path of (selectedItem as alias)
                end repeat
                return paths
            end tell
        end timeout
        """
        guard let script = NSAppleScript(source:source) else { throw DropError(L.t("Не удалось подготовить запрос Finder.","Cannot prepare Finder request.")) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error { throw DropError(L.t("Finder не ответил на запрос. Проверьте разрешение в Системные настройки → Конфиденциальность и безопасность → Автоматизация. ","Finder did not respond. Check permission in System Settings → Privacy & Security → Automation. ") + String(describing:error[NSAppleScript.errorMessage] ?? "")) }
        guard result.numberOfItems > 0 else { return [] }
        return (1...result.numberOfItems).compactMap { result.atIndex($0)?.stringValue }.map { URL(fileURLWithPath:$0) }
    }
}

final class ActionButton: NSButton {
    var primary = false
    private var hovering = false
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect:bounds,options:[.activeInKeyWindow,.mouseEnteredAndExited,.inVisibleRect],owner:self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func highlight(_ flag: Bool) { super.highlight(flag); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let background: NSColor = !isEnabled ? NSColor(calibratedWhite:0.15,alpha:1) : primary ? NSColor(calibratedRed:1,green:0.62,blue:0.27,alpha:1) : NSColor(calibratedRed:0.13,green:0.16,blue:0.20,alpha:1)
        (isHighlighted ? background.blended(withFraction:0.16,of:.black)! : hovering && isEnabled ? background.blended(withFraction:0.08,of:.white)! : background).setFill(); NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:9,yRadius:9).fill()
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let color: NSColor = !isEnabled ? .disabledControlTextColor : primary ? NSColor(calibratedWhite:0.06,alpha:1) : .labelColor
        let size: CGFloat = 13
        title.draw(in:NSRect(x:8,y:(bounds.height-size-3)/2,width:bounds.width-16,height:size+5),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:primary ? .semibold : .medium),.foregroundColor:color,.paragraphStyle:style])
        if window?.firstResponder === self { NSColor.keyboardFocusIndicatorColor.setStroke(); let ring = NSBezierPath(roundedRect:bounds.insetBy(dx:2,dy:2),xRadius:8,yRadius:8); ring.lineWidth = 2; ring.stroke() }
    }
}
