import SwiftUI
import AppKit

// ── Settings (native Settings scene, ⌘,) ──────────────────────────────────
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Output folder") {
                LabeledContent("Folder") {
                    HStack(spacing: 8) {
                        Text(model.outputPath)
                            .font(Theme.mono(11)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: 260, alignment: .trailing)
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
                            panel.directoryURL = URL(fileURLWithPath: model.outputPath)
                            panel.prompt = "Use folder"
                            if panel.runModal() == .OK, let url = panel.url { model.setOutputPath(url.path) }
                        }
                    }
                }
                Text("Las imágenes generadas por Higgsfield se guardan en esta carpeta.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("Tools") {
                LabeledContent("claude", value: Shell.resolve("claude") ?? "not found")
                LabeledContent("higgsfield", value: Shell.resolve("higgsfield") ?? "not found")
                LabeledContent("Higgsfield credits") {
                    HStack(spacing: 8) {
                        Text(model.credits.credits.map { "\($0) cr" } ?? "—")
                        Button("Refresh") { Task { await model.refreshCredits() } }.controlSize(.small)
                        Button("Log in") { model.showLogin = true; Task { try? await Higgsfield.login(); model.showLogin = false; await model.refreshCredits() } }.controlSize(.small)
                    }
                }
            }
            Section("Memory") {
                LabeledContent("Prompts stored", value: "\(model.memoryStats.total) · ★ \(model.memoryStats.fired) fired")
                LabeledContent("Data folder") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.memory]) }.controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// ── Prompt history ────────────────────────────────────────────────────────
struct HistorySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [MemoryEntry] = []
    @State private var query = ""
    @State private var selected: MemoryEntry.ID?

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_CO"); f.dateFormat = "d MMM · HH:mm"; return f
    }()

    private var filtered: [MemoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? entries : entries.filter { $0.description.lowercased().contains(q) || $0.prompt.lowercased().contains(q) }
    }
    private var current: MemoryEntry? { filtered.first { $0.id == selected } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Prompt history").font(.system(size: 13, weight: .semibold))
                Spacer()
                TextField("Search", text: $query).textFieldStyle(.roundedBorder).frame(width: 220)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()

            HSplitView {
                List(filtered, selection: $selected) { e in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            if e.fired { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Theme.accent) }
                            Text(e.description).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        }
                        Text(Self.df.string(from: e.date) + (e.aspectRatio.map { " · \($0)" } ?? ""))
                            .font(Theme.mono(10)).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .tag(e.id)
                }
                .listStyle(.inset)
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)

                VStack(alignment: .leading, spacing: 10) {
                    if let e = current {
                        Text(e.description).font(.system(size: 12.5, weight: .semibold))
                        ScrollView {
                            Text(e.prompt).font(.system(size: 12.5)).lineSpacing(3)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text("Select a prompt").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(16)
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 420)

            Divider()
            HStack {
                Text("\(filtered.count) prompts").font(Theme.mono(10.5)).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Use prompt") { if let e = current { model.usePrompt(e.prompt) }; dismiss() }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .disabled(current == nil)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(width: 720)
        .onAppear { entries = MemoryStore.entries(); selected = entries.first?.id }
    }
}

// ── Higgsfield login ──────────────────────────────────────────────────────
struct LoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Higgsfield login", systemImage: "person.badge.key").font(.system(size: 13, weight: .semibold))
            Text("Completa el login en la ventana del navegador que se abrió, o corre `higgsfield auth login` en una terminal.")
                .font(.system(size: 12.5)).foregroundStyle(.secondary).lineSpacing(3)
            HStack { Spacer(); Button("Listo") { dismiss() }.buttonStyle(.borderedProminent).tint(Theme.accent).keyboardShortcut(.defaultAction) }
        }
        .padding(20)
        .frame(width: 380)
    }
}
