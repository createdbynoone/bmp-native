import Foundation

enum Provider: String, CaseIterable, Identifiable {
    case seedream, nanobanana
    var id: String { rawValue }

    var shortLabel: String { self == .seedream ? "Seedream" : "NB Pro" }
    var label: String { self == .seedream ? "Seedream 5.0 Pro" : "Nano Banana Pro" }
    var slug: String { self == .seedream ? "seedream-5.0-pro" : "nano-banana-pro" }
    var jobType: String { self == .seedream ? "seedream_v5_pro" : "nano_banana_pro" }

    // Seedream 5.0 Pro has no 4:5 in its aspect_ratio enum (3:4 is its closest
    // portrait). First entry is the provider default.
    var ratios: [String] { self == .seedream ? ["3:4", "9:16"] : ["4:5", "9:16"] }
    var resolutions: [String] { self == .seedream ? ["1k", "2k"] : ["1k", "2k", "4k"] }
    var maxRefs: Int { self == .seedream ? 10 : 14 }
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
        if line.hasPrefix("Warning") || line.contains("accepts max") || (line.contains("/") && line.contains("generated —")) { return .warn }
        if line.hasPrefix("▶") { return .action }
        return .plain
    }
}
