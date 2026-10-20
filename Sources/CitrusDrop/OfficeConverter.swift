import AppKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers

enum OfficeConverter {
    // EPUB is an export format. LibreOffice cannot import arbitrary EPUB books.
    static func formats(for source: URL) -> [String] {
        let ext = source.pathExtension.lowercased()
        let office = Catalog.office != nil
        switch ext {
        case "txt", "md":
            return ["txt", "md", "html", "pdf"] + (office ? ["doc", "docx", "odt", "rtf", "epub", "png", "jpg"] : [])
        case "doc", "docx", "odt", "rtf", "html", "htm":
            return office ? ["doc", "docx", "odt", "rtf", "txt", "html", "pdf", "epub", "png", "jpg"] : ["txt", "html", "rtf", "docx", "odt"]
        case "xlsx", "xls", "ods", "csv", "tsv":
            return office ? ["xlsx", "xls", "ods", "csv", "tsv", "pdf", "png", "jpg"] : []
        case "ppt", "pptx", "odp":
            return office ? ["pptx", "ppt", "odp", "pdf", "png", "jpg"] : []
        default: return []
        }
    }

    static func convert(source: URL, output: URL, run: (URL, [String]) throws -> Void, checkCancellation: () throws -> Void = {}) throws {
        try checkCancellation()
        let fm = FileManager.default
        let input = source.pathExtension.lowercased(), ext = output.pathExtension.lowercased()
        guard formats(for: source).contains(ext) else {
            throw DropError(L.t("Эта пара форматов не поддерживается. EPUB доступен только для экспорта; Pages и Keynote сначала экспортируйте в DOCX/PPTX.", "This conversion is not supported. EPUB is export-only; export Pages and Keynote to DOCX/PPTX first."))
        }
        guard !fm.fileExists(atPath: output.path) else { throw DropError(L.t("Файл результата уже существует.", "The output already exists.")) }
        // Keep plain-text exports independent of a heavyweight Office installation.
        if ["txt", "md"].contains(input), ["txt", "md", "html", "pdf"].contains(ext) {
            let text = try String(contentsOf: source, encoding: .utf8)
            if ext == "pdf" { try TextPDF.write(text, to: output) }
            else if ext == "html" {
                let escaped = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
                try ("<!doctype html><meta charset=\"utf-8\"><pre>" + escaped + "</pre>").write(to: output, atomically: true, encoding: .utf8)
            } else { try text.write(to: output, atomically: true, encoding: .utf8) }
            return
        }
        if ["html","htm"].contains(input) {
            let html = String(decoding:try Data(contentsOf:source),as:UTF8.self)
            let remote = try NSRegularExpression(pattern:#"(?is)(?:\b(?:src|srcset|poster|data)\s*=\s*["']?\s*(?:https?:|ftp:|//)|url\(\s*["']?\s*(?:https?:|ftp:|//)|<(?:link|iframe|embed|object)\b[^>]*(?:https?:|ftp:|//))"#)
            if remote.firstMatch(in:html,range:NSRange(html.startIndex...,in:html)) != nil { throw DropError(L.t("HTML содержит внешние ресурсы. Сохраните страницу с локальными картинками перед конвертацией.","The HTML references remote resources. Save the page with local images before converting.")) }
        }
        guard let office = Catalog.office else {
            try run(URL(fileURLWithPath: "/usr/bin/textutil"), ["-convert", ext, "-encoding", "UTF-8", "-output", output.path, source.path])
            try validate(output)
            return
        }
        let workspace = fm.temporaryDirectory.appendingPathComponent("citrus-office-" + UUID().uuidString, isDirectory: true)
        let exports = workspace.appendingPathComponent("exports", isDirectory: true)
        try fm.createDirectory(at: exports, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workspace) }
        let profile = workspace.appendingPathComponent("profile", isDirectory: true)
        // A fresh profile avoids an already-running LibreOffice stealing this job.
        // Disable macros and remote document links in the conversion profile.
        try fm.createDirectory(at: profile.appendingPathComponent("user"), withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <oor:items xmlns:oor="http://openoffice.org/2001/registry"><item oor:path="/org.openoffice.Office.Common/Security/Scripting"><prop oor:name="DisableMacrosExecution" oor:op="fuse"><value>true</value></prop><prop oor:name="DisableActiveContent" oor:op="fuse"><value>true</value></prop></item><item oor:path="/org.openoffice.Office.Writer/Content/Update"><prop oor:name="Link" oor:op="fuse"><value>2</value></prop></item><item oor:path="/org.openoffice.Office.Calc/Content/Update"><prop oor:name="Link" oor:op="fuse"><value>2</value></prop></item></oor:items>
        """.write(to: profile.appendingPathComponent("user/registrymodifications.xcu"), atomically: true, encoding: .utf8)
        let rendered = ["png", "jpg"].contains(ext)
        let target = rendered ? "pdf" : ext
        let family = Family.of(source)
        let filter: String
        switch family {
        case .sheet:
            switch target {
            case "xlsx": filter = "xlsx:Calc MS Excel 2007 XML"
            case "xls": filter = "xls:MS Excel 97"
            case "ods": filter = "ods:calc8"
            case "csv", "tsv":
                // Token 12=0 exports the first sheet; CSV/TSV cannot hold a workbook.
                filter = "csv:Text - txt - csv (StarCalc):\(target == "tsv" ? 9 : 44),34,76,1,,0,false,true,true,false,false,0,false,false,false"
            default: filter = "pdf:calc_pdf_Export"
            }
        case .slides:
            switch target {
            case "pptx": filter = "pptx:Impress MS PowerPoint 2007 XML"
            case "ppt": filter = "ppt:MS PowerPoint 97"
            case "odp": filter = "odp:impress8"
            default: filter = "pdf:impress_pdf_Export"
            }
        default:
            let filters = ["doc": "MS Word 97", "docx": "Office Open XML Text", "odt": "writer8", "rtf": "Rich Text Format", "txt": "Text (encoded):UTF8", "html": "HTML (StarWriter):EmbedImages", "pdf": "writer_pdf_Export", "epub": "EPUB"]
            guard let name = filters[target] else { throw DropError(L.t("Неподдерживаемый формат документа.", "Unsupported document format.")) }
            filter = target + ":" + name
        }
        var args = ["-env:UserInstallation=" + profile.absoluteString, "--headless", "--nologo", "--nodefault", "--norestore"]
        if input == "csv" || input == "tsv" {
            // Force Calc: relying on extension detection imports TSV as Writer text.
            // UTF-8, stable en-US numeric parsing, quoted values stay text, no formulas.
            let delimiter = input == "tsv" ? 9 : try csvDelimiter(source)
            args.append("--infilter=Text - txt - csv (StarCalc):\(delimiter),34,76,1,,1033,true,false,false,false,false,0,false,false,false")
        } else if input == "html" || input == "htm" { args.append("--infilter=HTML (StarWriter)") }
        else if input == "txt" || input == "md" { args.append("--infilter=Text (encoded):UTF8,LF,Liberation Mono,en-US") }
        args += ["--convert-to", filter, "--outdir", exports.path, source.path]
        try run(office, args)
        let producedExtension = target == "tsv" ? "csv" : target
        let produced = exports.appendingPathComponent(source.deletingPathExtension().lastPathComponent).appendingPathExtension(producedExtension)
        try validate(produced)
        if rendered { try rasterize(produced, to: output, format: ext,checkCancellation:checkCancellation) }
        else {
            if target == "html" { try embedImages(in: produced, root: exports) }
            try fm.moveItem(at: produced, to: output)
        }
    }

    private static func validate(_ url: URL) throws {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
            throw DropError(L.t("LibreOffice не создал результат. Проверьте, что файл не повреждён и не защищён паролем.", "LibreOffice did not produce an output. Check that the file is valid and is not password protected."))
        }
        if url.pathExtension == "pdf", PDFDocument(url: url)?.pageCount ?? 0 == 0 { throw DropError(L.t("Не удалось создать читаемый PDF.", "Could not create a readable PDF.")) }
    }

    private static func csvDelimiter(_ source: URL) throws -> Int {
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        let sample = String(decoding: try handle.read(upToCount: 65536) ?? Data(), as: UTF8.self)
        let first = sample.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let declaration = first.trimmingCharacters(in: CharacterSet(charactersIn: "\"\u{FEFF}"))
        if declaration.hasPrefix("sep="), let value = declaration.last?.asciiValue { return Int(value) }
        var counts = [Character: Int](), quoted = false
        for character in first {
            if character == "\"" { quoted.toggle() }
            else if !quoted, [",", ";", "\t"].contains(character) { counts[character, default: 0] += 1 }
        }
        return Int((counts.max { $0.value < $1.value }?.key ?? ",").asciiValue ?? 44)
    }

    private static func embedImages(in html: URL, root: URL) throws {
        var content = try String(contentsOf: html, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"(?i)\bsrc\s*=\s*"([^"]+)""#)
        let ns = content as NSString
        for match in regex.matches(in: content, range: NSRange(location: 0, length: ns.length)).reversed() {
            let reference = ns.substring(with: match.range(at: 1))
            guard !reference.contains(":"), !reference.hasPrefix("//"), let decoded = reference.removingPercentEncoding else { continue }
            let asset = root.appendingPathComponent(decoded).standardizedFileURL
            guard asset.path.hasPrefix(root.standardizedFileURL.path + "/"), FileManager.default.fileExists(atPath: asset.path) else { continue }
            let mime = UTType(filenameExtension: asset.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let data = try Data(contentsOf: asset)
            let range = Range(match.range(at: 1), in: content)!
            content.replaceSubrange(range, with: "data:\(mime);base64," + data.base64EncodedString())
        }
        try content.write(to: html, atomically: true, encoding: .utf8)
    }

    private static func rasterize(_ source: URL, to output: URL, format: String,checkCancellation: () throws -> Void) throws {
        guard let document = PDFDocument(url: source), !document.isLocked, document.pageCount > 0 else { throw DropError(L.t("Не удалось прочитать PDF документа.", "Cannot read the document PDF.")) }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        do {
            for index in 0..<document.pageCount {
                try checkCancellation()
                guard let page = document.page(at: index) else { throw DropError(L.t("Не удалось прочитать страницу.", "Cannot read a page.")) }
                let box = page.bounds(for: .mediaBox)
                guard box.width > 0, box.height > 0, box.width.isFinite, box.height.isFinite else { throw DropError(L.t("Некорректный размер страницы.", "Invalid page size.")) }
                let scale = min(2, 4096 / max(box.width, box.height))
                let width = max(1, Int(ceil(box.width * scale))), height = max(1, Int(ceil(box.height * scale)))
                guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw DropError(L.t("Недостаточно памяти для страницы.", "Not enough memory for a page.")) }
                context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                context.scaleBy(x: scale, y: scale); context.translateBy(x: -box.minX, y: -box.minY)
                page.draw(with: .mediaBox, to: context)
                let destination = output.appendingPathComponent(String(format: "page-%04d.%@", index + 1, format))
                guard let image = context.makeImage(), let type = UTType(filenameExtension: format), let encoder = CGImageDestinationCreateWithURL(destination as CFURL, type.identifier as CFString, 1, nil) else { throw DropError(L.t("Не удалось сохранить страницу.", "Cannot save a page.")) }
                CGImageDestinationAddImage(encoder, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
                guard CGImageDestinationFinalize(encoder) else { throw DropError(L.t("Не удалось записать страницу.", "Cannot write a page.")) }
            }
        } catch { try? FileManager.default.removeItem(at: output); throw error }
    }
}
