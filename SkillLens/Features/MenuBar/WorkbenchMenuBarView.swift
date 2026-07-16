import SwiftUI

enum MenuBarPanelLayout {
    static let width: CGFloat = 380
    static let initialHeight: CGFloat = 420
    static let minimumHeight: CGFloat = 300
    static let maximumHeight: CGFloat = 520

    static func height(for contentHeight: CGFloat) -> CGFloat {
        min(max(ceil(contentHeight), minimumHeight), maximumHeight)
    }
}

private struct MenuBarContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct WorkbenchMenuBarView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(WorkbenchPreferences.showMenuBarTokenActivityKey) private var showTokenActivity = true
    @AppStorage(WorkbenchPreferences.showMenuBarStorageKey) private var showStorage = true
    @State private var panelHeight = MenuBarPanelLayout.initialHeight
    let openDestination: (SidebarDestination) -> Void
    let contentHeightDidChange: (CGFloat) -> Void

    init(
        openDestination: @escaping (SidebarDestination) -> Void,
        contentHeightDidChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.openDestination = openDestination
        self.contentHeightDidChange = contentHeightDidChange
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                if let limit = preferredLimit {
                    limitSection(limit)
                } else {
                    unavailableUsage
                }
                if showTokenActivity, let summary = model.tokenUsageSummary {
                    tokenSection(summary)
                }
                if showStorage, !model.storageRecords.isEmpty {
                    storageSection
                }
                selfCheckSection
                Divider()
                actions
            }
            .padding(14)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: MenuBarContentHeightKey.self,
                        value: geometry.size.height
                    )
                }
            }
        }
        .frame(width: MenuBarPanelLayout.width, height: panelHeight)
        .tint(WorkbenchTheme.accent)
        .onPreferenceChange(MenuBarContentHeightKey.self) { contentHeight in
            Task { @MainActor in
                updatePanelHeight(for: contentHeight)
            }
        }
        .task {
            let age = model.usageRefreshedAt.map { Date().timeIntervalSince($0) } ?? .infinity
            if age > 180 { await model.refreshUsage() }
        }
    }

    @MainActor
    private func updatePanelHeight(for contentHeight: CGFloat) {
        guard contentHeight > 0 else { return }
        let nextHeight = MenuBarPanelLayout.height(for: contentHeight)
        guard abs(nextHeight - panelHeight) >= 1 else { return }
        panelHeight = nextHeight
        contentHeightDidChange(nextHeight)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("MenuBarIcon")
                .resizable()
                .renderingMode(.template)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Workbench").font(.headline)
                Text(refreshText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isRefreshingUsage {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await model.refreshUsage() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新用量")
            }
        }
    }

    private var preferredLimit: RateLimitRecord? {
        model.rateLimits.first(where: { $0.name.lowercased() == "codex" }) ?? model.rateLimits.first
    }

    @ViewBuilder
    private func limitSection(_ limit: RateLimitRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Codex 限额").font(.subheadline.bold())
                Spacer()
                if let plan = limit.planType { Text(plan.uppercased()).font(.caption).foregroundStyle(.secondary) }
            }
            if let primary = limit.primary { limitRow(primary, title: windowTitle(primary, fallback: "主要窗口")) }
            if let secondary = limit.secondary { limitRow(secondary, title: windowTitle(secondary, fallback: "次要窗口")) }
            if let credits = model.resetCreditsAvailable {
                Label("可用重置额度 \(credits)", systemImage: "arrow.counterclockwise.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let reached = limit.reachedType {
                Label("Codex 返回限额状态：\(reached)", systemImage: "exclamationmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(WorkbenchTheme.subtleFill.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
    }

    private func limitRow(_ window: RateLimitWindowRecord, title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.caption.weight(.semibold))
                Spacer()
                Text("剩余 \(window.remainingPercent)%").font(.subheadline.bold())
            }
            ProgressView(value: Double(window.remainingPercent), total: 100)
                .tint(window.remainingPercent < 15 ? .red : (window.remainingPercent < 35 ? .orange : .teal))
            if let reset = window.resetsAt {
                Text("\(reset, style: .relative)重置")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var unavailableUsage: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("当前没有可用的官方限额数据", systemImage: "chart.xyaxis.line")
                .font(.subheadline.weight(.semibold))
            Text(model.usageError ?? "API Key 或 Bedrock 登录可能不提供 ChatGPT 用量接口；不可用不会显示成 0。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkbenchTheme.subtleFill.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
    }

    private func tokenSection(_ summary: TokenUsageSummary) -> some View {
        HStack(spacing: 12) {
            menuMetric("近 7 天", recentTokenText(7))
            Divider().frame(height: 34)
            menuMetric("累计 Token", summary.lifetimeTokens.map(compactNumber) ?? "不可用")
        }
    }

    private var storageSection: some View {
        let total = model.storageRecords.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return HStack {
            Label("Codex 本地存储", systemImage: "internaldrive")
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)).fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    private var selfCheckSection: some View {
        let failures = model.failedSelfCheckCount
        let warnings = model.warningSelfCheckCount
        return HStack {
            Label(
                failures > 0 ? "\(failures) 项异常" : (warnings > 0 ? "\(warnings) 项需确认" : "自检正常"),
                systemImage: failures > 0 ? "xmark.octagon.fill" : (warnings > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            )
            .foregroundStyle(failures > 0 ? .red : (warnings > 0 ? .orange : .green))
            Spacer()
            Button("查看") { openDestination(.diagnostics) }
                .buttonStyle(.borderless)
        }
        .font(.subheadline)
    }

    private var actions: some View {
        VStack(spacing: 2) {
            actionButton("打开用量", symbol: "chart.xyaxis.line") { openDestination(.usage) }
            actionButton("打开 Workbench", symbol: "macwindow") { openDestination(.dashboard) }
            SettingsLink {
                Label("设置…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 5)
            actionButton("退出 Workbench", symbol: "power") { NSApplication.shared.terminate(nil) }
        }
    }

    private func actionButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 5)
    }

    private func menuMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recentTokenText(_ days: Int) -> String {
        compactNumber(model.dailyTokenUsage.suffix(days).reduce(Int64(0)) { $0 + $1.tokens })
    }

    private func compactNumber(_ value: Int64) -> String {
        value.formatted(.number.notation(.compactName))
    }

    private func windowTitle(_ window: RateLimitWindowRecord, fallback: String) -> String {
        guard let minutes = window.windowDurationMinutes else { return fallback }
        if minutes <= 360 { return "短周期" }
        if minutes >= 6 * 24 * 60 { return "长周期" }
        return fallback
    }

    private var refreshText: String {
        guard let date = model.usageRefreshedAt else { return "等待首次更新" }
        return "用量更新于 \(date.formatted(date: .omitted, time: .shortened))"
    }
}
