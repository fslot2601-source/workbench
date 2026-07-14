import Foundation

actor CodexMemoryService {
    private let fileManager: FileManager
    private let maxPreviewBytes: Int
    private let maxScannedFiles: Int
    private let maxFileBytes: Int64

    static let defaultMaxFileBytes: Int64 = 512 * 1_024
    static let maximumPreviewCharacters = 720

    init(
        fileManager: FileManager = .default,
        maxPreviewBytes: Int = 8_192,
        maxScannedFiles: Int = 1_000,
        maxFileBytes: Int64 = CodexMemoryService.defaultMaxFileBytes
    ) {
        self.fileManager = fileManager
        self.maxPreviewBytes = maxPreviewBytes
        self.maxScannedFiles = maxScannedFiles
        self.maxFileBytes = maxFileBytes
    }

    func scan(codexHome: URL) -> MemorySnapshot {
        let home = codexHome.standardizedFileURL
        let memoryRoot = home.appending(path: "memories").standardizedFileURL
        guard safeDirectory(memoryRoot, inside: home) else {
            return MemorySnapshot(codexHomePath: home.path, records: [], items: [], warnings: ["Codex memories 目录不存在或不是安全目录。"])
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: memoryRoot,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return MemorySnapshot(codexHomePath: home.path, records: [], items: [], warnings: ["无法枚举 Codex memories 目录。"])
        }

        var records: [MemoryRecord] = []
        var warnings: [String] = []
        var scanned = 0

        for case let url as URL in enumerator {
            guard scanned < maxScannedFiles else {
                warnings.append("Memory 文件超过 \(maxScannedFiles) 个，已停止继续扫描。")
                break
            }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                warnings.append("已跳过符号链接。")
                continue
            }
            guard values.isRegularFile == true else { continue }
            guard url.pathExtension.lowercased() == "md" || url.pathExtension.lowercased() == "markdown" else { continue }
            guard contains(url.resolvingSymlinksInPath().standardizedFileURL, inside: memoryRoot) else {
                warnings.append("已跳过越界文件：\(url.lastPathComponent)")
                continue
            }
            scanned += 1
            records.append(record(for: url, root: memoryRoot, values: values))
        }

        let sortedRecords = records.sorted(by: sortRecords)
        return MemorySnapshot(
            codexHomePath: home.path,
            records: sortedRecords,
            items: knowledgeItems(records: sortedRecords, root: memoryRoot),
            warnings: warnings
        )
    }

    private func record(for url: URL, root: URL, values: URLResourceValues) -> MemoryRecord {
        let relative = relativePath(url, root: root)
        let kind = classify(relative)
        let size = Int64(values.fileSize ?? 0)
        let status: MemoryRecordStatus
        let previewText: String?
        let lines: Int
        if size > maxFileBytes {
            status = .tooLarge
            previewText = nil
            lines = 0
        } else if let value = preview(url) {
            status = .available
            previewText = value
            lines = lineCount(url)
        } else {
            status = .unreadable
            previewText = nil
            lines = 0
        }
        return MemoryRecord(
            kind: kind,
            title: title(for: url, relativePath: relative, kind: kind),
            relativePath: relative,
            absolutePath: url.path,
            sizeBytes: size,
            lineCount: lines,
            modifiedAt: values.contentModificationDate,
            preview: kind.isNoiseByDefault ? nil : previewText,
            isCollapsedByDefault: kind.isNoiseByDefault,
            status: status
        )
    }

    private func classify(_ relativePath: String) -> MemoryKind {
        if relativePath == "MEMORY.md" { return .curated }
        if relativePath == "memory_summary.md" { return .summary }
        if relativePath == "raw_memories.md" { return .raw }
        if relativePath.hasPrefix("rollout_summaries/") { return .rollout }
        if relativePath.hasPrefix("extensions/chronicle/") { return .chronicle }
        if relativePath.hasPrefix("extensions/ad_hoc/") { return .adHoc }
        return .unknown
    }

    private func title(for url: URL, relativePath: String, kind: MemoryKind) -> String {
        switch kind {
        case .curated: "MEMORY.md"
        case .summary: "memory_summary.md"
        case .raw: "raw_memories.md"
        default:
            url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
        }
    }

    private func preview(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: maxPreviewBytes)) ?? Data()
        guard !data.isEmpty, var text = decodeCompleteUTF8Prefix(data) else { return nil }
        text = redactSensitiveLines(in: text)
            .split(separator: "\n")
            .prefix(18)
            .map(String.init)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return String(text.prefix(Self.maximumPreviewCharacters))
    }

    private func decodeCompleteUTF8Prefix(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) { return text }

        // The bounded preview may stop in the middle of a multi-byte UTF-8
        // scalar. Remove only that incomplete trailing scalar; invalid bytes
        // elsewhere must still be reported as unreadable.
        let bytes = Array(data)
        guard !bytes.isEmpty else { return nil }
        var scalarStart = bytes.count - 1
        while scalarStart > 0, isUTF8Continuation(bytes[scalarStart]) {
            scalarStart -= 1
        }
        guard let expectedLength = utf8ScalarLength(bytes[scalarStart]), expectedLength > 1 else { return nil }
        let availableLength = bytes.count - scalarStart
        guard availableLength < expectedLength else { return nil }
        guard bytes[(scalarStart + 1)...].allSatisfy(isUTF8Continuation) else { return nil }
        return String(data: Data(bytes[..<scalarStart]), encoding: .utf8)
    }

    private func isUTF8Continuation(_ byte: UInt8) -> Bool {
        byte >= 0x80 && byte <= 0xBF
    }

    private func utf8ScalarLength(_ leadingByte: UInt8) -> Int? {
        switch leadingByte {
        case 0xC2...0xDF: 2
        case 0xE0...0xEF: 3
        case 0xF0...0xF4: 4
        default: nil
        }
    }

    private func lineCount(_ url: URL) -> Int {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              Int64(values.fileSize ?? 0) <= maxFileBytes,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return 0 }
        defer { try? handle.close() }
        var count = 0
        while autoreleasepool(invoking: {
            let data = try? handle.read(upToCount: 64 * 1024)
            guard let data, !data.isEmpty else { return false }
            count += data.reduce(0) { $0 + ($1 == 10 ? 1 : 0) }
            return true
        }) { }
        return count
    }

    private func redactSensitiveLines(in text: String) -> String {
        let markers = [
            "api_key", "apikey", "access_token", "auth_token", "password",
            "secret", "authorization", "private_key", "bearer ", "ghp_", "github_pat_", "sk-"
        ]
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let lowercased = line.lowercased()
            if markers.contains(where: { lowercased.contains($0) }) {
                return "[敏感内容已隐藏]"
            }
            return String(line)
        }.joined(separator: "\n")
    }

    private func knowledgeItems(records: [MemoryRecord], root: URL) -> [MemoryKnowledgeItem] {
        let recordByPath = Dictionary(uniqueKeysWithValues: records.map { ($0.relativePath, $0) })
        var drafts: [MemoryDraft] = []

        if let summary = recordByPath["memory_summary.md"],
           let text = fullText(for: summary, root: root) {
            drafts += parseSummary(text, source: summary)
        }

        if let curated = recordByPath["MEMORY.md"],
           let text = fullText(for: curated, root: root) {
            drafts += parseCurated(text, source: curated, records: recordByPath)
        }

        for record in records where record.kind == .adHoc && !record.relativePath.hasSuffix("/instructions.md") {
            guard let text = fullText(for: record, root: root) else { continue }
            drafts += parseAdHoc(text, source: record)
        }

        return merge(drafts)
    }

    private func parseSummary(_ text: String, source: MemoryRecord) -> [MemoryDraft] {
        let lines = text.components(separatedBy: .newlines)
        var drafts: [MemoryDraft] = []
        var category: MemoryCategory?
        var paragraph: [String] = []
        var paragraphLine = 1
        var projectHeading: String?
        var isInsideOlderTopics = false

        func flushParagraph() {
            guard let category, !paragraph.isEmpty else {
                paragraph.removeAll()
                return
            }
            let content = cleanMemoryText(paragraph.joined(separator: " "))
            if !content.isEmpty {
                drafts.append(draft(
                    category: category,
                    content: content,
                    scope: nil,
                    applicability: category == .project
                        ? projectApplicability(from: projectHeading ?? content, evidence: "memory_summary.md 的项目索引")
                        : .global,
                    active: true,
                    origin: .activeSummary,
                    source: source,
                    line: paragraphLine
                ))
            }
            paragraph.removeAll()
        }

        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                flushParagraph()
                let heading = String(trimmed.dropFirst(3)).lowercased()
                if heading == "user profile" {
                    category = .profile
                } else if heading == "user preferences" {
                    category = .preference
                } else if heading == "general tips" {
                    category = .experience
                } else if heading == "what's in memory" || heading == "whats in memory" {
                    category = .project
                    projectHeading = nil
                    isInsideOlderTopics = false
                } else {
                    category = nil
                }
                continue
            }
            guard let category else { continue }
            if category == .project, trimmed.hasPrefix("### ") {
                let heading = cleanMemoryText(String(trimmed.dropFirst(4)))
                isInsideOlderTopics = heading.lowercased() == "older memory topics"
                projectHeading = isInsideOlderTopics ? nil : heading
                continue
            }
            if category == .project, trimmed.hasPrefix("#### ") {
                let heading = cleanMemoryText(String(trimmed.dropFirst(5)))
                if isInsideOlderTopics, !isDateHeading(heading) {
                    projectHeading = heading
                }
                continue
            }
            if trimmed.hasPrefix("#") { continue }
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if trimmed.hasPrefix("- ") {
                flushParagraph()
                let content = cleanMemoryText(String(trimmed.dropFirst(2)))
                guard !content.isEmpty else { continue }
                let isIndented = rawLine.prefix { $0 == " " || $0 == "\t" }.count > 0
                if category == .project, isIndented, !drafts.isEmpty,
                   drafts[drafts.count - 1].category == .project {
                    drafts[drafts.count - 1].content += "\n" + content
                } else {
                    drafts.append(draft(
                        category: category,
                        content: content,
                        scope: nil,
                        applicability: category == .project
                            ? projectApplicability(from: projectHeading ?? content, evidence: "memory_summary.md 的项目索引")
                            : .global,
                        active: true,
                        origin: .activeSummary,
                        source: source,
                        line: lineNumber
                    ))
                }
                continue
            }
            if category == .profile {
                if paragraph.isEmpty { paragraphLine = lineNumber }
                paragraph.append(trimmed)
            }
        }
        flushParagraph()
        return drafts
    }

    private func parseCurated(
        _ text: String,
        source: MemoryRecord,
        records: [String: MemoryRecord]
    ) -> [MemoryDraft] {
        let lines = text.components(separatedBy: .newlines)
        var drafts: [MemoryDraft] = []
        var groupTitle: String?
        var groupScope: String?
        var groupApplicability: MemoryApplicability?
        var groupLine = 1
        var groupSourcePaths: [String] = []
        var category: MemoryCategory?

        func sourceReferences(line: Int) -> [MemorySourceReference] {
            var references = [reference(source, line: line)]
            for path in groupSourcePaths {
                guard let record = records[path] else { continue }
                references.append(reference(record, line: nil))
            }
            return references
        }

        func flushGroup() {
            guard let groupTitle else { return }
            let details = [groupTitle, groupScope].compactMap { $0 }.joined(separator: "\n")
            let content = cleanMemoryText(details)
            guard !content.isEmpty else { return }
            drafts.append(MemoryDraft(
                category: .project,
                content: content,
                scope: groupTitle,
                applicability: groupApplicability
                    ?? projectApplicability(from: groupTitle, evidence: "MEMORY.md 的 Task Group"),
                isActive: false,
                origin: .consolidated,
                sources: sourceReferences(line: groupLine),
                modifiedAt: source.modifiedAt
            ))
        }

        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# Task Group:") {
                flushGroup()
                groupTitle = cleanMemoryText(String(trimmed.dropFirst("# Task Group:".count)))
                groupScope = nil
                groupApplicability = nil
                groupSourcePaths = []
                groupLine = lineNumber
                category = nil
                continue
            }
            if trimmed.hasPrefix("scope:") {
                groupScope = cleanMemoryText(String(trimmed.dropFirst("scope:".count)))
                continue
            }
            if trimmed.hasPrefix("applies_to:") {
                let value = cleanMemoryText(String(trimmed.dropFirst("applies_to:".count)))
                let appliesTo = value.split(separator: ";", maxSplits: 1).first.map(String.init) ?? value
                groupApplicability = projectApplicability(
                    from: appliesTo,
                    evidence: "MEMORY.md 的 applies_to"
                )
                continue
            }
            if trimmed.hasPrefix("- "),
               let path = referencedMemoryPath(in: String(trimmed.dropFirst(2))) {
                if !groupSourcePaths.contains(path) { groupSourcePaths.append(path) }
            }
            if trimmed.hasPrefix("## ") {
                switch String(trimmed.dropFirst(3)).lowercased() {
                case "user preferences": category = .preference
                case "reusable knowledge": category = .experience
                case "failures and how to do differently": category = .caution
                default: category = nil
                }
                continue
            }
            guard let category, trimmed.hasPrefix("- ") else { continue }
            let content = cleanMemoryText(String(trimmed.dropFirst(2)))
            guard !content.isEmpty else { continue }
            drafts.append(MemoryDraft(
                category: category,
                content: content,
                scope: groupTitle,
                applicability: groupApplicability
                    ?? projectApplicability(from: groupTitle ?? content, evidence: "MEMORY.md 的 Task Group"),
                isActive: false,
                origin: .consolidated,
                sources: sourceReferences(line: lineNumber),
                modifiedAt: source.modifiedAt
            ))
        }
        flushGroup()
        return drafts
    }

    private func parseAdHoc(_ text: String, source: MemoryRecord) -> [MemoryDraft] {
        let lines = text.components(separatedBy: .newlines)
        var drafts: [MemoryDraft] = []
        for (offset, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else { continue }
            let content = cleanMemoryText(String(trimmed.dropFirst(2)))
            guard !content.isEmpty else { continue }
            drafts.append(draft(
                category: .manual,
                content: content,
                scope: nil,
                applicability: .unspecified,
                active: false,
                origin: .userNote,
                source: source,
                line: offset + 1
            ))
        }
        return drafts
    }

    private func merge(_ drafts: [MemoryDraft]) -> [MemoryKnowledgeItem] {
        var merged: [String: MemoryDraft] = [:]
        var order: [String] = []
        for draft in drafts {
            let key = normalizedMemoryText(draft.content)
            guard !key.isEmpty else { continue }
            if var existing = merged[key] {
                existing.isActive = existing.isActive || draft.isActive
                if draft.origin == .activeSummary {
                    existing.category = draft.category
                    existing.origin = .activeSummary
                }
                if existing.scope == nil { existing.scope = draft.scope }
                existing.applicability = mergeApplicability(existing.applicability, draft.applicability)
                if let date = draft.modifiedAt,
                   existing.modifiedAt == nil || date > existing.modifiedAt! {
                    existing.modifiedAt = date
                }
                for source in draft.sources where !existing.sources.contains(source) {
                    existing.sources.append(source)
                }
                merged[key] = existing
            } else {
                merged[key] = draft
                order.append(key)
            }
        }

        return order.compactMap { key in
            guard let draft = merged[key], let primary = draft.sources.first else { return nil }
            return MemoryKnowledgeItem(
                id: "\(primary.relativePath)#\(primary.line ?? 0)#\(draft.category.rawValue)",
                category: draft.category,
                content: draft.content,
                scope: draft.scope,
                applicability: draft.applicability,
                isActive: draft.isActive,
                origin: draft.origin,
                sources: draft.sources,
                modifiedAt: draft.modifiedAt
            )
        }.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive && !rhs.isActive }
            let lhsCategory = MemoryCategory.allCases.firstIndex(of: lhs.category) ?? .max
            let rhsCategory = MemoryCategory.allCases.firstIndex(of: rhs.category) ?? .max
            if lhsCategory != rhsCategory { return lhsCategory < rhsCategory }
            return lhs.content.localizedStandardCompare(rhs.content) == .orderedAscending
        }
    }

    private func draft(
        category: MemoryCategory,
        content: String,
        scope: String?,
        applicability: MemoryApplicability,
        active: Bool,
        origin: MemoryOrigin,
        source: MemoryRecord,
        line: Int
    ) -> MemoryDraft {
        MemoryDraft(
            category: category,
            content: content,
            scope: scope,
            applicability: applicability,
            isActive: active,
            origin: origin,
            sources: [reference(source, line: line)],
            modifiedAt: source.modifiedAt
        )
    }

    private func reference(_ record: MemoryRecord, line: Int?) -> MemorySourceReference {
        MemorySourceReference(
            relativePath: record.relativePath,
            absolutePath: record.absolutePath,
            line: line,
            kind: record.kind,
            modifiedAt: record.modifiedAt
        )
    }

    private func fullText(for record: MemoryRecord, root: URL) -> String? {
        guard record.status == .available,
              record.sizeBytes <= maxFileBytes
        else { return nil }
        let url = URL(fileURLWithPath: record.absolutePath).standardizedFileURL
        guard contains(url, inside: root),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let data = try? Data(contentsOf: url),
              Int64(data.count) <= maxFileBytes,
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return redactSensitiveLines(in: text)
    }

    private func referencedMemoryPath(in line: String) -> String? {
        let candidate = line.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        let path = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "`()"))
        guard path.hasPrefix("rollout_summaries/") || path.hasPrefix("extensions/") else { return nil }
        return path
    }

    private func cleanMemoryText(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["desc:", "learnings:", "description:"] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        text = text.replacingOccurrences(of: "[ad-hoc note]", with: "")
        text = DiagnosticRedactor.sanitize(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.prefix(2_000))
    }

    private func normalizedMemoryText(_ value: String) -> String {
        cleanMemoryText(value)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private func projectApplicability(from value: String, evidence: String) -> MemoryApplicability {
        let projects = projectReferences(from: value)
        guard !projects.isEmpty else { return .unspecified }
        return MemoryApplicability(kind: .project, projects: projects, evidence: evidence)
    }

    private func projectReferences(from value: String) -> [MemoryProjectReference] {
        var seen = Set<String>()
        return value.components(separatedBy: " and ").compactMap { rawPart in
            var context = cleanMemoryText(rawPart)
            if context.hasPrefix("cwd=") {
                context = String(context.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            }
            guard !context.isEmpty else { return nil }

            let path: String?
            let name: String
            if context.hasPrefix("/") {
                let normalized = URL(fileURLWithPath: context).standardizedFileURL.path
                path = normalized
                name = URL(fileURLWithPath: normalized).lastPathComponent
            } else {
                path = nil
                let components = context.split(separator: "/")
                let last = components.last.map(String.init) ?? context
                let quoteCharacters = CharacterSet(charactersIn: "“”\"")
                name = last.trimmingCharacters(in: .whitespacesAndNewlines.union(quoteCharacters))
                    .replacingOccurrences(of: "broader ", with: "", options: [.anchored, .caseInsensitive])
            }
            guard !name.isEmpty else { return nil }
            let key = path ?? context.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return MemoryProjectReference(name: name, path: path, context: context)
        }
    }

    private func mergeApplicability(
        _ lhs: MemoryApplicability,
        _ rhs: MemoryApplicability
    ) -> MemoryApplicability {
        var projects = lhs.projects
        for project in rhs.projects where !projects.contains(project) {
            projects.append(project)
        }

        let kind: MemoryApplicabilityKind
        if lhs.kind == .global || rhs.kind == .global {
            kind = .global
        } else if lhs.kind == .project || rhs.kind == .project {
            kind = .project
        } else {
            kind = .unspecified
        }
        let evidence = lhs.evidence ?? rhs.evidence
        return MemoryApplicability(kind: kind, projects: projects, evidence: evidence)
    }

    private func isDateHeading(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    private func safeDirectory(_ url: URL, inside root: URL) -> Bool {
        guard contains(url, inside: root), fileManager.fileExists(atPath: url.path) else { return false }
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        guard values.isDirectory == true,
              values.isSymbolicLink != true
        else { return false }
        return url.resolvingSymlinksInPath().standardizedFileURL == url.standardizedFileURL
    }

    private func relativePath(_ url: URL, root: URL) -> String {
        let path = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func contains(_ child: URL, inside root: URL) -> Bool {
        let childPath = child.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return childPath == rootPath || childPath.hasPrefix(rootPath + "/")
    }

    private func sortRecords(_ lhs: MemoryRecord, _ rhs: MemoryRecord) -> Bool {
        let lhsKind = MemoryKind.allCases.firstIndex(of: lhs.kind) ?? .max
        let rhsKind = MemoryKind.allCases.firstIndex(of: rhs.kind) ?? .max
        if lhsKind != rhsKind { return lhsKind < rhsKind }
        return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
    }
}

private struct MemoryDraft {
    var category: MemoryCategory
    var content: String
    var scope: String?
    var applicability: MemoryApplicability
    var isActive: Bool
    var origin: MemoryOrigin
    var sources: [MemorySourceReference]
    var modifiedAt: Date?
}
