import SwiftUI
import AppKit

@main
struct BMPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("BMP", id: "main") {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1060, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Prompt") {
                Button("Generate prompt") { model.generate() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canGenerate || model.generateStatus == .loading)
                Button("Fire to Higgsfield") { model.fire() }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .disabled(!model.canFire)
                Divider()
                Button("Prompt history…") { model.showHistory = true }
                    .keyboardShortcut("y", modifiers: .command)
                Button("Reset") { model.reset() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Open output folder") { NSWorkspace.shared.open(URL(fileURLWithPath: model.outputPath)) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var splashDone = false

    var body: some View {
        ZStack {
            if !splashDone {
                SplashView { withAnimation(Theme.ease) { splashDone = true } }
                    .transition(.opacity)
            } else if model.unlocked {
                MainView()
                    .transition(.opacity)
                    .task { await model.boot() }
            } else {
                LockScreen(appName: "BMP") { withAnimation(Theme.ease) { model.unlocked = true } }
                    .transition(.opacity)
            }
        }
        .background(Theme.bg)
        .background(WindowAccessor())
    }
}

// Keeps the native title bar but paints it with our background so the window
// reads as one surface (title, subtitle and toolbar buttons stay system-drawn).
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titlebarAppearsTransparent = true
            w.backgroundColor = NSColor(Theme.bg)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
