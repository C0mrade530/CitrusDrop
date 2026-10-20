import AppKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers

struct ConversionOptions {
    var maxDimension = 1920
    var quality = 0.8
    var cropWidth = 1080
    var cropHeight = 1080
    var trimStart = 0.0
    var trimDuration = 10.0
}

final class Converter {
    private let fm = FileManager.default
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?
    func cancel() {
        lock.lock(); cancelled = true; let active = process; lock.unlock()
        if let active, active.isRunning { active.terminate() }
    }
    private func checkCancellation() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw DropError(L.t("Операция отменена. Готовые результаты сохранены.","Cancelled. Completed results were preserved.")) }
    }
    // Sequential worker owns output naming; final moves fail rather than overwrite.
    func perform(_ operation: Operation, urls: [URL], options: ConversionOptions = .init(), progress: (String) -> Void) throws -> [URL] {
        try checkCancellation()
        guard !urls.isEmpty else { throw DropError("Выберите хотя бы один файл.") }
        for url in urls {
            guard url.isFileURL, fm.fileExists(atPath: url.path) else { throw DropError("Файл недоступен: \(url.lastPathComponent)") }
        }
        let supported: Bool
        if operation.id == "zip" { supported = true }
        else if operation.id == "mergePDF" { supported = urls.allSatisfy { [Family.image,.pdf].contains(Family.of($0)) } }
        else if operation.id.hasPrefix("convert:") {
            let target = String(operation.id.dropFirst(8))
            supported = urls.allSatisfy { Catalog.formats($0).contains(target) }
        } else { supported = urls.allSatisfy { source in Catalog.operations([source],mode:1).contains { $0.id == operation.id } } }
        guard supported else { throw DropError(L.t("Операция недоступна для выбранного типа файла. Проверьте формат и подключённые движки.","This operation is unavailable for the selected file type. Check the format and installed engines.")) }
        if operation.id == "mergePDF" { return [try mergePDF(urls)] }
        if operation.id == "zip" { return [try archive(urls, format: "zip")] }
        var outputs: [URL] = []
        for (index, source) in urls.enumerated() {
            try checkCancellation()
            progress("\(index + 1)/\(urls.count) · \(source.lastPathComponent)")
            do {
                if operation.id == "extract" { outputs.append(try extract(source)); continue }
                if operation.id == "splitPDF" { outputs += try splitPDF(source); continue }
                var format = operation.id.hasPrefix("convert:") ? String(operation.id.dropFirst(8)) : (operation.id == "pdfText" ? "txt" : source.pathExtension.lowercased())
                if ["compress","trim"].contains(operation.id), Family.of(source) == .video { format = source.pathExtension.lowercased() == "mov" && operation.id == "trim" ? "mov" : "mp4" }
                if operation.id == "compress", Family.of(source) == .image { format = try ImageCompression.preferredExtension(source) }
                if operation.id == "compress", Family.of(source) == .audio, ["wav","aiff","aif","flac","wma"].contains(format) { format = "m4a" }
                if operation.id == "trim", Family.of(source) == .audio, format == "wma" { format = "m4a" }
                if ["zip","tar","tgz"].contains(format), operation.id.hasPrefix("convert:") {
                    outputs.append(try archive([source], format: format)); continue
                }
                let stem = source.deletingPathExtension().lastPathComponent + (operation.id.hasPrefix("convert:") ? "" : "-" + operation.id)
                let rasterPDF = [Family.pdf,.document,.sheet,.slides].contains(Family.of(source)) && ["png","jpg"].contains(format)
                let destination = uniqueURL(in: source.deletingLastPathComponent(), stem: stem + (rasterPDF ? "-" + format + "-pages" : ""), ext: rasterPDF ? "" : format)
                let staging = source.deletingLastPathComponent().appendingPathComponent(".citrus-" + UUID().uuidString, isDirectory: true)
                try fm.createDirectory(at: staging, withIntermediateDirectories: false)
                defer { try? fm.removeItem(at: staging) }
                let temporary = staging.appendingPathComponent("output").appendingPathExtension(format)
                switch Family.of(source) {
                case .image:
                    if operation.id == "compress" { try ImageCompression.compress(source,to:temporary) }
                    else { try image(source, to: temporary, operation: operation.id, options: options) }
                case .audio, .video: try media(source, to: temporary, operation: operation.id, options: options)
                case .pdf:
                    if operation.id == "compress" { try PDFCompression.compress(source,to:temporary) }
                    else if format == "txt" { try pdfText(source).write(to: temporary, atomically: true, encoding: .utf8) }
                    else { try pdfImages(source, to: temporary, format: format) }
                case .subtitle:
                    let text = try String(contentsOf: source, encoding: .utf8)
                    try Subtitle.convert(text, from: source.pathExtension.lowercased(), to: format).write(to: temporary, atomically: true, encoding: .utf8)
                case .document, .sheet, .slides: try document(source, to: temporary)
                default: throw DropError("Этот тип файла пока не поддерживается.")
                }
                guard fm.fileExists(atPath: temporary.path) else { throw DropError("Конвертер не создал результат.") }
                try checkCancellation()
                try fm.moveItem(at: temporary, to: destination)
                outputs.append(destination)
            } catch {
                let completed = outputs.isEmpty ? "" : " Уже сохранено: \(outputs.count).\n" + outputs.map(\.path).joined(separator:"\n")
                throw DropError("\(source.lastPathComponent): \(error.localizedDescription)\(completed)")
            }
        }
        return outputs
    }

    private func image(_ source: URL, to output: URL, operation: String, options: ConversionOptions) throws {
        guard let input = CGImageSourceCreateWithURL(source as CFURL, nil) else { throw DropError("Не удалось прочитать изображение.") }
        let count = CGImageSourceGetCount(input)
        guard count > 0 else { throw DropError("Пустое изображение.") }
        if count > 1, ["compress","strip","rotate","resize","crop","flip","grayscale"].contains(operation) {
            throw DropError("Для анимированного изображения выберите конвертацию; инструменты не должны удалять кадры.")
        }
        let format = output.pathExtension.lowercased()
        if ["webp","avif"].contains(format) {
            guard let tool = Catalog.ffmpeg else { throw DropError("Установите FFmpeg для этого формата.") }
            try run(tool, ["-nostdin","-v","error","-i",source.path,"-frames:v","1",output.path]); return
        }
        let maxSize = operation == "resize" ? options.maxDimension : 32000
        let settings: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxSize]
        guard var bitmap = CGImageSourceCreateThumbnailAtIndex(input, 0, settings as CFDictionary) else { throw DropError("Не удалось декодировать изображение.") }
        if operation == "crop" {
            let width = min(bitmap.width, options.cropWidth), height = min(bitmap.height, options.cropHeight)
            guard let cropped = bitmap.cropping(to:CGRect(x:(bitmap.width-width)/2,y:(bitmap.height-height)/2,width:width,height:height)) else { throw DropError(L.t("Не удалось обрезать изображение.","Cannot crop image.")) }; bitmap = cropped
        }
        if operation == "flip" || operation == "grayscale" {
            let gray = operation == "grayscale"
            let space = gray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
            let alpha = gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
            guard let context = CGContext(data:nil,width:bitmap.width,height:bitmap.height,bitsPerComponent:8,bytesPerRow:0,space:space,bitmapInfo:alpha) else { throw DropError(L.t("Не хватает памяти.","Not enough memory.")) }
            if !gray { context.translateBy(x:CGFloat(bitmap.width),y:0); context.scaleBy(x:-1,y:1) }
            context.draw(bitmap,in:CGRect(x:0,y:0,width:bitmap.width,height:bitmap.height))
            guard let transformed = context.makeImage() else { throw DropError(L.t("Не удалось обработать изображение.","Cannot process image.")) }; bitmap = transformed
        }
        if operation == "rotate" {
            guard let context = CGContext(data: nil, width: bitmap.height, height: bitmap.width, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw DropError("Не хватает памяти для поворота.") }
            context.translateBy(x: CGFloat(bitmap.height), y: 0); context.rotate(by: .pi / 2)
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
            guard let rotated = context.makeImage() else { throw DropError("Не удалось повернуть изображение.") }; bitmap = rotated
        }
        if format == "pdf" {
            var box = CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height)
            guard let context = CGContext(output as CFURL, mediaBox: &box, nil) else { throw DropError("Не удалось создать PDF.") }
            context.beginPDFPage(nil); context.draw(bitmap, in: box); context.endPDFPage(); context.closePDF(); return
        }
        guard let type = UTType(filenameExtension: format), let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else { throw DropError("Формат \(format) недоступен в этой версии macOS.") }
        // Re-encoding discards input metadata. An animated input exports its first frame.
        CGImageDestinationAddImage(destination, bitmap, [kCGImageDestinationLossyCompressionQuality: operation == "compress" ? 0.55 : options.quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw DropError("Не удалось записать изображение.") }
    }

    private func media(_ source: URL, to output: URL, operation: String, options: ConversionOptions) throws {
        try MediaConverter.convert(source:source,output:output,operation:operation,options:options,run:run)
    }

    private func pdfText(_ source: URL) throws -> String {
        guard let pdf = PDFDocument(url: source) else { throw DropError("Повреждённый или закрытый PDF.") }
        guard !pdf.isLocked else { throw DropError("Сначала снимите пароль с PDF.") }
        guard let text = pdf.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DropError("В PDF нет текстового слоя. OCR в этой версии не включён.") }
        return text
    }
    private func pdfImages(_ source: URL, to output: URL, format: String) throws {
        guard let pdf = PDFDocument(url: source), !pdf.isLocked, pdf.pageCount > 0 else { throw DropError("PDF пуст или защищён.") }
        try fm.createDirectory(at: output, withIntermediateDirectories: false)
        for index in 0..<pdf.pageCount {
            try checkCancellation()
            guard let page = pdf.page(at: index) else { throw DropError("Не удалось прочитать страницу PDF.") }
            let bounds = page.bounds(for: .mediaBox)
            let scale = min(300.0 / 72, 6000 / max(bounds.width, bounds.height))
            let width = max(1, Int(bounds.width * scale)), height = max(1, Int(bounds.height * scale))
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw DropError("Недостаточно памяти для PDF.") }
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0,y: 0,width: width,height: height)); context.scaleBy(x: scale, y: scale); context.translateBy(x: -bounds.minX, y: -bounds.minY); page.draw(with: .mediaBox, to: context)
            let url = output.appendingPathComponent(String(format: "page-%04d.%@", index + 1, format))
            guard let image = context.makeImage(), let type = UTType(filenameExtension: format), let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { throw DropError("Не удалось сохранить страницу.") }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw DropError("Ошибка сохранения страницы PDF.") }
        }
    }
    private func mergePDF(_ sources: [URL]) throws -> URL {
        let output = PDFDocument()
        for source in sources {
            try checkCancellation()
            if Family.of(source) == .pdf {
                guard let pdf = PDFDocument(url: source), !pdf.isLocked else { throw DropError("PDF недоступен: \(source.lastPathComponent)") }
                for index in 0..<pdf.pageCount {
                    try checkCancellation()
                    if let page = pdf.page(at: index) { output.insert(page, at: output.pageCount) }
                }
            } else {
                guard let image = NSImage(contentsOf: source), let page = PDFPage(image: image) else { throw DropError("Не удалось добавить \(source.lastPathComponent)") }
                output.insert(page, at: output.pageCount)
            }
        }
        let url = uniqueURL(in: sources[0].deletingLastPathComponent(), stem: "CitrusDrop-merged", ext: "pdf")
        guard let data = output.dataRepresentation() else { throw DropError("Не удалось создать PDF.") }
        try checkCancellation()
        try data.write(to: url, options: .withoutOverwriting); return url
    }
    private func splitPDF(_ source: URL) throws -> [URL] {
        guard let pdf = PDFDocument(url: source), !pdf.isLocked, pdf.pageCount > 0 else { throw DropError("PDF недоступен.") }
        let output = uniqueURL(in: source.deletingLastPathComponent(), stem: source.deletingPathExtension().lastPathComponent + "-pages", ext: "")
        try fm.createDirectory(at: output, withIntermediateDirectories: false)
        do {
            for index in 0..<pdf.pageCount {
            try checkCancellation()
                let doc = PDFDocument(); guard let page = pdf.page(at: index) else { throw DropError("Ошибка чтения PDF.") }; doc.insert(page, at: 0)
                guard doc.write(to: output.appendingPathComponent(String(format: "page-%04d.pdf",index + 1))) else { throw DropError("Ошибка записи PDF.") }
            }
        } catch { try? fm.removeItem(at: output); throw error }
        return [output]
    }
    private func document(_ source: URL, to output: URL) throws {
        try OfficeConverter.convert(source:source,output:output,run:run,checkCancellation:checkCancellation)
    }
    private func archive(_ sources: [URL], format: String) throws -> URL {
        let directory = sources[0].deletingLastPathComponent()
        let output = uniqueURL(in: directory, stem: sources.count == 1 ? sources[0].deletingPathExtension().lastPathComponent : "CitrusDrop-archive", ext: format)
        let staging = fm.temporaryDirectory.appendingPathComponent("citrus-archive-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let payload = staging.appendingPathComponent("files")
        try fm.createDirectory(at: payload, withIntermediateDirectories: false)
        for source in sources {
            let target = payload.appendingPathComponent(source.lastPathComponent)
            guard !fm.fileExists(atPath: target.path) else { throw DropError("В наборе есть одинаковые имена файлов.") }
            if Family.of(source) == .archive {
                try unpack(source, to: target)
            } else { try fm.copyItem(at: source, to: target) }
        }
        let temporary = staging.appendingPathComponent("archive." + format)
        if format == "zip" { try run(URL(fileURLWithPath:"/usr/bin/ditto"),["-c","-k","--sequesterRsrc",payload.path,temporary.path]) }
        else { try run(URL(fileURLWithPath:"/usr/bin/tar"),[format == "tgz" ? "-czf" : "-cf",temporary.path,"-C",payload.path,"."]) }
        try fm.moveItem(at: temporary, to: output); return output
    }
    private func extract(_ source: URL) throws -> URL {
        let output = uniqueURL(in: source.deletingLastPathComponent(), stem: source.deletingPathExtension().lastPathComponent + "-extracted", ext: "")
        let staging = fm.temporaryDirectory.appendingPathComponent("citrus-extract-" + UUID().uuidString)
        defer { try? fm.removeItem(at: staging) }
        try unpack(source, to: staging)
        try fm.moveItem(at: staging, to: output)
        return output
    }
    private func unpack(_ source: URL, to directory: URL) throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        // macOS bsdtar rejects traversal and writes through directory symlinks by default.
        // Never use -P / --absolute-paths or -U. Fresh private staging prevents overwrite.
        try run(URL(fileURLWithPath:"/usr/bin/tar"),["-xf",source.path,"-C",directory.path,"--no-same-owner","--no-same-permissions","--no-acls","--no-xattrs","--no-mac-metadata","--safe-writes"])
        guard let entries = fm.enumerator(at:directory,includingPropertiesForKeys:[.isSymbolicLinkKey,.isRegularFileKey,.isDirectoryKey]) else { throw DropError(L.t("Не удалось прочитать архив.","Cannot read archive.")) }
        for case let entry as URL in entries {
            try checkCancellation()
            let values = try entry.resourceValues(forKeys:[.isSymbolicLinkKey,.isRegularFileKey,.isDirectoryKey])
            if values.isSymbolicLink == true || (values.isRegularFile != true && values.isDirectory != true) { throw DropError(L.t("Архив содержит ссылки или специальные файлы. Распаковка отменена.","Archive contains links or special files. Extraction cancelled.")) }
        }
    }
    private func run(_ executable: URL, _ arguments: [String]) throws {
        let process = Process()
        if executable.lastPathComponent == "soffice" {
            // Office files may reference remote resources. Keep conversion offline.
            // Embedded Python must not rewrite the vendor's sealed bytecode resources.
            var environment = ProcessInfo.processInfo.environment
            environment["PYTHONDONTWRITEBYTECODE"] = "1"
            process.environment = environment
            process.executableURL = URL(fileURLWithPath:"/usr/bin/sandbox-exec")
            process.arguments = ["-p","(version 1) (allow default) (deny network-outbound (remote ip \"*:*\")) (deny network-inbound (remote ip \"*:*\"))",executable.path] + arguments
        } else { process.executableURL = executable; process.arguments = arguments }
        let log = fm.temporaryDirectory.appendingPathComponent("citrus-log-" + UUID().uuidString)
        fm.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close(); try? fm.removeItem(at: log) }
        process.standardError = handle; process.standardOutput = handle; process.standardInput = FileHandle.nullDevice
        try checkCancellation()
        lock.lock()
        if cancelled { lock.unlock(); try checkCancellation(); return }
        do { try process.run(); self.process = process; lock.unlock() } catch { lock.unlock(); throw error }
        process.waitUntilExit()
        lock.lock(); self.process = nil; lock.unlock()
        try checkCancellation()
        if process.terminationStatus != 0 {
            let message = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            throw DropError("\(executable.lastPathComponent): \(message.suffix(1500))")
        }
    }
}
