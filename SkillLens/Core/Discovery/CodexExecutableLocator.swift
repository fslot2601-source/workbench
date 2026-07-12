import Foundation

struct CodexExecutableLocator: Sendable {
    func locate(preferredPath: String? = nil) -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        let candidates = [
            preferredPath,
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex"
        ].compactMap { $0 }

        return candidates
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}
