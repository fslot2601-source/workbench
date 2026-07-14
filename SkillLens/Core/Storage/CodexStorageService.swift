import Foundation

actor CodexStorageService {
    private let fileManager = FileManager.default
    private let disposalMode: StorageDisposalMode
    private let allowedComponents: [CodexStorageKind: String] = [
        .cache: "cache",
        .temporary: ".tmp",
        .logs: "log",
        .archivedSessions: "archived_sessions"
    ]

    init(disposalMode: StorageDisposalMode = .systemTrash) {
        self.disposalMode = disposalMode
    }

    func scan(codexHome: URL, now: Date = Date()) -> [StorageRecord] {
        let home = canonical(codexHome)
        guard let children = try? fileManager.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }

        let records = children.map { url in
            let kind = classify(url.lastPathComponent)
            let measurement = measure(url)
            let selection = cleanupSelection(for: kind, root: url, now: now)
            return StorageRecord(
                kind: kind,
                path: url.path,
                sizeBytes: measurement.bytes,
                itemCount: measurement.count,
                reclaimableSizeBytes: selection.bytes,
                reclaimableItemCount: selection.candidates.count,
                cleanupFingerprint: selection.candidates.isEmpty ? nil : selection.fingerprint
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

    func clear(record: StorageRecord, codexHome: URL, now: Date = Date()) throws -> StorageCleanupResult {
        guard record.kind.cleanable else { throw CodexStorageError.protectedCategory }
        let (home, target) = try validatedTarget(record: record, codexHome: codexHome)
        guard record.hasReclaimableContent else { throw CodexStorageError.nothingToClean }

        let selection = cleanupSelection(for: record.kind, root: target, now: now)
        guard selection.bytes == record.reclaimableSizeBytes,
              selection.candidates.count == record.reclaimableItemCount,
              record.cleanupFingerprint == selection.fingerprint
        else { throw CodexStorageError.changedSinceScan }
        guard !selection.candidates.isEmpty else { throw CodexStorageError.nothingToClean }

        let disposition: StorageCleanupDisposition
        switch record.kind {
        case .cache:
            try replaceWholeDirectory(target, inside: home, moveToTrash: false, kind: record.kind)
            disposition = .permanentlyRemoved
        case .archivedSessions:
            try replaceWholeDirectory(target, inside: home, moveToTrash: true, kind: record.kind)
            disposition = disposalMode == .systemTrash ? .movedToTrash : .permanentlyRemoved
        case .temporary, .logs:
            try moveSelectedFiles(selection.candidates, from: target, inside: home, kind: record.kind)
            disposition = disposalMode == .systemTrash ? .movedToTrash : .permanentlyRemoved
        default:
            throw CodexStorageError.protectedCategory
        }

        return StorageCleanupResult(
            kind: record.kind,
            reclaimedBytes: selection.bytes,
            reclaimedItemCount: selection.candidates.count,
            disposition: disposition
        )
    }

    private func validatedTarget(record: StorageRecord, codexHome: URL) throws -> (home: URL, target: URL) {
        let suppliedHome = codexHome.standardizedFileURL
        let suppliedTarget = URL(fileURLWithPath: record.path).standardizedFileURL
        guard suppliedHome.path != "/", !suppliedHome.path.isEmpty else {
            throw CodexStorageError.invalidCodexHome
        }
        guard fileManager.fileExists(atPath: suppliedHome.path) else {
            throw CodexStorageError.invalidCodexHome
        }

        let suppliedHomeValues = try suppliedHome.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard suppliedHomeValues.isDirectory == true, suppliedHomeValues.isSymbolicLink != true else {
            throw CodexStorageError.symbolicLink
        }

        let home = canonical(suppliedHome)
        let target = canonical(suppliedTarget)
        guard target.deletingLastPathComponent() == home,
              allowedComponents[record.kind] == target.lastPathComponent
        else { throw CodexStorageError.outsideCodexHome }
        guard fileManager.fileExists(atPath: target.path) else { throw CodexStorageError.changedSinceScan }

        let homeValues = try home.resourceValues(forKeys: [.isDirectoryKey, .volumeIdentifierKey])
        guard homeValues.isDirectory == true else { throw CodexStorageError.invalidCodexHome }
        let suppliedTargetValues = try suppliedTarget.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard suppliedTargetValues.isSymbolicLink != true else { throw CodexStorageError.symbolicLink }
        let targetValues = try target.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .volumeIdentifierKey])
        guard targetValues.isSymbolicLink != true else { throw CodexStorageError.symbolicLink }
        guard targetValues.isDirectory == true else { throw CodexStorageError.notDirectory }
        guard let targetVolume = targetValues.volumeIdentifier as? AnyHashable,
              let homeVolume = homeValues.volumeIdentifier as? AnyHashable,
              targetVolume == homeVolume
        else { throw CodexStorageError.outsideCodexHome }
        return (home, target)
    }

    private func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func replaceWholeDirectory(
        _ target: URL,
        inside home: URL,
        moveToTrash: Bool,
        kind: CodexStorageKind
    ) throws {
        let staging = home.appending(path: "SkillLens-\(kind.rawValue)-\(UUID().uuidString)")
        var movedToStaging = false
        do {
            try fileManager.moveItem(at: target, to: staging)
            movedToStaging = true
            try fileManager.createDirectory(at: target, withIntermediateDirectories: false)
            try dispose(staging, moveToTrash: moveToTrash)
            movedToStaging = false
        } catch {
            if movedToStaging, fileManager.fileExists(atPath: staging.path) {
                if fileManager.fileExists(atPath: target.path) {
                    try? fileManager.removeItem(at: target)
                }
                do {
                    try fileManager.moveItem(at: staging, to: target)
                    movedToStaging = false
                } catch {
                    throw CodexStorageError.rollbackFailed(quarantinePath: staging.path)
                }
            }
            throw error
        }
    }

    private func moveSelectedFiles(
        _ candidates: [StorageCandidate],
        from target: URL,
        inside home: URL,
        kind: CodexStorageKind
    ) throws {
        let staging = home.appending(path: "SkillLens-\(kind.rawValue)-\(UUID().uuidString)")
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        var moved: [(source: URL, staged: URL)] = []

        do {
            for candidate in candidates {
                guard try candidateStillMatches(candidate) else { throw CodexStorageError.changedSinceScan }
                guard let relativePath = relativePath(of: candidate.url, inside: target) else {
                    throw CodexStorageError.outsideCodexHome
                }
                let destination = staging.appending(path: relativePath)
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.moveItem(at: candidate.url, to: destination)
                moved.append((candidate.url, destination))
            }
            try dispose(staging, moveToTrash: true)
        } catch {
            if fileManager.fileExists(atPath: staging.path) {
                do {
                    for item in moved.reversed() {
                        try fileManager.createDirectory(
                            at: item.source.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try fileManager.moveItem(at: item.staged, to: item.source)
                    }
                    try? fileManager.removeItem(at: staging)
                } catch {
                    throw CodexStorageError.rollbackFailed(quarantinePath: staging.path)
                }
            }
            throw error
        }
    }

    private func dispose(_ url: URL, moveToTrash: Bool) throws {
        if moveToTrash, disposalMode == .systemTrash {
            var trashedURL: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &trashedURL)
        } else {
            try fileManager.removeItem(at: url)
        }
    }

    private func candidateStillMatches(_ candidate: StorageCandidate) throws -> Bool {
        let values = try candidate.url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { return false }
        let bytes = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        return bytes == candidate.bytes
            && normalizedModificationTime(values.contentModificationDate ?? .distantPast)
                == normalizedModificationTime(candidate.modifiedAt)
    }

    private func cleanupSelection(for kind: CodexStorageKind, root: URL, now: Date) -> StorageSelection {
        guard kind.cleanable,
              (try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]))?.isDirectory == true,
              (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true
        else { return .empty }

        let cutoff: Date?
        switch kind {
        case .temporary: cutoff = now.addingTimeInterval(-24 * 60 * 60)
        case .logs: cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .cache, .archivedSessions: cutoff = nil
        default: return .empty
        }

        let candidates = regularFiles(inside: root).filter { candidate in
            guard let cutoff else { return true }
            return candidate.modifiedAt < cutoff
        }
        let selection = StorageSelection(
            candidates: candidates,
            bytes: candidates.reduce(0) { $0 + $1.bytes },
            fingerprint: fingerprint(candidates, relativeTo: root)
        )
        return selection
    }

    private func regularFiles(inside root: URL) -> [StorageCandidate] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var candidates: [StorageCandidate] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }
            candidates.append(StorageCandidate(
                url: url,
                bytes: Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .distantPast
            ))
        }
        return candidates.sorted { $0.url.path < $1.url.path }
    }

    private func fingerprint(_ candidates: [StorageCandidate], relativeTo root: URL) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for candidate in candidates {
            guard let relativePath = relativePath(of: candidate.url, inside: root) else { continue }
            let value = "\(relativePath)\u{0}\(candidate.bytes)\u{0}\(normalizedModificationTime(candidate.modifiedAt))\n"
            for byte in value.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
        }
        return String(hash, radix: 16)
    }

    private func relativePath(of url: URL, inside root: URL) -> String? {
        let rootPath = canonical(root).path
        let itemPath = canonical(url).path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard itemPath.hasPrefix(prefix) else { return nil }
        return String(itemPath.dropFirst(prefix.count))
    }

    private func normalizedModificationTime(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
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

enum StorageDisposalMode: Sendable {
    case systemTrash
    case removeImmediatelyForTesting
}

enum StorageCleanupDisposition: Hashable, Sendable {
    case permanentlyRemoved
    case movedToTrash
}

struct StorageCleanupResult: Hashable, Sendable {
    let kind: CodexStorageKind
    let reclaimedBytes: Int64
    let reclaimedItemCount: Int
    let disposition: StorageCleanupDisposition
}

private struct StorageCandidate: Sendable {
    let url: URL
    let bytes: Int64
    let modifiedAt: Date
}

private struct StorageSelection: Sendable {
    let candidates: [StorageCandidate]
    let bytes: Int64
    let fingerprint: String

    static let empty = StorageSelection(candidates: [], bytes: 0, fingerprint: "")
}

enum CodexStorageError: LocalizedError, Sendable {
    case protectedCategory
    case nothingToClean
    case invalidCodexHome
    case outsideCodexHome
    case symbolicLink
    case notDirectory
    case changedSinceScan
    case rollbackFailed(quarantinePath: String)

    var errorDescription: String? {
        switch self {
        case .protectedCategory: "这类数据受到保护，不能由 Workbench 清理。"
        case .nothingToClean: "当前没有符合清理规则的文件。"
        case .invalidCodexHome: "Codex Home 路径无效，清理已取消。"
        case .outsideCodexHome: "清理目标不在当前 Codex Home 的安全白名单内。"
        case .symbolicLink: "清理目标是符号链接，为避免误删真实目录，操作已取消。"
        case .notDirectory: "清理目标不是预期目录，为避免误删未知文件，操作已取消。"
        case .changedSinceScan: "内容在扫描后发生了变化。请重新扫描并再次确认。"
        case .rollbackFailed(let path): "清理没有完成，数据已保留在 \(path)。请勿继续清理，并在 Finder 中检查该目录。"
        }
    }
}
