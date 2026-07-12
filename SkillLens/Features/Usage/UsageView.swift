import Charts
import SwiftUI

struct UsageView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let error = model.usageError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }

                if model.rateLimits.isEmpty && model.tokenUsageSummary == nil && model.isRefreshingUsage {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在读取官方账户用量…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else if model.rateLimits.isEmpty && model.tokenUsageSummary == nil {
                    ContentUnavailableView(
                        "当前账号没有可用的官方用量数据",
                        systemImage: "chart.xyaxis.line",
                        description: Text("API Key 或 Bedrock 登录可能不支持 ChatGPT 用量接口；不可用不会被显示成 0。")
                    )
                } else {
                    rateLimitsSection
                    tokenSummarySection
                    dailyChartSection
                }
            }
            .padding(24)
        }
        .navigationTitle("Codex 用量")
        .task { await model.refreshUsage() }
        .toolbar {
            Button {
                Task { await model.refreshUsage() }
            } label: {
                Label("刷新用量", systemImage: "arrow.clockwise")
            }
            .disabled(model.isRefreshingUsage)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("官方账户用量")
                        .font(.largeTitle.bold())
                    Text("数据来自当前 Codex App Server 的账户接口，不读取登录令牌，也不根据本地日志估算费用。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isRefreshingUsage { ProgressView().controlSize(.small) }
            }
            if let refreshedAt = model.usageRefreshedAt {
                Text("更新于 \(refreshedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var rateLimitsSection: some View {
        if !model.rateLimits.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("限额窗口").font(.title2.bold())
                    Spacer()
                    if let count = model.resetCreditsAvailable {
                        StatusBadge(text: "可用重置额度 \(count)", color: .indigo, symbol: "arrow.counterclockwise.circle")
                    }
                }
                ForEach(model.rateLimits) { limit in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(displayName(limit)).font(.headline)
                            Spacer()
                            if let plan = limit.planType { Text(plan.uppercased()).font(.caption).foregroundStyle(.secondary) }
                        }
                        if let primary = limit.primary { windowRow(primary, title: windowTitle(primary, fallback: "主要窗口")) }
                        if let secondary = limit.secondary { windowRow(secondary, title: windowTitle(secondary, fallback: "次要窗口")) }
                        if let reached = limit.reachedType {
                            Label(reachedDescription(reached), systemImage: "exclamationmark.octagon.fill")
                                .foregroundStyle(.red)
                        }
                        if let balance = limit.creditBalance {
                            LabeledContent("余额", value: balance)
                        }
                    }
                    .padding(16)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    @ViewBuilder
    private var tokenSummarySection: some View {
        if let summary = model.tokenUsageSummary {
            VStack(alignment: .leading, spacing: 12) {
                Text("Token 活动").font(.title2.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                    UsageMetric(title: "累计 Token", value: tokenText(summary.lifetimeTokens), symbol: "sum")
                    UsageMetric(title: "单日峰值", value: tokenText(summary.peakDailyTokens), symbol: "chart.bar.fill")
                    UsageMetric(title: "当前连续使用", value: dayText(summary.currentStreakDays), symbol: "flame.fill")
                    UsageMetric(title: "最长连续使用", value: dayText(summary.longestStreakDays), symbol: "calendar")
                    UsageMetric(title: "最长单次任务", value: durationText(summary.longestRunningTurnSeconds), symbol: "timer")
                }
            }
        }
    }

    @ViewBuilder
    private var dailyChartSection: some View {
        if !model.dailyTokenUsage.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("每日 Token").font(.title2.bold())
                Chart(model.dailyTokenUsage) { bucket in
                    BarMark(
                        x: .value("日期", bucket.startDate),
                        y: .value("Token", bucket.tokens)
                    )
                    .foregroundStyle(.teal.gradient)
                }
                .chartXAxis(.hidden)
                .frame(height: 220)
                Text("官方接口只提供 Token 活动，不提供截图中的美元费用和最常用模型；Skill Lens 不会伪造这些数字。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func windowRow(_ window: RateLimitWindowRecord, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.callout.weight(.semibold))
                Spacer()
                Text("剩余 \(window.remainingPercent)%").font(.headline)
            }
            ProgressView(value: Double(window.remainingPercent), total: 100)
                .tint(window.remainingPercent < 15 ? .red : (window.remainingPercent < 35 ? .orange : .teal))
            HStack {
                if let minutes = window.windowDurationMinutes { Text("周期 \(durationMinutes(minutes))") }
                Spacer()
                if let reset = window.resetsAt { Text("重置于 \(reset.formatted(date: .abbreviated, time: .shortened))") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func displayName(_ limit: RateLimitRecord) -> String {
        limit.name == "codex" ? "Codex" : limit.name
    }

    private func windowTitle(_ window: RateLimitWindowRecord, fallback: String) -> String {
        guard let minutes = window.windowDurationMinutes else { return fallback }
        if minutes <= 360 { return "短周期" }
        if minutes >= 6 * 24 * 60 { return "长周期" }
        return fallback
    }

    private func durationMinutes(_ minutes: Int) -> String {
        if minutes % 10_080 == 0 { return "\(minutes / 10_080) 周" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440) 天" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时" }
        return "\(minutes) 分钟"
    }

    private func reachedDescription(_ value: String) -> String {
        switch value {
        case "rate_limit_reached": "当前限额已用尽"
        case "workspace_owner_credits_depleted", "workspace_member_credits_depleted": "工作区额度已用尽"
        case "workspace_owner_usage_limit_reached", "workspace_member_usage_limit_reached": "工作区用量上限已达到"
        default: "Codex 返回了限额状态：\(value)"
        }
    }

    private func tokenText(_ value: Int64?) -> String {
        guard let value else { return "不可用" }
        return value.formatted(.number.notation(.compactName))
    }

    private func dayText(_ value: Int64?) -> String { value.map { "\($0) 天" } ?? "不可用" }
    private func durationText(_ value: Int64?) -> String {
        guard let value else { return "不可用" }
        let hours = value / 3_600
        let minutes = value % 3_600 / 60
        if hours > 0 { return minutes > 0 ? "\(hours) 小时 \(minutes) 分" : "\(hours) 小时" }
        return "\(max(1, minutes)) 分钟"
    }
}

private struct UsageMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.teal).frame(width: 30)
            VStack(alignment: .leading) {
                Text(value).font(.title2.bold())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
}
