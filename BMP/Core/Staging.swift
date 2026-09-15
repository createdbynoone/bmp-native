import Foundation

// Dropped files keep their original names (camera IDs, Pinterest slugs, accented
// Spanish text). Claude reads the filename as text next to the image, and a loaded
// name can bias the description. Staging a copy under a neutral "imageN" name
// removes that bias and sidesteps the macOS NFC/NFD accent mismatch entirely.
enum Staging {
    private static let root: URL = {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bmp-staged-refs", isDirectory: true)
    }()
    private static var counter = 0
    private static let lock = NSLock()

    static func reset() {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        counter = 0
    }

    static func stage(_ urls: [URL]) throws -> [String] {
        try urls.map { original in
            guard FileManager.default.fileExists(atPath: original.path) else {
                throw NSError(domain: "BMP", code: 1, userInfo: [NSLocalizedDescriptionKey: "File not found: \(original.lastPathComponent)"])
            }
            var ext = original.pathExtension.lowercased()
            if ext.isEmpty { ext = "jpg" }
            lock.lock(); counter += 1; let n = counter; lock.unlock()
            let staged = root.appendingPathComponent("image\(n).\(ext)")
            try FileManager.default.copyItem(at: original, to: staged)
            return staged.path
        }
    }
}
