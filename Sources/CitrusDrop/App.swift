import AppKit
import PDFKit

final class App: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var panel: WheelPanel!
    private var wheel: DropWheel!
    private var timer: Timer?
    private var files: [URL] = []
    private var available: [Operation] = []
    private var selectedOperations: [Int: String] = [:]
    private var mode = 0
    private var busy = false
    private var worker: Converter?
    private var engineSetup: EngineSetupWindow?
    private var enabled = true
    private var dragCount = NSPasteboard(name:.drag).changeCount
    private var dragArmed = false
    private var shiftBegan: Date?
    private var shiftKeyCount: UInt32 = 0
    private var shiftUsedMouse = false
    private var readingFinder = false
    private var finderShift = UserDefaults.standard.bool(forKey:"finderShift")
    private var lastButtons: Int = 0
    private var lastFlags: NSEvent.ModifierFlags = []
    private var dismissedDrag = false
    private var previews: [NSWindow] = []
    private var results: [URL] = []
    private var picker: NSPopUpButton!
    private var selection: NSTextField!
    private var state: NSTextField!
    private var runButton: NSButton!
    private var progress: NSProgressIndicator!
    private var revealButton: NSButton!
    private var tabs: NSSegmentedControl!
    private var dropView: FileDropView!
    private var operationLabel: NSTextField!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named:.darkAqua)
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        buildMenu(); buildWindow(); buildPanel()
        timer = Timer.scheduledTimer(withTimeInterval:0.045,repeats:true) { [weak self] _ in self?.pollDrag() }
        RunLoop.main.add(timer!, forMode:.common)
        showWindow(nil)
        if Catalog.ffmpeg == nil || Catalog.executable("ffprobe") == nil || Catalog.office == nil { DispatchQueue.main.async { self.dependencies() } }
    }
    private func button(_ title: String, action: Selector) -> NSButton {
        let button = ActionButton(title:title,target:self,action:action); button.bezelStyle = .regularSquare; button.isBordered = false; return button
    }
    private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString:text); field.font = .systemFont(ofSize:size,weight:weight); return field
    }
    private func place(_ view: NSView, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, in parent: NSView) {
        view.frame = NSRect(x:x,y:y,width:width,height:height); parent.addSubview(view)
    }
    private func buildMenu() {
        if statusItem == nil { statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength) }
        statusItem.button?.image = NSImage(systemSymbolName:"arrow.triangle.2.circlepath.circle",accessibilityDescription:"CitrusDrop")
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector, _ key: String = "") {
            let entry = NSMenuItem(title:title,action:action,keyEquivalent:key); entry.target = self; menu.addItem(entry)
        }
        item(L.t("Открыть CitrusDrop…","Open CitrusDrop…"),#selector(showWindow(_:)))
        item(L.t("Открыть файлы…","Choose files…"),#selector(chooseFiles),"o")
        item(enabled ? L.t("✓ Меню при перетаскивании","✓ Drag menu enabled") : L.t("Включить меню перетаскивания","Enable drag menu"),#selector(toggleDrag))
        menu.addItem(.separator())
        item(L.t("Зависимости и форматы…","Dependencies & formats…"),#selector(dependencies))
        item("Русский / English",#selector(changeLanguage))
        item(L.t("Настроить Finder…","Set up Finder…"),#selector(setupFinder))
        item((finderShift ? "✓ " : "") + L.t("Shift на выделенном файле","Shift on selected files"),#selector(toggleFinderShift))
        menu.addItem(.separator()); item(L.t("Выйти","Quit"),#selector(quit),"q")
        statusItem.menu = menu
        let main = NSMenu(); let root = NSMenuItem(title:"CitrusDrop",action:nil,keyEquivalent:""); root.submenu = menu.copy() as? NSMenu; main.addItem(root); NSApp.mainMenu = main
    }
    private func buildWindow() {
        if window != nil { window.close() }
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:720,height:650),styleMask:[.titled,.closable,.miniaturizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title = "CitrusDrop"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(calibratedRed:0.055,green:0.071,blue:0.094,alpha:1)
        window.isReleasedWhenClosed = false; window.delegate = self; window.center()
        let content = window.contentView!
        let mark = NSImageView(); mark.image = Bundle.main.url(forResource:"CitrusDrop",withExtension:"icns").flatMap { NSImage(contentsOf:$0) } ?? NSImage(systemSymbolName:"arrow.triangle.2.circlepath",accessibilityDescription:"CitrusDrop"); mark.contentTintColor = NSColor(calibratedRed:1,green:0.62,blue:0.27,alpha:1)
        place(mark,32,561,34,34,in:content)
        place(label("CitrusDrop",size:26,weight:.semibold),80,568,350,34,in:content)
        let subtitle = label(L.t("Локальный конвертер файлов","Local file converter"),size:12); subtitle.textColor = NSColor(calibratedRed:0.69,green:0.75,blue:0.82,alpha:1)
        place(subtitle,81,546,400,20,in:content)
        let language = NSPopUpButton(frame:.zero,pullsDown:false); language.addItems(withTitles:["Русский","English"]); language.selectItem(at:L.english ? 1 : 0); language.target = self; language.action = #selector(selectLanguage(_:))
        place(language,568,570,120,28,in:content)
        let divider = NSBox(); divider.boxType = .separator; place(divider,32,526,656,1,in:content)
        tabs = NSSegmentedControl(labels:[L.t("Конвертация","Convert"),L.t("Инструменты","Tools"),L.t("Действия","Actions")],trackingMode:.selectOne,target:self,action:#selector(changeMode(_:)))
        tabs.selectedSegment = mode; tabs.segmentStyle = .separated; tabs.selectedSegmentBezelColor = NSColor(calibratedRed:0.25,green:0.34,blue:0.43,alpha:1); place(tabs,32,476,656,30,in:content)
        dropView = FileDropView(frame:.zero); dropView.onFiles = { [weak self] urls in self?.setFiles(urls) }
        place(dropView,32,275,656,180,in:content)
        place(button(L.t("Выбрать файлы…","Choose files…"),action:#selector(chooseFiles)),32,229,172,34,in:content)
        place(button(L.t("Выбрать папку…","Choose folder…"),action:#selector(chooseFolder)),214,229,172,34,in:content)
        selection = label(L.t("Файлы не выбраны","No files selected"),size:12); selection.textColor = NSColor(calibratedRed:0.69,green:0.75,blue:0.82,alpha:1)
        place(selection,32,194,656,26,in:content)
        operationLabel = label("",size:11,weight:.medium); operationLabel.textColor = .secondaryLabelColor; place(operationLabel,32,174,446,18,in:content)
        picker = NSPopUpButton(frame:.zero,pullsDown:false); picker.target = self; picker.action = #selector(selectOperation); place(picker,32,139,446,34,in:content)
        runButton = button(L.t("Выполнить","Run"),action:#selector(runSelected)); (runButton as? ActionButton)?.primary = true; runButton.keyEquivalent = "\r"
        place(runButton,494,139,194,34,in:content)
        progress = NSProgressIndicator(); progress.style = .spinning; progress.isDisplayedWhenStopped = false; place(progress,33,100,18,18,in:content)
        state = label(L.t("Готово. Оригиналы сохраняются.","Ready. Original files are preserved."),size:12); place(state,61,82,627,36,in:content)
        revealButton = button(L.t("Показать результат","Show results"),action:#selector(revealResults)); revealButton.isHidden = results.isEmpty; place(revealButton,488,39,200,30,in:content)
        place(button(L.t("Настроить Finder","Set up Finder"),action:#selector(setupFinder)),32,39,154,30,in:content)
        place(button(L.t("Форматы и движки","Formats & engines"),action:#selector(dependencies)),196,39,177,30,in:content)
        let help = label(L.t("⇧ Форматы   ⌘ Инструменты   ⌃ Действия   ·   Перетащите файл и нажмите клавишу", "⇧ Formats   ⌘ Tools   ⌃ Actions   ·   Drag a file, then press a key"),size:10)
        help.textColor = NSColor(calibratedRed:0.57,green:0.64,blue:0.72,alpha:1); place(help,32,10,656,18,in:content)
        updateSelection()
    }
    private func buildPanel() {
        panel = WheelPanel(contentRect:NSRect(x:0,y:0,width:332,height:332),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isFloatingPanel = true; panel.level = .popUpMenu; panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; panel.hidesOnDeactivate = false; panel.acceptsMouseMovedEvents = true
        wheel = DropWheel(frame:NSRect(x:0,y:0,width:332,height:332)); panel.contentView = wheel
        wheel.onDrop = { [weak self] operation, urls in self?.panel.orderOut(nil); self?.dismissedDrag = true; self?.execute(operation,urls:urls) }
        wheel.onModeChange = { [weak self] mode in guard let self else { return }; self.wheel.mode = mode; self.wheel.operations = Catalog.operations(self.wheel.files,mode:mode); self.wheel.selected = -1; self.wheel.needsDisplay = true }
        wheel.onDismiss = { [weak self] in self?.dismissedDrag = true; self?.panel.orderOut(nil) }
    }
    private func pollDrag() {
        let buttons = NSEvent.pressedMouseButtons
        let flags = NSEvent.modifierFlags.intersection([.shift,.command,.control,.option])
        let pasteboard = NSPasteboard(name:.drag)
        if flags == .shift, lastFlags != .shift { shiftBegan = Date(); shiftUsedMouse = buttons != 0; shiftKeyCount = CGEventSource.counterForEventType(.combinedSessionState,eventType:.keyDown) }
        if shiftBegan != nil, buttons != 0 { shiftUsedMouse = true }
        if flags.isEmpty, lastFlags == .shift, let began = shiftBegan {
            shiftBegan = nil
            if finderShift, !busy, !shiftUsedMouse, CGEventSource.counterForEventType(.combinedSessionState,eventType:.keyDown) == shiftKeyCount, Date().timeIntervalSince(began) < 1.0,
               NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" { openFinderSelection() }
        }
        if buttons & 1 == 0 {
            if lastButtons & 1 != 0, dragArmed {
                // Keep panel alive until AppKit has delivered performDragOperation.
                DispatchQueue.main.asyncAfter(deadline:.now()+0.12) { if NSEvent.pressedMouseButtons & 1 == 0 { self.panel.orderOut(nil) } }
            }
            dragArmed = false; dismissedDrag = false; dragCount = pasteboard.changeCount
        } else {
            if pasteboard.changeCount != dragCount { dragArmed = true; dragCount = pasteboard.changeCount }
            if enabled, !busy, dragArmed, !dismissedDrag, flags != lastFlags || !panel.isVisible {
                let selectedMode: Int? = flags.contains(.control) ? 2 : flags.contains(.command) ? 1 : flags.contains(.shift) ? 0 : nil
                if let selectedMode {
                    let urls = pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL] ?? []
                    let operations = Catalog.operations(urls,mode:selectedMode)
                    if !operations.isEmpty {
                        wheel.operations = operations; wheel.files = urls; wheel.mode = selectedMode; wheel.selected = -1; wheel.needsDisplay = true
                        if !panel.isVisible {
                            let mouse = NSEvent.mouseLocation
                            let screen = NSScreen.screens.first(where:{ $0.frame.contains(mouse) })?.visibleFrame ?? NSScreen.main!.visibleFrame
                            let origin = NSPoint(x:min(max(mouse.x-166,screen.minX),screen.maxX-332),y:min(max(mouse.y-166,screen.minY),screen.maxY-332))
                            panel.setFrameOrigin(origin); panel.orderFrontRegardless()
                        }
                    }
                }
            }
        }
        // Physical Escape is readable without a keyboard event tap or Accessibility permission.
        if panel.isVisible, CGEventSource.keyState(.combinedSessionState,key:53) { dismissedDrag = true; panel.orderOut(nil) }
        lastButtons = buttons; lastFlags = flags
    }
    private func setFiles(_ urls: [URL]) {
        guard !busy else { return }
        files = urls.filter(\.isFileURL); results = []; revealButton.isHidden = true; updateSelection(); updateModeInstruction()
    }
    private func updateSelection() {
        guard selection != nil else { return }
        selection.stringValue = files.isEmpty ? L.t("Файлы не выбраны","No files selected") : files.prefix(3).map(\.lastPathComponent).joined(separator:" · ") + (files.count > 3 ? " (+\(files.count-3))" : "")
        available = Catalog.operations(files,mode:mode); picker.removeAllItems(); picker.addItems(withTitles:available.map(L.operation))
        if let id = selectedOperations[mode], let index = available.firstIndex(where: { $0.id == id }) { picker.selectItem(at:index) }
        if available.isEmpty { picker.addItem(withTitle: files.isEmpty ? L.t("Сначала выберите файлы","Choose files first") : L.t("Нет доступных операций","No available operations")) }
        dropView.mode = mode; dropView.fileCount = files.count
        operationLabel.stringValue = [L.t("Новый формат","Output format"),L.t("Инструмент","Tool"),L.t("Действие с файлами","File action")][mode]
        picker.setAccessibilityLabel(operationLabel.stringValue)
        tabs.isEnabled = !busy
        picker.isEnabled = !busy && !available.isEmpty; runButton.isEnabled = busy || !available.isEmpty
        updateRunButton()
    }
    private func updateRunButton() {
        if busy { runButton.title = L.t("Отменить","Cancel"); return }
        if mode == 0 { runButton.title = L.t("Конвертировать","Convert") }
        else if available.indices.contains(picker.indexOfSelectedItem) { runButton.title = L.operation(available[picker.indexOfSelectedItem]) }
        else { runButton.title = mode == 1 ? L.t("Применить","Apply") : L.t("Выполнить","Run") }
    }
    @objc private func selectOperation() {
        if available.indices.contains(picker.indexOfSelectedItem) { selectedOperations[mode] = available[picker.indexOfSelectedItem].id }
        updateRunButton()
    }
    @objc func showWindow(_ sender: Any?) { NSApp.activate(ignoringOtherApps:true); window.makeKeyAndOrderFront(nil) }
    @objc private func chooseFiles() {
        let dialog = NSOpenPanel(); dialog.allowsMultipleSelection = true; dialog.canChooseDirectories = false
        if dialog.runModal() == .OK { setFiles(dialog.urls); showWindow(nil) }
    }
    @objc private func chooseFolder() {
        let dialog = NSOpenPanel(); dialog.canChooseDirectories = true; dialog.canChooseFiles = false; dialog.allowsMultipleSelection = true
        if dialog.runModal() == .OK { setFiles(dialog.urls); showWindow(nil) }
    }
    @objc private func changeMode(_ sender: NSSegmentedControl) {
        guard !busy, (0...2).contains(sender.selectedSegment) else { return }
        mode = sender.selectedSegment; updateSelection(); updateModeInstruction()
    }
    private func updateModeInstruction() {
        state.stringValue = files.isEmpty ? L.t("Выберите или перетащите файлы, чтобы увидеть операции.","Choose or drop files to see available operations.") : [L.t("Выберите новый формат. Результат сохранится рядом с оригиналом.","Choose an output format. The result is saved beside the original."),L.t("Выберите инструмент. Обработанный файл сохранится отдельной копией.","Choose a tool. The processed file is saved as a separate copy."),L.t("Выберите действие для выделенных файлов.","Choose an action for the selected files.")][mode]
        if !files.isEmpty && available.isEmpty { state.stringValue = L.t("Нет общих операций. Проверьте выбранные файлы и раздел «Форматы и движки».","No shared operations. Check the selected files and Formats & engines.") }
    }
    @objc private func runSelected() { if busy { worker?.cancel(); return }; let index = picker.indexOfSelectedItem; guard available.indices.contains(index) else { return }; execute(available[index],urls:files) }
    @objc private func revealResults() { NSWorkspace.shared.activateFileViewerSelecting(results) }
    @objc private func toggleDrag() { enabled.toggle(); panel.orderOut(nil); buildMenu() }
    @objc private func quit() {
        if busy || engineSetup?.isInstalling == true { alert(L.t("Идёт обработка","Processing files"), L.t("Дождитесь завершения операции перед выходом.","Wait for the current operation to finish before quitting.")); return }
        NSApp.terminate(nil)
    }
    @objc private func selectLanguage(_ sender: NSPopUpButton) { applyLanguage(sender.indexOfSelectedItem == 1) }
    @objc private func changeLanguage() { applyLanguage(!L.english) }
    private func applyLanguage(_ english: Bool) {
        if engineSetup?.isInstalling != true { engineSetup?.close(); engineSetup = nil }
        L.english = english; wheel.setAccessibilityLabel(L.t("Меню файлов","File wheel")); wheel.needsDisplay = true; buildMenu(); let visible = window.isVisible; buildWindow(); if visible { showWindow(nil) }
        if busy { progress.startAnimation(nil); state.stringValue = L.t("Обработка…","Processing…") }
    }
    @objc private func dependencies() {
        if engineSetup == nil { engineSetup = EngineSetupWindow(); engineSetup?.onInstalled = { [weak self] in self?.updateSelection() } }
        engineSetup?.present()
    }
    private func alert(_ title: String, _ message: String) {
        let dialog = NSAlert(); dialog.messageText = title; dialog.informativeText = message; dialog.addButton(withTitle:"OK")
        NSApp.activate(ignoringOtherApps:true); dialog.runModal()
    }
    private func number(_ title: String, default value: String) -> Double? {
        let dialog = NSAlert(); dialog.messageText = title; let input = NSTextField(string:value); input.frame = NSRect(x:0,y:0,width:280,height:26); dialog.accessoryView = input
        dialog.addButton(withTitle:"OK"); dialog.addButton(withTitle:L.t("Отмена","Cancel")); NSApp.activate(ignoringOtherApps:true)
        guard dialog.runModal() == .alertFirstButtonReturn, let number = Double(input.stringValue.replacingOccurrences(of:",",with:".")), number.isFinite else { return nil }
        return number
    }
    private func execute(_ operation: Operation, urls: [URL]) {
        guard !busy else { return }
        files = urls; updateSelection()
        if ["reveal","copyPath","copy","duplicate","move","airdrop","float","terminal"].contains(operation.id) { fileAction(operation.id,urls:urls); return }
        var options = ConversionOptions()
        if operation.id == "crop" {
            guard let width = number(L.t("Ширина обрезки по центру, пиксели","Center crop width, pixels"),default:"1080"), width >= 1, width <= 32000,
                  let height = number(L.t("Высота обрезки по центру, пиксели","Center crop height, pixels"),default:"1080"), height >= 1, height <= 32000 else { return }
            options.cropWidth = Int(width); options.cropHeight = Int(height)
        }
        if operation.id == "resize" {
            guard let size = number(L.t("Максимальная сторона, пиксели","Maximum dimension, pixels"),default:"1920"), size >= 16, size <= 16000 else { return }; options.maxDimension = Int(size)
        }
        if operation.id == "trim" {
            guard let start = number(L.t("Начало, секунды","Start, seconds"),default:"0"), start >= 0,
                  let duration = number(L.t("Длительность, секунды","Duration, seconds"),default:"10"), duration > 0 else { return }
            options.trimStart = start; options.trimDuration = duration
        }
        busy = true; results = []; revealButton.isHidden = true; updateSelection(); progress.startAnimation(nil)
        state.stringValue = L.t("Обработка…","Processing…"); showWindow(nil)
        let captured = options
        let converter = Converter(); worker = converter
        DispatchQueue.global(qos:.userInitiated).async {
            let result = Result { try converter.perform(operation,urls:urls,options:captured) { text in DispatchQueue.main.async { self.state.stringValue = text } } }
            DispatchQueue.main.async {
                self.busy = false; self.worker = nil; self.progress.stopAnimation(nil); self.updateSelection()
                switch result {
                case .success(let outputs):
                    self.results = outputs; self.revealButton.isHidden = outputs.isEmpty
                    self.state.stringValue = L.t("Готово · результатов: \(outputs.count). Копии рядом с оригиналами.","Done · \(outputs.count) result(s). Saved next to the originals.")
                    if operation.id == "compress" {
                        let before = urls.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0) }
                        let after = outputs.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0) }
                        if before > 0 { let percent = Int((1 - Double(after)/Double(before))*100); self.state.stringValue = L.t("Готово · сжато на \(percent)% · копии рядом с оригиналами.","Done · \(percent)% smaller · saved next to originals.") }
                    }
                    self.statusItem.button?.image = NSImage(systemSymbolName:"checkmark.circle",accessibilityDescription:L.t("Готово","Done"))
                case .failure(let error):
                    self.state.stringValue = L.error(error.localizedDescription)
                    self.alert(L.t("Операция не завершена","Operation could not finish"),L.error(error.localizedDescription))
                }
            }
        }
    }
    private func fileAction(_ action: String, urls: [URL]) {
        guard let first = urls.first else { return }
        results = []; revealButton.isHidden = true
        do {
            switch action {
            case "reveal": NSWorkspace.shared.activateFileViewerSelecting(urls); state.stringValue = L.t("Показываю выбранные файлы в Finder.","Showing selected files in Finder.")
            case "copyPath": NSPasteboard.general.clearContents(); NSPasteboard.general.setString(urls.map(\.path).joined(separator:"\n"),forType:.string); state.stringValue = L.t("Пути скопированы в буфер обмена.","File paths copied to the clipboard.")
            case "copy": NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(urls as [NSURL]); state.stringValue = L.t("Файлы скопированы. Вставьте их в нужную папку.","Files copied. Paste them into the destination folder.")
            case "duplicate":
                for source in urls { let destination = uniqueURL(in:source.deletingLastPathComponent(),stem:source.deletingPathExtension().lastPathComponent + "-copy",ext:source.pathExtension); try FileManager.default.copyItem(at:source,to:destination); results.append(destination) }
                state.stringValue = L.t("Создано копий: \(results.count). Оригиналы сохранены.","Created \(results.count) duplicate(s). Originals are preserved.")
            case "move":
                let chooser = NSOpenPanel(); chooser.canChooseFiles = false; chooser.canChooseDirectories = true; chooser.prompt = L.t("Переместить сюда","Move here")
                NSApp.activate(ignoringOtherApps:true)
                if chooser.runModal() == .OK, let directory = chooser.url {
                    // Validate the entire batch before moving anything.
                    let names = urls.map(\.lastPathComponent)
                    guard Set(names).count == names.count else { throw DropError(L.t("В наборе есть одинаковые имена файлов.","The selection contains duplicate filenames.")) }
                    for source in urls {
                        let destination = directory.appendingPathComponent(source.lastPathComponent)
                        if FileManager.default.fileExists(atPath:destination.path) { throw DropError(L.t("В папке уже есть файл: ","A file already exists: ") + source.lastPathComponent) }
                    }
                    var moved: [(URL,URL)] = []
                    do { for source in urls { let target = directory.appendingPathComponent(source.lastPathComponent); try FileManager.default.moveItem(at:source,to:target); moved.append((source,target)) } }
                    catch {
                        var rollbackFailed: [String] = []
                        for (source,target) in moved.reversed() { do { try FileManager.default.moveItem(at:target,to:source) } catch { rollbackFailed.append(target.path) } }
                        if !rollbackFailed.isEmpty { throw DropError(error.localizedDescription + "\n" + L.t("Остались в новой папке:\n","Remain in destination:\n") + rollbackFailed.joined(separator:"\n")) }
                        throw error
                    }
                    results = moved.map { $0.1 }; files = []; updateSelection()
                    state.stringValue = L.t("Перемещено файлов: \(results.count).", "Moved \(results.count) file(s).")
                }
            case "airdrop":
                guard let service = NSSharingService(named:.sendViaAirDrop), service.canPerform(withItems:urls) else { throw DropError(L.t("AirDrop недоступен на этом Mac.","AirDrop is unavailable on this Mac.")) }; service.perform(withItems:urls); state.stringValue = L.t("Выберите получателя в окне AirDrop.","Choose a recipient in the AirDrop window.")
            case "terminal":
                let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/bin/open"); process.arguments = ["-a","Terminal",Family.of(first) == .folder ? first.path : first.deletingLastPathComponent().path]; try process.run()
                state.stringValue = L.t("Открываю папку в Терминале.","Opening the folder in Terminal.")
            case "float": floatPreview(first); state.stringValue = L.t("Предпросмотр открыт поверх других окон.","Preview opened above other windows.")
            default: break
            }
        } catch { state.stringValue = L.error(error.localizedDescription); alert(L.t("Не удалось выполнить действие","Action failed"),L.error(error.localizedDescription)) }
        revealButton.isHidden = results.isEmpty
    }
    private func floatPreview(_ url: URL) {
        let preview = NSPanel(contentRect:NSRect(x:0,y:0,width:500,height:420),styleMask:[.titled,.closable,.resizable,.utilityWindow],backing:.buffered,defer:false)
        preview.title = url.lastPathComponent; preview.level = .floating; preview.isReleasedWhenClosed = false; preview.center()
        if Family.of(url) == .pdf { let view = PDFView(frame:preview.contentView!.bounds); view.autoresizingMask = [.width,.height]; view.document = PDFDocument(url:url); view.autoScales = true; preview.contentView = view }
        else if let image = NSImage(contentsOf:url) { let view = NSImageView(frame:preview.contentView!.bounds); view.image = image; view.imageScaling = .scaleProportionallyUpOrDown; view.autoresizingMask = [.width,.height]; preview.contentView = view }
        else {
            let view = NSTextView(frame:preview.contentView!.bounds); view.isEditable = false
            let size = (try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? Int.max
            view.string = size < 2_000_000 ? ((try? String(contentsOf:url,encoding:.utf8)) ?? url.path) : url.path
            let scroll = NSScrollView(frame:preview.contentView!.bounds); scroll.documentView = view; scroll.hasVerticalScroller = true; scroll.autoresizingMask = [.width,.height]; view.autoresizingMask = [.width]; preview.contentView = scroll
        }
        previews.removeAll(where:{ !$0.isVisible }); previews.append(preview); preview.makeKeyAndOrderFront(nil)
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if window == nil { files = urls; return }
        guard !busy else { showWindow(nil); return }
        mode = 0; tabs.selectedSegment = 0; setFiles(urls); showWindow(nil)
    }
    @objc private func setupFinder() {
        NSUpdateDynamicServices()
        let dialog = NSAlert(); dialog.messageText = L.t("CitrusDrop в Finder", "CitrusDrop in Finder")
        dialog.informativeText = L.t("Правая кнопка на файле → Службы → CitrusDrop — Конвертировать… или Сжать. Если пункт не появился, включите его в Системные настройки → Клавиатура → Сочетания клавиш → Службы → Файлы и папки.\n\nМожно также включить короткое нажатие Shift на выделенных файлах. macOS запросит доступ к Finder.","Right-click a file → Services → CitrusDrop — Convert… or Compress. If missing, enable it in System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders.\n\nYou can also enable tapping Shift on selected files. macOS will ask for permission to access Finder.")
        dialog.addButton(withTitle:L.t("Включить Shift","Enable Shift")); dialog.addButton(withTitle:L.t("Готово","Done"))
        NSApp.activate(ignoringOtherApps:true)
        if dialog.runModal() == .alertFirstButtonReturn { finderShift = true; UserDefaults.standard.set(true,forKey:"finderShift"); buildMenu(); openFinderSelection() }
    }
    @objc private func toggleFinderShift() {
        finderShift.toggle(); UserDefaults.standard.set(finderShift,forKey:"finderShift"); buildMenu()
        if finderShift { openFinderSelection() }
    }
    private func openFinderSelection() {
        guard !readingFinder else { return }; readingFinder = true
        state.stringValue = L.t("Ждём разрешения macOS для Finder…","Waiting for macOS Finder permission…")
        FinderSelection.requestPermission { [weak self] status in
            guard let self else { return }
            defer { self.readingFinder = false }
            guard status == 0 else {
                self.finderShift = false; UserDefaults.standard.set(false,forKey:"finderShift"); self.buildMenu()
                self.state.stringValue = L.t("Shift выключен. Перетаскивание и службы Finder доступны.","Shift disabled. Dragging and Finder services remain available.")
                self.alert(L.t("Доступ к Finder","Finder access"),L.t("Разрешите CitrusDrop управлять Finder в Системные настройки → Конфиденциальность и безопасность → Автоматизация, затем включите Shift снова.","Allow CitrusDrop to control Finder in System Settings → Privacy & Security → Automation, then enable Shift again."))
                return
            }
            do {
                let selected = try FinderSelection.read()
                self.state.stringValue = L.t("Shift включён. Выделите файл в Finder и коротко нажмите Shift.","Shift enabled. Select a file in Finder and tap Shift.")
                if !selected.isEmpty { self.showClickWheel(selected) }
            } catch { self.alert(L.t("Доступ к Finder","Finder access"),error.localizedDescription) }
        }
    }
    private func showClickWheel(_ urls: [URL]) {
        guard !busy else { return }
        let operations = Catalog.operations(urls,mode:0)
        if operations.isEmpty { setFiles(urls); showWindow(nil); return }
        wheel.files = urls; wheel.mode = 0; wheel.operations = operations; wheel.selected = -1; wheel.needsDisplay = true
        let mouse = NSEvent.mouseLocation; let screen = NSScreen.screens.first(where:{ $0.frame.contains(mouse) })?.visibleFrame ?? NSScreen.main!.visibleFrame
        panel.setFrameOrigin(NSPoint(x:min(max(mouse.x-166,screen.minX),screen.maxX-332),y:min(max(mouse.y-166,screen.minY),screen.maxY-332)))
        NSApp.activate(ignoringOtherApps:true); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(wheel)
    }
    @objc func convertSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = serviceFiles(pasteboard)
        guard !urls.isEmpty else { error.pointee = L.t("Не получены файлы Finder.","No Finder files received.") as NSString; return }
        showClickWheel(urls)
    }
    @objc func compressSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard !busy else { showWindow(nil); return }
        let urls = serviceFiles(pasteboard)
        guard !urls.isEmpty else { error.pointee = L.t("Не получены файлы Finder.","No Finder files received.") as NSString; return }
        let operations = Catalog.operations(urls,mode:1)
        if let compress = operations.first(where:{ $0.id == "compress" }) { execute(compress,urls:urls) }
        else { mode = 1; tabs.selectedSegment = 1; setFiles(urls); showWindow(nil) }
    }
    private func serviceFiles(_ pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL], !urls.isEmpty { return urls }
        return (pasteboard.propertyList(forType:NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] ?? []).map { URL(fileURLWithPath:$0) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { (busy || engineSetup?.isInstalling == true) ? .terminateCancel : .terminateNow }
}
