import SwiftUI

// Native window: standard title bar + unified toolbar (title/subtitle, toolbar
// buttons, ⌘-shortcuts in the menu bar), resizable split between inputs and
// output, fire controls in a bottom bar, status line in the footer.
struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var m = model
        VStack(spacing: 0) {
            if !model.missingTools.isEmpty { MissingToolsBar(tools: model.missingTools) }

            HSplitView {
                InputsColumn()
                    .frame(minWidth: 320, idealWidth: 360, maxWidth: 460)
                OutputColumn()
                    .frame(minWidth: 420, maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            FireBar()
            Divider()
            FooterBar()
        }
        .background(Theme.bg)
        .navigationTitle("BMP")
        .navigationSubtitle("Brotherhood Marketing Prompts")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.showHistory = true } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                    .help("Prompt history  ⌘Y")
                    .keyboardShortcut("y", modifiers: .command)
                Button { model.reset() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                    .help("Reset inputs  ⌘R")
                    .keyboardShortcut("r", modifiers: .command)
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                    .help("Settings  ⌘,")
            }
        }
        .sheet(isPresented: $m.showHistory) { HistorySheet() }
        .sheet(isPresented: $m.showLogin) { LoginSheet() }
    }
}

struct MissingToolsBar: View {
    let tools: [String]
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Falta el CLI \(tools.joined(separator: " y ")) — instala con `npm i -g @anthropic-ai/claude-code @higgsfield/cli` y reabre BMP.")
                .font(Theme.mono(11))
            Spacer()
        }
        .foregroundStyle(Theme.warn)
        .padding(.horizontal, 16).padding(.vertical, 7)
        .background(Theme.warn.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }
}

// ── Inputs ────────────────────────────────────────────────────────────────
struct InputsColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var m = model
        ScrollView {
            VStack(spacing: 12) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "References", hint: "composition · mood")
                        DropZone(placeholder: "Drop references", files: $m.refs) { model.addRefs($0) }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Product", hint: "Brotherhood garment")
                        DropZone(placeholder: "Drop product", files: $m.products) { model.addProducts($0) }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Brief")
                        Editor(text: $m.brief, placeholder: "Gorra en ola de playa, luz dorada al atardecer")
                            .frame(minHeight: 72, maxHeight: 140)
                    }
                }

                Button { model.generate() } label: {
                    HStack(spacing: 8) {
                        if model.generateStatus == .loading {
                            ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
                            Text("Generating with Claude…")
                        } else {
                            Image(systemName: "text.badge.star")
                            Text("Generate prompt")
                        }
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)
                .disabled(!model.canGenerate || model.generateStatus == .loading)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Generate prompt  ⌘↩")

                if !model.generateError.isEmpty {
                    Text(model.generateError)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.danger)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Theme.danger.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
    }
}

// ── Output ────────────────────────────────────────────────────────────────
struct OutputColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            if !model.prompt.isEmpty {
                PromptOutputView(prompt: model.prompt)
                    .frame(maxHeight: .infinity)
                    .layoutPriority(model.showLog ? 3 : 1)
            }
            if model.showLog {
                ActivityLogView(entries: model.log, running: model.tasks) { model.clearLog() }
                    .frame(minHeight: 120, maxHeight: model.prompt.isEmpty ? .infinity : 260)
            }
            if model.prompt.isEmpty && !model.showLog {
                EmptyState(steps: ["Drop references and the product", "Write a short brief", "Generate, then fire to Higgsfield"])
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface.opacity(0.5))
        .animation(Theme.ease, value: model.prompt.isEmpty)
        .animation(Theme.ease, value: model.showLog)
    }
}

// ── Fire bar ──────────────────────────────────────────────────────────────
struct FireBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var m = model
        HStack(alignment: .bottom, spacing: 16) {
            Segment(title: "Engine", options: Provider.allCases,
                    selection: Binding(get: { model.provider }, set: { model.setProvider($0) }),
                    display: { $0.shortLabel })
            Segment(title: "Ratio", options: model.provider.ratios, selection: $m.aspectRatio)
            Segment(title: "Resolution", options: model.provider.resolutions, selection: $m.resolution, display: { $0.uppercased() })
            Segment(title: "Variations", options: [1, 2, 3, 4], selection: $m.variations, display: { "×\($0)" })
            Spacer(minLength: 8)
            FireButton(status: model.fireStatus, running: model.tasks, disabled: !model.canFire,
                       title: "\(model.provider.label)\(model.variations > 1 ? "  ×\(model.variations)" : "")") { model.fire() }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }
}

// ── Footer ────────────────────────────────────────────────────────────────
struct FooterBar: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack {
            Text(model.footerLabel.uppercased()).font(Theme.mono(10.5)).tracking(1.2).foregroundStyle(Theme.muted)
            Spacer()
            HStack(spacing: 14) {
                if model.memoryStats.total > 0 {
                    HStack(spacing: 4) {
                        Text("memory \(model.memoryStats.total)").font(Theme.mono(10.5)).foregroundStyle(Theme.muted)
                        Text("·").foregroundStyle(Theme.muted)
                        Text("★ \(model.memoryStats.fired) fired").font(Theme.mono(10.5)).foregroundStyle(Theme.accent.opacity(0.75))
                    }
                }
                if let c = model.credits.credits { CreditsRing(credits: c, plan: model.credits.plan) }
                Text("v\(model.appVersion)").font(Theme.mono(10.5)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(.bar)
    }
}
