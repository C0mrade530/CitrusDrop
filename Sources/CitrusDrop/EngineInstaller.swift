import Foundation
import CryptoKit

/// Optional, local engines. Vendor binaries keep their original signatures and licenses.
enum EngineInstaller {
    static var root: URL {
        if let path = ProcessInfo.processInfo.environment["CITRUSDROP_ENGINES_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CitrusDrop/Engines", isDirectory: true)
    }

    static func install(progress: @escaping (String) -> Void) async throws {
        try await installMedia(progress: progress)
        try await installOffice(progress: progress)
    }

    static func installMedia(progress: @escaping (String) -> Void) async throws {
        let destination = root.appendingPathComponent("ffmpeg-9.0.2", isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try await validateMedia(at: destination)
            progress(L.t("Видео и аудио готовы.", "Video and audio are ready.")); return
        }
        let staging = try makeStagingDirectory()
        defer { try? FileManager.default.removeItem(at: staging) }
        let payload = staging.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: false)
        #if arch(arm64)
        let base = "https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2/"
        let archives = [("ffmpeg", "c8ed4c4e6978a03c485edbfe4e0a5dc2380f8a30bba5150531b31b094492d924"),
                        ("ffprobe", "fcbe839537485eaee7a7a8bc5cbc0f90d53617e80943e8a5b2e31cb851197ea6")]
        #else
        let base = "https://ffmpeg.martin-riedl.de/download/macos/amd64/1789931006_9.0.2/"
        let archives = [("ffmpeg", "7c6b4125b191cbf773832dc51f424cf2b6bb7da43007d1e066f95909e47cacd4"),
                        ("ffprobe", "2322438ed2f6319a691291b247d09c69dcaa3a982460d1f269a7e1af335cfdfd")]
        #endif
        for (name, hash) in archives {
            progress(L.t("Скачиваю \(name) 9.0.2…", "Downloading \(name) 9.0.2…"))
            let archive = staging.appendingPathComponent(name + ".zip")
            try await download(base + name + ".zip", to: archive, sha256: hash)
            let listing = try await run("/usr/bin/unzip", ["-Z1", archive.path])
            guard listing.split(whereSeparator: \.isNewline).map(String.init) == [name] else {
                throw DropError(L.t("Неожиданное содержимое архива \(name).", "Unexpected contents in the \(name) archive."))
            }
            try await run("/usr/bin/ditto", ["-x", "-k", archive.path, payload.path])
            let binary = payload.appendingPathComponent(name)
            try requireRegularFile(binary)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        }
        progress(L.t("Проверяю подписи видео- и аудиодвижков…", "Verifying media engine signatures…"))
        try await validateMedia(at: payload)
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: payload, to: destination)
        progress(L.t("Видео и аудио готовы.", "Video and audio are ready."))
    }

    static func installOffice(progress: @escaping (String) -> Void) async throws {
        let destination = root.appendingPathComponent("LibreOffice-26.8.1.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try await validateOffice(at: destination)
            progress(L.t("Офисные форматы готовы.", "Office formats are ready.")); return
        }
        let staging = try makeStagingDirectory()
        defer { try? FileManager.default.removeItem(at: staging) }
        #if arch(arm64)
        let url = "https://download.documentfoundation.org/libreoffice/stable/26.8.1/mac/aarch64/LibreOffice_26.8.1_MacOS_aarch64.dmg"
        let hash = "ca074e0b13571efb30a31fc531c5f95e997030637325e5d5de92d67aefdf0dfc"
        #else
        let url = "https://download.documentfoundation.org/libreoffice/stable/26.8.1/mac/x86_64/LibreOffice_26.8.1_MacOS_x86-64.dmg"
        let hash = "4c7464313a529e9074400cbcdc894fc40ac4ef9421ded03b16b5a78d12cb155e"
        #endif
        progress(L.t("Скачиваю LibreOffice 26.8.1 (около 300 МБ)…", "Downloading LibreOffice 26.8.1 (about 300 MB)…"))
        let archive = staging.appendingPathComponent("LibreOffice.dmg")
        try await download(url, to: archive, sha256: hash)
        let mount = staging.appendingPathComponent("volume", isDirectory: true)
        let payload = staging.appendingPathComponent("LibreOffice.app", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: false)
        do {
            progress(L.t("Устанавливаю офисный движок…", "Installing the office engine…"))
            try await run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount.path, archive.path])
            let source = mount.appendingPathComponent("LibreOffice.app", isDirectory: true)
            try requireDirectory(source)
            try await run("/usr/bin/ditto", [source.path, payload.path])
            try await run("/usr/bin/hdiutil", ["detach", mount.path], cancellable: false)
        } catch {
            // Even a cancelled attach can have mounted the disk before it exits.
            _ = try? await run("/usr/bin/hdiutil", ["detach", mount.path], cancellable: false)
            throw error
        }
        progress(L.t("Проверяю подпись LibreOffice…", "Verifying the LibreOffice signature…"))
        try await validateOffice(at: payload)
        try Task.checkCancellation()
        // FileManager refuses an existing destination; never replace an unknown engine.
        try FileManager.default.moveItem(at: payload, to: destination)
        progress(L.t("Офисные форматы готовы.", "Office formats are ready."))
    }

    private static func makeStagingDirectory() throws -> URL {
        try Task.checkCancellation()
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let capacity = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = capacity.volumeAvailableCapacityForImportantUsage, available < 2_000_000_000 {
            throw DropError(L.t("Для установки движков освободите минимум 2 ГБ на диске.", "Free at least 2 GB of disk space to install the engines."))
        }
        let staging = root.appendingPathComponent(".install-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return staging
    }

    private static func download(_ address: String, to destination: URL, sha256 expected: String) async throws {
        try Task.checkCancellation()
        let url = URL(string: address)!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 900
        let session = URLSession(configuration: configuration, delegate: EngineHTTPSDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let result: (URL, URLResponse)
        do { result = try await session.download(from: url) }
        catch { try Task.checkCancellation(); throw error }
        let (temporary, response) = result
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme?.lowercased() == "https" else {
            throw DropError(L.t("Сервер не отдал установщик по HTTPS. Попробуйте позже.", "The server did not provide the installer over HTTPS. Try again later."))
        }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: temporary, to: destination)
        let handle = try FileHandle(forReadingFrom: destination)
        defer { try? handle.close() }
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            digest.update(data: chunk)
        }
        let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            throw DropError(L.t("Контрольная сумма установщика не совпадает. Установка отменена.", "The installer checksum does not match. Installation cancelled."))
        }
    }

    private static func validateMedia(at directory: URL) async throws {
        try requireDirectory(directory)
        for name in ["ffmpeg", "ffprobe"] {
            let binary = directory.appendingPathComponent(name)
            try requireRegularFile(binary)
            try await verifySignature(binary, team: "KU3N25YGLU")
            let version = try await run(binary.path, ["-version"])
            guard version.hasPrefix("\(name) version 9.0.2") else {
                throw DropError(L.t("Неверная версия управляемого движка \(name).", "The managed \(name) engine has an unexpected version."))
            }
        }
    }

    private static func validateOffice(at app: URL) async throws {
        try requireDirectory(app)
        try await verifySignature(app, team: "7P5S3ZLCN7", deep: true)
        let binary = app.appendingPathComponent("Contents/MacOS/soffice")
        try requireRegularFile(binary)
        let profile = FileManager.default.temporaryDirectory.appendingPathComponent("citrus-office-check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: profile) }
        let version = try await run(binary.path, ["-env:UserInstallation=" + profile.absoluteString, "--headless", "--version"])
        guard version.hasPrefix("LibreOffice 26.8.1") else {
            throw DropError(L.t("Неверная версия управляемого LibreOffice.", "The managed LibreOffice engine has an unexpected version."))
        }
    }

    private static func verifySignature(_ url: URL, team: String, deep: Bool = false) async throws {
        let requirement = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        try await run("/usr/bin/codesign", ["--verify", "--strict"] + (deep ? ["--deep"] : []) + ["-R=" + requirement, url.path])
    }

    private static func requireRegularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw DropError(L.t("Небезопасный файл движка: ", "Unsafe engine file: ") + url.lastPathComponent)
        }
    }

    private static func requireDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw DropError(L.t("Небезопасная папка движка: ", "Unsafe engine directory: ") + url.lastPathComponent)
        }
    }

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String], cancellable: Bool = true) async throws -> String {
        let command = EngineInstallProcess(executable, arguments)
        if !cancellable { return try await command.run() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await command.run()
        } onCancel: { command.cancel() }
    }
}

