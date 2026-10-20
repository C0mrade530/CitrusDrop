import AppKit

final class EngineSetupWindow: NSWindowController {
    private var task: Task<Void,Never>?
    var isInstalling: Bool { task != nil }
    private let status = NSTextField(wrappingLabelWithString: "")
    private let media = NSTextField(labelWithString: "")
    private let office = NSTextField(labelWithString: "")
    private let install = ActionButton(title:"",target:nil,action:nil)
    private let cancel = NSButton(title:"",target:nil,action:nil)
    private let spinner = NSProgressIndicator()
    var onInstalled: (() -> Void)?
    var ready: Bool { Catalog.ffmpeg != nil && Catalog.executable("ffprobe") != nil && Catalog.office != nil }
    init() {
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:550,height:360),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title = L.t("Движки CitrusDrop","CitrusDrop engines"); window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(calibratedRed:0.055,green:0.071,blue:0.094,alpha:1)
        super.init(window:window)
        window.center()
        let root = window.contentView!
        func add(_ view:NSView,_ x:CGFloat,_ y:CGFloat,_ width:CGFloat,_ height:CGFloat) { view.frame = NSRect(x:x,y:y,width:width,height:height); root.addSubview(view) }
        let title = NSTextField(labelWithString:L.t("Все движки. Один раз.","Your engines. Set up once.")); title.font = .systemFont(ofSize:23,weight:.semibold); add(title,28,292,490,35)
        let explanation = NSTextField(wrappingLabelWithString:L.t("Бесплатные FFmpeg и LibreOffice обеспечивают видео, аудио и офисные форматы. Файлы обрабатываются на Mac; для первоначальной загрузки нужен интернет.","Free FFmpeg and LibreOffice enable video, audio and office formats. Files are processed on your Mac; initial downloads need internet.")); explanation.font = .systemFont(ofSize:12); explanation.textColor = .secondaryLabelColor; add(explanation,28,224,494,62)
        media.font = .systemFont(ofSize:14,weight:.medium); office.font = media.font
        add(media,28,185,494,25); add(office,28,150,494,25)
        spinner.style = .spinning; spinner.isDisplayedWhenStopped = false; add(spinner,28,98,18,18)
        status.font = .systemFont(ofSize:12); add(status,58,82,464,48)
        install.target = self; install.action = #selector(start); install.isBordered = false; install.primary = true; add(install,28,28,358,36)
        cancel.title = L.t("Закрыть","Close"); cancel.target = self; cancel.action = #selector(stopOrClose); cancel.bezelStyle = .rounded; add(cancel,398,28,124,36)
        refresh()
    }
    required init?(coder:NSCoder) { fatalError() }
    func present() { refresh(); NSApp.activate(ignoringOtherApps:true); showWindow(nil) }
    private func refresh() {
        let hasMedia = Catalog.ffmpeg != nil && Catalog.executable("ffprobe") != nil
        media.stringValue = L.t("Видео и аудио · ","Video & audio · ") + (hasMedia ? L.t("готово","ready") : L.t("нужна установка","setup needed"))
        office.stringValue = L.t("Документы, таблицы, презентации · ","Documents, spreadsheets, slides · ") + (Catalog.office != nil ? L.t("готово","ready") : L.t("нужна установка","setup needed"))
        install.title = ready ? L.t("Все движки подключены","All engines are ready") : L.t("Установить бесплатные движки","Install free engines")
        install.isEnabled = !ready && task == nil
        if task == nil { status.stringValue = ready ? L.t("Можно конвертировать. Подписки и API-ключи не нужны.","Ready to convert. No subscription or API keys.") : L.t("До 380 МБ загрузки, около 1 ГБ на диске. Проверяются контрольные суммы и подписи издателей.","Up to 380 MB download, about 1 GB installed. Downloads and publisher signatures are verified.") }
    }
    @objc private func start() {
        guard task == nil else { return }
        install.isEnabled = false; spinner.startAnimation(nil); cancel.title = L.t("Отмена","Cancel")
        task = Task { [weak self] in
            guard let self else { return }
            let progress: (String)->Void = { [weak self] text in DispatchQueue.main.async { self?.status.stringValue = text } }
            do {
                if Catalog.ffmpeg == nil || Catalog.executable("ffprobe") == nil { try await EngineInstaller.installMedia(progress:progress) }
                if Catalog.office == nil { try await EngineInstaller.installOffice(progress:progress) }
                self.task = nil; self.spinner.stopAnimation(nil); self.cancel.title = L.t("Закрыть","Close")
                self.refresh(); self.onInstalled?()
            } catch {
                self.task = nil; self.spinner.stopAnimation(nil); self.cancel.title = L.t("Закрыть","Close"); self.refresh()
                self.status.stringValue = L.t("Установка не завершена: ","Setup could not finish: ") + error.localizedDescription
            }
        }
    }
    @objc private func stopOrClose() { if let task { task.cancel(); status.stringValue = L.t("Отменяем установку…","Cancelling setup…") } else { close() } }
}
