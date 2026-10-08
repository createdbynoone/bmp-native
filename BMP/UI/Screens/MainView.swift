import SwiftUI

// Native window: standard title bar + unified toolbar (title/subtitle, toolbar
// buttons, ⌘-shortcuts in the menu bar), resizable split between inputs and
// output, fire controls in a bottom bar, status line in the footer.
struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var m = model
        VStack(spacing: 0) {
            if let u = model.update { UpdateBar(update: u) { model.update = nil } }
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

struct UpdateBar: View {
    let update: AvailableUpdate
    let onDismiss: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.accent)
            Text("Hay una versión nueva: v\(update.version)").font(Theme.body(12))
            Button("Descargar") { NSWorkspace.shared.open(update.url) }
                .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
            Spacer()
            Button { onDismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Ocultar")
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(Theme.accent.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct MissingToolsBar: View {
    let tools: [String]
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Falta el CLI \(tools.joined(separator: " y ")). Instala con `npm i -g @anthropic-ai/claude-code @higgsfield/cli` y reabre BMP.")
                .font(Theme.body(12))
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
                        Eyebrow(text: "Reference", hint: "1 max · scene, light, mood")
                        DropZone(placeholder: "Drop reference", files: $m.refs, max: 1) { model.addRefs($0) }
                        if !model.refs.isEmpty {
                            TextField("What to take from it (light, angle, setting…)", text: $m.refSpecs, axis: .vertical)
                                .textFieldStyle(.roundedBorder).font(Theme.body(12.5)).lineLimit(1...3)
                        }
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
                        HStack {
                            Eyebrow(text: "Brief", hint: "auto · Sonnet")
                            Spacer()
                            Button { model.autoWriteBrief() } label: {
                                if model.briefLoading { ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 14, height: 14) }
                                else { Label("Auto-write", systemImage: "sparkles") }
                            }
                            .buttonStyle(.accessoryBar).controlSize(.small)
                            .disabled(!model.canAutoBrief)
                            .help("Sonnet writes the brief from the reference, product and specs")
                        }
                        Editor(text: $m.brief, placeholder: "Vacío: Sonnet lo escribe desde la referencia y el producto")
                            .frame(minHeight: 72, maxHeight: 140)
                    }
                }

                Button { model.generate() } label: {
                    HStack(spacing: 8) {
                        if model.generateStatus == .loading {
                            ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
                            Text(model.generateStage.isEmpty ? "Generating…" : model.generateStage + "…")
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
                .disabled(!model.canGenerate || model.generateStatus == .loading || model.briefLoading)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Generate prompt  ⌘↩")

                if !model.generateError.isEmpty {
                    Text(model.generateError)
                        .font(Theme.body(12))
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
                EmptyState(steps: ["Drop one reference and the product", "Add specs, or let Sonnet write the brief", "Generate with Opus, then fire to Higgsfield"])
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
            Text(model.footerLabel).font(Theme.caption(11)).foregroundStyle(Theme.muted).monospacedDigit()
            Spacer()
            HStack(spacing: 14) {
                if model.memoryStats.total > 0 {
                    HStack(spacing: 4) {
                        Text("\(model.memoryStats.total) in memory").font(Theme.caption(11)).foregroundStyle(Theme.muted).monospacedDigit()
                        Text("·").foregroundStyle(Theme.muted)
                        Text("★ \(model.memoryStats.fired) fired").font(Theme.caption(11)).foregroundStyle(Theme.accent.opacity(0.75)).monospacedDigit()
                    }
                }
                if let c = model.credits.credits { CreditsRing(credits: c, plan: model.credits.plan) }
                Text("v\(model.appVersion)").font(Theme.caption(11)).foregroundStyle(Theme.muted).monospacedDigit()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(.bar)
    }
}
