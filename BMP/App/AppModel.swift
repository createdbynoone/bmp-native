import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    // ── Lock ──────────────────────────────────────────────────────────────
    var unlocked = false

    // ── Inputs ────────────────────────────────────────────────────────────
    var refs: [String] = []
    var products: [String] = []
    var brief = ""

    // ── Prompt ────────────────────────────────────────────────────────────
    var prompt = ""
    var generateStatus: GenerateStatus = .idle
    var generateError = ""
    var memoryId: String?

    // ── Fire settings ─────────────────────────────────────────────────────
    var provider: Provider = .nanobanana
    var aspectRatio = Provider.nanobanana.ratios[0]
    var resolution = "2k"
    var variations = 1

    // ── Tasks (ref-counted; nothing in the UI resets an in-flight one) ────
    var tasks = 0
    var fireResult: FireStatus = .idle
    var log: [LogEntry] = []

    // ── Chrome ────────────────────────────────────────────────────────────
    var memoryStats: (total: Int, fired: Int) = (0, 0)
    var credits: (credits: Int?, plan: String?) = (nil, nil)
    var showHistory = false
    var showLogin = false
    var missingTools: [String] = []
    var outputPath: String = Prefs.load().outputPath

    private var lastFire = Date.distantPast
    private let logCap = 400

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var fireStatus: FireStatus { tasks > 0 ? .loading : fireResult }
    var canGenerate: Bool { !refs.isEmpty && !products.isEmpty && !brief.trimmingCharacters(in: .whitespaces).isEmpty }
    var canFire: Bool { !prompt.isEmpty }
    var showLog: Bool { !log.isEmpty || tasks > 0 }
    var footerLabel: String { "\(provider.slug) · \(aspectRatio) · \(resolution.uppercased())" }

    // ── Boot ──────────────────────────────────────────────────────────────
    func boot() async {
        Staging.reset()
        refreshMemoryStats()
        var missing: [String] = []
        if !ClaudeCLI.isInstalled { missing.append("claude") }
        if !Higgsfield.isInstalled { missing.append("higgsfield") }
        missingTools = missing
        if Higgsfield.isInstalled {
            let authed = await Higgsfield.isAuthenticated()
            if !authed {
                showLogin = true
                Task { try? await Higgsfield.login(); showLogin = false; await refreshCredits() }
            }
            await refreshCredits()
        }
    }

    func refreshMemoryStats() { memoryStats = MemoryStore.stats() }
    func refreshCredits() async { credits = await Higgsfield.credits() }

    func setOutputPath(_ path: String) {
        var p = Prefs.load(); p.outputPath = path; p.save()
        outputPath = path
    }

    // ── Log ───────────────────────────────────────────────────────────────
    func push(_ line: String) {
        log.append(LogEntry(date: Date(), line: line))
        if log.count > logCap { log.removeFirst(log.count - logCap) }
    }

    func clearLog() { log = []; fireResult = .idle }

    // Guard against double-clicks now that fire stays enabled while batches run
    private func fireGate() -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastFire) < 0.6 { return false }
        lastFire = now
        return true
    }

    // ── Provider ──────────────────────────────────────────────────────────
    func setProvider(_ p: Provider) {
        provider = p
        if !p.resolutions.contains(resolution) { resolution = "2k" }
        // 3:4 vs 4:5 portrait differs per provider — keep 9:16, else snap to default
        if !p.ratios.contains(aspectRatio) { aspectRatio = p.ratios[0] }
    }

    // ── Drops ─────────────────────────────────────────────────────────────
    func addRefs(_ urls: [URL]) { if let staged = try? Staging.stage(urls) { refs += staged } }
    func addProducts(_ urls: [URL]) { if let staged = try? Staging.stage(urls) { products += staged } }

    // ── Generate prompt ───────────────────────────────────────────────────
    func generate() {
        guard canGenerate, generateStatus != .loading else { return }
        generateStatus = .loading; prompt = ""; generateError = ""
        push("▶ Claude · generating prompt...")
        let (r, p, d) = (refs, products, brief)
        Task {
            do {
                let result = try await ClaudeCLI.generatePrompt(refs: r, products: p, description: d)
                prompt = result.prompt; memoryId = result.memoryId; generateStatus = .done
                push("Prompt ready ✓")
                refreshMemoryStats()
            } catch {
                generateError = error.localizedDescription; generateStatus = .error
                push("Prompt generation failed — \(error.localizedDescription)")
            }
        }
    }

    func usePrompt(_ p: String) { prompt = p; generateStatus = .done; memoryId = nil }

    // ── Fire ──────────────────────────────────────────────────────────────
    func fire() {
        guard canFire, fireGate() else { return }
        let s = (prompt: prompt, products: products, ratio: aspectRatio, res: resolution, provider: provider, n: variations, memoryId: memoryId)
        tasks += 1
        push("▶ \(s.provider.label) ×\(s.n) · \(s.ratio) · \(s.res.uppercased())")
        Task {
            defer { tasks -= 1 }
            do {
                // Refs are uploaded ONCE and shared across the parallel batch
                var refIds: [String]? = nil
                if !s.products.isEmpty && s.n > 1 {
                    let files = Array(s.products.prefix(14))
                    push("Uploading \(files.count) image\(files.count > 1 ? "s" : "")...")
                    refIds = try await withThrowingTaskGroup(of: (Int, String).self) { group in
                        for (i, f) in files.enumerated() { group.addTask { (i, try await Higgsfield.upload(f)) } }
                        var out = [String?](repeating: nil, count: files.count)
                        for try await (i, id) in group { out[i] = id }
                        return out.compactMap { $0 }
                    }
                    push("\(files.count) image\(files.count > 1 ? "s" : "") ready ✓")
                }

                let succeeded = await withTaskGroup(of: Bool.self) { group in
                    for _ in 0..<s.n {
                        group.addTask { [self] in
                            await self.runJob(prompt: s.prompt, products: s.products, ratio: s.ratio, res: s.res, provider: s.provider, refIds: refIds)
                        }
                    }
                    var ok = 0
                    for await r in group where r { ok += 1 }
                    return ok
                }

                let failed = s.n - succeeded
                if s.n > 1 {
                    push(failed == 0 ? "All \(s.n) variations generated."
                        : succeeded == 0 ? "All \(s.n) variations failed."
                        : "\(succeeded)/\(s.n) generated — \(failed) failed.")
                }
                fireResult = succeeded > 0 ? .done : .error
                if succeeded > 0, let id = s.memoryId {
                    MemoryStore.markFired(id: id, aspectRatio: s.ratio)
                    refreshMemoryStats()
                }
            } catch {
                fireResult = .error
                push("Error: \(error.localizedDescription)")
            }
        }
    }

    private func runJob(prompt: String, products: [String], ratio: String, res: String, provider: Provider, refIds: [String]?) async -> Bool {
        let safeRatio = provider.ratios.contains(ratio) ? ratio : provider.ratios[0]
        let safeRes = provider.resolutions.contains(res) ? res : provider.resolutions.last!

        var refs = Array((refIds ?? []).prefix(provider.maxRefs))
        if refs.isEmpty && !products.isEmpty {
            if products.count > provider.maxRefs {
                push("\(provider.label) accepts max \(provider.maxRefs) reference images — using the first \(provider.maxRefs)")
            }
            refs = Array(products.prefix(provider.maxRefs))
        }

        push("Submitting \(provider.jobType) (\(safeRatio) · \(safeRes.uppercased()))...")
        do {
            let job = try await Higgsfield.generate(provider.jobType, [
                ("prompt", prompt), ("aspect_ratio", safeRatio), ("resolution", safeRes),
                ("image_references", refs.isEmpty ? nil : refs),
            ]) { [weak self] line in Task { @MainActor in self?.push(line) } }

            guard let url = job.result_url else { push("No image in response"); return false }
            let name = "bmp_\(Int(Date().timeIntervalSince1970 * 1000)).\(Downloader.ext(of: url, fallback: "jpg"))"
            let dest = URL(fileURLWithPath: outputPath).appendingPathComponent(name)
            push("Downloading image...")
            try await Downloader.download(url, to: dest)
            if let px = Downloader.pixelSize(of: dest.path) { push("Saved: \(name) · \(px.0)×\(px.1)px") }
            else { push("Saved: \(name)") }
            return true
        } catch {
            push("Error: \(error.localizedDescription)")
            return false
        }
    }

    // ── Reset ─────────────────────────────────────────────────────────────
    func reset() {
        refs = []; products = []; brief = ""; prompt = ""; generateStatus = .idle; memoryId = nil; variations = 1; generateError = ""
        if tasks == 0 { fireResult = .idle; log = [] }
    }
}
