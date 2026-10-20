import AppKit

let arguments = CommandLine.arguments
if arguments.contains("--version") { print("CitrusDrop 0.2.0"); exit(0) }
if arguments.contains("--help") {
    print("""
    CitrusDrop 0.2.0 — local conversion for macOS
    --convert FORMAT FILE...    Convert local files, preserve originals
    --perform OPERATION FILE... compress, strip, splitPDF, mergePDF, zip
    --install-engines           Download verified free media/Office engines
    --supported-formats FILE   List formats available on this Mac
    --self-test                Run temporary-fixture checks
    """); exit(0)
}
if arguments.contains("--install-engines") {
    Task {
        do {
            let report:(String)->Void = { fputs($0 + "\n",stderr) }
            if Catalog.ffmpeg == nil || Catalog.executable("ffprobe") == nil { try await EngineInstaller.installMedia(progress:report) }
            if Catalog.office == nil { try await EngineInstaller.installOffice(progress:report) }
            print("CitrusDrop engines are ready."); exit(0)
        } catch { fputs(error.localizedDescription + "\n",stderr); exit(1) }
    }
    dispatchMain()
}
if arguments.contains("--self-test") {
    do { try SelfTest.run(); print("All checks passed"); exit(0) }
    catch { fputs("FAIL: \(error)\n",stderr); exit(1) }
}
if let index = arguments.firstIndex(of:"--supported-formats"), arguments.count > index + 1 {
    print(Catalog.formats(URL(fileURLWithPath:arguments[index+1])).joined(separator:" ")); exit(0)
}
if let index = arguments.firstIndex(where:{ ["--convert","--perform"].contains($0) }), arguments.count > index + 2 {
    do {
        let id = arguments[index] == "--convert" ? "convert:" + arguments[index+1].lowercased() : arguments[index+1]
        let allowed = ["compress","strip","resize","rotate","crop","flip","grayscale","splitPDF","mergePDF","pdfText","zip","extract"]
        guard id.hasPrefix("convert:") || allowed.contains(id) else { throw DropError("Unsupported operation") }
        let operation = Operation(id,id)
        let urls = arguments.dropFirst(index+2).map { URL(fileURLWithPath:$0) }
        let output = try Converter().perform(operation,urls:urls) { fputs("\($0)\n",stderr) }
        output.forEach { print($0.path) }; exit(0)
    } catch { fputs("\(error.localizedDescription)\n",stderr); exit(1) }
}
let application = NSApplication.shared
let delegate = App()
application.delegate = delegate
application.run()
