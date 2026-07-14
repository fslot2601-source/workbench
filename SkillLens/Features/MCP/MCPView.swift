import AppKit
import SwiftUI
@preconcurrency import Translation

struct MCPView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: String?
    @State private var searchText = ""
    @State private var filter: MCPListFilter = .all
    @State private var translations = MCPTranslationCache.load()
    @State private var isTranslating = false
    @State private var translationError: String?
    @State private var confirmsReloadAll = false

    @ViewBuilder
    var body: some View {
        if #available(macOS 15.0, *) {
            content
                .modifier(
                    MCPTranslationTask(
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
        GeometryReader { geometry in
            let titleBarInset = min(geometry.safeAreaInsets.top, 52)
            let contentHeight = max(0, geometry.size.height - titleBarInset)

            HSplitView {
                VStack(spacing: 0) {
                    listHeader
                    Divider()
                    if model.mcpServers.isEmpty && model.isRefreshingMCP {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("正在读取 MCP 配置与能力…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if model.mcpServers.isEmpty {
                        ContentUnavailableView(
                            "没有发现 MCP Server",
                            systemImage: "server.rack",
                            description: Text(model.mcpError ?? "当前有效配置中没有 MCP。")
                        )
                    } else if filteredServers.isEmpty {
                        VStack(spacing: 12) {
                            ContentUnavailableView(
                                searchText.isEmpty ? "“\(filter.title)”中没有 MCP" : "没有匹配的 MCP",
                                systemImage: searchText.isEmpty ? "line.3.horizontal.decrease.circle" : "magnifyingglass",
                                description: Text(
                                    searchText.isEmpty
                                        ? "当前没有符合这个状态的 MCP，可以切换到“全部”继续查看。"
                                        : "更换搜索词，或清除筛选条件。"
                                )
                            )
                            Button("查看全部") {
                                searchText = ""
                                filter = .all
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(filteredServers, selection: $selectedID) { server in
                            MCPRow(server: server, translatedPurpose: translatedText(for: server.purposeSummary))
                                .tag(server.id)
                        }
                        .listStyle(.inset)
                        .scrollContentBackground(.hidden)
                    }
                }
                .frame(minWidth: 320, idealWidth: 350, maxWidth: 390)
                .frame(height: contentHeight, alignment: .top)
                .background(WorkbenchTheme.panel)

                Group {
                    if let selectedServer {
                        MCPDetailView(
                            server: selectedServer,
                            translations: translations,
                            isTranslating: isTranslating,
                            translationError: translationError
                        )
                        .id(selectedServer.id)
                    } else {
                        ContentUnavailableView("选择一个 MCP", systemImage: "server.rack")
                            .frame(minWidth: 420)
                    }
                }
                .frame(height: contentHeight, alignment: .top)
                .background(WorkbenchTheme.canvas)
            }
            .frame(width: geometry.size.width, height: contentHeight, alignment: .topLeading)
            .padding(.top, titleBarInset)
        }
        .navigationTitle("MCP")
        .accessibilityIdentifier("screen-mcp")
        .task {
            await model.refreshMCP()
            if selectedID == nil { selectedID = preferredSelectionID }
        }
        .onChange(of: filteredServers.map(\.id)) { _, ids in
            if let selectedID, ids.contains(selectedID) { return }
            selectedID = preferredSelectionID ?? ids.first
        }
        .toolbar {
            Button { Task { await model.refreshMCP() } } label: {
                Label("重新检测 MCP", systemImage: "arrow.clockwise")
            }
            .disabled(model.isRefreshingMCP || model.isReloadingAllMCP)
        }
        .confirmationDialog("重新加载全部 MCP？", isPresented: $confirmsReloadAll) {
            Button("重新加载全部") {
                Task { await model.reloadAllMCP() }
            }
        } message: {
            Text("Codex 的重载接口会让 Workbench 当前连接中的所有 MCP 一起重新启动或连接。过程中保留上一轮状态，完成后统一更新；不会修改任何开关。")
        }
    }

    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("配置、连接与工具状态").font(.callout.weight(.semibold))
                    Text("\(effectiveCount) 个已生效 · \(enabledCount) 个已启用 · \(problemCount) 个问题")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isRefreshingMCP { ProgressView().controlSize(.small) }
            }

            TextField("搜索名称、用途或工具", text: $searchText)
                .textFieldStyle(.roundedBorder)

            Picker("筛选", selection: $filter) {
                ForEach(MCPListFilter.allCases) { item in Text(item.title).tag(item) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if pendingReloadCount > 0 {
                HStack {
                    Label("\(pendingReloadCount) 项配置等待重新加载", systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("重新加载全部") { confirmsReloadAll = true }
                        .font(.caption)
                        .disabled(model.isRefreshingMCP || model.isReloadingAllMCP)
                }
            } else if model.isReloadingAllMCP {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在重新加载全部 MCP，暂时保留上一轮状态…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let warning = model.mcpWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let error = model.mcpError {
                Label(error, systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
    }

    private var filteredServers: [MCPRecord] {
        model.mcpServers.filter { server in
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .effective: server.effectiveState == .effective
            case .checking: server.isReloadPending || [.starting, .configuredOnly, .statusUnavailable].contains(server.effectiveState)
            case .disabled: server.effectiveState == .disabled
            case .problem: server.hasProblem
            }
            guard matchesFilter else { return false }
            guard !searchText.isEmpty else { return true }
            let toolText = server.tools.flatMap { [$0.name, $0.title, $0.description].compactMap { $0 } }.joined(separator: " ")
            return [server.name, server.displayName, server.purposeSummary, translatedText(for: server.purposeSummary) ?? "", toolText]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedServer: MCPRecord? {
        guard let selectedID else { return nil }
        return model.mcpServers.first { $0.id == selectedID }
    }

    private var translationSources: [String] {
        var candidates = model.mcpServers.map(\.purposeSummary)
        if let selectedServer {
            candidates += selectedServer.tools.compactMap(\.description)
            candidates += selectedServer.resources.compactMap(\.description)
        }
        var seen = Set<String>()
        return candidates.filter { SkillTranslationPolicy.needsChineseTranslation($0) && seen.insert($0).inserted }
    }

    private func translatedText(for source: String) -> String? {
        guard let value = translations[source], !value.isEmpty, value != source else { return nil }
        return value
    }

    private var effectiveCount: Int { model.mcpServers.filter { $0.effectiveState == .effective }.count }
    private var enabledCount: Int { model.mcpServers.filter(\.configuredEnabledState).count }
    private var problemCount: Int { model.mcpServers.filter(\.hasProblem).count }
    private var pendingReloadCount: Int { model.mcpServers.filter(\.isReloadPending).count }
    private var preferredSelectionID: String? {
        model.mcpServers.first(where: \.hasProblem)?.id
            ?? model.mcpServers.first(where: { $0.effectiveState == .effective })?.id
            ?? model.mcpServers.first?.id
    }
}

private enum MCPListFilter: String, CaseIterable, Identifiable {
    case all, effective, checking, disabled, problem
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "全部"
        case .effective: "生效"
        case .checking: "待确认"
        case .disabled: "停用"
        case .problem: "问题"
        }
    }
}

private struct MCPRow: View {
    let server: MCPRecord
    let translatedPurpose: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: server.effectiveState.symbol)
                .foregroundStyle(server.effectiveState.color)
                .font(.title3)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(server.displayName).font(.headline).lineLimit(1)
                Text(translatedPurpose ?? server.purposeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("\(server.transport.title) · \(server.toolCount) 工具 · \(server.resourceCount + server.resourceTemplateCount) 资源")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(server.effectiveState.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(server.effectiveState.color)
                if server.isReloadPending {
                    Text("配置待重新加载")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

private struct MCPDetailView: View {
    @Environment(AppModel.self) private var model
    let server: MCPRecord
    let translations: [String: String]
    let isTranslating: Bool
    let translationError: String?
    @State private var confirmsChange = false
    @State private var isChanging = false
    @State private var showsStatusGuide = false
    @State private var showsOriginalPurpose = false
    @State private var conversationTestTarget: MCPConversationTestTarget?
    @State private var toolSearchText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                detailSection("它是做什么的") {
                    Text(displayedPurpose).textSelection(.enabled)
                    translationFooter
                }

                detailSection("暴露的功能") {
                    Text("这里逐项显示 MCP 暴露给 Codex 的工具。‘已暴露’表示 Codex 能看到功能定义，不代表已经真实调用成功。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if server.tools.isEmpty {
                        Label(
                            server.isEnabled ? "当前没有读取到已暴露的功能。" : "启用并重新检测后，功能会显示在这里。",
                            systemImage: "wrench.and.screwdriver"
                        )
                        .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Text("\(server.toolCount) 个功能")
                                .font(.callout.weight(.semibold))
                            Spacer()
                            if server.toolCount > 5 {
                                TextField("搜索功能名称或用途", text: $toolSearchText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 280)
                            }
                        }
                        if filteredTools.isEmpty {
                            ContentUnavailableView.search(text: toolSearchText)
                                .frame(minHeight: 150)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(filteredTools) { tool in
                                    exposedToolRow(tool)
                                }
                            }
                        }
                    }
                }

                detailSection("生效状态") {
                    Text("从配置到工具暴露逐层检查；哪一层未通过，就从哪一层处理。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(server.healthChecks) { check in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: check.status.symbol)
                                .foregroundStyle(check.status.color)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(check.title).fontWeight(.semibold)
                                    Text(check.status.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(check.status.color)
                                }
                                Text(check.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    Button {
                        Task { await model.refreshMCP() }
                    } label: {
                        Label(model.isRefreshingMCP ? "正在检测…" : "重新检测", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isRefreshingMCP)
                }

                detailSection("资源与模板") {
                    LabeledContent("已暴露功能", value: "\(server.toolCount)")
                    LabeledContent("资源", value: "\(server.resourceCount)")
                    LabeledContent("资源模板", value: "\(server.resourceTemplateCount)")
                    if !server.resources.isEmpty {
                        Divider()
                        ForEach(server.resources) { resource in
                            capabilityRow(
                                name: resource.displayName,
                                identifier: resource.name,
                                description: resource.description,
                                kind: resource.kind.title
                            )
                        }
                    }
                    if server.resources.isEmpty {
                        Text(server.isEnabled ? "这个 MCP 没有暴露资源或资源模板。" : "启用并重新检测后，资源会显示在这里。")
                            .foregroundStyle(.secondary)
                    }
                    Text("不会展示资源地址、输入结构、命令参数或环境变量值。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                detailSection("连接与配置") {
                    LabeledContent("类型", value: server.transport.title)
                    LabeledContent("地址或启动器", value: server.endpointSummary)
                    LabeledContent("认证", value: server.authStatus.title)
                    if let version = server.version { LabeledContent("服务版本", value: version) }
                    LabeledContent("启动超时", value: server.startupTimeoutSeconds.map { "\($0) 秒" } ?? "Codex 默认")
                    LabeledContent("单次工具超时", value: server.toolTimeoutSeconds.map { "\($0) 秒" } ?? "Codex 默认")
                    LabeledContent("检测时间", value: server.checkedAt.formatted(date: .omitted, time: .standard))
                    if let issue = server.configurationIssue {
                        Label(issue, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    }
                    if let error = server.errorMessage {
                        Label(DiagnosticRedactor.commandSummary(error), systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .frame(minWidth: 420)
        .confirmationDialog(server.configuredEnabledState ? "停用这个 MCP 配置？" : "启用这个 MCP 配置？", isPresented: $confirmsChange) {
            Button(server.configuredEnabledState ? "停用配置" : "启用配置", role: server.configuredEnabledState ? .destructive : nil) {
                isChanging = true
                Task {
                    await model.setMCP(server, enabled: !server.configuredEnabledState)
                    isChanging = false
                }
            }
        } message: {
            Text("这次只写入当前 MCP 的用户级配置并回读验证，不会重新启动其他 MCP。运行状态会在你点击“重新加载全部”或重新打开 Codex 后更新。")
        }
        .sheet(item: $conversationTestTarget) { target in
            MCPConversationTestSheet(
                server: server,
                initialMode: target.mode,
                initialToolName: target.toolName
            )
                .environment(model)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(server.displayName).font(.largeTitle.bold())
                HStack {
                    StatusBadge(
                        text: server.effectiveState.title,
                        color: server.effectiveState.color,
                        symbol: server.effectiveState.symbol
                    )
                    StatusBadge(
                        text: server.isReloadPending
                            ? (server.configuredEnabledState ? "配置待启用" : "配置待停用")
                            : (server.configuredEnabledState ? "配置已启用" : "配置已停用"),
                        color: server.isReloadPending ? .orange : (server.configuredEnabledState ? .blue : .secondary),
                        symbol: server.isReloadPending ? "clock.arrow.circlepath" : nil
                    )
                    if server.isRequired { StatusBadge(text: "启动必需", color: .purple, symbol: "exclamationmark.shield") }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    showsStatusGuide.toggle()
                } label: {
                    Label("状态说明", systemImage: "info.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .popover(isPresented: $showsStatusGuide, arrowEdge: .top) {
                    statusGuide.padding(18).frame(width: 400)
                }

                Button {
                    conversationTestTarget = .visibility
                } label: {
                    Label("检查是否可见", systemImage: "bubble.left.and.text.bubble.right")
                }
                .buttonStyle(.bordered)
                .help("打开一个预填好的 Codex 对话，检查这个 MCP 是否可见")

                Button(server.configuredEnabledState ? "停用配置" : "启用配置") { confirmsChange = true }
                    .buttonStyle(.borderedProminent)
                    .tint(server.configuredEnabledState ? .secondary : .accentColor)
                    .disabled(isChanging || model.isChangingConfiguration || !server.canModify)
                    .help(server.canModify ? "修改用户级 MCP 配置，并在写后重新读取验证" : (server.readOnlyReason ?? "该 MCP 保持只读"))
            }
        }
    }

    private var statusGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("怎样理解 MCP 状态").font(.headline)
            guideRow("已配置", "Codex 找到了配置，不代表已经启动。")
            guideRow("已启用", "配置允许加载，不代表连接成功。")
            guideRow("已生效", "已经连接，并读取到工具或资源清单。")
            guideRow("工具已暴露", "Codex 能看到工具定义，不代表已经真实调用成功。")
            guideRow("等待重新加载", "目标配置已经写入，但当前运行状态仍保持不变；重载会同时重启全部 MCP。")
            Divider()
            Text("“重新检测”只读取配置和状态，不会擅自调用工具。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func guideRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).fontWeight(.semibold)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var translatedPurpose: String? { translatedText(for: server.purposeSummary) }
    private var filteredTools: [MCPToolRecord] {
        guard !toolSearchText.isEmpty else { return server.tools }
        return server.tools.filter { tool in
            [
                tool.name,
                tool.displayName,
                tool.description ?? "",
                translatedText(for: tool.description) ?? ""
            ]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(toolSearchText)
        }
    }

    private var displayedPurpose: String {
        showsOriginalPurpose ? server.purposeSummary : (translatedPurpose ?? server.purposeSummary)
    }

    @ViewBuilder
    private var translationFooter: some View {
        if translatedPurpose != nil {
            HStack(spacing: 8) {
                Label("由 macOS 自动翻译", systemImage: "character.book.closed").foregroundStyle(.secondary)
                Button(showsOriginalPurpose ? "查看中文" : "查看英文原文") { showsOriginalPurpose.toggle() }
                    .buttonStyle(.link)
            }
            .font(.caption)
        } else if SkillTranslationPolicy.needsChineseTranslation(server.purposeSummary), isTranslating {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在使用 macOS 翻译…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if SkillTranslationPolicy.needsChineseTranslation(server.purposeSummary), let translationError {
            Label("自动翻译暂时不可用，当前显示英文原文", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .help(translationError)
        }
    }

    private func translatedText(for source: String?) -> String? {
        guard let source, let value = translations[source], !value.isEmpty, value != source else { return nil }
        return value
    }

    private func capabilityRow(name: String, identifier: String, description: String?, kind: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).fontWeight(.semibold)
                Text(kind).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            if name != identifier {
                Text(identifier).font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
            }
            if let description {
                Text(translatedText(for: description) ?? description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 3)
    }

    private func exposedToolRow(_ tool: MCPToolRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(.blue)
                Text(tool.displayName).fontWeight(.semibold)
                StatusBadge(text: "已暴露", color: .green, symbol: "checkmark.circle.fill")
                Spacer()
                Button {
                    conversationTestTarget = .tool(tool.name)
                } label: {
                    Label("测试这个功能", systemImage: "bubble.left.and.text.bubble.right")
                }
                .buttonStyle(.bordered)
                .disabled(!server.isEnabled || server.effectiveState != .effective)
                .help(
                    server.effectiveState == .effective
                        ? "打开 Codex 对话，针对这个功能准备一次受控测试"
                        : "这个 MCP 生效后才能准备真实调用测试"
                )
            }
            Text(tool.name)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            if let description = tool.description {
                Text(translatedText(for: description) ?? description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            } else {
                Text("服务没有提供这个功能的用途说明。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(WorkbenchTheme.subtleFill.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
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

private struct MCPConversationTestTarget: Identifiable {
    let mode: MCPConversationTestMode
    let toolName: String?

    var id: String { "\(mode.rawValue):\(toolName ?? "server")" }

    static let visibility = MCPConversationTestTarget(mode: .visibility, toolName: nil)
    static func tool(_ name: String) -> MCPConversationTestTarget {
        MCPConversationTestTarget(mode: .realInvocation, toolName: name)
    }
}

private struct MCPConversationTestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    let server: MCPRecord
    @State private var mode: MCPConversationTestMode
    @State private var selectedToolName: String
    @State private var objective = ""
    @State private var launchError: String?

    init(
        server: MCPRecord,
        initialMode: MCPConversationTestMode = .visibility,
        initialToolName: String? = nil
    ) {
        self.server = server
        _mode = State(initialValue: initialMode)
        _selectedToolName = State(initialValue: initialToolName ?? server.tools.first?.name ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("在 Codex 中测试 \(server.displayName)")
                        .font(.title2.bold())
                    Text("打开一个新的 Codex 对话，并把测试内容预填到输入框。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
            }

            Picker("测试方式", selection: $mode) {
                ForEach(MCPConversationTestMode.allCases) { item in
                    Text(item.title).tag(item)
                        .disabled(item == .realInvocation && !canPrepareRealInvocation)
                }
            }
            .pickerStyle(.segmented)

            Label(mode.explanation, systemImage: mode == .visibility ? "eye" : "exclamationmark.shield")
                .font(.callout)
                .foregroundStyle(mode == .visibility ? Color.secondary : Color.orange)

            if mode == .realInvocation {
                if server.tools.isEmpty {
                    Label("当前没有可选择的工具；请先重新检测 MCP。", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Picker("要测试的工具", selection: $selectedToolName) {
                        ForEach(server.tools) { tool in
                            Text(tool.displayName).tag(tool.name)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("你想验证什么").fontWeight(.semibold)
                        TextEditor(text: $objective)
                            .font(.body)
                            .frame(minHeight: 76)
                            .padding(6)
                            .background(WorkbenchTheme.subtleFill, in: RoundedRectangle(cornerRadius: 8))
                        Text("例如：查询一条不会修改数据的账号信息。不要在这里填写密码、Token 或其他密钥。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("将预填到 Codex 的内容").fontWeight(.semibold)
                ScrollView {
                    Text(promptPreview ?? "请先补全测试内容。")
                        .font(.callout)
                        .foregroundStyle(promptPreview == nil ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(height: 180)
                .background(WorkbenchTheme.subtleFill.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
            }

            if let launchError {
                Label(launchError, systemImage: "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Label("只会打开并预填，不会自动发送；你可以在 Codex 中检查后再发送。", systemImage: "hand.raised")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("打开测试对话") { openConversation() }
                    .buttonStyle(.borderedProminent)
                    .disabled(promptPreview == nil)
            }
        }
        .padding(24)
        .frame(width: 660)
    }

    private var promptPreview: String? {
        MCPConversationTestDraft.prompt(
            server: server,
            mode: mode,
            toolName: selectedToolName,
            objective: objective
        )
    }

    private var canPrepareRealInvocation: Bool {
        server.isEnabled && server.effectiveState == .effective && !server.tools.isEmpty
    }

    private func openConversation() {
        launchError = nil
        guard let promptPreview,
              let url = MCPConversationTestDraft.codexURL(prompt: promptPreview, workspaceURL: model.workspaceURL)
        else {
            launchError = "测试内容或工作区路径无效。"
            return
        }
        guard NSWorkspace.shared.open(url) else {
            launchError = "没有找到可以打开 Codex 对话的应用。"
            return
        }
        dismiss()
    }
}

private extension MCPEffectiveState {
    var symbol: String {
        switch self {
        case .effective: "checkmark.circle.fill"
        case .starting: "hourglass.circle.fill"
        case .disabled: "pause.circle.fill"
        case .configuredOnly, .statusUnavailable: "questionmark.circle.fill"
        case .connectedNoCapabilities, .needsLogin, .configurationProblem, .startupFailed:
            "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .effective: .green
        case .starting: .blue
        case .disabled: .secondary
        case .configuredOnly, .statusUnavailable: .orange
        case .connectedNoCapabilities, .needsLogin, .configurationProblem, .startupFailed: .red
        }
    }
}

private extension MCPHealthCheckStatus {
    var symbol: String {
        switch self {
        case .passed: "checkmark.circle.fill"
        case .attention: "hourglass.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .inactive: "pause.circle.fill"
        case .unknown: "questionmark.circle.fill"
        case .notVerified: "minus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .passed: .green
        case .attention: .blue
        case .failed: .red
        case .inactive, .notVerified: .secondary
        case .unknown: .orange
        }
    }
}

private enum MCPTranslationCache {
    private static let defaultsKey = "mcp-description-translations.zh-Hans.v1"
    static func load() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }
    static func save(_ translations: [String: String]) {
        UserDefaults.standard.set(translations, forKey: defaultsKey)
    }
}

@available(macOS 15.0, *)
private struct MCPTranslationTask: ViewModifier {
    let sources: [String]
    @Binding var translations: [String: String]
    @Binding var isTranslating: Bool
    @Binding var translationError: String?
    @State private var configuration: TranslationSession.Configuration?
    @State private var requestedSources: [String] = []

    func body(content: Content) -> some View {
        content
            .task(id: pendingSources) { requestTranslation(for: pendingSources) }
            .translationTask(configuration) { session in await translate(using: session) }
    }

    private var pendingSources: [String] { sources.filter { translations[$0] == nil } }

    @MainActor
    private func requestTranslation(for pending: [String]) {
        guard !pending.isEmpty else { isTranslating = false; return }
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
        guard !pending.isEmpty else { isTranslating = false; return }
        do {
            var updated = translations
            for source in pending {
                let translated = try await session.translate(source).targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !translated.isEmpty { updated[source] = translated }
            }
            translations = updated
            MCPTranslationCache.save(updated)
            translationError = nil
        } catch is CancellationError {
            return
        } catch {
            translationError = error.localizedDescription
        }
        isTranslating = false
    }
}
