import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .frame(maxHeight: .infinity)
                .layoutPriority(1)

            Divider()

            NavigationStack {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(WorkbenchTheme.canvas)
                    .clipped()
                    .accessibilityIdentifier("screen-\(model.selection.rawValue)")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        model.chooseWorkspace()
                    } label: {
                        Label("切换工作区", systemImage: "folder")
                    }
                    if [.dashboard, .skills, .hooks].contains(model.selection) {
                        Button {
                            Task {
                                if model.selection == .dashboard {
                                    await model.refreshOverview(forceReload: true)
                                } else {
                                    await model.refresh(forceReload: true)
                                }
                            }
                        } label: {
                            Label("重新扫描", systemImage: "arrow.clockwise")
                        }
                        .disabled(
                            model.isRefreshing ||
                            (model.selection == .dashboard && (
                                model.isRefreshingUsage ||
                                model.isRefreshingMCP ||
                                model.isScanningStorage ||
                                model.isScanningMemory
                            ))
                        )
                    }
                }
            }
        }
        .background(WorkbenchTheme.canvas)
        .tint(WorkbenchTheme.accent)
    }

    private var sidebar: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 4) {
                ForEach(SidebarDestination.allCases) { destination in
                    Button {
                        model.selection = destination
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: destination.symbol)
                                .frame(width: 20)
                            Text(destination.title)
                                .font(.body.weight(.medium))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .contentShape(Rectangle())
                        .foregroundStyle(model.selection == destination ? .white : .primary)
                        .background {
                            if model.selection == destination {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(WorkbenchTheme.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sidebar-\(destination.rawValue)")
                    .accessibilityValue(model.selection == destination ? "已选择" : "")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("primary-sidebar")
        .safeAreaInset(edge: .bottom) {
            workspaceFooter
        }
        .background(WorkbenchTheme.sidebar)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch model.selection {
        case .dashboard: DashboardView()
        case .skills: SkillsView()
        case .hooks: HooksView()
        case .memory: MemoryView()
        case .usage: UsageView()
        case .mcp: MCPView()
        case .storage: StorageView()
        case .backup: BackupView()
        case .history: ChangeHistoryView()
        case .diagnostics: DiagnosticsView()
        }
    }

    private var workspaceFooter: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("当前工作区")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(model.workspaceURL.lastPathComponent.isEmpty ? model.workspaceURL.path : model.workspaceURL.lastPathComponent)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Text(model.workspaceURL.path)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(WorkbenchTheme.sidebar)
    }
}
