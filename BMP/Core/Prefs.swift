import Foundation

// Same files the Electron build uses (~/Library/Application Support/BMP/), so
// prompt history and the output folder carry over between the two apps.
enum AppPaths {
    static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("BMP", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static var prefs: URL { supportDir.appendingPathComponent("bmp-prefs.json") }
    static var memory: URL { supportDir.appendingPathComponent("bmp-memory.json") }
    static var higgsfieldCredentials: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/higgsfield/credentials.json")
    }
    static var defaultOutput: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path
    }
}

struct Prefs: Codable {
    var iconStyle: String = "Default"
    var outputPath: String = AppPaths.defaultOutput
    var unlockedAt: String?
    var authFailCount: Int?
    var authLockUntil: Double?   // ms since epoch, like the Electron build

    static func load() -> Prefs {
        guard let data = try? Data(contentsOf: AppPaths.prefs),
              let decoded = try? JSONDecoder().decode(Prefs.self, from: data) else { return Prefs() }
        return decoded
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) { try? data.write(to: AppPaths.prefs, options: .atomic) }
    }
}
