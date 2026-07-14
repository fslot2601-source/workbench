import Charts
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    private let capabilityColumns = Array(
        repeating: GridItem(.flexible(minimum: 150), spacing: 12),
        count: 4
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if !model.hasCompletedInitialRefresh {
                    loadingView
                } else {
                    recentUsageSection
                    capabilitySection
                    storageSection
                }
            }
            .padding(24)
            .frame(maxWidth: 1_180, alignment: .leading)
        }
        .navigationTitle("总览")
        .background(WorkbenchTheme.canvas)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Codex 总览")
                    .font(.largeTitle.bold())
                Text("用一页看清账号用量、扩展能力和本机占用。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(text: model.connectionState.title, color: connectionColor, symbol: connectionSymbol)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在读取 Codex 的完整状态…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var recentUsageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "最近使用量",
                subtitle: "来自 Codex 官方账户接口，不估算费用或模型占比。",
                destination: .usage
            )

            VStack(alignment: .leading, spacing: 16) {
                if model.isRefreshingUsage && model.rateLimits.isEmpty && model.dailyTokenUsage.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在读取账户限额和 Token 活动…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                } else if model.rateLimits.isEmpty && model.dailyTokenUsage.isEmpty && model.tokenUsageSummary == nil {
                    HStack(spacing: 12) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("当前账号没有可显示的官方用量")
                                .font(.headline)
                            Text(model.usageError ?? "部分登录方式不提供用量接口，这里不会把未知显示成 0。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
                } else {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 14) {
                            if usageWindows.isEmpty {
                                Text("当前账号没有返回限额窗口。")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(usageWindows) { item in
                                    usageWindowRow(item)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 24) {
                                usageMetric(title: "近 7 天 Token", value: tokenText(recentTokenTotal))
                                usageMetric(title: "最近一天", value: tokenText(recentDailyUsage.last?.tokens))
                                usageMetric(
                                    title: "连续使用",
                                    value: model.tokenUsageSummary?.currentStreakDays.map { "\($0) 天" } ?? "不可用"
                                )
                            }

                            if !recentDailyUsage.isEmpty {
                                Chart(recentDailyUsage) { bucket in
                                    BarMark(
                                        x: .value("日期", bucket.startDate),
                                        y: .value("Token", bucket.tokens)
                                    )
                                    .foregroundStyle(.teal.gradient)
                                    .cornerRadius(3)
                                }
                                .chartXAxis(.hidden)
                                .chartYAxis(.hidden)
                                .frame(height: 72)
                                .accessibilityLabel("近七天 Token 使用趋势")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let error = model.usageError {
                        Label("部分用量读取不完整：\(error)", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(18)
            .background(WorkbenchTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { cardBorder }
            .accessibilityIdentifier("dashboard-recent-usage")
        }
    }

    private var capabilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("能力状态")
                    .font(.title2.bold())
                Text("停用或隐藏不等于故障；只有无法正常工作的项目才会标记为有问题。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: capabilityColumns, alignment: .leading, spacing: 12) {
                capabilityCard(
                    title: "Skills",
                    symbol: "wand.and.stars",
                    count: model.skills.count,
                    primary: "\(availableSkills) 个可用 · \(explicitOnlySkills) 个仅点名",
                    secondary: skillSecondaryText,
                    state: skillCardState,
                    destination: .skills
                )
                capabilityCard(
                    title: "MCP",
                    symbol: "server.rack",
                    count: model.mcpServers.count,
                    primary: "\(readyMCP) 个已生效 · \(enabledMCP) 个已启用",
                    secondary: mcpSecondaryText,
                    state: mcpCardState,
                    destination: .mcp
                )
                capabilityCard(
                    title: "Hooks",
                    symbol: "point.3.connected.trianglepath.dotted",
                    count: model.hooks.count,
                    primary: "\(runnableHooks) 个可以运行 · \(disabledHooks) 个已停用",
                    secondary: hookSecondaryText,
                    state: hookCardState,
                    destination: .hooks
                )
                capabilityCard(
                    title: "Memory",
                    symbol: "brain",
                    count: model.memorySnapshot?.items.count ?? 0,
                    primary: memoryPrimaryText,
                    secondary: memorySecondaryText,
                    state: memoryCardState,
                    destination: .memory
                )
            }
            .accessibilityIdentifier("dashboard-capabilities")
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "本机存储",
                subtitle: "先看整体占用，再决定是否进入存储页清理可安全重建的缓存。",
                destination: .storage
            )

            VStack(alignment: .leading, spacing: 16) {
                if model.isScanningStorage && model.storageRecords.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在统计 Codex 本地文件…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 110)
                } else if model.storageRecords.isEmpty {
                    Label(model.storageError ?? "没有发现可统计的 Codex 本地数据。", systemImage: "internaldrive")
                        .foregroundStyle(model.storageError == nil ? Color.secondary : Color.orange)
                        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(byteText(totalStorageBytes))
                                .font(.system(size: 32, weight: .semibold, design: .rounded))
                            Text("Codex 本地总占用")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(byteText(cacheBytes))
                                .font(.title2.bold())
                            Text("可清理缓存")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    storageBar

                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(model.storageRecords.prefix(5))) { record in
                            HStack(alignment: .top, spacing: 7) {
                                Circle()
                                    .fill(storageColor(record.kind))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.kind.title)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                    Text(byteText(record.sizeBytes))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let error = model.storageError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(18)
            .background(WorkbenchTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { cardBorder }
            .accessibilityIdentifier("dashboard-storage")
        }
    }

    private func sectionHeader(title: String, subtitle: String, destination: SidebarDestination) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.bold())
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("查看详情") { model.selection = destination }
                .buttonStyle(.link)
        }
    }

    private func usageWindowRow(_ item: DashboardUsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(item.title).font(.callout.weight(.semibold))
                Spacer()
                Text("剩余 \(item.window.remainingPercent)%")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(usageColor(item.window.remainingPercent))
            }
            ProgressView(value: Double(item.window.remainingPercent), total: 100)
                .tint(usageColor(item.window.remainingPercent))
            if let reset = item.window.resetsAt {
                Text("\(reset.formatted(date: .abbreviated, time: .shortened)) 重置")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func usageMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func capabilityCard(
        title: String,
        symbol: String,
        count: Int,
        primary: String,
        secondary: String,
        state: DashboardCardState,
        destination: SidebarDestination
    ) -> some View {
        Button { model.selection = destination } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(state.color)
                    Spacer()
                    StatusBadge(text: state.title, color: state.color, symbol: state.symbol)
                }
                Text("\(count)")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(primary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(secondary)
                    .font(.caption2)
                    .foregroundStyle(state.color)
                    .lineLimit(2)
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
            .background(WorkbenchTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { cardBorder }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(count)，\(primary)，\(secondary)")
    }

    private var storageBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(model.storageRecords.filter { $0.sizeBytes > 0 }) { record in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(storageColor(record.kind))
                        .frame(width: storageWidth(record.sizeBytes, available: proxy.size.width))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(height: 10)
        .accessibilityLabel("Codex 本地存储占用分布")
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(.quaternary)
    }

    private var recentDailyUsage: [DailyTokenUsage] {
        Array(model.dailyTokenUsage.sorted { $0.startDate < $1.startDate }.suffix(7))
    }

    private var recentTokenTotal: Int64? {
        guard !recentDailyUsage.isEmpty else { return nil }
        return recentDailyUsage.reduce(0) { $0 + $1.tokens }
    }

    private var usageWindows: [DashboardUsageWindow] {
        var result: [DashboardUsageWindow] = []
        for limit in model.rateLimits {
            let prefix = model.rateLimits.count > 1 ? "\(limit.name) · " : ""
            if let window = limit.primary {
                result.append(.init(id: "\(limit.id)-primary", title: prefix + windowTitle(window, fallback: "短周期"), window: window))
            }
            if let window = limit.secondary {
                result.append(.init(id: "\(limit.id)-secondary", title: prefix + windowTitle(window, fallback: "长周期"), window: window))
            }
        }
        return Array(result.prefix(2))
    }

    private var availableSkills: Int { model.skills.filter { $0.effectiveState == .available }.count }
    private var disabledSkills: Int { model.skills.filter { $0.effectiveState == .disabled }.count }
    private var explicitOnlySkills: Int { model.skills.filter { $0.invocationPolicy == .explicitOnly }.count }
    private var brokenSkills: Int { model.skills.filter(\.hasProblem).count }
    private var runnableHooks: Int { model.hooks.filter { $0.runnableState == .ready }.count }
    private var disabledHooks: Int { model.hooks.filter { $0.runnableState == .disabled }.count }
    private var brokenHooks: Int {
        model.hooks.filter { ![.ready, .disabled].contains($0.runnableState) }.count
    }
    private var enabledMCP: Int { model.mcpServers.filter(\.isEnabled).count }
    private var readyMCP: Int {
        model.mcpServers.filter { $0.effectiveState == .effective }.count
    }
    private var brokenMCP: Int {
        model.mcpServers.filter(\.hasProblem).count
    }
    private var memoryProblems: Int {
        model.memorySnapshot?.records.filter { $0.status == .unreadable }.count ?? 0
    }
    private var oversizedMemoryFiles: Int {
        model.memorySnapshot?.records.filter { $0.status == .tooLarge }.count ?? 0
    }

    private var skillSecondaryText: String {
        if let error = model.skillsError { return "读取失败：\(error)" }
        if brokenSkills > 0 { return "\(brokenSkills) 个有问题" }
        return disabledSkills > 0 ? "\(disabledSkills) 个已隐藏" : "没有发现异常"
    }

    private var mcpSecondaryText: String {
        if let error = model.mcpError { return "读取失败：\(error)" }
        if model.mcpWarning != nil { return "状态检测未完成，配置仍已保留" }
        if brokenMCP > 0 { return "\(brokenMCP) 个有问题" }
        let disabled = model.mcpServers.filter { !$0.isEnabled }.count
        return disabled > 0 ? "\(disabled) 个已停用" : "没有发现异常"
    }

    private var hookSecondaryText: String {
        if let error = model.hooksError { return "读取失败：\(error)" }
        if brokenHooks > 0 { return "\(brokenHooks) 个无法正常运行" }
        return model.hookWarnings.isEmpty ? "没有发现异常" : "有 \(model.hookWarnings.count) 条提示"
    }

    private var memoryPrimaryText: String {
        guard let snapshot = model.memorySnapshot else { return "尚未完成扫描" }
        if snapshot.records.isEmpty { return "当前没有可展示的记忆文件" }
        if snapshot.items.isEmpty { return "来源已读取，但没有解析到可读记忆" }
        return "\(snapshot.activeItems.count) 条当前生效 · \(snapshot.durableItems.count) 条长期记忆"
    }

    private var memorySecondaryText: String {
        if let error = model.memoryError { return "读取失败：\(error)" }
        if memoryProblems > 0 { return "\(memoryProblems) 个文件无法读取" }
        if oversizedMemoryFiles > 0 { return "\(oversizedMemoryFiles) 个大文件仅展示基本信息" }
        guard let snapshot = model.memorySnapshot else { return "等待读取" }
        if snapshot.records.isEmpty { return "Memory 尚未启用" }
        if !snapshot.warnings.isEmpty { return "有 \(snapshot.warnings.count) 条扫描提示" }
        return "没有发现异常"
    }

    private var skillCardState: DashboardCardState {
        if model.skillsError != nil { return .warning }
        if brokenSkills > 0 { return .problem }
        if model.skills.isEmpty { return .inactive }
        return .healthy
    }

    private var mcpCardState: DashboardCardState {
        if model.isRefreshingMCP && model.mcpServers.isEmpty { return .loading }
        if model.mcpError != nil { return .warning }
        if brokenMCP > 0 { return .problem }
        if model.mcpWarning != nil { return .warning }
        if model.mcpServers.isEmpty { return .inactive }
        return .healthy
    }

    private var hookCardState: DashboardCardState {
        if model.hooksError != nil { return .warning }
        if brokenHooks > 0 { return .problem }
        if model.hooks.isEmpty { return .inactive }
        return .healthy
    }

    private var memoryCardState: DashboardCardState {
        if model.isScanningMemory && model.memorySnapshot == nil { return .loading }
        if model.memoryError != nil { return .warning }
        if memoryProblems > 0 { return .problem }
        guard let snapshot = model.memorySnapshot, !snapshot.records.isEmpty else { return .inactive }
        if snapshot.items.isEmpty { return .notice }
        if oversizedMemoryFiles > 0 || !snapshot.warnings.isEmpty { return .notice }
        return .healthy
    }

    private var totalStorageBytes: Int64 { model.storageRecords.reduce(0) { $0 + $1.sizeBytes } }
    private var cacheBytes: Int64 {
        model.storageRecords.filter { $0.kind.cleanable }.reduce(0) { $0 + $1.sizeBytes }
    }

    private func storageWidth(_ bytes: Int64, available: CGFloat) -> CGFloat {
        guard totalStorageBytes > 0 else { return 0 }
        return available * CGFloat(Double(bytes) / Double(totalStorageBytes))
    }

    private func storageColor(_ kind: CodexStorageKind) -> Color {
        switch kind {
        case .sessions: .blue
        case .archivedSessions: .cyan
        case .plugins: .orange
        case .skills: .green
        case .packages: .purple
        case .cache: .yellow
        case .temporary: .pink
        case .logs: .mint
        case .database: .indigo
        case .other: .gray
        }
    }

    private func usageColor(_ remaining: Int) -> Color {
        if remaining < 15 { return .red }
        if remaining < 35 { return .orange }
        return .teal
    }

    private func windowTitle(_ window: RateLimitWindowRecord, fallback: String) -> String {
        guard let minutes = window.windowDurationMinutes else { return fallback }
        if minutes <= 360 { return "短周期" }
        if minutes >= 6 * 24 * 60 { return "每周" }
        if minutes >= 24 * 60 { return "\(minutes / 1_440) 天周期" }
        return "\(minutes / 60) 小时周期"
    }

    private func tokenText(_ value: Int64?) -> String {
        guard let value else { return "不可用" }
        return value.formatted(.number.notation(.compactName))
    }

    private func byteText(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private var connectionColor: Color {
        switch model.connectionState {
        case .connected: .green
        case .failed: .red
        case .locating, .connecting: .blue
        case .idle: .secondary
        }
    }

    private var connectionSymbol: String {
        switch model.connectionState {
        case .connected: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .locating, .connecting: "arrow.triangle.2.circlepath"
        case .idle: "circle.dashed"
        }
    }
}

private struct DashboardUsageWindow: Identifiable {
    let id: String
    let title: String
    let window: RateLimitWindowRecord
}

private enum DashboardCardState {
    case healthy
    case problem
    case warning
    case notice
    case inactive
    case loading

    var title: String {
        switch self {
        case .healthy: "正常"
        case .problem: "有问题"
        case .warning: "读取不完整"
        case .notice: "有提示"
        case .inactive: "未配置"
        case .loading: "读取中"
        }
    }

    var symbol: String {
        switch self {
        case .healthy: "checkmark.circle.fill"
        case .problem: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .notice: "info.circle.fill"
        case .inactive: "minus.circle.fill"
        case .loading: "arrow.triangle.2.circlepath"
        }
    }

    var color: Color {
        switch self {
        case .healthy: .green
        case .problem: .red
        case .warning: .orange
        case .notice: .blue
        case .inactive: .secondary
        case .loading: .blue
        }
    }
}
