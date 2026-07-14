import Foundation

struct MemorySnapshot: Sendable, Equatable {
    let codexHomePath: String
    let records: [MemoryRecord]
    let items: [MemoryKnowledgeItem]
    let warnings: [String]

    var totalSizeBytes: Int64 { records.reduce(0) { $0 + $1.sizeBytes } }
    var visibleRecords: [MemoryRecord] { records.filter { !$0.kind.isNoiseByDefault } }
    var activeItems: [MemoryKnowledgeItem] { items.filter(\.isActive) }
    var durableItems: [MemoryKnowledgeItem] { items.filter { !$0.isActive } }
}

struct MemoryKnowledgeItem: Identifiable, Hashable, Sendable {
    let id: String
    let category: MemoryCategory
    let content: String
    let scope: String?
    let applicability: MemoryApplicability
    let isActive: Bool
    let origin: MemoryOrigin
    let sources: [MemorySourceReference]
    let modifiedAt: Date?

    var searchText: String {
        ([
            content,
            scope ?? "",
            category.title,
            origin.title,
            applicability.kind.title,
            applicability.evidence ?? ""
        ] + applicability.projects.flatMap { [$0.name, $0.path ?? "", $0.context] }
            + sources.map(\.relativePath))
            .joined(separator: " ")
    }
}

struct MemoryApplicability: Hashable, Sendable {
    var kind: MemoryApplicabilityKind
    var projects: [MemoryProjectReference]
    var evidence: String?

    static let global = MemoryApplicability(
        kind: .global,
        projects: [],
        evidence: "来自 Memory 的跨项目摘要分区"
    )

    static let unspecified = MemoryApplicability(
        kind: .unspecified,
        projects: [],
        evidence: nil
    )

    var projectSummary: String? {
        guard !projects.isEmpty else { return nil }
        let names = projects.map(\.name)
        return names.count == 1 ? names[0] : "\(names[0]) 等 \(names.count) 个"
    }
}

enum MemoryApplicabilityKind: String, CaseIterable, Hashable, Sendable {
    case global
    case project
    case unspecified

    var title: String {
        switch self {
        case .global: "全局记忆"
        case .project: "项目相关"
        case .unspecified: "待确认范围"
        }
    }

    var explanation: String {
        switch self {
        case .global: "内容没有限定具体项目，Codex 可能在不同工作区中使用它。"
        case .project: "内容带有项目或工作区范围，使用时应结合关联项目理解。"
        case .unspecified: "这条记忆可能正在生效，但来源没有写明它适用于全局还是某个项目，需要人工确认。"
        }
    }

    var symbol: String {
        switch self {
        case .global: "globe"
        case .project: "folder.fill"
        case .unspecified: "questionmark.folder"
        }
    }
}

struct MemoryProjectReference: Identifiable, Hashable, Sendable {
    let name: String
    let path: String?
    let context: String

    var id: String { path ?? context }
}

enum MemoryInstructionBuilder {
    static func makeGlobal(for item: MemoryKnowledgeItem) -> String {
        """
        请检查并整理下面这条 Codex Memory。确认内容仍然准确后，将它明确整理为全局记忆，使其不限定具体项目；保留原意、避免创建重复条目，并告诉我最终修改了什么。

        记忆内容：
        \(item.content)

        来源定位：
        \(sourceLocator(for: item))
        """
    }

    static func associate(_ item: MemoryKnowledgeItem, with projectURL: URL) -> String {
        let project = projectURL.standardizedFileURL
        let name = project.lastPathComponent.isEmpty ? project.path : project.lastPathComponent
        return """
        请检查并整理下面这条 Codex Memory。确认内容仍然准确后，将它的适用范围明确关联到指定项目；保留原意、避免创建重复条目，并告诉我最终修改了什么。

        关联项目：\(name)
        项目路径：\(project.path)

        记忆内容：
        \(item.content)

        来源定位：
        \(sourceLocator(for: item))
        """
    }

    static func remove(_ item: MemoryKnowledgeItem) -> String {
        """
        请检查下面这条 Codex Memory。如果它确实已经不需要，请从当前生效摘要和长期记忆中移除对应内容。执行前核对来源定位，只处理这一条，避免影响其他 Memory，并告诉我最终修改了什么。

        记忆内容：
        \(item.content)

        来源定位：
        \(sourceLocator(for: item))
        """
    }

