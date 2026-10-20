import AppKit
import ImageIO

struct DropError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum Family: String {
    case image, video, audio, pdf, document, sheet, slides, subtitle, archive, folder, other
    static func of(_ url: URL) -> Family {
        var directory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue { return .folder }
        let ext = url.pathExtension.lowercased()
        let groups: [(Family, [String])] = [
            (.image, ["jpg","jpeg","png","heic","heif","tiff","tif","bmp","gif","webp","avif","ico"]),
            (.video, ["mp4","mov","mkv","webm","avi","wmv","m4v","mpeg","mpg"]),
            (.audio, ["mp3","m4a","wav","flac","ogg","opus","aiff","aif","wma","aac"]),
            (.pdf, ["pdf"]), (.document, ["doc","docx","odt","rtf","rtfd","txt","html","htm","md","epub","pages"]),
            (.sheet, ["xlsx","xls","ods","csv","tsv"]), (.slides, ["ppt","pptx","odp","key"]),
            (.subtitle, ["srt","vtt"]), (.archive, ["zip","tar","gz","tgz","bz2","xz","rar","7z"])
        ]
        return groups.first(where: { $0.1.contains(ext) })?.0 ?? .other
    }
}

struct Operation: Equatable {
    let id: String
    let title: String
    let symbol: String
    init(_ id: String, _ title: String, _ symbol: String = "arrow.triangle.2.circlepath") {
        self.id = id; self.title = title; self.symbol = symbol
    }
}

enum Catalog {
    static var ffmpeg: URL? { executable("ffmpeg") }
    static var office: URL? { executable("soffice") }
    static func executable(_ name: String) -> URL? {
        let managed = [EngineInstaller.root.appendingPathComponent("ffmpeg-9.0.2").path, EngineInstaller.root.appendingPathComponent("LibreOffice-26.8.1.app/Contents/MacOS").path, Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers").path]
        let roots = managed + (ProcessInfo.processInfo.environment["CITRUSDROP_MANAGED_ONLY"] == "1" ? [] : ["/opt/homebrew/bin", "/usr/local/bin", "/Applications/LibreOffice.app/Contents/MacOS"])
        return roots.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    static var imageOutputs: [String] {
        let types = CGImageDestinationCopyTypeIdentifiers() as! [String]
        return [("png","public.png"),("jpg","public.jpeg"),("heic","public.heic"),("tiff","public.tiff"),("bmp","com.microsoft.bmp"),("gif","com.compuserve.gif")].filter { types.contains($0.1) }.map(\.0) + (ffmpeg == nil ? [] : ["webp","avif"])
    }
    static func formats(_ url: URL) -> [String] {
        let result: [String]
        switch Family.of(url) {
        case .image: result = imageOutputs + ["pdf"]
        case .audio: result = MediaConverter.availableFormats(forVideo:false)
        case .video: result = MediaConverter.availableFormats(forVideo:true)
        case .pdf: result = ["png","jpg","txt"]
        case .document, .sheet, .slides: result = OfficeConverter.formats(for:url)
        case .subtitle: result = ["srt","vtt","txt"]
        case .folder: result = ["zip","tar","tgz"]
        case .archive: result = ["zip","tar","tgz"]
        case .other: result = ["zip"]
        }
        return Array(NSOrderedSet(array: result)) as! [String]
    }
    static func operations(_ urls: [URL], mode: Int) -> [Operation] {
        guard let first = urls.first else { return [] }
        if mode == 2 {
            return [Operation("reveal","В Finder","folder"), Operation("copyPath","Путь","link"), Operation("copy","Копировать","doc.on.doc"), Operation("duplicate","Дубликат","plus.square.on.square"), Operation("move","Переместить","folder.badge.arrow.forward"), Operation("airdrop","AirDrop","airplayaudio"), Operation("float","Поверх окон","macwindow"), Operation("terminal","Терминал","terminal")]
        }
        if mode == 1 {
            let families = Set(urls.map { Family.of($0).rawValue })
            if families == [Family.image.rawValue] { return [Operation("resize","Размер","arrow.up.left.and.arrow.down.right"),Operation("crop","Обрезать","crop"),Operation("flip","Отразить","arrow.left.and.right.righttriangle.left.righttriangle.right"),Operation("grayscale","Чёрно-белое","circle.lefthalf.filled"),Operation("rotate","Повернуть","rotate.right"),Operation("compress","Сжать","arrow.down.right.and.arrow.up.left"),Operation("strip","Без метаданных","eye.slash"),Operation("mergePDF","Общий PDF","doc.richtext")] }
            if families == [Family.pdf.rawValue] { return [Operation("compress","Сжать","arrow.down.right.and.arrow.up.left"),Operation("mergePDF","Объединить","doc.on.doc"),Operation("splitPDF","Разделить","scissors"),Operation("pdfText","Извлечь текст","text.alignleft")] }
            if families.isSubset(of: [Family.audio.rawValue, Family.video.rawValue]), ffmpeg != nil { return [Operation("compress","Сжать","arrow.down.right.and.arrow.up.left"),Operation("trim","Обрезать","scissors"),Operation("strip","Без метаданных","eye.slash")] }
            if families == [Family.archive.rawValue] { return [Operation("extract","Распаковать","archivebox")] }
            return [Operation("zip","В ZIP","archivebox")]
        }
        let formats = formats(first).filter { format in urls.allSatisfy { self.formats($0).contains(format) } }
        return formats.map { Operation("convert:" + $0, $0.uppercased()) }
    }
}

func uniqueURL(in directory: URL, stem: String, ext: String) -> URL {
    var index = 0
    while true {
        let suffix = index == 0 ? "" : " (\(index))"
        let url = directory.appendingPathComponent(stem + suffix).appendingPathExtension(ext)
        if !FileManager.default.fileExists(atPath: url.path) { return url }
        index += 1
    }
}
