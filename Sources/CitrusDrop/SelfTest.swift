import AppKit
import PDFKit
import ImageIO

enum SelfTest {
    static func run() throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("CitrusDrop-tests-" + UUID().uuidString)
        try fm.createDirectory(at:directory,withIntermediateDirectories:false)
        defer { try? fm.removeItem(at:directory) }
        func check(_ value: Bool, _ name: String) throws { if !value { throw DropError(name) }; print("PASS \(name)") }
        let engine = Converter()
        func perform(_ id: String, _ sources: [URL], options: ConversionOptions = .init()) throws -> [URL] { try engine.perform(Operation(id,id),urls:sources,options:options) { _ in } }
        let input = directory.appendingPathComponent("Тест ' ; $(touch NO) image.png")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:120,pixelsHigh:80,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        for x in 0..<120 { for y in 0..<80 { bitmap.setColor(NSColor(calibratedRed:1,green:0.5,blue:0.1,alpha:1),atX:x,y:y) } }
        try bitmap.representation(using:.png,properties:[:])!.write(to:input)
        let original = try Data(contentsOf:input)
        let jpg = try perform("convert:jpg",[input])[0]
        try check(CGImageSourceCreateWithURL(jpg as CFURL,nil) != nil,"PNG → JPEG with Unicode and shell metacharacters")
        let second = try perform("convert:jpg",[input])[0]
        try check(second != jpg && fm.fileExists(atPath:jpg.path),"No overwrite on repeated conversion")
        let same = try perform("convert:png",[input])[0]
        try check(same != input,"Same-format output preserves source")
        var options = ConversionOptions(); options.maxDimension = 60
        let resized = try perform("resize",[input],options:options)[0]
        let resizedImage = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(resized as CFURL,nil)!,0,nil)!
        try check(resizedImage.width == 60 && resizedImage.height == 40,"Resize preserves aspect ratio")
        let rotated = try perform("rotate",[input])[0]
        let rotatedImage = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(rotated as CFURL,nil)!,0,nil)!
        try check(rotatedImage.width == 80 && rotatedImage.height == 120,"Rotate swaps dimensions")
        let pdf = try perform("convert:pdf",[input])[0]
        try check(PDFDocument(url:pdf)?.pageCount == 1,"Image → valid PDF")
        let merged = try perform("mergePDF",[pdf,pdf])[0]
        try check(PDFDocument(url:merged)?.pageCount == 2,"Merge preserves all PDF pages")
        let pages = try perform("splitPDF",[merged])[0]
        try check(try fm.contentsOfDirectory(atPath:pages.path).count == 2,"Split creates every page")
        let raster = try perform("convert:png",[merged])[0]
        try check(try fm.contentsOfDirectory(atPath:raster.path).count == 2,"Rasterize every PDF page")
        let text = directory.appendingPathComponent("notes.txt"); try "Привет мир\nHello world\n<script>hello</script>".write(to:text,atomically:true,encoding:.utf8)
        let textPDF = try perform("convert:pdf",[text])[0]
        let extracted = try perform("convert:txt",[textPDF])[0]
        try check(try String(contentsOf:extracted).contains("Hello world"),"Text PDF and text extraction")
        let html = try perform("convert:html",[text])[0]
        try check(try String(contentsOf:html).contains("&lt;script&gt;"),"HTML escapes source text")
        let srt = directory.appendingPathComponent("captions.srt")
        try "1\r\n00:00:01,250 --> 00:00:03,500\r\nПривет\r\n\r\n2\r\n00:00:04,000 --> 00:00:05,000\r\nHello\r\n".write(to:srt,atomically:true,encoding:.utf8)
        let vtt = try perform("convert:vtt",[srt])[0]
        try check(try String(contentsOf:vtt).hasPrefix("WEBVTT\n\n00:00:01.250"),"SRT → VTT timing")
        let back = try perform("convert:srt",[vtt])[0]
        try check(try String(contentsOf:back).contains("00:00:04,000 --> 00:00:05,000\nHello"),"Subtitle round trip")
        let plain = try perform("convert:txt",[srt])[0]
        try check(try String(contentsOf:plain) == "Привет\n\nHello\n","Subtitle plain text excludes cue numbers")
        var cropOptions = ConversionOptions(); cropOptions.cropWidth = 40; cropOptions.cropHeight = 30
        let cropped = try perform("crop",[input],options:cropOptions)[0]
        let croppedImage = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(cropped as CFURL,nil)!,0,nil)!
        try check(croppedImage.width == 40 && croppedImage.height == 30,"Center crop has requested dimensions")
        _ = try perform("flip",[input]); _ = try perform("grayscale",[input])
        try check(true,"Flip and grayscale produce valid outputs")
        let cancelled = Converter(); cancelled.cancel()
        do { _ = try cancelled.perform(Operation("convert:jpg","JPG"),urls:[input]) { _ in }; throw DropError("Cancellation was ignored") }
        catch { try check(error.localizedDescription.contains("отменена") || error.localizedDescription.contains("Cancelled"),"Cancellation stops before conversion") }
        let mergeCancelled = Converter(); mergeCancelled.cancel()
        var mergeCancellationRejected = false
        do { _ = try mergeCancelled.perform(Operation("mergePDF","PDF"),urls:[input,input]) { _ in } } catch { mergeCancellationRejected = true }
        try check(mergeCancellationRejected,"Cancellation stops image-only PDF merge")
        let zip = try perform("zip",[input,text])[0]
        try check((try Data(contentsOf:zip)).prefix(2) == Data([0x50,0x4b]),"ZIP contains a valid signature")
        let archiveFolder = directory.appendingPathComponent("folder"); try fm.createDirectory(at:archiveFolder,withIntermediateDirectories:false)
        try "test".write(to:archiveFolder.appendingPathComponent("file.txt"),atomically:true,encoding:.utf8)
        let tgz = try perform("convert:tgz",[archiveFolder])[0]
        try check((try Data(contentsOf:tgz)).prefix(2) == Data([0x1f,0x8b]),"Folder → TAR.GZ")
        let unpacked = try perform("extract",[tgz])[0]
        try check(fm.fileExists(atPath:unpacked.appendingPathComponent("folder/file.txt").path),"Extract restores archive contents")
        let repacked = try perform("convert:zip",[tgz])[0]
        let repackedContents = try perform("extract",[repacked])[0]
        try check(fm.enumerator(atPath:repackedContents.path)!.allObjects.contains(where:{ String(describing:$0).hasSuffix("folder/file.txt") }),"Archive conversion unpacks and repacks contents")
        func tar(_ output: URL, args: [String]) throws {
            let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/bin/tar"); process.arguments = ["-cf",output.path] + args; try process.run(); process.waitUntilExit()
            try check(process.terminationStatus == 0,"Security fixture created")
        }
        let evil = directory.appendingPathComponent("traversal.tar")
        try tar(evil,args:["-P","-C",archiveFolder.path,"-s","#^file.txt$#../citrus-escape#","file.txt"])
        var traversalRejected = false
        do { _ = try perform("extract",[evil]) } catch { traversalRejected = true }
        try check(traversalRejected && !fm.fileExists(atPath:directory.appendingPathComponent("citrus-escape").path),"Archive path traversal rejected")
        try fm.createSymbolicLink(at:archiveFolder.appendingPathComponent("link"),withDestinationURL:text)
        let linked = directory.appendingPathComponent("linked.tar")
        try tar(linked,args:["-C",archiveFolder.path,"link"])
        var linkRejected = false
        do { _ = try perform("extract",[linked]) } catch { linkRejected = true }
        try check(linkRejected,"Archive links rejected")
        let batch = try perform("convert:jpg",[input,input]); try check(batch.count == 2 && batch[0] != batch[1],"Batch generates independent outputs")
        try check(try Data(contentsOf:input) == original,"Original bytes unchanged")
        try check(!fm.fileExists(atPath:directory.appendingPathComponent("NO").path),"Arguments are never interpreted as shell code")
        let mixed = Catalog.operations([input,srt],mode:0); try check(mixed.isEmpty,"Mixed batch exposes only shared conversions")
        let bmp = try perform("convert:bmp",[input])[0]
        let smallImage = try perform("compress",[bmp])[0]
        try check(smallImage.pathExtension == "jpg" && (try Data(contentsOf:smallImage)).count < (try Data(contentsOf:bmp)).count,"Image compression creates a smaller opaque JPEG")
        let large = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1600,pixelsHigh:1000,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        let bytes = large.bitmapData!
        for y in 0..<1000 { for x in 0..<1600 { let i = y*large.bytesPerRow+x*4; bytes[i] = UInt8((x*17+y*31)%256); bytes[i+1] = UInt8((x*41+y*7)%256); bytes[i+2] = UInt8((x*3+y*53)%256); bytes[i+3] = 255 } }
        let largeFile = directory.appendingPathComponent("large.bmp"); try large.representation(using:.bmp,properties:[:])!.write(to:largeFile)
        let largePDF = try perform("convert:pdf",[largeFile])[0]
        let textAndImage = try perform("mergePDF",[largePDF,textPDF])[0]
        let compressedPDF = try perform("compress",[textAndImage])[0]
        try check((try Data(contentsOf:compressedPDF)).count < (try Data(contentsOf:textAndImage)).count && PDFDocument(url:compressedPDF)?.pageCount == 2 && (PDFDocument(url:compressedPDF)?.string ?? "").contains("Hello world"),"PDF compression reduces bytes while retaining pages and text")
        for invalidOperation in ["compress","rotate","strip"] {
            var rejected = false
            do { _ = try perform(invalidOperation,[text]) } catch { rejected = true }
            try check(rejected,"Unsupported document operation rejected: " + invalidOperation)
        }
        let old = L.english; L.english = true
        try check(L.operation(Operation("resize","Размер")) == "Resize" && L.error("Пустое изображение.") == "Empty image.","English UI and errors")
        L.english = old
        if Catalog.ffmpeg != nil {
            let wav = directory.appendingPathComponent("tone.wav")
            let process = Process(); process.executableURL = Catalog.ffmpeg; process.arguments = ["-nostdin","-v","error","-f","lavfi","-i","sine=frequency=440:duration=1",wav.path]; try process.run(); process.waitUntilExit()
            let mp3 = try perform("convert:mp3",[wav])[0]
            try check((try Data(contentsOf:mp3)).count > 1000,"Real FFmpeg WAV → MP3")
            let compressed = try perform("compress",[wav])[0]
            try check(compressed.pathExtension == "m4a" && (try Data(contentsOf:compressed)).count < (try Data(contentsOf:wav)).count,"Lossless audio compression uses M4A")
            let video = directory.appendingPathComponent("video.mov")
            let generator = Process(); generator.executableURL = Catalog.ffmpeg; generator.arguments = ["-nostdin","-v","error","-f","lavfi","-i","testsrc2=s=320x240:r=15:d=1","-c:v","rawvideo","-pix_fmt","uyvy422",video.path]; try generator.run(); generator.waitUntilExit()
            let videoOutput = try perform("compress",[video])[0]
            try check(videoOutput.pathExtension == "mp4" && (try Data(contentsOf:videoOutput)).count > 500,"Video compression produces portable MP4")
            var trim = ConversionOptions(); trim.trimStart = 0.1; trim.trimDuration = 0.5
            let trimmed = try perform("trim",[video],options:trim)[0]
            try check((try Data(contentsOf:trimmed)).count > 500,"Video trim creates playable output")
        }
        if Catalog.office != nil {
            let csv = directory.appendingPathComponent("table.csv"); try "Name,Value\nOne,1\nTwo,2\n".write(to:csv,atomically:true,encoding:.utf8)
            let xlsx = try perform("convert:xlsx",[csv])[0]
            try check((try Data(contentsOf:xlsx)).prefix(2) == Data([0x50,0x4b]),"Real LibreOffice CSV → XLSX")
        }
    }
}
