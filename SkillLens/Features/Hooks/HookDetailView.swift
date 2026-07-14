import SwiftUI

struct HookDetailView: View {
    @Environment(AppModel.self) private var model
    let hook: HookRecord
    @State private var revealsCommand = false
    @State private var isChanging = false
    @State private var confirmsChange = false
    @State private var pendingEnabled: Bool?
    @State private var showsHookHelp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                overviewGrid
                recentObservationSection
                technicalSection
                sourceSection

                Text("启停操作通过 Codex 官方配置接口完成，并在写入后重新读取验证。停用不会删除原始配置；启用也不会代替 Codex 的信任审批。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .frame(minWidth: 360)
        .confirmationDialog(confirmationTitle, isPresented: $confirmsChange) {
            if let pendingEnabled {
                Button(pendingEnabled ? "启用 Hook" : "停用 Hook", role: pendingEnabled ? nil : .destructive) {
                    isChanging = true
                    Task {
                        await model.setHook(hook, enabled: pendingEnabled)
                        isChanging = false
                        self.pendingEnabled = nil
                    }
                }
            }
            Button("取消", role: .cancel) { pendingEnabled = nil }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 9) {
                Text(hook.displayName)
                    .font(.largeTitle.bold())
                HStack {
                    StatusBadge(text: "触发：\(hook.event.title)", color: .blue, symbol: "bolt.fill")
                    StatusBadge(text: hook.runnableState.title, color: hook.runnableState.color)
                    StatusBadge(text: hook.trustStatus.title, color: trustColor)
                    if hook.isEffectivelyManaged {
                        StatusBadge(text: "不可由用户修改", color: .purple, symbol: "lock.fill")
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    showsHookHelp.toggle()
                } label: {
                    Label("Hook 说明", systemImage: "info.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .popover(isPresented: $showsHookHelp, arrowEdge: .top) {
                    hookGuide
                        .padding(18)
                        .frame(width: 390)
                }

                Menu {
                    Button {
                        requestStateChange(enabled: true)
                    } label: {
                        Label("已启用", systemImage: hook.isEnabled ? "checkmark" : "play.circle")
                    }
                    .disabled(hook.isEnabled)

                    Button(role: .destructive) {
                        requestStateChange(enabled: false)
                    } label: {
                        Label("已停用", systemImage: hook.isEnabled ? "pause.circle" : "checkmark")
                    }
                    .disabled(!hook.isEnabled)
                } label: {
                    Label(
                        "切换此 Hook：\(hook.configurationStateTitle)",
                        systemImage: hook.isEnabled ? "bolt.fill" : "pause.circle"
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(isChanging || model.isChangingConfiguration || hook.isEffectivelyManaged)
                .help(hook.isEffectivelyManaged ? "管理员托管的 Hook 不能修改" : "修改后会重新读取并验证 Codex 的实际状态")
            }
        }
    }

    private var overviewGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 235), spacing: 14)], spacing: 14) {
            summaryCard(
                title: "什么时候触发",
                text: hook.triggerSummary,
                symbol: "bolt.fill",
                color: .orange
            )
            summaryCard(
                title: "哪些情况符合条件",
                text: hook.matchSummary,
                symbol: "line.3.horizontal.decrease.circle",
                color: .blue
            )
            summaryCard(
                title: "触发后做什么",
                text: hook.actionSummary,
                symbol: "terminal",
                color: .green
            )
            summaryCard(
                title: "能否影响流程 · \(hook.effectTitle)",
                text: hook.effectSummary,
                symbol: "hand.raised.fill",
                color: .purple
            )
        }
    }

    private var recentObservationSection: some View {
        section("最近触发") {
            if let recentRun {
                LabeledContent(
                    "最近观察到",
                    value: recentRun.startedAt.formatted(date: .abbreviated, time: .standard)
                )
                LabeledContent("结果", value: runStatusTitle(recentRun.status))
                if let duration = recentRun.durationMilliseconds {
                    LabeledContent("耗时", value: "\(duration) 毫秒")
                }
                LabeledContent("记录来源", value: recentRun.sessionOwnership.title)
            } else {
                Label("当前 App Server 连接尚未观察到这类事件。", systemImage: "clock.badge.questionmark")
                    .foregroundStyle(.secondary)
            }
            Text("这是“\(hook.event.title)”事件的观察记录，不代表能够确认本页这个具体 Hook 已经执行。同一事件下的多个 Hook 会共享这个触发时机。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var technicalSection: some View {
        section("技术细节") {
            LabeledContent("Hook 标识", value: hook.key)
            LabeledContent("Codex 事件", value: hook.rawEventName)
            LabeledContent("匹配条件", value: hook.matcher?.isEmpty == false ? hook.matcher! : "未限定")
            LabeledContent("处理器", value: hook.handlerType.title)
            if hook.handlerType == .unknown {
                LabeledContent("处理器原值", value: hook.rawHandlerType)
            }
            LabeledContent("最长等待", value: "\(hook.timeoutSeconds) 秒")
            if hook.handlerType != .command {
                Label("当前 Codex 版本只会执行本地命令处理器；这个处理器不会运行。", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Button(revealsCommand ? "隐藏脱敏命令" : "显示脱敏命令") {
                revealsCommand.toggle()
            }
            if revealsCommand {
                Text(DiagnosticRedactor.commandSummary(hook.command))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var sourceSection: some View {
        section("来源与信任") {
            LabeledContent("来源", value: hook.source.title)
            LabeledContent("信任", value: hook.trustStatus.title)
            if hook.source == .unknown {
                LabeledContent("来源原值", value: hook.rawSource)
            }
            if hook.trustStatus == .unknown {
                LabeledContent("信任原值", value: hook.rawTrustStatus)
            }
            if let pluginID = hook.pluginID {
                LabeledContent("插件", value: pluginID)
            }
            LabeledContent("配置位置") {
                VStack(alignment: .trailing, spacing: 5) {
                    Text(hook.sourcePath)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                    Button("在 Finder 中显示") { model.revealInFinder(path: hook.sourcePath) }
                        .font(.caption)
                }
            }
        }
    }

    private var hookGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hook 是怎么工作的")
                .font(.headline)
            guideRow(symbol: "bolt.fill", title: "事件", text: "Codex 运行到某个生命周期节点，例如提交提示词、调用工具或本轮准备结束。")
            guideRow(symbol: "line.3.horizontal.decrease.circle", title: "匹配条件", text: "决定这次事件是否符合范围，例如只检查终端命令，或者匹配所有工具。")
            guideRow(symbol: "terminal", title: "处理器", text: "匹配后自动运行本地脚本，用于提醒、记录、检查、阻止或改变后续流程。")
            Divider()
            guideRow(symbol: "bolt.fill", title: "已启用", text: "满足事件和匹配条件时，Codex 可以运行这个 Hook。")
            guideRow(symbol: "pause.circle", title: "已停用", text: "保留原始 Hook 配置，但 Codex 不会运行它。")
            Text("启用不等于已信任。个人、项目和插件 Hook 如果待信任或信任后发生变化，Codex 仍会跳过执行。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var recentRun: HookRunRecord? {
        model.hookRuns
            .filter { $0.event == hook.event }
            .max { $0.startedAt < $1.startedAt }
    }

    private var confirmationTitle: String {
        guard let pendingEnabled else { return "切换 Hook 状态？" }
        return pendingEnabled ? "启用这个 Hook？" : "停用这个 Hook？"
    }

    private var confirmationMessage: String {
        guard let pendingEnabled else { return "" }
        let action = pendingEnabled
            ? "启用后，满足触发事件和匹配条件时，Codex 可以运行这个处理器；待信任或已修改的 Hook 仍不会运行。"
            : "停用后，Codex 将跳过这个处理器，但不会删除个人、项目或插件中的原始配置。"
        return "\(action) Workbench 会在写入后重新读取验证。"
    }

    private func requestStateChange(enabled: Bool) {
        guard enabled != hook.isEnabled else { return }
        pendingEnabled = enabled
        confirmsChange = true
    }

    private func summaryCard(title: String, text: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(color)
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(WorkbenchTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func guideRow(symbol: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.blue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkbenchTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var trustColor: Color {
        switch hook.trustStatus {
        case .trusted, .managed: .green
        case .untrusted, .modified: .orange
        case .unknown: .secondary
        }
    }

    private func runStatusTitle(_ status: HookRunStatus) -> String {
        switch status {
        case .running: "运行中"
        case .completed: "已完成"
        case .failed: "失败"
        case .blocked: "已阻止"
        case .stopped: "已停止"
        case .unknown: "状态未知"
        }
    }
}
