import Foundation

struct CodexExecutableLocator: Sendable {
    func locate(preferredPath: String? = nil) -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appending(path: "codex").path }
        let candidates = ([
            preferredPath,
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex"
        ].compactMap { $0 } + pathCandidates)

        var seen: Set<String> = []
        return candidates.lazy
            .map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL }
            .first { url in
                guard seen.insert(url.path).inserted,
                      fileManager.isExecutableFile(atPath: url.path),
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                else { return false }
                return values.isRegularFile == true
            }
    }
}
