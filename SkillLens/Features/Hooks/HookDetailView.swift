import SwiftUI

struct HookDetailView: View {
    @Environment(AppModel.self) private var model
    let hook: HookRecord
    @State private var revealsCommand = false
    @State private var isChanging = false
    @State private var confirmsChange = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(hook.event.title)
                                .font(.largeTitle.bold())
                            HStack {
                                StatusBadge(text: hook.runnableState.title, color: hook.runnableState.color)
                                StatusBadge(text: hook.trustStatus.title, color: trustColor)
                                if hook.isEffectivelyManaged {
                                    StatusBadge(text: "不可由用户修改", color: .purple, symbol: "lock.fill")
                                }
                            }
                        }
                        Spacer()
                        Button(hook.isEnabled ? "停用" : "启用") {
                            confirmsChange = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(hook.isEnabled ? .secondary : .accentColor)
                        .disabled(isChanging || model.isChangingConfiguration || hook.isEffectivelyManaged)
                        .help(hook.isEffectivelyManaged ? "管理员托管的 Hook 不能修改" : "通过 Codex 配置接口写入，并在写后重新读取验证")
                    }
                }

                flowSection

                section("什么时候触发") {
                    LabeledContent("事件", value: hook.event.title)
                    LabeledContent("协议原值", value: hook.rawEventName)
                    LabeledContent("匹配条件", value: hook.matcher?.isEmpty == false ? hook.matcher! : "所有匹配项")
                }

                section("执行方式") {
                    LabeledContent("处理器", value: hook.handlerType.title)
                    if hook.handlerType == .unknown {
                        LabeledContent("处理器原值", value: hook.rawHandlerType)
                    }
                    LabeledContent("最长等待", value: "\(hook.timeoutSeconds) 秒")
                    if hook.handlerType != .command {
                        Label("Skill Lens 当前不提供这种处理器的执行预览或修改能力，请以 Codex 的实际状态为准。", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    Button(revealsCommand ? "隐藏命令" : "显示脱敏命令") {
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

                Text("启停操作通过 Codex 官方配置接口完成，并使用配置版本避免覆盖并发修改；信任审批和 managed 配置不会通过猜测文件格式修改。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(minWidth: 470)
        .confirmationDialog(hook.isEnabled ? "停用这个 Hook？" : "启用这个 Hook？", isPresented: $confirmsChange) {
            Button(hook.isEnabled ? "停用 Hook" : "启用 Hook", role: hook.isEnabled ? .destructive : nil) {
                isChanging = true
                Task {
                    await model.setHook(hook, enabled: !hook.isEnabled)
                    isChanging = false
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会在个人 Codex 配置中写入该 Hook 的启停状态，并影响使用同一配置的 Codex 客户端。原始项目或插件配置不会被直接改写，托管配置仍保持只读。")
        }
    }

    private var flowSection: some View {
        HStack(spacing: 10) {
            flowNode(title: hook.event.title, subtitle: "触发时机", symbol: "bolt.fill")
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            flowNode(title: hook.matcher?.isEmpty == false ? hook.matcher! : "全部", subtitle: "匹配对象", symbol: "line.3.horizontal.decrease.circle")
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            flowNode(title: hook.handlerType.title, subtitle: "执行处理", symbol: "terminal")
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func flowNode(title: String, subtitle: String, symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.blue)
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
    }

    private var trustColor: Color {
        switch hook.trustStatus {
        case .trusted, .managed: .green
        case .untrusted, .modified: .orange
        case .unknown: .secondary
        }
    }
}
