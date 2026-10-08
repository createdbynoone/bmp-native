import Foundation

enum Provider: String, CaseIterable, Identifiable {
    case seedream, nanobanana, nanobanana21
    var id: String { rawValue }

    var shortLabel: String {
        switch self { case .seedream: "Seedream"; case .nanobanana: "NB Pro"; case .nanobanana21: "NB 2.1" }
    }
    var label: String {
        switch self { case .seedream: "Seedream 5.0 Pro"; case .nanobanana: "Nano Banana Pro"; case .nanobanana21: "Nano Banana 2.1" }
    }
    var slug: String {
        switch self { case .seedream: "seedream-5.0-pro"; case .nanobanana: "nano-banana-pro"; case .nanobanana21: "nano-banana-2.1" }
    }
    var jobType: String {
        switch self { case .seedream: "seedream_v5_pro"; case .nanobanana: "nano_banana_pro"; case .nanobanana21: "nano_banana_2_1" }
    }

    // Seedream 5.0 Pro has no 4:5 in its aspect_ratio enum (3:4 is its closest
    // portrait). First entry is the provider default.
    var ratios: [String] { self == .seedream ? ["3:4", "9:16"] : ["4:5", "9:16"] }
    var resolutions: [String] { self == .seedream ? ["1k", "2k"] : ["1k", "2k", "4k"] }
    var maxRefs: Int { self == .seedream ? 10 : 14 }

    /// Extra CLI params that only this model understands (Nano Banana 2.1 "thinks"
    /// before rendering; `high` follows dense garment/layout specs far better).
    var extraParams: [(String, Any?)] { self == .nanobanana21 ? [("thinking_level", "high")] : [] }
}

enum FireStatus: Equatable { case idle, loading, done, error }
enum GenerateStatus: Equatable { case idle, loading, done, error }

struct LogEntry: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let line: String

    enum Kind { case ok, error, warn, action, plain }
    var kind: Kind {
        if line.contains("✓") || line.hasPrefix("Saved") || (line.hasPrefix("All ") && line.contains("generated")) { return .ok }
        if line.lowercased().hasPrefix("error") || line.contains("failed") || line.hasPrefix("Rate limit") || line.contains("no llegó") || line.contains("No se pudo") { return .error }
        if line.hasPrefix("Warning") || line.contains("accepts max") || (line.contains("/") && line.contains("generated,")) { return .warn }
        if line.hasPrefix("▶") { return .action }
        return .plain
    }
}
