import AppKit
import SwiftUI
@preconcurrency import Translation

struct MemoryView: View {
    @Environment(AppModel.self) private var model
    @State private var mode: MemoryViewMode = .knowledge
    @State private var selectedItemID: String?
    @State private var selectedRecordID: String?
    @State private var selectedCategory: MemoryCategory?
    @State private var selectedApplicability: MemoryApplicabilityKind?
    @State private var selectedSourceKind: MemoryKind?
    @State private var searchText = ""
    @State private var translations = MemoryTranslationCache.load()
    @State private var isTranslating = false
    @State private var translationError: String?

    @ViewBuilder
    var body: some View {
        if #available(macOS 15.0, *) {
            content
                .modifier(
                    MemoryTranslationTask(
                        sources: translationSources,
                        translations: $translations,
                        isTranslating: $isTranslating,
                        translationError: $translationError
                    )
                )
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Picker("显示内容", selection: $mode) {
                ForEach(MemoryViewMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            .padding(12)
            Divider()

            switch mode {
            case .knowledge:
                knowledgeView
            case .sources:
                sourcesView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Codex Memory")
        .task {
            await model.scanMemory()
            chooseInitialSelections()
        }
        .onChange(of: filteredItems.map(\.id)) { _, ids in
            if let selectedItemID, ids.contains(selectedItemID) { return }
            selectedItemID = ids.first
        }
        .onChange(of: filteredRecords.map(\.id)) { _, ids in
            if let selectedRecordID, ids.contains(selectedRecordID) { return }
            selectedRecordID = ids.first
        }
        .onChange(of: mode) { _, _ in
            searchText = ""
        }
        .toolbar {
            Button { Task { await model.scanMemory() } } label: {
                Label("刷新 Memory", systemImage: "arrow.clockwise")
            }
            .disabled(model.isScanningMemory)
        }
    }

    private var knowledgeView: some View {
        GeometryReader { geometry in
            HSplitView {
                VStack(spacing: 0) {
                    knowledgeControls
                    Divider()
                    if model.isScanningMemory && model.memorySnapshot == nil {
                        loading
                    } else if filteredItems.isEmpty {
                        ContentUnavailableView(
                            "没有匹配的记忆内容",
                            systemImage: "brain",
                            description: Text(model.memoryError ?? "调整搜索或分类，或者切换到“来源文件”查看 Codex 的生成材料。")
                        )
                    } else {
                        List(selection: $selectedItemID) {
                            if !activeItems.isEmpty {
                                Section("当前生效 · \(activeItems.count)") {
                                    ForEach(activeItems) { item in
                                        MemoryItemRow(item: item, translated: translated(item.content))
                                            .tag(item.id)
                                    }
                                }
                            }
                            if !durableItems.isEmpty {
                                Section("长期记忆 · \(durableItems.count)") {
                                    ForEach(durableItems) { item in
                                        MemoryItemRow(item: item, translated: translated(item.content))
                                            .tag(item.id)
                                    }
                                }
                            }
                        }
                        .listStyle(.inset)
                        .scrollContentBackground(.hidden)
                    }
                }
                .frame(minWidth: 300, idealWidth: 350, maxWidth: 390)
                .frame(height: geometry.size.height, alignment: .top)
                .background(WorkbenchTheme.panel)

                Group {
                    if let selectedItem {
                        MemoryItemDetail(
                            item: selectedItem,
                            workspaceURL: model.workspaceURL,
                            translatedContent: translated(selectedItem.content),
                            isTranslating: isTranslating,
                            translationError: translationError
                        )
                        .id(selectedItem.id)
                    } else {
                        ContentUnavailableView(
                            "选择一条记忆",
                            systemImage: "brain",
                            description: Text("查看 Codex 记住的内容、是否正在生效以及来源证据。")
                        )
                        .frame(minWidth: 360)
                    }
                }
                .frame(height: geometry.size.height, alignment: .top)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }

    private var sourcesView: some View {
        GeometryReader { geometry in
            HSplitView {
                VStack(spacing: 0) {
                    sourceControls
                    Divider()
                    if model.isScanningMemory && model.memorySnapshot == nil {
                        loading
                    } else if filteredRecords.isEmpty {
                        ContentUnavailableView(
                            "没有匹配的来源文件",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text(model.memoryError ?? "未发现符合条件的 Memory 来源文件。")
                        )
                    } else {
                        List(filteredRecords, selection: $selectedRecordID) { record in
                            MemorySourceRow(record: record).tag(record.id)
                        }
                        .listStyle(.inset)
                    }
                }
                .frame(minWidth: 300, idealWidth: 350, maxWidth: 390)
                .frame(height: geometry.size.height, alignment: .top)

                Group {
                    if let selectedRecord {
                        MemorySourceDetail(record: selectedRecord)
                            .id(selectedRecord.id)
                    } else {
                        ContentUnavailableView(
                            "选择一个来源文件",
                            systemImage: "doc.text",
                            description: Text("来源文件只用于追溯和排查，不等同于一条正在生效的记忆。")
                        )
                        .frame(minWidth: 360)
                    }
                }
                .frame(height: geometry.size.height, alignment: .top)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }

    private var knowledgeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Codex 记住了什么")
                        .font(.callout.weight(.semibold))
                    if let snapshot = model.memorySnapshot {
                        let projectCount = snapshot.items.filter { $0.applicability.kind == .project }.count
                        Text("\(snapshot.activeItems.count) 条当前生效 · \(snapshot.durableItems.count) 条长期记忆 · \(projectCount) 条项目相关")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if model.isScanningMemory || isTranslating {
                    ProgressView().controlSize(.small)
                }
            }
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索记忆内容、项目或来源", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(9)
            .background(WorkbenchTheme.subtleFill, in: RoundedRectangle(cornerRadius: 9))

            HStack {
                Picker("分类", selection: $selectedCategory) {
                    Text("全部分类").tag(MemoryCategory?.none)
                    ForEach(MemoryCategory.allCases, id: \.self) { category in
                        Text(category.title).tag(Optional(category))
                    }
                }
                .pickerStyle(.menu)

                Picker("范围", selection: $selectedApplicability) {
                    Text("全部范围").tag(MemoryApplicabilityKind?.none)
                    ForEach(MemoryApplicabilityKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(Optional(kind))
                    }
                }
                .pickerStyle(.menu)
            }

            Text("范围表示内容适用于哪里；Memory 文件仍统一保存在 Codex Home。")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if let translationError {
                Label("自动翻译暂不可用：\(translationError)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            warningLabels
        }
        .padding(12)
    }

    private var sourceControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("来源文件")
                        .font(.callout.weight(.semibold))
                    Text("用于追溯 Memory 的生成层、任务摘要与 Chronicle 观察材料。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isScanningMemory { ProgressView().controlSize(.small) }
            }
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索文件名或路径", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(9)
            .background(WorkbenchTheme.subtleFill, in: RoundedRectangle(cornerRadius: 9))

            Picker("来源类型", selection: $selectedSourceKind) {
                Text("全部来源").tag(MemoryKind?.none)
                ForEach(MemoryKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(Optional(kind))
                }
            }
            .pickerStyle(.menu)

            if let snapshot = model.memorySnapshot {
                Text("\(snapshot.records.count) 个来源文件 · \(memoryByteText(snapshot.totalSizeBytes))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            warningLabels
        }
        .padding(12)
    }

    @ViewBuilder
    private var warningLabels: some View {
        if let error = model.memoryError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        ForEach(model.memorySnapshot?.warnings ?? [], id: \.self) { warning in
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var loading: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在读取 Codex Memory…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredItems: [MemoryKnowledgeItem] {
        let items = model.memorySnapshot?.items ?? []
        return items.filter { item in
            guard selectedCategory == nil || item.category == selectedCategory else { return false }
            guard selectedApplicability == nil || item.applicability.kind == selectedApplicability else { return false }
            guard !searchText.isEmpty else { return true }
            return [item.searchText, translated(item.content) ?? ""]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(searchText)
        }
    }

    private var activeItems: [MemoryKnowledgeItem] { filteredItems.filter(\.isActive) }
    private var durableItems: [MemoryKnowledgeItem] { filteredItems.filter { !$0.isActive } }

    private var filteredRecords: [MemoryRecord] {
        let records = model.memorySnapshot?.records ?? []
        return records.filter { record in
            guard selectedSourceKind == nil || record.kind == selectedSourceKind else { return false }
            guard !searchText.isEmpty else { return true }
            return [record.title, record.relativePath, record.kind.title]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedItem: MemoryKnowledgeItem? {
        guard let selectedItemID else { return nil }
        return model.memorySnapshot?.items.first { $0.id == selectedItemID }
    }

    private var selectedRecord: MemoryRecord? {
        guard let selectedRecordID else { return nil }
        return model.memorySnapshot?.records.first { $0.id == selectedRecordID }
    }

    private var translationSources: [String] {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return [] }
        var seen = Set<String>()
        return (model.memorySnapshot?.items ?? [])
            .map(\.content)
            .filter {
                SkillTranslationPolicy.needsChineseTranslation($0)
                    && seen.insert($0).inserted
            }
    }

    private func translated(_ source: String) -> String? {
        guard let value = translations[source], !value.isEmpty, value != source else { return nil }
        return value
    }

    private func chooseInitialSelections() {
        if selectedItemID == nil { selectedItemID = filteredItems.first?.id }
        if selectedRecordID == nil { selectedRecordID = filteredRecords.first?.id }
    }
}

private enum MemoryViewMode: String, CaseIterable, Identifiable {
    case knowledge
    case sources
    var id: String { rawValue }
    var title: String { self == .knowledge ? "记忆内容" : "来源文件" }
}

private struct MemoryItemRow: View {
    let item: MemoryKnowledgeItem
    let translated: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.category.symbol)
                .font(.title3)
                .foregroundStyle(item.isActive ? Color.teal : Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(translated ?? item.content)
                    .font(.callout.weight(.medium))
                    .lineLimit(3)
                HStack(spacing: 6) {
                    Text(item.category.title)
                    Text("·")
                    Text(item.isActive ? "当前生效" : item.origin.title)
                }
                .font(.caption2)
                .foregroundStyle(item.isActive ? Color.teal : Color.secondary)
                Label(applicabilityText, systemImage: item.applicability.kind.symbol)
                    .font(.caption2)
                    .foregroundStyle(item.applicability.kind == .project ? Color.blue : Color.secondary)
                    .lineLimit(1)
                if let scope = item.scope, !scope.isEmpty {
                    Text(scope)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private var applicabilityText: String {
        guard item.applicability.kind == .project,
              let projects = item.applicability.projectSummary
        else { return item.applicability.kind.title }
        return "项目 · \(projects)"
    }
}

private struct MemoryItemDetail: View {
    let item: MemoryKnowledgeItem
    let workspaceURL: URL
    let translatedContent: String?
    let isTranslating: Bool
    let translationError: String?
    @State private var showsOriginal = false
    @State private var copied = false
    @State private var copiedManagementAction: MemoryManagementAction?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.category.title)
                            .font(.largeTitle.bold())
                        HStack {
                            StatusBadge(
                                text: item.isActive ? "当前生效" : "长期记忆",
                                color: item.isActive ? .teal : .secondary,
                                symbol: item.isActive ? "checkmark.circle.fill" : "text.book.closed"
                            )
                            StatusBadge(text: item.origin.title, color: .blue)
                            StatusBadge(
                                text: item.applicability.kind.title,
                                color: item.applicability.kind == .project ? .blue : .secondary,
                                symbol: item.applicability.kind.symbol
                            )
                        }
                    }
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.content, forType: .string)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            copied = false
                        }
                    } label: {
                        Label(copied ? "已复制" : "复制内容", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }

                detailSection("Codex 记住的内容") {
                    Text(displayedContent)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if translatedContent != nil {
                        HStack(spacing: 10) {
                            Label("由 macOS 自动翻译", systemImage: "character.book.closed")
                            Button(showsOriginal ? "显示中文" : "查看原文") {
                                showsOriginal.toggle()
                            }
                            .buttonStyle(.link)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else if isTranslating && SkillTranslationPolicy.needsChineseTranslation(item.content) {
                        Label("正在使用 macOS 翻译…", systemImage: "character.book.closed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let translationError, SkillTranslationPolicy.needsChineseTranslation(item.content) {
                        Text("自动翻译暂不可用：\(translationError)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                detailSection("这条记忆代表什么") {
                    Text(item.category.explanation)
                        .foregroundStyle(.secondary)
                    LabeledContent("状态", value: item.isActive ? "已进入当前生效摘要" : "保存在长期记忆中，按需召回")
                    LabeledContent("来源类型", value: item.origin.title)
                    if let scope = item.scope, !scope.isEmpty {
                        LabeledContent("记忆主题", value: scope)
                    }
                    if let modifiedAt = item.modifiedAt {
                        LabeledContent("最近更新", value: modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                detailSection("适用范围") {
                    Label(item.applicability.kind.title, systemImage: item.applicability.kind.symbol)
                        .font(.headline)
                    Text(item.applicability.kind.explanation)
                        .foregroundStyle(.secondary)

                    if !item.applicability.projects.isEmpty {
                        Divider()
                        Text(item.applicability.kind == .global ? "相关项目来源" : "关联项目")
                            .font(.callout.weight(.semibold))
                        ForEach(item.applicability.projects) { project in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(project.name, systemImage: project.path == nil ? "rectangle.stack" : "folder")
                                    .font(.callout.weight(.semibold))
                                Text(project.path ?? project.context)
                                    .font(.system(.caption, design: project.path == nil ? .default : .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    if let evidence = item.applicability.evidence {
                        LabeledContent("判断依据", value: evidence)
                    }
                    Text("这里显示的是内容的语义范围，不代表 Codex 为每个项目建立了独立 Memory 数据库。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if item.applicability.kind == .unspecified {
                    detailSection("整理这条记忆") {
                        Text("选择希望的处理方式。Workbench 只会生成并复制一段修改指令，由你粘贴给 Codex 后再执行，不会直接改写 Memory 文件。")
                            .foregroundStyle(.secondary)

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 120), spacing: 10)],
                            alignment: .leading,
                            spacing: 10
                        ) {
                            Button {
                                copyManagementInstruction(
                                    MemoryInstructionBuilder.makeGlobal(for: item),
                                    action: .makeGlobal
                                )
                            } label: {
                                Label("设为全局", systemImage: "globe")
                            }

                            Button {
                                chooseProjectAndCopyInstruction()
                            } label: {
                                Label("关联项目…", systemImage: "folder.badge.plus")
                            }

                            Button {
                                copyManagementInstruction(
                                    MemoryInstructionBuilder.remove(item),
                                    action: .remove
                                )
                            } label: {
                                Label("不再需要", systemImage: "trash")
                            }
                        }
                        .buttonStyle(.bordered)

                        if let copiedManagementAction {
                            Label(
                                "已复制“\(copiedManagementAction.title)”指令，请粘贴到 Codex。",
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.green)
                        }
                    }
                }

                detailSection("来源证据") {
                    ForEach(item.sources) { source in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(source.kind.title, systemImage: source.kind.symbol)
                                    .font(.callout.weight(.semibold))
                                Spacer()
                                Button("Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: source.absolutePath)])
                                }
                                .font(.caption)
                            }
                            Text(source.relativePath + (source.line.map { " · 第 \($0) 行" } ?? ""))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            if let modifiedAt = source.modifiedAt {
                                Text(modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        if source.id != item.sources.last?.id { Divider() }
                    }
                }

                Label(
                    "如果内容不准确，复制后直接在 Codex 中说明你希望怎么修改。Workbench 只负责展示，不会改写 Codex 生成的 Memory 文件。",
                    systemImage: "bubble.left.and.bubble.right"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .frame(minWidth: 360)
    }

    private var displayedContent: String {
        if showsOriginal { return item.content }
        return translatedContent ?? item.content
    }

    private func chooseProjectAndCopyInstruction() {
        let panel = NSOpenPanel()
        panel.title = "选择这条 Memory 关联的项目"
        panel.prompt = "关联此项目"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = workspaceURL
        guard panel.runModal() == .OK, let projectURL = panel.url else { return }
        copyManagementInstruction(
            MemoryInstructionBuilder.associate(item, with: projectURL),
            action: .associateProject
        )
    }

    private func copyManagementInstruction(_ instruction: String, action: MemoryManagementAction) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(instruction, forType: .string)
        copiedManagementAction = action
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if copiedManagementAction == action {
                copiedManagementAction = nil
            }
        }
    }

    @ViewBuilder
    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkbenchTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }
}

private enum MemoryManagementAction: Equatable {
    case makeGlobal
    case associateProject
    case remove

    var title: String {
        switch self {
        case .makeGlobal: "设为全局"
        case .associateProject: "关联项目"
        case .remove: "不再需要"
        }
    }
}

private struct MemorySourceRow: View {
    let record: MemoryRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: record.kind.symbol)
                .font(.title3)
                .foregroundStyle(record.kind.isNoiseByDefault ? Color.secondary : Color.teal)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title).font(.headline).lineLimit(1)
                Text(record.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(record.lineCount) 行 · \(memoryByteText(record.sizeBytes))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 5)
    }
}

private struct MemorySourceDetail: View {
    @Environment(AppModel.self) private var model
    let record: MemoryRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(record.title).font(.largeTitle.bold())
                        HStack {
                            StatusBadge(text: record.kind.title, color: record.kind.isNoiseByDefault ? .secondary : .teal, symbol: record.kind.symbol)
                            StatusBadge(text: "来源材料", color: .secondary)
                        }
                    }
                    Spacer()
                    Button { model.revealInFinder(path: record.absolutePath) } label: {
                        Label("Finder", systemImage: "folder")
                    }
                }

                sourceSection("用途") {
                    Text(record.kind.explanation)
                        .foregroundStyle(.secondary)
                    Text("这个文件用于追溯 Memory 的来源或生成过程，不代表其中每一行都会在当前任务中生效。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                sourceSection("文件信息") {
                    LabeledContent("路径", value: record.relativePath)
                    LabeledContent("大小", value: memoryByteText(record.sizeBytes))
                    LabeledContent("行数", value: "\(record.lineCount)")
                    if let modifiedAt = record.modifiedAt {
                        LabeledContent("修改时间", value: modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                sourceSection("有限预览") {
                    if let preview = record.preview, !preview.isEmpty {
                        Text(preview)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(record.kind.isNoiseByDefault ? "这类来源默认不读取正文，避免把大量原始记录或 Chronicle 噪声放到前台。" : "没有可预览内容。")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .frame(minWidth: 360)
    }

    @ViewBuilder
    private func sourceSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkbenchTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }
}

private enum MemoryTranslationCache {
    private static let defaultsKey = "memory-content-translations.zh-Hans.v1"

    static func load() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    static func save(_ translations: [String: String]) {
        UserDefaults.standard.set(translations, forKey: defaultsKey)
    }
}

@available(macOS 15.0, *)
private struct MemoryTranslationTask: ViewModifier {
    let sources: [String]
    @Binding var translations: [String: String]
    @Binding var isTranslating: Bool
    @Binding var translationError: String?

    @State private var configuration: TranslationSession.Configuration?
    @State private var requestedSources: [String] = []

    func body(content: Content) -> some View {
        content
            .task(id: pendingSources) {
                requestTranslation(for: pendingSources)
            }
            .translationTask(configuration) { session in
                await translate(using: session)
            }
    }

    private var pendingSources: [String] {
        sources.filter { translations[$0] == nil }
    }

    @MainActor
    private func requestTranslation(for pending: [String]) {
        guard !pending.isEmpty else {
            isTranslating = false
            return
        }
        requestedSources = pending
        isTranslating = true
        translationError = nil
        if configuration == nil {
            configuration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "zh-Hans")
            )
        } else {
            configuration?.invalidate()
        }
    }

    @MainActor
    private func translate(using session: TranslationSession) async {
        let pending = requestedSources.filter { translations[$0] == nil }
        guard !pending.isEmpty else {
            isTranslating = false
            return
        }
        var updated = translations
        var translatedCount = 0
        var consecutiveFailures = 0
        var failedCount = 0
        var lastError: String?
        for source in pending {
            do {
                let response = try await session.translate(source)
                let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translated.isEmpty else { continue }
                updated[source] = translated
                translatedCount += 1
                consecutiveFailures = 0
                if translatedCount.isMultiple(of: 20) {
                    MemoryTranslationCache.save(updated)
                }
            } catch is CancellationError {
                return
            } catch {
                failedCount += 1
                consecutiveFailures += 1
                lastError = error.localizedDescription
                // A few malformed entries should not block the rest. When the
                // system translation service itself is unavailable, stop
                // quickly instead of retrying the whole Memory library.
                if consecutiveFailures >= 3 { break }
            }
        }
        translations = updated
        MemoryTranslationCache.save(updated)
        translationError = failedCount == 0
            ? nil
            : "\(failedCount) 条暂未完成：\(lastError ?? "系统翻译服务不可用")"
        isTranslating = false
    }
}

private func memoryByteText(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
