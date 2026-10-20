#!/usr/bin/env python3
"""Run real MediaConverter jobs, then inspect and decode their results. macOS + Swift + FFmpeg required."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
FFMPEG = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
FFPROBE = str(Path(FFMPEG).with_name("ffprobe"))
CHECKS = []


def run(*args, expect=0):
    result = subprocess.run([str(arg) for arg in args], capture_output=True, text=True, timeout=180)
    if result.returncode != expect:
        raise AssertionError(f"{args[0]} exited {result.returncode}: {result.stderr[-2500:]}")
    return result


def check(name, condition=True):
    if not condition:
        raise AssertionError(name)
    CHECKS.append(name)
    print("PASS", name, flush=True)


def ff(*args):
    return run(FFMPEG, "-nostdin", "-v", "error", "-y", *args)


def probe(path):
    return json.loads(run(FFPROBE, "-v", "error", "-show_streams", "-show_format", "-of", "json", path).stdout)


def stream(path, kind):
    return next(s for s in probe(path)["streams"] if s["codec_type"] == kind)


def decode(path):
    ff("-xerror", "-i", path, "-f", "null", "-")


def main():
    started = time.time()
    with tempfile.TemporaryDirectory(prefix="CitrusDrop-media-checks-") as folder:
        directory = Path(folder)
        main_swift = directory / "main.swift"
        main_swift.write_text('''import Foundation
let args = CommandLine.arguments
if args.count == 2 && args[1] == "--engine" { print(Catalog.ffmpeg?.path ?? ""); exit(0) }
let source = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
var options = ConversionOptions()
options.trimStart = Double(args[4])!; options.trimDuration = Double(args[5])!
func run(_ executable: URL, _ arguments: [String]) throws {
    let process = Process(), pipe = Pipe()
    process.executableURL = executable; process.arguments = arguments
    process.standardOutput = pipe; process.standardError = pipe; process.standardInput = FileHandle.nullDevice
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    if process.terminationStatus != 0 { throw DropError(String(decoding:data,as:UTF8.self)) }
}
do {
    try MediaConverter.convert(source:source,output:output,operation:args[3],options:options,run:run)
} catch { fputs(error.localizedDescription + "\\n",stderr); exit(1) }
''', encoding="utf-8")
        # Compile the real media source and option declaration without pulling in unrelated UI/office tests.
        converter_source = (ROOT / "Sources/CitrusDrop/Converter.swift").read_text(encoding="utf-8")
        options_declaration = converter_source.split("struct ConversionOptions {", 1)[1].split("\n}", 1)[0]
        options_swift = directory / "Options.swift"
        options_swift.write_text("struct ConversionOptions {" + options_declaration + "\n}\n", encoding="utf-8")
        names = ["Models", "Localization", "MediaConverter", "OfficeConverter", "TextFormats", "EngineInstaller"]
        sources = [ROOT / f"Sources/CitrusDrop/{name}.swift" for name in names]
        sources = [path for path in sources if path.exists()]
        sources.append(options_swift)
        if not (ROOT / "Sources/CitrusDrop/EngineInstaller.swift").exists():
            # The media harness only needs discovery; installation is tested separately.
            with main_swift.open("a", encoding="utf-8") as handle:
                handle.write('\nenum EngineInstaller { static let root = FileManager.default.temporaryDirectory }\n')
        harness = directory / "media-check"
        run("swiftc", "-O", *sources, main_swift, "-o", harness)
        converter_engine = run(harness, "--engine").stdout.strip()

        def convert(source, name, operation="convert", start=0, duration=10, fail=False):
            output = directory / name
            result = run(harness, source, output, operation, start, duration, expect=1 if fail else 0)
            if fail:
                return result.stderr
            decode(output)
            return output

        tone = directory / "Тон ' ; $(touch NO).wav"
        ff("-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100:duration=1.4", "-c:a", "pcm_s24le", "-metadata", "title=PRIVATE-TITLE", "-metadata", "comment=PRIVATE-COMMENT", tone)
        original = hashlib.sha256(tone.read_bytes()).hexdigest()
        expected = {"mp3": "mp3", "m4a": "aac", "aac": "aac", "wav": "pcm_s24le", "flac": "flac", "ogg": None, "opus": "opus", "aiff": "pcm_s24be"}
        for ext, codec in expected.items():
            output = convert(tone, "tone." + ext)
            info = stream(output, "audio")
            check("44.1 kHz 24-bit WAV → " + ext.upper(), codec is None or info["codec_name"] == codec)
            if ext in ("opus", "ogg"):
                check(ext.upper() + " uses a valid installed encoder", info["codec_name"] in ("opus", "vorbis"))
        check("Lossless PCM precision retained", stream(directory / "tone.wav", "audio")["bits_per_sample"] == 24)
        compressed = convert(tone, "compressed.m4a", "compress")
        check("PCM audio compression reduces actual bytes", compressed.stat().st_size < tone.stat().st_size)
        stripped = convert(tone, "stripped.wav", "strip")
        info = probe(stripped)
        check("Audio source metadata removed", "PRIVATE" not in json.dumps(info))
        check("Metadata removal retains lossless audio codec", stream(stripped, "audio")["codec_name"] == "pcm_s24le")

        video = directory / "odd video.mkv"
        ff("-f", "lavfi", "-i", "testsrc=size=321x241:rate=12:duration=1.5", "-f", "lavfi", "-i", "sine=duration=1.5", "-c:v", "ffv1", "-pix_fmt", "bgr0", "-c:a", "pcm_s16le", "-metadata", "title=PRIVATE-TITLE", "-metadata:s:a:0", "title=PRIVATE-TRACK", video)
        for ext in ("mp4", "mov", "mkv", "webm", "gif"):
            output = convert(video, "video." + ext)
            info = stream(output, "video")
            check("Odd-sized video + audio → " + ext.upper(), info["width"] > 0 and info["height"] > 0)
            if ext != "gif":
                check(ext.upper() + " preserves audio", stream(output, "audio")["codec_type"] == "audio")
                numerator, denominator = map(int, info["display_aspect_ratio"].split(":"))
                # Matroska stores integer display dimensions, so a chroma-rounding pixel can quantize SAR.
                check(ext.upper() + " preserves display aspect within one pixel", abs(numerator / denominator - 321 / 241) < 1 / info["height"])
        compressed = convert(video, "video-compressed.mp4", "compress")
        check("Video compression reduces actual bytes", compressed.stat().st_size < video.stat().st_size)
        trimmed = convert(video, "trimmed.mp4", "trim", 0.25, 0.5)
        check("Video trim has requested duration", abs(float(probe(trimmed)["format"]["duration"]) - 0.5) < 0.12)
        audio_trim = convert(tone, "trimmed.wav", "trim", 0.25, 0.5)
        check("Audio trim is sample accurate", abs(float(probe(audio_trim)["format"]["duration"]) - 0.5) < 0.002)
        stripped_video = convert(video, "stripped.mkv", "strip")
        check("Video global and stream metadata removed", "PRIVATE" not in json.dumps(probe(stripped_video)))
        check("Metadata removal preserves video/audio streams", len(probe(stripped_video)["streams"]) == 2)

        silent = directory / "silent.mov"
        ff("-f", "lavfi", "-i", "color=c=orange:size=96x64:duration=1", "-c:v", "libx264", silent)
        silent_output = convert(silent, "silent.mp4")
        check("Silent video remains valid without an audio stream", len(probe(silent_output)["streams"]) == 1)
        check("Audio extraction from silent video fails clearly", bool(convert(silent, "missing.mp3", fail=True).strip()))
        for start, duration in ((-1, 1), (0, 0), (0, -1), (5, 1)):
            check(f"Invalid trim rejected ({start}, {duration})", bool(convert(silent, f"bad-{start}-{duration}.mp4", "trim", start, duration, fail=True).strip()))
        corrupt = directory / "corrupt.mp4"
        corrupt.write_bytes(b"not a media file")
        check("Corrupt input is rejected", bool(convert(corrupt, "invalid.mp4", fail=True).strip()))

        rotated = directory / "rotated.mov"
        ff("-display_rotation:v:0", "90", "-i", silent, "-c", "copy", rotated)
        rotated_output = convert(rotated, "upright.mp4")
        info = stream(rotated_output, "video")
        check("Phone rotation is applied once", (info["width"], info["height"]) == (64, 96))
        rotated_stripped = convert(rotated, "rotated-stripped.mov", "strip")
        check("Metadata removal preserves display rotation", any(abs(side.get("rotation", 0)) == 90 for side in stream(rotated_stripped, "video").get("side_data_list", [])))

        alpha = directory / "alpha.mov"
        ff("-f", "lavfi", "-i", "color=c=red@0.35:size=96x64:duration=0.5,format=argb", "-c:v", "qtrle", alpha)
        for ext in ("mov", "mkv", "webm"):
            output = convert(alpha, "alpha-out." + ext)
            info = stream(output, "video")
            is_alpha = info["pix_fmt"] in ("argb", "bgra", "yuva420p") or info.get("tags", {}).get("alpha_mode") == "1"
            check("Transparency survives " + ext.upper(), is_alpha)
        alpha_webm = directory / "alpha-out.webm"
        alpha_roundtrip = convert(alpha_webm, "alpha-roundtrip.mov")
        check("WebM alpha decodes through libvpx", stream(alpha_roundtrip, "video")["pix_fmt"] == "argb")
        alpha_stripped = convert(alpha_webm, "alpha-stripped.webm", "strip")
        alpha_tags = {key.lower(): value for key, value in stream(alpha_stripped, "video").get("tags", {}).items()}
        check("Metadata removal retains required alpha signaling", alpha_tags.get("alpha_mode") == "1" and b"\x53\xc0\x81\x01" in alpha_stripped.read_bytes())
        for image in (alpha, alpha_roundtrip):
            values = subprocess.run([FFMPEG, "-nostdin", "-v", "error", "-i", str(image), "-frames:v", "1", "-vf", "alphaextract", "-f", "rawvideo", "-"], capture_output=True, timeout=30, check=True).stdout
            check("Actual transparent pixel values survive " + image.name, len(values) > 0 and 20 < sum(values) / len(values) < 230)
        check("MP4 transparency loss is rejected", bool(convert(alpha, "alpha-invalid.mp4", fail=True).strip()))

        surround = directory / "surround.wav"
        ff("-f", "lavfi", "-i", "anullsrc=channel_layout=5.1:sample_rate=48000", "-t", "0.4", surround)
        for ext in ("m4a", "opus", "mp3"):
            output = convert(surround, "surround." + ext)
            check("5.1 audio → " + ext.upper(), stream(output, "audio")["channels"] == (2 if ext == "mp3" else 6))

        hdr = directory / "hdr.mov"
        ff("-f", "lavfi", "-i", "color=c=orange:size=96x64:duration=0.3", "-vf", "format=yuv420p10le,setparams=color_primaries=bt2020:color_trc=smpte2084:colorspace=bt2020nc", "-c:v", "libx265", "-x265-params", "log-level=error:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc", "-tag:v", "hvc1", hdr)
        check("HDR fixture actually carries PQ transfer metadata", stream(hdr, "video")["color_transfer"] == "smpte2084")
        hdr_output = convert(hdr, "hdr-output.mp4")
        check("HDR export retains 10-bit HEVC and transfer", stream(hdr_output, "video")["pix_fmt"] == "yuv420p10le" and stream(hdr_output, "video")["color_transfer"] == "smpte2084")
        check("Unicode and shell characters stay literal", not (directory / "NO").exists())
        check("Original source bytes unchanged", hashlib.sha256(tone.read_bytes()).hexdigest() == original)
        report = {"checks": CHECKS, "passed": len(CHECKS), "seconds": round(time.time() - started, 2), "ffmpeg": run(converter_engine, "-version").stdout.splitlines()[0], "converter_engine": converter_engine, "fixture_engine": FFMPEG}
        report_path = ROOT / "docs/media-test-results.json"
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"{len(CHECKS)} media checks passed; report: {report_path}", flush=True)


if __name__ == "__main__":
    main()
