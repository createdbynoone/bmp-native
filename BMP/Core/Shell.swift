import Foundation

struct ShellResult {
    let stdout: String
    let stderr: String
    let status: Int32
}

enum ShellError: LocalizedError {
    case binaryNotFound(String)
    case failed(bin: String, status: Int32, stderr: String)
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let bin):
            return "`\(bin)` no está instalado o no está en el PATH (\(Shell.searchPath.joined(separator: ":")))"
        case .failed(let bin, let status, let stderr):
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return msg.isEmpty ? "\(bin) salió con código \(status)" : msg
        case .timeout(let bin):
            return "\(bin) excedió el tiempo de espera"
        }
    }
}

// GUI apps don't inherit the login-shell PATH, so `claude` / `higgsfield`
// are resolved against the usual install locations manually.
enum Shell {
    static let searchPath: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs = [
            "\(home)/.local/bin",       // claude CLI
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/bin",
            "/bin",
        ]
        if let inherited = ProcessInfo.processInfo.environment["PATH"] {
            dirs += inherited.split(separator: ":").map(String.init)
        }
        return dirs
    }()

    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath.joined(separator: ":")
        // A leftover ANTHROPIC_API_KEY would make the claude CLI bill per-token
        // instead of using the logged-in subscription session.
        env.removeValue(forKey: "ANTHROPIC_API_KEY")
        return env
    }

    static func resolve(_ bin: String) -> String? {
        if bin.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: bin) ? bin : nil }
        for dir in searchPath {
            let candidate = "\(dir)/\(bin)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        func append(_ chunk: Data) { lock.lock(); buffer.append(chunk); lock.unlock() }
        var data: Data { lock.lock(); defer { lock.unlock() }; return buffer }
    }
    private final class Watchdog: @unchecked Sendable { var timedOut = false; var timer: DispatchWorkItem? }

    // readabilityHandler delivers chunks on the handle's own queue as they arrive —
    // no GCD thread sits blocked in readDataToEndOfFile for the life of the process.
    private static func drain(_ pipe: Pipe, into sink: Sink, group: DispatchGroup) {
        group.enter()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {                 // EOF: writer closed
                handle.readabilityHandler = nil
                group.leave()
            } else {
                sink.append(chunk)
            }
        }
    }

    /// Runs `bin args...`, capturing stdout/stderr. Throws on non-zero exit.
    @discardableResult
    static func run(_ bin: String, _ args: [String], timeout: TimeInterval? = nil) async throws -> ShellResult {
        guard let exe = resolve(bin) else { throw ShellError.binaryNotFound(bin) }

        return try await withCheckedThrowingContinuation { cont in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: exe)
            process.arguments = args
            process.environment = environment()
            process.qualityOfService = .userInitiated

            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice

            let outSink = Sink(), errSink = Sink()
            let group = DispatchGroup()
            drain(out, into: outSink, group: group)
            drain(err, into: errSink, group: group)

            let dog = Watchdog()
            if let timeout {
                let item = DispatchWorkItem { dog.timedOut = true; process.terminate() }
                dog.timer = item
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
            }

            process.terminationHandler = { proc in
                dog.timer?.cancel()
                group.notify(queue: .global()) {
                    let stdout = String(decoding: outSink.data, as: UTF8.self)
                    let stderr = String(decoding: errSink.data, as: UTF8.self)
                    if dog.timedOut {
                        cont.resume(throwing: ShellError.timeout(bin))
                    } else if proc.terminationStatus != 0 {
                        cont.resume(throwing: ShellError.failed(bin: bin, status: proc.terminationStatus, stderr: stderr))
                    } else {
                        cont.resume(returning: ShellResult(stdout: stdout, stderr: stderr, status: proc.terminationStatus))
                    }
                }
            }

            do { try process.run() } catch { cont.resume(throwing: error) }
        }
    }
}
