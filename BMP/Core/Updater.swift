import Foundation
import AppKit

// Update notice: the native builds are not Sparkle-enabled, so on launch we ask
// GitHub for the latest release and, if it is newer than this build, show a bar
// with a download link. Install stays manual (drag the new .app to Applications).
struct AvailableUpdate: Equatable {
    let version: String
    let url: URL
}

enum Updater {
    static let repo = "createdbynoone/bmp-native"

    private static func parts(_ v: String) -> [Int] {
        v.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0) ?? 0 }
    }

    static func isNewer(_ remote: String, than local: String) -> Bool {
        let (r, l) = (parts(remote), parts(local))
        for i in 0..<max(r.count, l.count) {
            let (a, b) = (i < r.count ? r[i] : 0, i < l.count ? l[i] : 0)
            if a != b { return a > b }
        }
        return false
    }

    /// Latest published release if newer than `current`; nil when up to date or offline.
    static func check(current: String) async -> AvailableUpdate? {
        guard let api = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var req = URLRequest(url: api, timeoutInterval: 8)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let html = obj["html_url"] as? String, let url = URL(string: html),
              isNewer(tag, than: current) else { return nil }
        return AvailableUpdate(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), url: url)
    }
}