private final class EngineHTTPSDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme?.lowercased() == "https" ? request : nil)
    }
}

/// Process output goes to a file so a verbose tool cannot fill a pipe and hang setup.
private final class EngineInstallProcess: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var cancelled = false

    init(_ executable: String, _ arguments: [String]) {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        // LibreOffice startup can otherwise regenerate signed, bundled Python caches.
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = environment
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if process.isRunning { process.terminate() }
    }

    func run() async throws -> String {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("citrus-install-log-" + UUID().uuidString)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let output = try FileHandle(forWritingTo: log)
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if cancelled {
                lock.unlock(); try? output.close(); try? FileManager.default.removeItem(at: log)
                continuation.resume(throwing: CancellationError()); return
            }
            process.standardOutput = output; process.standardError = output
            process.terminationHandler = { [self] process in
                try? output.close()
                var message = ""
                if let input = try? FileHandle(forReadingFrom: log) {
                    if let length = try? input.seekToEnd() {
                        try? input.seek(toOffset: length > 16_384 ? length - 16_384 : 0)
                        message = String(decoding: (try? input.readToEnd()) ?? Data(), as: UTF8.self)
                    }
                    try? input.close()
                }
                try? FileManager.default.removeItem(at: log)
                lock.lock(); let wasCancelled = cancelled; lock.unlock()
                process.terminationHandler = nil
                if wasCancelled { continuation.resume(throwing: CancellationError()) }
                else if process.terminationStatus != 0 {
                    continuation.resume(throwing: DropError("\(process.executableURL?.lastPathComponent ?? "Installer"): \(message.suffix(1800))"))
                } else { continuation.resume(returning: message) }
            }
            do { try process.run(); lock.unlock() }
            catch {
                process.terminationHandler = nil; lock.unlock()
                try? output.close(); try? FileManager.default.removeItem(at: log)
                continuation.resume(throwing: error)
            }
        }
    }
}
