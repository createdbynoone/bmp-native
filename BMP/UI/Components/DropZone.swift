import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO

// ── Finder drag & drop → file URLs (images only) ─────────────────────────
enum FileDrop {
    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff", "gif", "bmp", "avif"]

    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var out: [URL] = []
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url: URL? = await withCheckedContinuation { cont in
                p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let data = item as? Data, let u = URL(dataRepresentation: data, relativeTo: nil) { cont.resume(returning: u) }
                    else if let u = item as? URL { cont.resume(returning: u) }
                    else { cont.resume(returning: nil) }
                }
            }
            if let url, imageExts.contains(url.pathExtension.lowercased()) { out.append(url) }
        }
        return out
    }
}

// ── Thumbnail loader (downsampled, cached) ────────────────────────────────
// Nonisolated async → runs on the cooperative pool, never on the main actor.
enum Thumbs {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.totalCostLimit = 48 * 1024 * 1024   // ~0.4 MB per 320px thumb → ~120 refs
        return c
    }()

    static func load(_ path: String, maxPixel: Int = 320) async -> NSImage? {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        if Task.isCancelled { return nil }     // thumb removed before we got to it
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(img, forKey: path as NSString, cost: cg.bytesPerRow * cg.height)
        return img
    }
}

struct Thumb: View {
    let path: String
    var size: CGFloat = 56
    var badge: String? = nil
    var highlighted = false
    var onRemove: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil
    @State private var image: NSImage?
    @State private var hover = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Theme.raised)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(highlighted ? Theme.accent.opacity(0.7) : (hover ? Theme.hairlineStrong : Theme.hairline)))
            .overlay(alignment: .bottom) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(highlighted ? Theme.bg : Theme.text.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                        .background(highlighted ? Theme.accent.opacity(0.9) : Color.black.opacity(0.65))
                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }

            if let onRemove, hover {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(Color.black.opacity(0.85)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.2)))
                }
                .buttonStyle(.plain)
                .offset(x: 3, y: -3)
                .transition(.opacity)
            }
        }
        .trackHover($hover)
        .task(id: path) { image = await Thumbs.load(path) }
    }
}

// ── Drop zone ─────────────────────────────────────────────────────────────
struct DropZone: View {
    let placeholder: String
    @Binding var files: [String]
    var onDrop: ([URL]) -> Void
    var max: Int? = nil
    @State private var targeted = false

    var body: some View {
        Group {
            if files.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(targeted ? Theme.text : Theme.muted)
                    Text(placeholder.uppercased())
                        .font(Theme.label(10)).tracking(1.2)
                        .foregroundStyle(targeted ? Theme.text : Theme.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 74)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(files.enumerated()), id: \.offset) { i, f in
                            Thumb(path: f, onRemove: { files.remove(at: i) })
                        }
                        if max == nil || files.count < max! {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .frame(width: 56, height: 56)
                                .overlay(Image(systemName: "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.muted))
                        }
                    }
                    .padding(2)
                }
                .frame(minHeight: 60)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .fill(targeted ? Color.white.opacity(0.04) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .strokeBorder(targeted ? Theme.hairlineStrong : (files.isEmpty ? Theme.hairline : .clear),
                              style: StrokeStyle(lineWidth: 1, dash: files.isEmpty ? [4, 4] : []))
        )
        .animation(Theme.ease, value: targeted)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            Task {
                let urls = await FileDrop.urls(from: providers)
                if !urls.isEmpty { await MainActor.run { onDrop(urls) } }
            }
            return true
        }
    }
}
