#!/usr/bin/env python3
"""Real Office conversion checks. Uses only Python/Swift stdlibs and LibreOffice.

    python3 tests/office-checks.py --full --report .build/office-qa.json

All fixtures and converter outputs are generated in a disposable directory.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import subprocess
import struct
import tempfile
import time
import zipfile
import zlib


ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Sources/CitrusDrop"
TOKEN = "Привет CitrusDrop"


def odf(path, kind, body):
    mime = "application/vnd.oasis.opendocument." + kind
    content = '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-content office:version="1.2"
xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
xmlns:xlink="http://www.w3.org/1999/xlink"
xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"
xmlns:presentation="urn:oasis:names:tc:opendocument:xmlns:presentation:1.0">
<office:automatic-styles><style:style style:name="PageBreak" style:family="paragraph"><style:paragraph-properties fo:break-before="page"/></style:style><style:style style:name="Wide" style:family="table-column"><style:table-column-properties style:column-width="8cm"/></style:style></office:automatic-styles>
<office:body>''' + body + "</office:body></office:document-content>"
    styles = '''<?xml version="1.0" encoding="UTF-8"?><office:document-styles office:version="1.2" xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"><office:automatic-styles><style:page-layout style:name="pm1"><style:page-layout-properties fo:page-width="28cm" fo:page-height="21cm" style:print-orientation="landscape"/></style:page-layout></office:automatic-styles><office:master-styles><style:master-page style:name="Default" style:page-layout-name="pm1"/></office:master-styles></office:document-styles>'''
    manifest = f'''<?xml version="1.0" encoding="UTF-8"?><manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"><manifest:file-entry manifest:full-path="/" manifest:media-type="{mime}"/><manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/><manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/><manifest:file-entry manifest:full-path="Pictures/orange.png" manifest:media-type="image/png"/></manifest:manifest>'''
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("mimetype", mime)
        archive.writestr("content.xml", content)
        archive.writestr("styles.xml", styles)
        archive.writestr("META-INF/manifest.xml", manifest)
        def chunk(tag, data):
            return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 40, 40, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress((b"\0" + bytes([255, 128, 20]) * 40) * 40)) + chunk(b"IEND", b"")
        archive.writestr("Pictures/orange.png", png)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--full", action="store_true", help="Exercise every advertised output from every fixture format")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    results = []
    start = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="citrus-office-qa-") as temporary:
        base = Path(temporary)
        harness = base / "main.swift"
        harness.write_text('''import Foundation
import PDFKit
import ImageIO
@main struct OfficeProbe {
 static func main() throws {
  let args = CommandLine.arguments
  if args[1] == "--formats" { print(OfficeConverter.formats(for: URL(fileURLWithPath:args[2])).joined(separator:",")); return }
  if args[1] == "--pdf-info" { let doc = PDFDocument(url:URL(fileURLWithPath:args[2]))!; print(doc.pageCount); print(doc.string ?? ""); return }
  if args[1] == "--image-info" { let image = CGImageSourceCreateWithURL(URL(fileURLWithPath:args[2]) as CFURL,nil)!; let bitmap = CGImageSourceCreateImageAtIndex(image,0,nil)!; print("\\(bitmap.width)x\\(bitmap.height)"); return }
  let source = URL(fileURLWithPath:args[1]), output = URL(fileURLWithPath:args[2])
  let result = try Converter().perform(Operation("convert:" + output.pathExtension, output.pathExtension), urls:[source]) { _ in }
  guard result.count == 1 else { throw DropError("Expected one result") }
  try FileManager.default.moveItem(at:result[0],to:output)
 }
}
''')
        binary = base / "office-probe"
        swift_sources = [SOURCES / name for name in ["OfficeConverter.swift", "Models.swift", "TextFormats.swift", "Localization.swift", "Converter.swift"]]
        swift_sources += [SOURCES / name for name in ["EngineInstaller.swift", "MediaConverter.swift", "Compression.swift"] if (SOURCES / name).exists()]
        subprocess.run(["swiftc", "-parse-as-library", *map(str, swift_sources), str(harness), "-o", str(binary)], check=True, timeout=120)

        def probe(*arguments):
            return subprocess.run([str(binary), *map(str, arguments)], check=True, capture_output=True, text=True, cwd=base, timeout=90).stdout

        def check(name, value):
            if not value:
                raise AssertionError(name)
            results.append({"name": name, "status": "passed"})
            print("PASS", name, flush=True)

        writer = base / "Тест ' ; $(touch NO).odt"
        odf(writer, "text", f'<office:text><text:h text:outline-level="1">{TOKEN}</text:h><text:p>Page one with table.<draw:frame draw:name="Image" text:anchor-type="as-char" svg:width="1cm" svg:height="1cm"><draw:image xlink:href="Pictures/orange.png" xlink:type="simple" xlink:show="embed" xlink:actuate="onLoad"/></draw:frame></text:p><table:table table:name="Table"><table:table-column table:number-columns-repeated="2"/><table:table-row><table:table-cell office:value-type="string"><text:p>Header</text:p></table:table-cell><table:table-cell office:value-type="float" office:value="42"><text:p>42</text:p></table:table-cell></table:table-row></table:table><text:p text:style-name="PageBreak">Second page</text:p></office:text>')
        deck = base / "slides.odp"
        odf(deck, "presentation", '<office:presentation>' + "".join(f'<draw:page draw:name="Slide{i}" draw:master-page-name="Default"><draw:frame svg:x="2cm" svg:y="2cm" svg:width="20cm" svg:height="5cm"><draw:text-box><text:p>{TOKEN} {i}</text:p></draw:text-box></draw:frame></draw:page>' for i in [1, 2]) + '</office:presentation>')
        workbook = base / "table.ods"
        odf(workbook, "spreadsheet", f'<office:spreadsheet><table:table table:name="Данные"><table:table-column table:style-name="Wide" table:number-columns-repeated="2"/><table:table-row><table:table-cell office:value-type="string"><text:p>Name</text:p></table:table-cell><table:table-cell office:value-type="string"><text:p>Value</text:p></table:table-cell></table:table-row><table:table-row><table:table-cell office:value-type="string"><text:p>{TOKEN}</text:p></table:table-cell><table:table-cell office:value-type="float" office:value="42"><text:p>42</text:p></table:table-cell></table:table-row></table:table><table:table table:name="Second"><table:table-column table:style-name="Wide"/><table:table-row><table:table-cell office:value-type="string"><text:p>Second sheet</text:p></table:table-cell></table:table-row></table:table></office:spreadsheet>')
        text = base / "notes.txt"
        text.write_text(TOKEN + '\n<script>hello</script>\n', encoding="utf-8")
        markdown = base / "notes.md"
        markdown.write_text("# " + TOKEN + "\n\nMarkdown kept as literal text.\n", encoding="utf-8")
        csvfile = base / "input.csv"
        csvfile.write_text('Name;Value\n"' + TOKEN + '";42\n"contains;separator";8\n', encoding="utf-8")
        tsvfile = base / "input.tsv"
        tsvfile.write_text('Name\tValue\n' + TOKEN + '\t42\n"=1+1"\t7\n', encoding="utf-8")

        def convert(source, target, suffix=""):
            folder = base / ("out-" + str(len(results)) + "-" + source.suffix[1:] + "-" + target + suffix)
            folder.mkdir(exist_ok=True)
            output = folder / ("output." + target)
            original = hashlib.sha256(source.read_bytes()).hexdigest()
            probe(source, output)
            check(source.suffix[1:].upper() + " → " + target.upper() + suffix, output.is_dir() or output.stat().st_size > 0)
            check("Original preserved " + source.suffix + " → " + target + suffix, hashlib.sha256(source.read_bytes()).hexdigest() == original)
            if target in ["docx", "xlsx", "pptx", "odt", "ods", "odp", "epub"]:
                with zipfile.ZipFile(output) as archive:
                    check("Valid package " + target + suffix, archive.testzip() is None)
            if target in ["doc", "xls", "ppt"]:
                check("Valid legacy Office signature " + target + suffix, output.read_bytes().startswith(bytes.fromhex("d0cf11e0a1b11ae1")))
            if target == "pdf":
                info = probe("--pdf-info", output)
                check("PDF text and pages " + source.suffix + suffix, "Привет" in info and int(info.splitlines()[0]) >= (2 if source.suffix in [".pptx", ".ppt", ".odp", ".docx", ".odt", ".rtf", ".ods", ".xlsx", ".xls"] else 1))
            if target in ["png", "jpg"]:
                pages = sorted(output.iterdir())
                check("Every page rasterized " + source.suffix + suffix, len(pages) >= (2 if source.suffix in [".pptx", ".ppt", ".odp", ".docx", ".odt", ".rtf", ".ods", ".xlsx", ".xls"] else 1) and "x" in probe("--image-info", pages[-1]))
            return output

        writers = [writer]
        for ext in ["doc", "docx", "rtf", "html"]:
            writers.append(convert(writer, ext, " fixture"))
        check("Exported HTML embeds images without disposable sidecars", "data:image/" in writers[-1].read_text(encoding="utf-8"))
        sheets = [workbook, csvfile, tsvfile]
        for ext in ["xlsx", "xls"]:
            sheets.append(convert(workbook, ext, " fixture"))
        decks = [deck]
        for ext in ["pptx", "ppt"]:
            decks.append(convert(deck, ext, " fixture"))

        if args.full:
            for source in writers + [text, markdown] + sheets + decks:
                for target in probe("--formats", source).strip().split(","):
                    if target:
                        convert(source, target)
        else:
            for source, targets in [(writers[2], ["pdf", "epub", "png"]), (writers[-1], ["docx"]), (text, ["pdf", "html", "docx"]), (markdown, ["odt"]), (sheets[-2], ["pdf", "csv", "tsv"]), (tsvfile, ["xlsx"]), (decks[1], ["pdf", "png", "jpg", "odp"])]:
                for target in targets:
                    convert(source, target)
        # A real round trip checks TSV cell boundaries, UTF-8 and no formula evaluation.
        imported = convert(tsvfile, "xlsx", " TSV import regression")
        roundtrip = convert(imported, "tsv", " TSV roundtrip")
        rows = list(csv.reader(roundtrip.open(encoding="utf-8"), delimiter="\t"))
        check("TSV has two columns and preserves Cyrillic/formula text", rows[1] == [TOKEN, "42"] and rows[2] == ["=1+1", "7"])
        imported_csv = convert(csvfile, "xlsx", " semicolon CSV regression")
        roundtrip_csv = convert(imported_csv, "csv", " CSV roundtrip")
        rows = list(csv.reader(roundtrip_csv.open(encoding="utf-8")))
        check("CSV delimiter detection respects quotes and Cyrillic", rows[1] == [TOKEN, "42"] and rows[2] == ["contains;separator", "8"])
        check("Unsupported EPUB/Pages/Keynote imports are not advertised", all(probe("--formats", base / ("unsupported." + ext)).strip() == "" for ext in ["epub", "pages", "key"]))
        check("Shell metacharacters were not executed", not (base / "NO").exists())

    report = {"suite": "office", "full": args.full, "passed": len(results), "durationSeconds": round(time.monotonic() - start, 2), "checks": results}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: value for key, value in report.items() if key != "checks"}), flush=True)


if __name__ == "__main__":
    main()
