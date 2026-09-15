import SwiftUI
import AppKit

// ── Activity log ──────────────────────────────────────────────────────────
struct ActivityLogView: View {
    let entries: [LogEntry]
    let running: Int
    let onClear: () -> Void

    private static let time: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    private func color(_ k: LogEntry.Kind) -> Color {
        switch k {
        case .ok: return Theme.ok
        case .error: return Theme.danger
        case .warn: return Theme.warn
        case .action: return Theme.accent
        case .plain: return Theme.secondary
        }
    }

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    Eyebrow(text: "Activity", hint: running > 0 ? "\(running) running" : nil)
                    if running > 0 { PulseDot(color: Theme.accent, size: 5).frame(width: 5, height: 5) }
                    Spacer()
                    Button("Clear", action: onClear).buttonStyle(.accessoryBar).controlSize(.small)
                }
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)
                Hairline()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(entries) { e in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(Self.time.string(from: e.date))
                                        .font(Theme.mono(10.5)).foregroundStyle(Theme.muted)
                                    Text(e.line)
                                        .font(Theme.mono(11))
                                        .foregroundStyle(color(e.kind))
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .id(e.id)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: entries.count) { _, _ in
                        if let last = entries.last { withAnimation(Theme.ease) { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
            }
        }
    }
}

// ── Prompt output ─────────────────────────────────────────────────────────
struct PromptOutputView: View {
    let prompt: String
    @State private var copied = false

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    Eyebrow(text: "Prompt", hint: "\(prompt.count) chars")
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(prompt, forType: .string)
                        withAnimation(Theme.ease) { copied = true }
                        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); withAnimation(Theme.ease) { copied = false } }
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.accessoryBar).controlSize(.small)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                }
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)
                Hairline()
                ScrollView {
                    Text(prompt)
                        .font(.system(size: 13))
                        .lineSpacing(4)
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
            }
        }
    }
}

// ── Empty state ───────────────────────────────────────────────────────────
struct EmptyState: View {
    let steps: [String]
    var body: some View {
        VStack(spacing: 14) {
            BrandMark(size: 34, color: Theme.muted).padding(.bottom, 8)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(spacing: 10) {
                    Text(String(format: "%02d", i + 1)).font(Theme.mono(10.5)).foregroundStyle(Theme.muted)
                    Text(s).font(Theme.body(12.5)).foregroundStyle(Theme.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ── Plain multi-line editor with placeholder ─────────────────────────────
struct Editor: View {
    @Binding var text: String
    let placeholder: String
    var font: Font = Theme.body(13.5)
    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder).font(font).foregroundStyle(Theme.muted).lineSpacing(3)
                    .padding(.top, 0).padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(font)
                .lineSpacing(3)
                .foregroundStyle(Theme.text)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
        }
    }
}

// ── Credits ring ──────────────────────────────────────────────────────────
struct CreditsRing: View {
    let credits: Int
    let plan: String?
    private let maxCredits = 1000.0
    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 2)
                Circle().trim(from: 0, to: min(Double(credits) / maxCredits, 1))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 12, height: 12)
            Text("\(credits) cr").font(Theme.mono(10.5)).foregroundStyle(Theme.secondary).monospacedDigit()
            if let plan, !plan.isEmpty {
                Text(plan.uppercased()).font(Theme.mono(10)).tracking(1).foregroundStyle(Theme.muted)
            }
        }
    }
}
