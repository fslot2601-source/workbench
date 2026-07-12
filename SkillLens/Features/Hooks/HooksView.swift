import SwiftUI

struct HooksView: View {
    @Environment(AppModel.self) private var model
    @State private var mode: HookViewMode = .configuration
    @State private var selectedID: String?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("显示内容", selection: $mode) {
                ForEach(HookViewMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            .padding(12)
            Divider()

            switch mode {
            case .configuration:
                configurationView
            case .activity:
                HookActivityView(runs: model.hookRuns)
            }
        }
        .navigationTitle("Hooks")
        .onAppear {
            if selectedID == nil { selectedID = filteredHooks.first?.id }
        }
    }

    private var configurationView: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索触发时机、来源或匹配条件", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(9)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
                .padding(12)
                Divider()

                if filteredHooks.isEmpty {
                    ContentUnavailableView(
                        "当前工作区没有 Hook",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Hooks 会按工作区计算有效配置。")
                    )
                } else {
                    List(filteredHooks, selection: $selectedID) { hook in
                        HookRow(hook: hook)
                            .tag(hook.id)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 340, idealWidth: 410)

            if let selectedHook {
                HookDetailView(hook: selectedHook)
            } else {
                ContentUnavailableView("选择一个 Hook", systemImage: "link")
                    .frame(minWidth: 430)
            }
        }
    }

    private var filteredHooks: [HookRecord] {
        guard !searchText.isEmpty else { return model.hooks }
        return model.hooks.filter { hook in
            [hook.event.title, hook.rawEventName, hook.source.title, hook.matcher ?? "", hook.statusMessage ?? ""]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedHook: HookRecord? {
        guard let selectedID else { return nil }
        return model.hooks.first { $0.id == selectedID }
    }
}
private enum HookViewMode: String, CaseIterable, Identifiable {
    case configuration, activity
    var id: String { rawValue }
    var title: String { self == .configuration ? "配置状态" : "本连接运行记录" }
}

private struct HookRow: View {
    let hook: HookRecord

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: hook.runnableState == .ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(hook.runnableState.color)
                .font(.title3)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 5) {
                Text(hook.event.title)
                    .font(.headline)
                Text(hook.statusMessage ?? hook.matcher ?? hook.handlerType.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("\(hook.source.title) · \(hook.runnableState.title)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5)
    }
}
