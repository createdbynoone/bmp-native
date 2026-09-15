import SwiftUI
import AppKit

// Pulsing dot driven by Core Animation. A SwiftUI `repeatForever` animation keeps
// the entire view graph re-rendering at display rate for as long as it runs
// (measured ~45 % CPU on an idle grid); a CABasicAnimation on a layer costs the
// main thread nothing — the render server does the fading.
struct PulseDot: NSViewRepresentable {
    var color: Color
    var size: CGFloat = 5
    var ring = false          // hairline ring instead of a filled dot

    func makeNSView(context: Context) -> PulseLayerView {
        let v = PulseLayerView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        v.apply(color: NSColor(color), size: size, ring: ring)
        return v
    }
    func updateNSView(_ v: PulseLayerView, context: Context) { v.apply(color: NSColor(color), size: size, ring: ring) }

    final class PulseLayerView: NSView {
        private var size: CGFloat = 5
        override var intrinsicContentSize: NSSize { NSSize(width: size, height: size) }

        override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
        required init?(coder: NSCoder) { nil }

        func apply(color: NSColor, size: CGFloat, ring: Bool) {
            self.size = size
            guard let layer else { return }
            layer.cornerRadius = size / 2
            if ring { layer.borderColor = color.cgColor; layer.borderWidth = 1; layer.backgroundColor = nil }
            else { layer.backgroundColor = color.cgColor; layer.borderWidth = 0 }
            invalidateIntrinsicContentSize()
            pulse()
        }

        // CA drops animations when a layer leaves the tree — re-arm on every attach.
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); pulse() }

        private func pulse() {
            guard let layer, window != nil, layer.animation(forKey: "pulse") == nil else { return }
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1; a.toValue = 0.35
            a.duration = 0.9; a.autoreverses = true; a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(a, forKey: "pulse")
        }
    }
}

// Native segmented picker with a small eyebrow above it — the one control
// pattern the whole fire bar is built from.
struct Segment<T: Hashable>: View {
    let title: String
    let options: [T]
    @Binding var selection: T
    var display: (T) -> String = { "\($0)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(Theme.label(9.5)).tracking(1.2).foregroundStyle(Theme.muted)
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { o in
                    Text(display(o)).font(.system(size: 11, weight: .medium)).monospacedDigit().tag(o)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
        }
    }
}

// Fire button: native bordered button whose tint follows the task state.
struct FireButton: View {
    let status: FireStatus
    let running: Int
    let disabled: Bool
    let title: String
    let action: () -> Void

    private var tint: Color {
        switch status {
        case .loading: return Theme.accent
        case .done: return Theme.ok
        case .error: return Theme.danger
        case .idle: return Theme.accent
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                switch status {
                case .loading:
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
                    Text("Generating\(running > 1 ? " ×\(running)" : "")")
                    if !disabled { Text("· fire again").foregroundStyle(.secondary) }
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                    Text("Done · fire again")
                case .error:
                    Image(systemName: "exclamationmark.circle")
                    Text("Error · retry")
                case .idle:
                    Image(systemName: "bolt.fill")
                    Text(title)
                }
            }
            .font(.system(size: 12.5, weight: .semibold))
            .frame(minWidth: 190)
            .padding(.vertical, 2)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(tint)
        .disabled(disabled)
        .keyboardShortcut(.return, modifiers: [.command, .shift])
        .help(status == .loading && !disabled ? "Task keeps running in background. Click to fire another batch in parallel" : "Fire to Higgsfield  ⌘⇧↩")
    }
}
