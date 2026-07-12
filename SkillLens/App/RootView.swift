import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(SidebarDestination.allCases, selection: $model.selection) { destination in
                Label(destination.title, systemImage: destination.symbol)
                    .tag(destination)
                    .accessibilityIdentifier("sidebar-\(destination.rawValue)")
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 250)
            .safeAreaInset(edge: .bottom) {
                workspaceFooter
            }
        } detail: {
            Group {
                switch model.selection {
                case .dashboard: DashboardView()
                case .skills: SkillsView()
                case .hooks: HooksView()
                case .usage: UsageView()
                case .mcp: MCPView()
                case .storage: StorageView()
                case .history: ChangeHistoryView()
                case .diagnostics: DiagnosticsView()
                }
            }
            .id(model.selection)
            .accessibilityIdentifier("screen-\(model.selection.rawValue)")
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        model.chooseWorkspace()
                    } label: {
                        Label("切换工作区", systemImage: "folder")
                    }
                    if [.dashboard, .skills, .hooks].contains(model.selection) {
                        Button {
                            Task { await model.refresh(forceReload: true) }
                        } label: {
                            Label("重新扫描", systemImage: "arrow.clockwise")
                        }
                        .disabled(model.isRefreshing)
                    }
                }
            }
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
        .background(.bar)
    }
}
