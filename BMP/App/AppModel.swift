import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    // ── Lock ──────────────────────────────────────────────────────────────
    // The key is asked once per Mac; afterwards the Keychain token opens the app directly.
    var unlocked = AppLock.isRemembered()

    // ── Inputs ────────────────────────────────────────────────────────────
    var refs: [String] = []
    var products: [String] = []
    var brief = ""
    var refSpecs = ""                 // what to take from the (single) reference

    // ── Prompt ────────────────────────────────────────────────────────────
    var prompt = ""
    var generateStatus: GenerateStatus = .idle
    var generateError = ""
    var memoryId: String?
    var generateStage = ""            // "Brief · Sonnet" / "Prompt · Opus" while loading
    var briefLoading = false
    // The brief Sonnet wrote + the inputs it was written from: while the field still
    // holds that text and the inputs changed, Generate rewrites it instead of reusing a stale one.
    private var autoBrief: (text: String, signature: String)?

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
    var credits: (credits: Double?, plan: String?) = (nil, nil)
    var showHistory = false
    var showLogin = false
    var missingTools: [String] = []
    var outputPath: String = Prefs.load().outputPath

    private var lastFire = Date.distantPast
    private let logCap = 400

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var fireStatus: FireStatus { tasks > 0 ? .loading : fireResult }
    // The brief is optional: left empty, Sonnet writes it from the reference + product + specs.
    var canGenerate: Bool { !refs.isEmpty && !products.isEmpty }
    var canAutoBrief: Bool { canGenerate && generateStatus != .loading && !briefLoading }
    var canFire: Bool { !prompt.isEmpty }
    var showLog: Bool { !log.isEmpty || tasks > 0 }
    var footerLabel: String { "\(provider.label) \(aspectRatio) \(resolution.uppercased())" }

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
    // One reference only: a second drop replaces the first (several references pull the
    // prompt in different directions). Staging decodes/re-encodes, so it runs off-main.
    func addRefs(_ urls: [URL]) {
        guard let first = urls.first else { return }
        if urls.count > 1 { push("Warning: only 1 reference is used, took \(first.lastPathComponent)") }
        stageOffMain([first]) { self.refs = $0 }
    }
    func addProducts(_ urls: [URL]) { stageOffMain(urls) { self.products += $0 } }

    private func stageOffMain(_ urls: [URL], apply: @escaping @MainActor ([String]) -> Void) {
        Task {
            let staged = await Task.detached(priority: .userInitiated) { try? Staging.stage(urls) }.value
            if let staged { apply(staged) }
        }
    }

    private var inputSignature: String { (refs + products + [refSpecs]).joined(separator: "|") }

    /// Stage 1 on demand: the sparkle button next to the brief.
    func autoWriteBrief() {
        guard canAutoBrief else { return }
        briefLoading = true; generateError = ""
        push("▶ Sonnet · writing brief...")
        let (r, p, sp, sig) = (refs, products, refSpecs, inputSignature)
        Task {
            defer { briefLoading = false }
            do {
                let text = try await ClaudeCLI.generateBrief(refs: r, products: p, specs: sp)
                brief = text; autoBrief = (text, sig)
                push("Brief ready ✓")
            } catch {
                generateError = error.localizedDescription
                push("Brief failed: \(error.localizedDescription)")
            }
        }
    }

    // ── Generate prompt ───────────────────────────────────────────────────
    func generate() {
        guard canGenerate, generateStatus != .loading, !briefLoading else { return }
        generateStatus = .loading; prompt = ""; generateError = ""
        let (r, p, sp, sig) = (refs, products, refSpecs, inputSignature)
        let typed = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        let stale = autoBrief.map { $0.text == brief && $0.signature != sig } ?? false
        Task {
            do {
                var description = typed
                if description.isEmpty || stale {
                    generateStage = "Brief · Sonnet"
                    push("▶ Sonnet · writing brief...")
                    description = try await ClaudeCLI.generateBrief(refs: r, products: p, specs: sp)
                    brief = description; autoBrief = (description, sig)
                    push("Brief ready ✓")
                }
                generateStage = "Prompt · Opus"
                push("▶ Opus · writing prompt...")
                let result = try await ClaudeCLI.generatePrompt(refs: r, products: p, description: description, specs: sp)
                prompt = result.prompt; memoryId = result.memoryId; generateStatus = .done
                push("Prompt ready ✓")
                refreshMemoryStats()
            } catch {
                generateError = error.localizedDescription; generateStatus = .error
                push("Prompt generation failed: \(error.localizedDescription)")
            }
            generateStage = ""
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
                        : "\(succeeded)/\(s.n) generated, \(failed) failed.")
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
                push("\(provider.label) accepts max \(provider.maxRefs) reference images, using the first \(provider.maxRefs)")
            }
            refs = Array(products.prefix(provider.maxRefs))
        }

        push("Submitting \(provider.jobType) (\(safeRatio) · \(safeRes.uppercased()))...")
        do {
            let job = try await Higgsfield.generate(provider.jobType, [
                ("prompt", prompt), ("aspect_ratio", safeRatio), ("resolution", safeRes),
                ("image_references", refs.isEmpty ? nil : refs),
            ] + provider.extraParams) { [weak self] line in Task { @MainActor in self?.push(line) } }

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
        refs = []; products = []; brief = ""; refSpecs = ""; autoBrief = nil; prompt = ""; generateStatus = .idle; memoryId = nil; variations = 1; generateError = ""
        if tasks == 0 { fireResult = .idle; log = [] }
    }
}
