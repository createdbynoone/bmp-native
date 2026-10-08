import Foundation
import ImageIO
import UniformTypeIdentifiers

// Dropped files keep their original names (camera IDs, Pinterest slugs, accented
// Spanish text). Claude reads the filename as text next to the image, and a loaded
// name can bias the description. Staging a copy under a neutral "imageN" name
// removes that bias and sidesteps the macOS NFC/NFD accent mismatch entirely.
//
// Staging also normalizes the image for Claude's Read tool, which only understands
// jpg/png/gif/webp: HEIC, AVIF, TIFF, BMP are re-encoded as JPEG, EXIF rotation is
// baked in, and anything above `maxEdge` is downscaled (huge files read slowly and
// get resampled by the model anyway).
enum Staging {
    private static let root: URL = {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bmp-staged-refs", isDirectory: true)
    }()
    private static let maxEdge = 2560
    private static let passthrough: Set<String> = ["jpg", "jpeg", "png", "webp", "gif"]
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

            let src = CGImageSourceCreateWithURL(original as CFURL, nil)
            let props = src.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
            let longEdge = max(props?[kCGImagePropertyPixelWidth] as? Int ?? 0, props?[kCGImagePropertyPixelHeight] as? Int ?? 0)
            let orientation = props?[kCGImagePropertyOrientation] as? Int ?? 1

            if let src, !passthrough.contains(ext) || longEdge > maxEdge || (orientation != 1 && ext != "png") {
                let opts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxEdge,
                ]
                let staged = root.appendingPathComponent("image\(n).jpg")
                if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary),
                   let dest = CGImageDestinationCreateWithURL(staged as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
                    if CGImageDestinationFinalize(dest) { return staged.path }
                }
            }
            let staged = root.appendingPathComponent("image\(n).\(ext)")
            try FileManager.default.copyItem(at: original, to: staged)
            return staged.path
        }
    }
}
