import Foundation
import CoreText
import CoreGraphics

enum Subtitle {
    static func convert(_ input: String, from: String, to: String) throws -> String {
        let normalized = input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\u{FEFF}", with: "")
        let regex = try NSRegularExpression(pattern: #"(?m)^(?:(\d{2,}):)?(\d{2}):(\d{2})[.,](\d{3})\s+-->\s+(?:(\d{2,}):)?(\d{2}):(\d{2})[.,](\d{3})([^\n]*)\n"#)
        let ns = normalized as NSString
        let matches = regex.matches(in: normalized, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { throw DropError("Нет корректных таймкодов SRT/VTT.") }
        var cues: [(String,String,String)] = []
        for (index, match) in matches.enumerated() {
            func group(_ i: Int) -> String { match.range(at: i).location == NSNotFound ? "00" : ns.substring(with: match.range(at: i)) }
            let start = NSMaxRange(match.range)
            let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            var lines = ns.substring(with: NSRange(location: start, length: end - start)).components(separatedBy: "\n")
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
            // Cue identifiers precede the next timestamp; a blank line separates them from body text.
            if let blank = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) { lines = Array(lines[..<blank]) }
            let body = lines.joined(separator: "\n")
            cues.append(("\(group(1)):\(group(2)):\(group(3)).\(group(4))", "\(group(5)):\(group(6)):\(group(7)).\(group(8))", body))
        }
        if to == "txt" { return cues.map(\.2).joined(separator: "\n\n") + "\n" }
        return (to == "vtt" ? "WEBVTT\n\n" : "") + cues.enumerated().map { index, cue in
            let start = to == "srt" ? cue.0.replacingOccurrences(of:".",with:",") : cue.0
            let end = to == "srt" ? cue.1.replacingOccurrences(of:".",with:",") : cue.1
            return (to == "srt" ? "\(index + 1)\n" : "") + start + " --> " + end + "\n" + cue.2
        }.joined(separator: "\n\n") + "\n"
    }
}

enum TextPDF {
    static func write(_ text: String, to url: URL) throws {
        let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 12, nil)])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var box = CGRect(x: 0,y: 0,width: 595,height: 842)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw DropError("Не удалось создать PDF.") }
        var offset = 0
        repeat {
            context.beginPDFPage(nil)
            let path = CGPath(rect: box.insetBy(dx: 48, dy: 48), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()
            if visible.length == 0 { break }
            offset += visible.length
        } while offset < attributed.length
        context.closePDF()
    }
}
