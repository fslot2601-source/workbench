import Foundation

enum CodexExecutableLocatorError: LocalizedError, Equatable, Sendable {
    case pathDoesNotExist(String)
    case applicationHasNoBundledCodex(String)
    case notRegularFile(String)
    case notExecutable(String)

    var errorDescription: String? {
        switch self {
        case .pathDoesNotExist(let path):
            "所选位置不存在：\(path)"
        case .applicationHasNoBundledCodex(let path):
            "所选应用不包含 Codex 可执行文件：\(path)"
        case .notRegularFile(let path):
            "所选内容不是 ChatGPT.app 或 Codex 可执行文件：\(path)"
        case .notExecutable(let path):
            "所选文件没有执行权限：\(path)"
        }
    }
}

struct CodexExecutableLocator: Sendable {
    func locate(preferredPath: String? = nil) -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appending(path: "codex") }
        let applicationCandidates = applicationDirectories(fileManager: fileManager).flatMap { directory in
            ["ChatGPT.app", "Codex.app"].map { directory.appending(path: $0, directoryHint: .isDirectory) }
        }
        var candidates: [URL] = []
        if let preferredPath, !preferredPath.isEmpty {
            candidates.append(URL(fileURLWithPath: preferredPath))
        }
        candidates.append(contentsOf: applicationCandidates)
        candidates.append(contentsOf: [
            URL(fileURLWithPath: "\(home)/.local/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex")
        ])
        candidates.append(contentsOf: pathCandidates)

        var seen: Set<String> = []
        return candidates.lazy
            .flatMap { expandedCandidates(for: $0, fileManager: fileManager) }
            .map { $0.resolvingSymlinksInPath().standardizedFileURL }
            .first { candidate in
                seen.insert(candidate.path).inserted && isValidExecutable(candidate, fileManager: fileManager)
            }
    }

    func resolveSelection(_ selectedURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let url = selectedURL.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw CodexExecutableLocatorError.pathDoesNotExist(url.path)
        }

        if isDirectory.boolValue {
            let bundled = bundledCodexURL(in: url).resolvingSymlinksInPath().standardizedFileURL
            guard fileManager.fileExists(atPath: bundled.path) else {
                throw CodexExecutableLocatorError.applicationHasNoBundledCodex(url.path)
            }
            return try validateExecutable(bundled, fileManager: fileManager)
        }

        return try validateExecutable(url, fileManager: fileManager)
    }

    private func applicationDirectories(fileManager: FileManager) -> [URL] {
        [
            fileManager.urls(for: .applicationDirectory, in: .localDomainMask).first,
            fileManager.urls(for: .applicationDirectory, in: .userDomainMask).first,
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory)
        ].compactMap { $0 }
    }

    private func expandedCandidates(for url: URL, fileManager: FileManager) -> [URL] {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return [bundledCodexURL(in: resolved)]
        }
        if resolved.pathExtension.localizedCaseInsensitiveCompare("app") == .orderedSame {
            return [bundledCodexURL(in: resolved)]
        }
        return [resolved]
    }

    private func bundledCodexURL(in applicationURL: URL) -> URL {
        applicationURL.appending(path: "Contents/Resources/codex")
    }

    private func isValidExecutable(_ url: URL, fileManager: FileManager) -> Bool {
        (try? validateExecutable(url, fileManager: fileManager)) != nil
    }

    private func validateExecutable(_ url: URL, fileManager: FileManager) throws -> URL {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
              values.isRegularFile == true
        else {
            throw CodexExecutableLocatorError.notRegularFile(url.path)
        }
        guard fileManager.isExecutableFile(atPath: url.path) else {
            throw CodexExecutableLocatorError.notExecutable(url.path)
        }
        return url
    }
}
