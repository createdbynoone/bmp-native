import Foundation
import ImageIO

enum Downloader {
    static func download(_ urlString: String, to dest: URL) async throws {
        guard urlString.hasPrefix("https://"), let url = URL(string: urlString) else {
            throw NSError(domain: "BMP", code: 2, userInfo: [NSLocalizedDescriptionKey: "Only HTTPS downloads are allowed"])
        }
        let (tmp, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "BMP", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Download failed (HTTP \(http.statusCode))"])
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
    }

    /// File extension from a result URL, falling back when it isn't a short clean one.
    static func ext(of urlString: String, fallback: String) -> String {
        guard let url = URL(string: urlString) else { return fallback }
        let e = url.pathExtension.lowercased()
        return (e.isEmpty || e.count > 4) ? fallback : e
    }

    static func pixelSize(of path: String) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }
}
