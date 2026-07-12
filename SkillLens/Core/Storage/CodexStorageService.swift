import Foundation

actor CodexStorageService {
    private let fileManager = FileManager.default
    private let cleanableComponents: Set<String> = ["cache"]

    func scan(codexHome: URL) -> [StorageRecord] {
        let home = codexHome.standardizedFileURL
        guard let children = try? fileManager.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }

        let records = children.map { url in
            let measurement = measure(url)
            return StorageRecord(
                kind: classify(url.lastPathComponent),
                path: url.path,
                sizeBytes: measurement.bytes,
                itemCount: measurement.count
            )
        }

        let known = records.filter { $0.kind != .other }
        let other = records.filter { $0.kind == .other }
        let groupedOther: [StorageRecord]
        if other.isEmpty {
            groupedOther = []
        } else {
            groupedOther = [StorageRecord(
                kind: .other,
                path: home.appending(path: "其他数据（合并显示）").path,
                sizeBytes: other.reduce(0) { $0 + $1.sizeBytes },
                itemCount: other.reduce(0) { $0 + $1.itemCount }
            )]
        }

        return (known + groupedOther)
        .sorted { lhs, rhs in
            if lhs.sizeBytes == rhs.sizeBytes { return lhs.path < rhs.path }
            return lhs.sizeBytes > rhs.sizeBytes
        }
    }

    func clear(record: StorageRecord, codexHome: URL) throws {
        guard record.kind.cleanable else { throw CodexStorageError.protectedCategory }
        let home = codexHome.standardizedFileURL
        let target = URL(fileURLWithPath: record.path).standardizedFileURL
        guard home.path != "/", !home.path.isEmpty else { throw CodexStorageError.invalidCodexHome }
        guard target.deletingLastPathComponent() == home,
              cleanableComponents.contains(target.lastPathComponent)
        else { throw CodexStorageError.outsideCodexHome }

        let values = try target.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .volumeIdentifierKey])
        let homeValues = try home.resourceValues(forKeys: [.volumeIdentifierKey])
        guard values.isSymbolicLink != true else { throw CodexStorageError.symbolicLink }
        guard values.volumeIdentifier as? AnyHashable == homeValues.volumeIdentifier as? AnyHashable else {
            throw CodexStorageError.outsideCodexHome
        }
        guard fileManager.fileExists(atPath: target.path) else { return }
        let current = measure(target)
        guard current.bytes == record.sizeBytes, current.count == record.itemCount else {
            throw CodexStorageError.changedSinceScan
        }

        if values.isDirectory == true {
            let quarantine = home.appending(path: ".skilllens-cleanup-\(UUID().uuidString)")
            try fileManager.moveItem(at: target, to: quarantine)
            try fileManager.createDirectory(at: target, withIntermediateDirectories: false)
            try fileManager.removeItem(at: quarantine)
        } else {
            try fileManager.removeItem(at: target)
        }
    }

    private func classify(_ name: String) -> CodexStorageKind {
        switch name {
        case "sessions": .sessions
        case "archived_sessions": .archivedSessions
        case "plugins": .plugins
        case "skills": .skills
        case "packages": .packages
        case "cache": .cache
        case ".tmp": .temporary
        case "log": .logs
        default:
            if name.hasSuffix(".sqlite") || name.hasSuffix(".db") { .database }
            else { .other }
        }
    }

    private func measure(_ root: URL) -> (bytes: Int64, count: Int) {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey
        ]
        guard let rootValues = try? root.resourceValues(forKeys: keys) else { return (0, 0) }
        if rootValues.isRegularFile == true {
            return (Int64(rootValues.totalFileAllocatedSize ?? rootValues.fileAllocatedSize ?? 0), 1)
        }
        guard rootValues.isSymbolicLink != true,
              let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true }
              )
        else { return (0, 0) }

        var bytes: Int64 = 0
        var count = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if values.isRegularFile == true {
                bytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                count += 1
            }
        }
        return (bytes, count)
    }
}

enum CodexStorageError: LocalizedError, Sendable {
    case protectedCategory
    case invalidCodexHome
    case outsideCodexHome
    case symbolicLink
    case changedSinceScan

    var errorDescription: String? {
        switch self {
        case .protectedCategory: "这类数据受到保护，不能自动清理。"
        case .invalidCodexHome: "Codex Home 路径无效，清理已取消。"
        case .outsideCodexHome: "清理目标不在当前 Codex Home 的安全白名单内。"
        case .symbolicLink: "清理目标是符号链接，为避免误删真实目录，操作已取消。"
        case .changedSinceScan: "缓存内容在扫描后发生了变化。请重新扫描并再次确认。"
        }
    }
}