    private static func sourceLocator(for item: MemoryKnowledgeItem) -> String {
        item.sources.map { source in
            "- \(source.relativePath)\(source.line.map { "：第 \($0) 行" } ?? "")"
        }.joined(separator: "\n")
    }
}

struct MemorySourceReference: Identifiable, Hashable, Sendable {
    let relativePath: String
    let absolutePath: String
    let line: Int?
    let kind: MemoryKind
    let modifiedAt: Date?

    var id: String { "\(relativePath)#\(line ?? 0)" }
}

enum MemoryCategory: String, CaseIterable, Hashable, Sendable {
    case profile
    case preference
    case project
    case experience
    case caution
    case manual

    var title: String {
        switch self {
        case .profile: "用户画像"
        case .preference: "用户偏好"
        case .project: "项目与主题"
        case .experience: "可复用经验"
        case .caution: "注意与验证"
        case .manual: "用户补充"
        }
    }

    var explanation: String {
        switch self {
        case .profile: "Codex 对你的长期工作方式和关注方向的概括。"
        case .preference: "过去任务中反复确认、可能影响以后协作方式的偏好。"
        case .project: "用于帮助 Codex 识别项目、工作主题和相关上下文。"
        case .experience: "过去任务中提炼出的可复用经验和处理方法。"
        case .caution: "容易过期、需要实时核对，或曾经出现过问题的内容。"
        case .manual: "由用户明确补充的记忆材料。"
        }
    }

    var symbol: String {
        switch self {
        case .profile: "person.crop.circle"
        case .preference: "heart.text.square"
        case .project: "folder"
        case .experience: "lightbulb"
        case .caution: "exclamationmark.triangle"
        case .manual: "square.and.pencil"
        }
    }
}

enum MemoryOrigin: String, Hashable, Sendable {
    case activeSummary
    case consolidated
    case userNote

    var title: String {
        switch self {
        case .activeSummary: "当前生效摘要"
        case .consolidated: "长期整理记忆"
        case .userNote: "用户补充"
        }
    }
}

struct MemoryRecord: Identifiable, Hashable, Sendable {
    let kind: MemoryKind
    let title: String
    let relativePath: String
    let absolutePath: String
    let sizeBytes: Int64
    let lineCount: Int
    let modifiedAt: Date?
    let preview: String?
    let isCollapsedByDefault: Bool
    let status: MemoryRecordStatus

    var id: String { relativePath }
}

enum MemoryRecordStatus: String, Hashable, Sendable {
    case available
    case tooLarge
    case unreadable

    var title: String {
        switch self {
        case .available: "可预览"
        case .tooLarge: "文件过大"
        case .unreadable: "无法读取"
        }
    }
}

enum MemoryKind: String, CaseIterable, Hashable, Sendable {
    case curated
    case summary
    case raw
    case rollout
    case chronicle
    case adHoc
    case unknown

    var title: String {
        switch self {
        case .curated: "整理记忆"
        case .summary: "摘要"
        case .raw: "原始池"
        case .rollout: "运行摘要"
        case .chronicle: "Chronicle"
        case .adHoc: "临时补充"
        case .unknown: "其他"
        }
    }

    var explanation: String {
        switch self {
        case .curated: "适合优先阅读的长期记忆入口。"
        case .summary: "压缩后的主题索引，适合快速定位。"
        case .raw: "较原始的记忆材料，默认折叠以减少噪声。"
        case .rollout: "历史任务的结构化回放摘要，通常只在追溯时查看。"
        case .chronicle: "高频活动记录，体量大且上下文碎，默认折叠。"
        case .adHoc: "手动或临时追加的记忆补充。"
        case .unknown: "未识别用途的记忆文件，只读展示。"
        }
    }

    var symbol: String {
        switch self {
        case .curated: "text.book.closed"
        case .summary: "list.bullet.rectangle"
        case .raw: "tray.full"
        case .rollout: "clock.arrow.circlepath"
        case .chronicle: "waveform.path.ecg"
        case .adHoc: "square.and.pencil"
        case .unknown: "questionmark.folder"
        }
    }

    var isNoiseByDefault: Bool {
        switch self {
        case .raw, .chronicle: true
        default: false
        }
    }
}
