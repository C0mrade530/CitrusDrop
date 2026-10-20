import AppKit
import ImageIO
import UniformTypeIdentifiers
import Quartz

enum ImageCompression {
    private static func bitmap(_ source:URL) throws -> CGImage {
        guard let input = CGImageSourceCreateWithURL(source as CFURL,nil), CGImageSourceGetCount(input) == 1,
              let image = CGImageSourceCreateThumbnailAtIndex(input,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:1920] as CFDictionary) else {
            throw DropError(L.t("Сжатие доступно для обычных изображений. Анимации не изменены.","Compression requires a still image. Animated files are unchanged."))
        }
        return image
    }
    static func preferredExtension(_ source:URL) throws -> String {
        let image = try bitmap(source)
        let info = image.alphaInfo
        guard [.first,.last,.premultipliedFirst,.premultipliedLast,.alphaOnly].contains(info) else { return "jpg" }
        let count = image.width * image.height
        var pixels = [UInt8](repeating:0,count:count*4)
        let opaque = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data:bytes.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
            for index in stride(from:3,to:count*4,by:4) { if bytes[index] != 255 { return false } }
            return true
        }
        return opaque ? "jpg" : "png"
    }
    static func compress(_ source:URL,to output:URL) throws {
        let image = try bitmap(source)
        let originalSize = try source.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        let format = output.pathExtension
        guard let type = UTType(filenameExtension:format) else { throw DropError(L.t("Неподдерживаемый формат.","Unsupported format.")) }
        for quality in format == "jpg" ? [0.7,0.5,0.35] : [1.0] {
            guard let writer = CGImageDestinationCreateWithURL(output as CFURL,type.identifier as CFString,1,nil) else { throw DropError(L.t("Не удалось создать изображение.","Cannot create image.")) }
            CGImageDestinationAddImage(writer,image,[kCGImageDestinationLossyCompressionQuality:quality] as CFDictionary)
            guard CGImageDestinationFinalize(writer) else { throw DropError(L.t("Не удалось записать изображение.","Cannot write image.")) }
            if (try output.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) < originalSize { return }
        }
        throw DropError(L.t("Изображение уже хорошо сжато. Уменьшить его размер без дополнительной потери качества не удалось; оригинал сохранён.","The image is already compact. Its size could not be reduced at this quality; the original is preserved."))
    }
}

enum PDFCompression {
    static func compress(_ source:URL,to output:URL) throws {
        guard let document = PDFDocument(url:source), !document.isLocked, document.pageCount > 0 else { throw DropError(L.t("PDF пуст, повреждён или защищён.","The PDF is empty, damaged or locked.")) }
        guard let filter = QuartzFilter(url:URL(fileURLWithPath:"/System/Library/Filters/Reduce File Size.qfilter")) else { throw DropError(L.t("Системный фильтр сжатия PDF недоступен.","The system PDF compression filter is unavailable.")) }
        guard document.write(to:output,withOptions:[PDFDocumentWriteOption(rawValue:"QuartzFilter"):filter]), let result = PDFDocument(url:output), result.pageCount == document.pageCount else { throw DropError(L.t("Не удалось сжать PDF.","Cannot compress PDF.")) }
        if let text = document.string, !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, (result.string ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { throw DropError(L.t("Сжатие не должно удалять текстовый слой. Оригинал сохранён.","Compression must not discard the text layer. The original is preserved.")) }
        guard (try output.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) < (try source.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) else { throw DropError(L.t("PDF уже хорошо сжат. Меньший результат не получен; оригинал сохранён.","The PDF is already compact. No smaller output was produced; the original is preserved.")) }
    }
}
