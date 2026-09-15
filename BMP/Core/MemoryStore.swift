import Foundation

struct MemoryEntry: Codable, Identifiable, Hashable {
    var id: String
    var timestamp: Double          // ms since epoch (shared format with Electron build)
    var description: String
    var prompt: String
    var fired: Bool
    var aspectRatio: String?

    var date: Date { Date(timeIntervalSince1970: timestamp / 1000) }
}

private struct MemoryFile: Codable {
    var entries: [MemoryEntry]
}

// Prompt memory: every generated prompt is stored; fired ones are the strongest
// signal and get injected back into the system prompt as calibration examples.
enum MemoryStore {
    private static func load() -> [MemoryEntry] {
        guard let data = try? Data(contentsOf: AppPaths.memory),
              let file = try? JSONDecoder().decode(MemoryFile.self, from: data) else { return [] }
        return file.entries
    }

    private static func save(_ entries: [MemoryEntry]) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(MemoryFile(entries: entries)) {
            try? data.write(to: AppPaths.memory, options: .atomic)
        }
    }

    static func entries() -> [MemoryEntry] { load().reversed() }

    static func stats() -> (total: Int, fired: Int) {
        let all = load()
        return (all.count, all.filter(\.fired).count)
    }

    @discardableResult
    static func add(description: String, prompt: String) -> MemoryEntry {
        var all = load()
        let id = "\(Int(Date().timeIntervalSince1970 * 1000))-\(String(UUID().uuidString.prefix(5)).lowercased())"
        let entry = MemoryEntry(id: id, timestamp: Date().timeIntervalSince1970 * 1000,
                                description: description, prompt: prompt, fired: false, aspectRatio: nil)
        all.append(entry)
        if all.count > 200 { all = Array(all.suffix(200)) }
        save(all)
        return entry
    }

    static func markFired(id: String, aspectRatio: String) {
        var all = load()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        all[i].fired = true
        all[i].aspectRatio = aspectRatio
        save(all)
    }

    static func context() -> String {
        let all = load()
        if all.isEmpty { return "" }
        let fired = all.filter(\.fired).suffix(8)
        let recent = all.filter { !$0.fired }.suffix(5)
        let pool = (Array(fired) + Array(recent)).sorted { $0.timestamp < $1.timestamp }
        if pool.isEmpty { return "" }

        let df = DateFormatter()
        df.locale = Locale(identifier: "es_CO")
        df.dateFormat = "d MMM"

        let blocks = pool.map { e -> String in
            let label = e.fired ? "★ FIRED" : "○ generated"
            return "[\(label) · \(df.string(from: e.date))]\nBrief: \"\(e.description)\"\nPrompt:\n\(e.prompt)"
        }.joined(separator: "\n\n---\n\n")

        return """


        ## PROMPT MEMORY — \(pool.count) past Brotherhood prompts (★ = approved & fired to Higgsfield)
        Study these to calibrate vocabulary, light descriptions, garment detail depth, color language, and brand tone. Fired prompts are your strongest signal — replicate what makes them work.

        \(blocks)

        ---
        Apply learnings silently. Output ONLY the new prompt.
        """
    }
}
