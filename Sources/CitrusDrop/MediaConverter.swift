import Foundation

/// Local, cancellable FFmpeg jobs. ffprobe validates the actual streams rather than trusting extensions.
enum MediaConverter {
    private static let audioFormats = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "aiff"]
    private static let videoFormats = ["mp4", "mov", "mkv", "webm", "gif"]
    static var ffprobe: URL? {
        if let ffmpeg = Catalog.ffmpeg {
            let sibling = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
            if FileManager.default.isExecutableFile(atPath: sibling.path) { return sibling }
        }
        return Catalog.executable("ffprobe")
    }

    // Refresh after the in-app installer changes the helper path. Missing libraries must not become menu promises.
    private static let capabilityLock = NSLock()
    private static var capabilityPath = ""
    private static var capabilityEncoders: Set<String> = []
    private static var encoders: Set<String> {
        guard let ffmpeg = Catalog.ffmpeg else { return [] }
        capabilityLock.lock(); defer { capabilityLock.unlock() }
        if capabilityPath == ffmpeg.path { return capabilityEncoders }
        let process = Process(), pipe = Pipe()
        process.executableURL = ffmpeg; process.arguments = ["-hide_banner", "-encoders"]
        process.standardOutput = pipe; process.standardError = pipe; process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return [] }
        capabilityEncoders = Set(text.split(separator: "\n").compactMap { line -> String? in
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count > 1, fields[0].count == 6, "VAS".contains(fields[0].first!) else { return nil }
            return String(fields[1])
        })
        capabilityPath = ffmpeg.path
        return capabilityEncoders
    }

    static func availableFormats(forVideo: Bool) -> [String] {
        guard ffprobe != nil else { return [] }
        let formats = forVideo ? videoFormats + audioFormats : audioFormats
        return formats.filter { format in
            switch format {
            case "mp3": return encoders.contains("libmp3lame")
            case "m4a", "aac": return encoders.contains("aac")
            case "wav": return encoders.contains("pcm_s16le")
            case "aiff": return encoders.contains("pcm_s16be")
            case "flac": return encoders.contains("flac")
            case "ogg": return encoders.contains("libvorbis") || encoders.contains("libopus")
            case "opus": return encoders.contains("libopus")
            case "webm": return encoders.contains("libvpx-vp9") && encoders.contains("libopus")
            case "gif": return encoders.contains("gif")
            default: return encoders.contains("libx264") && encoders.contains("aac")
            }
        }
    }

    private struct Probe: Decodable {
        struct Stream: Decodable {
            var index: Int
            var codec_type: String?
            var codec_name: String?
            var pix_fmt: String?
            var bits_per_raw_sample: String?
            var channels: Int?
            var color_transfer: String?
            var disposition: [String: Int]?
            var tags: [String: String]?
            var alpha: Bool {
                let pixel = pix_fmt ?? ""
                return ["rgba", "argb", "bgra", "abgr", "yuva", "gbrap", "ya8", "ya16"].contains(where: pixel.hasPrefix)
                    || tags?["alpha_mode"] == "1" || tags?["ALPHA_MODE"] == "1"
            }
            var hdr: Bool { ["smpte2084", "arib-std-b67"].contains(color_transfer ?? "") }
        }
        struct Format: Decodable { var duration: String? }
        var streams: [Stream]
        var format: Format?
        var video: Stream? { streams.first { $0.codec_type == "video" && $0.disposition?["attached_pic"] != 1 } }
        var audio: Stream? { streams.first { $0.codec_type == "audio" } }
        var duration: Double? { format?.duration.flatMap(Double.init) }
    }

    private static func probe(_ source: URL, run: (URL, [String]) throws -> Void) throws -> Probe {
        guard let executable = ffprobe else {
            throw DropError(L.t("Нужен ffprobe из того же бесплатного пакета FFmpeg. Откройте меню «Зависимости».", "ffprobe from the free FFmpeg package is required. Open Dependencies in the menu."))
        }
        let json = FileManager.default.temporaryDirectory.appendingPathComponent("citrus-probe-" + UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: json) }
        try run(executable, ["-v", "error", "-protocol_whitelist", "file,pipe", "-show_entries",
            "stream=index,codec_type,codec_name,pix_fmt,bits_per_raw_sample,channels,color_transfer:stream_disposition=attached_pic:stream_tags=alpha_mode:format=duration",
            "-of", "json", "-o", json.path, source.path])
        do { return try JSONDecoder().decode(Probe.self, from: Data(contentsOf: json)) }
        catch { throw DropError(L.t("Не удалось прочитать потоки медиафайла.", "Cannot read the media streams.")) }
    }

    static func convert(source: URL, output: URL, operation: String, options: ConversionOptions,
                        run: (URL, [String]) throws -> Void) throws {
        guard let ffmpeg = Catalog.ffmpeg else {
            throw DropError(L.t("Нужен FFmpeg. Инструкция: меню → Зависимости.", "FFmpeg is required. See Menu → Dependencies."))
        }
        let input = try probe(source, run: run), format = output.pathExtension.lowercased()
        let audioOnly = operation == "strip" ? input.video == nil : audioFormats.contains(format) || format == "aif"
        guard input.audio != nil || input.video != nil else {
            throw DropError(L.t("В файле нет аудио или видео.", "The file contains no audio or video streams."))
        }
        if audioOnly && input.audio == nil {
            throw DropError(L.t("В этом видео нет звуковой дорожки для экспорта.", "This video has no audio track to export."))
        }
        if !audioOnly && input.video == nil {
            throw DropError(L.t("В этом файле нет видеодорожки.", "This file has no video track."))
        }
        if operation != "strip" && !availableFormats(forVideo: input.video != nil).contains(format == "aif" ? "aiff" : format) {
            throw DropError(L.t("Установленная сборка FFmpeg не содержит кодек для \(format.uppercased()).", "This FFmpeg build has no encoder for \(format.uppercased())."))
        }
        var args = ["-nostdin", "-hide_banner", "-v", "error", "-xerror", "-n", "-protocol_whitelist", "file,pipe"]
        if operation == "trim" {
            guard options.trimStart.isFinite, options.trimDuration.isFinite, options.trimStart >= 0, options.trimDuration > 0 else {
                throw DropError(L.t("Начало обрезки должно быть не меньше нуля, длительность — больше нуля.", "Trim start must be nonnegative and duration must be positive."))
            }
            if let duration = input.duration, duration.isFinite, duration > 0, options.trimStart >= duration {
                throw DropError(L.t("Начало обрезки находится за концом файла.", "Trim start is beyond the end of the file."))
            }
            args += ["-ss", String(options.trimStart)]
        }
        // FFmpeg's native VP9 decoder discards alpha; libvpx decodes its auxiliary alpha stream.
        if input.video?.alpha == true, input.video?.codec_name == "vp9", operation != "strip" { args += ["-c:v", "libvpx-vp9"] }
        args += ["-i", source.path]
        if operation == "trim" { args += ["-t", String(options.trimDuration)] }
        if operation == "strip" {
            // Keep all original tracks and display matrices; remove source global/stream tags and chapters.
            args += ["-map", "0", "-c", "copy", "-map_metadata", "-1", "-map_metadata:s", "-1", "-map_chapters", "-1", "-metadata", "encoder=", "-fflags", "+bitexact"]
            if input.video?.alpha == true, ["webm", "mkv"].contains(format) { args += ["-metadata:s:v:0", "alpha_mode=1"] }
            if format == "m4v" { args += ["-f", "mp4"] }
        } else if audioOnly {
            args += ["-map", "0:\(input.audio!.index)", "-vn", "-sn", "-dn"]
            args += try audioArguments(format, stream: input.audio!, compress: operation == "compress")
        } else {
            let video = input.video!
            if format != "gif" { args += ["-map", "0:\(video.index)"] }
            if let audio = input.audio, format != "gif" { args += ["-map", "0:\(audio.index)"] }
            args += ["-sn", "-dn"]
            if format == "gif" {
                if video.hdr { throw DropError(L.t("Для HDR сначала экспортируйте видео в SDR: GIF не хранит HDR.", "Convert HDR to SDR first: GIF cannot store HDR.")) }
                args += ["-an", "-filter_complex", "[0:\(video.index)]fps=12,scale='min(640,iw)':-1:flags=lanczos,split[a][b];[a]palettegen=reserve_transparent=1[p];[b][p]paletteuse=dither=sierra2_4a[gif]", "-map", "[gif]", "-loop", "0"]
            } else {
                args += try videoArguments(format, stream: video, compress: operation == "compress", quality: options.quality)
                if let audio = input.audio {
                    args += try audioArguments(format == "webm" ? "opus" : "m4a", stream: audio, compress: operation == "compress")
                }
                args += ["-metadata:s:v:0", "rotate=0"]
            }
            if ["mp4", "mov"].contains(format) { args += ["-movflags", "+faststart"] }
        }
        if operation != "strip" {
            args += ["-map_metadata", "0"]
            if operation == "trim" { args += ["-map_chapters", "-1"] }
        }
        try run(ffmpeg, args + [output.path])
        let result = try probe(output, run: run)
        let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, audioOnly ? result.audio != nil : result.video != nil else {
            throw DropError(L.t("Конвертер не создал корректный медиафайл.", "The converter did not create valid media."))
        }
        if operation == "compress", size >= (try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) {
            throw DropError(L.t("Файл уже хорошо сжат: уменьшить его с выбранным качеством не удалось. Оригинал сохранён.", "This file is already compact: compression at this quality did not reduce its size. The original is preserved."))
        }
    }

    private static func audioArguments(_ format: String, stream: Probe.Stream, compress: Bool) throws -> [String] {
        let bits = Int(stream.bits_per_raw_sample ?? "") ?? 16
        switch format {
        case "mp3": return ["-c:a", "libmp3lame", "-q:a", compress ? "7" : "2", "-ac", String(min(2, stream.channels ?? 2)), "-ar", "44100"]
        case "m4a", "aac": return ["-c:a", "aac", "-b:a", compress ? "96k" : "192k", "-ar", "48000"]
        case "wav": return ["-c:a", bits > 16 ? "pcm_s24le" : "pcm_s16le"]
        case "aiff", "aif": return ["-c:a", bits > 16 ? "pcm_s24be" : "pcm_s16be"]
        case "flac": return ["-c:a", "flac", "-compression_level", "8"]
        case "ogg" where encoders.contains("libvorbis"): return ["-c:a", "libvorbis", "-q:a", compress ? "1" : "5"]
        case "ogg", "opus": return ["-c:a", "libopus", "-b:a", compress ? "64k" : "128k", "-ar", "48000"]
        default: throw DropError(L.t("Неподдерживаемый аудиоформат.", "Unsupported audio format."))
        }
    }

    private static func videoArguments(_ format: String, stream: Probe.Stream, compress: Bool, quality: Double) throws -> [String] {
        if stream.alpha && stream.hdr {
            if format == "mov", encoders.contains("prores_ks") { return ["-c:v", "prores_ks", "-profile:v", "4", "-pix_fmt", "yuva444p10le"] }
            if format == "mkv", encoders.contains("ffv1") { return ["-c:v", "ffv1", "-level", "3", "-pix_fmt", "yuva444p16le"] }
            throw DropError(L.t("Для HDR с прозрачностью выберите MOV или MKV с кодеком ProRes/FFV1.", "For HDR with transparency choose MOV or MKV with ProRes/FFV1."))
        }
        if stream.alpha {
            switch format {
            case "mov": return ["-c:v", "qtrle", "-pix_fmt", "argb"]
            case "mkv": return ["-c:v", "ffv1", "-level", "3", "-pix_fmt", "bgra"]
            case "webm": return ["-c:v", "libvpx-vp9", "-pix_fmt", "yuva420p", "-auto-alt-ref", "0", "-b:v", "0", "-crf", compress ? "36" : "24"]
            default: throw DropError(L.t("MP4 не сохраняет прозрачность. Выберите MOV, MKV или WebM.", "MP4 cannot preserve transparency. Choose MOV, MKV or WebM."))
            }
        }
        let crf = compress ? 30 : Int(18 + (1 - min(1, max(0, quality.isFinite ? quality : 0.8))) * 14)
        // Even chroma dimensions also work for odd-sized sources. scale preserves display aspect through SAR.
        let filter = "scale=ceil(iw/2)*2:ceil(ih/2)*2"
        if format == "webm" {
            return ["-c:v", "libvpx-vp9", "-pix_fmt", stream.hdr ? "yuv420p10le" : "yuv420p", "-b:v", "0", "-crf", compress ? "38" : "30", "-deadline", "good", "-cpu-used", "2"]
        }
        if stream.hdr {
            guard encoders.contains("libx265") else { throw DropError(L.t("Для сохранения HDR нужен FFmpeg с libx265.", "Preserving HDR requires FFmpeg with libx265.")) }
            return ["-vf", filter, "-c:v", "libx265", "-pix_fmt", "yuv420p10le", "-crf", String(crf), "-preset", "medium"] + (["mp4", "mov"].contains(format) ? ["-tag:v", "hvc1"] : [])
        }
        return ["-vf", filter, "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", String(crf), "-preset", "medium"]
    }
}
