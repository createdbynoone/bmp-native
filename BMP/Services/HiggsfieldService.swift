import Foundation

struct HFJob: Decodable {
    let id: String
    let status: String
    let result_url: String?
    let min_result_url: String?
}

enum HiggsfieldError: LocalizedError {
    case noJobId
    case failed
    case nsfw
    case timeout
    case noResult

    var errorDescription: String? {
        switch self {
        case .noJobId: return "Higgsfield: no job id returned"
        case .failed: return "Higgsfield: generation failed (credits refunded)"
        case .nsfw: return "Higgsfield: rejected by content moderation (credits refunded)"
        case .timeout: return "Timeout: job exceeded 10 minutes"
        case .noResult: return "No file in response"
        }
    }
}

// Image/video generation goes through the official `higgsfield` CLI — auth is a
// one-time OAuth browser login, billed against the user's own plan. Every call
// appends --json and parses stdout.
enum Higgsfield {
    static let bin = "higgsfield"

    static var isInstalled: Bool { Shell.resolve(bin) != nil }

    private static func json(_ args: [String]) async throws -> Any {
        let r = try await Shell.run(bin, args + ["--json"])
        return try JSONSerialization.jsonObject(with: Data(r.stdout.utf8))
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ args: [String]) async throws -> T {
        let r = try await Shell.run(bin, args + ["--json"])
        return try JSONDecoder().decode(T.self, from: Data(r.stdout.utf8))
    }

    // A fresh OAuth login has no workspace selected; solo accounts only have one.
    static func ensureWorkspaceSelected() async throws {
        if let status = try? await json(["workspace", "status"]) as? [String: Any], status["id"] != nil { return }
        if let list = try await json(["workspace", "list"]) as? [[String: Any]],
           let first = list.first?["id"] as? String {
            try await Shell.run(bin, ["workspace", "set", first])
        }
    }

    static func isAuthenticated() async -> Bool {
        guard FileManager.default.fileExists(atPath: AppPaths.higgsfieldCredentials.path) else { return false }
        do { try await ensureWorkspaceSelected(); return true } catch { return false }
    }

    static func login() async throws {
        try await Shell.run(bin, ["auth", "login"], timeout: 120)
        try await ensureWorkspaceSelected()
    }

    // `credits` comes back as a decimal (e.g. 509.5) — bridging it `as? Int` fails
    // and left the footer/settings showing no balance at all.
    static func credits() async -> (credits: Double?, plan: String?) {
        guard let status = try? await json(["account", "status"]) as? [String: Any] else { return (nil, nil) }
        return ((status["credits"] as? NSNumber)?.doubleValue, status["subscription_plan_type"] as? String)
    }

    static func upload(_ path: String) async throws -> String {
        guard let r = try await json(["upload", "create", path]) as? [String: Any],
              let id = r["id"] as? String else { throw HiggsfieldError.noResult }
        return id
    }

    /// Ordered param list → `--flag-name=value` args. Arrays become repeated flags
    /// (order preserved). The `=` form is required for cobra bool flags.
    static func args(_ params: [(String, Any?)]) -> [String] {
        var out: [String] = []
        for (key, value) in params {
            guard let value else { continue }
            let flag = "--" + key.replacingOccurrences(of: "_", with: "-")
            if let arr = value as? [Any] {
                for v in arr { out.append("\(flag)=\(v)") }
            } else {
                out.append("\(flag)=\(value)")
            }
        }
        return out
    }

    /// `generate create` (no --wait) then poll `generate get`, 10 min cap. Each poll
    /// is a CLI process + TLS handshake, so the interval backs off once a job is
    /// clearly a long one: 2s → 3s for the first 45s → 5s after that.
    static func generate(_ jobType: String, _ params: [(String, Any?)], progress: @escaping (String) -> Void) async throws -> HFJob {
        let ids = try await decode([String].self, ["generate", "create", jobType] + args(params))
        guard let jobId = ids.first else { throw HiggsfieldError.noJobId }

        var last = ""
        let start = Date()
        var elapsed: TimeInterval = 0
        while elapsed < 600 {
            let wait: TimeInterval = elapsed == 0 ? 2 : elapsed < 45 ? 3 : 5
            try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            let job = try await decode(HFJob.self, ["generate", "get", jobId])
            elapsed = Date().timeIntervalSince(start)
            if job.status != last { progress("\(job.status) · \(Int(elapsed.rounded()))s"); last = job.status }
            switch job.status {
            case "completed": return job
            case "failed": throw HiggsfieldError.failed
            case "nsfw": throw HiggsfieldError.nsfw
            default: continue
            }
        }
        throw HiggsfieldError.timeout
    }
}
