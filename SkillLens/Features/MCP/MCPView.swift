import SwiftUI

struct MCPView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: String?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                scopeNotice
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
                        description: Text(model.mcpError ?? "当前有效配置中没有 MCP，或此 Codex 版本不支持状态接口。")
                    )
                } else {
                    List(model.mcpServers, selection: $selectedID) { server in
                        MCPRow(server: server).tag(server.id)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 340, idealWidth: 410)

            if let selectedServer {
                MCPDetailView(server: selectedServer)
                    .id(selectedServer.id)
            } else {
                ContentUnavailableView("选择一个 MCP", systemImage: "server.rack")
                    .frame(minWidth: 450)
            }
        }
        .navigationTitle("MCP")
        .task {
            await model.refreshMCP()
            if selectedID == nil { selectedID = model.mcpServers.first?.id }
        }
        .onChange(of: model.mcpServers.map(\.id)) { _, ids in
            if let selectedID, ids.contains(selectedID) { return }
            selectedID = ids.first
        }
        .toolbar {
            Button { Task { await model.refreshMCP() } } label: {
                Label("刷新 MCP", systemImage: "arrow.clockwise")
            }
            .disabled(model.isRefreshingMCP)
        }
    }

    private var scopeNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("当前有效配置与本连接能力清单").font(.callout.weight(.semibold))
            Text("“已启用”只代表配置开关；“能力已读取”不等于进程一直运行。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = model.mcpError { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectedServer: MCPRecord? {
        guard let selectedID else { return nil }
        return model.mcpServers.first { $0.id == selectedID }
    }
}

private struct MCPRow: View {
    let server: MCPRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusSymbol).foregroundStyle(statusColor).font(.title3).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(server.displayName).font(.headline).lineLimit(1)
                Text("\(server.transport.title) · \(server.startupStatus.title)")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(server.toolCount) 工具 · \(server.resourceCount + server.resourceTemplateCount) 资源")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5)
    }

    private var statusSymbol: String {
        switch server.startupStatus {
        case .ready, .inventoryAvailable: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .starting: "hourglass.circle.fill"
        case .disabled, .cancelled: "pause.circle.fill"
        case .configured, .unknown: "questionmark.circle.fill"
        }
    }
    private var statusColor: Color {
        switch server.startupStatus {
        case .ready, .inventoryAvailable: .green
        case .failed: .red
        case .starting: .blue
        case .disabled, .cancelled: .secondary
        case .configured, .unknown: .orange
        }
    }
}

private struct MCPDetailView: View {
    @Environment(AppModel.self) private var model
    let server: MCPRecord
    @State private var confirmsChange = false
    @State private var isChanging = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(server.displayName).font(.largeTitle.bold())
                        HStack {
                            StatusBadge(text: server.isEnabled ? "配置已启用" : "配置已停用", color: server.isEnabled ? .blue : .secondary)
                            StatusBadge(text: server.startupStatus.title, color: statusColor)
                            if server.isRequired { StatusBadge(text: "启动必需", color: .purple, symbol: "exclamationmark.shield") }
                        }
                    }
                    Spacer()
                    Button(server.isEnabled ? "停用配置" : "启用配置") { confirmsChange = true }
                        .buttonStyle(.borderedProminent)
                        .tint(server.isEnabled ? .secondary : .accentColor)
                        .disabled(isChanging || !CodexService.isSafeConfigKey(server.name))
                }

                detailSection("连接") {
                    LabeledContent("类型", value: server.transport.title)
                    LabeledContent("地址或启动器", value: server.endpointSummary)
                    LabeledContent("认证", value: server.authStatus.title)
                    if let version = server.version { LabeledContent("服务版本", value: version) }
                    if let error = server.errorMessage {
                        Label(DiagnosticRedactor.commandSummary(error), systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    }
                }

                detailSection("能力") {
                    LabeledContent("工具", value: "\(server.toolCount)")
                    LabeledContent("资源", value: "\(server.resourceCount)")
                    LabeledContent("资源模板", value: "\(server.resourceTemplateCount)")
                    Text("这里只显示计数，不展示工具输入结构、资源 URI、命令参数或环境变量值。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                detailSection("超时") {
                    LabeledContent("启动", value: server.startupTimeoutSeconds.map { "\($0) 秒" } ?? "Codex 默认")
                    LabeledContent("单次工具", value: server.toolTimeoutSeconds.map { "\($0) 秒" } ?? "Codex 默认")
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(minWidth: 470)
        .confirmationDialog(server.isEnabled ? "停用这个 MCP 配置？" : "启用这个 MCP 配置？", isPresented: $confirmsChange) {
            Button(server.isEnabled ? "停用配置" : "启用配置", role: server.isEnabled ? .destructive : nil) {
                isChanging = true
                Task {
                    await model.setMCP(server, enabled: !server.isEnabled)
                    isChanging = false
                }
            }
        } message: {
            Text("这会修改用户级 Codex 配置并影响其他 Codex 客户端。Skill Lens 会做版本校验、重新加载和回读验证。")
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
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
    }

    private var statusColor: Color {
        switch server.startupStatus {
        case .ready, .inventoryAvailable: .green
        case .failed: .red
        case .starting: .blue
        case .disabled, .cancelled: .secondary
        case .configured, .unknown: .orange
        }
    }
}
