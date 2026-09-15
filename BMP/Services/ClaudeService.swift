import Foundation

enum ClaudeError: LocalizedError {
    case missingImages([String])
    case noResult
    case cliError(String)
    case unread([String])
    case rateLimited(Int)

    var errorDescription: String? {
        switch self {
        case .missingImages(let names):
            return "No se pudo acceder a estas imágenes (¿se movieron, se renombraron, o no están descargadas de iCloud?): \(names.joined(separator: ", "))"
        case .noResult: return "Claude CLI no devolvió resultado"
        case .cliError(let msg): return msg
        case .unread(let names):
            return "Claude no llegó a ver \(names.count) imagen(es) antes de generar el prompt: \(names.joined(separator: ", ")). Vuelve a intentar."
        case .rateLimited(let s): return "Rate limit: wait \(s)s before generating again"
        }
    }
}

// Prompt generation runs through the Claude Code CLI in headless mode so it bills
// against the user's subscription, not per-token API usage. --safe-mode skips
// CLAUDE.md/skills; --tools Read + bypassPermissions lets it view the image paths
// with no write/exec capability; --add-dir scopes read access to their folders.
//
// The transcript is streamed (stream-json) so we can count which paths the Read
// tool actually opened and fail loudly if any reference was skipped.
enum ClaudeCLI {
    static let model = "claude-sonnet-5"
    static var isInstalled: Bool { Shell.resolve("claude") != nil }

    private static let cooldown: TimeInterval = 4
    private static var lastGenerate: Date = .distantPast

    static func generatePrompt(refs: [String], products: [String], description: String) async throws -> (prompt: String, memoryId: String) {
        let now = Date()
        if now.timeIntervalSince(lastGenerate) < cooldown {
            throw ClaudeError.rateLimited(Int((cooldown - now.timeIntervalSince(lastGenerate)).rounded(.up)))
        }
        lastGenerate = now

        let system = Prompts.system + MemoryStore.context()
        let unique = Set(refs + products).count
        let user = block("REFERENCE IMAGES (composition/mood)", refs)
            + block("PRODUCT PHOTOS (Brotherhood garment)", products)
            + "## USER BRIEF:\n\(description)\n\n"
            + "You MUST call the Read tool once for each of the \(unique) image path(s) listed above before writing anything — do not skip any, do not infer content from filenames alone. Only after viewing every image, generate the marketing image prompt."

        let prompt = try await call(system: system, user: user, images: refs + products)
        let entry = MemoryStore.add(description: description, prompt: prompt)
        return (prompt, entry.id)
    }

    private static func block(_ label: String, _ paths: [String]) -> String {
        if paths.isEmpty { return "" }
        let lines = paths.enumerated().map { "Image \($0.offset + 1): \($0.element)" }.joined(separator: "\n")
        return "## \(label):\n\(lines)\n\n"
    }

    private static func call(system: String, user: String, images: [String]) async throws -> String {
        let unique = Array(NSOrderedSet(array: images)) as! [String]
        let missing = unique.filter { !FileManager.default.fileExists(atPath: $0) }
        if !missing.isEmpty { throw ClaudeError.missingImages(missing.map { ($0 as NSString).lastPathComponent }) }

        let dirs = Array(NSOrderedSet(array: unique.map { ($0 as NSString).deletingLastPathComponent })) as! [String]
        var args = [
            "-p", user,
            "--output-format", "stream-json",
            "--verbose",
            "--model", model,
            "--system-prompt", system,
            "--tools", "Read",
            "--permission-mode", "bypassPermissions",
            "--safe-mode",
            "--no-session-persistence",
        ]
        for d in dirs { args += ["--add-dir", d] }

        let result = try await Shell.run("claude", args)

        // macOS can echo paths back in NFD even when we sent NFC — compare normalized.
        var readPaths = Set<String>()
        var final: [String: Any]?
        for line in result.stdout.split(separator: "\n") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = obj["type"] as? String else { continue }
            if type == "assistant" {
                let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
                for b in content where b["type"] as? String == "tool_use" && b["name"] as? String == "Read" {
                    if let p = (b["input"] as? [String: Any])?["file_path"] as? String {
                        readPaths.insert(p.precomposedStringWithCanonicalMapping)
                    }
                }
            } else if type == "result" {
                final = obj
            }
        }

        guard let final else { throw ClaudeError.noResult }
        if final["is_error"] as? Bool == true { throw ClaudeError.cliError(final["result"] as? String ?? "Claude CLI error") }

        let unread = unique.filter { !readPaths.contains($0.precomposedStringWithCanonicalMapping) }
        if !unread.isEmpty { throw ClaudeError.unread(unread.map { ($0 as NSString).lastPathComponent }) }

        return (final["result"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
