import AppKit
import SwiftUI

struct WorkbenchSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("常规", systemImage: "gearshape") }
            CodexSettingsView()
                .environment(model)
                .tabItem { Label("Codex", systemImage: "terminal") }
            AboutSettingsView()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 410)
        .navigationTitle("Workbench 设置")
        .background(SettingsWindowTitleSetter(title: "Workbench 设置"))
    }
}

private struct SettingsWindowTitleSetter: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> TitleSettingView {
        TitleSettingView(title: title)
    }

    func updateNSView(_ nsView: TitleSettingView, context: Context) {
        nsView.title = title
        nsView.applyTitle()
    }
}

private final class TitleSettingView: NSView {
    var title: String

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyTitle()
        DispatchQueue.main.async { [weak self] in
            self?.applyTitle()
        }
    }

    func applyTitle() {
        window?.title = title
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(WorkbenchPreferences.showMenuBarIconKey) private var showMenuBarIcon = true
    @AppStorage(WorkbenchPreferences.menuBarRefreshMinutesKey) private var refreshMinutes = WorkbenchPreferences.defaultRefreshMinutes
    @AppStorage(WorkbenchPreferences.showMenuBarTokenActivityKey) private var showTokenActivity = true
    @AppStorage(WorkbenchPreferences.showMenuBarStorageKey) private var showStorage = true

    var body: some View {
        Form {
            Section("状态栏") {
                Toggle("在菜单栏显示 Workbench", isOn: $showMenuBarIcon)
                Picker("自动更新用量", selection: $refreshMinutes) {
                    ForEach(WorkbenchPreferences.supportedRefreshMinutes, id: \.self) { minutes in
                        Text("每 \(minutes) 分钟").tag(minutes)
                    }
                }
                .disabled(!showMenuBarIcon)
                Toggle("显示 Token 活动", isOn: $showTokenActivity)
                    .disabled(!showMenuBarIcon)
                Toggle("显示本地存储占用", isOn: $showStorage)
                    .disabled(!showMenuBarIcon)
                Text("自动更新只读取 Codex 官方账户接口，不读取登录令牌，也不会估算美元费用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}

private struct CodexSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("当前工作区") {
                LabeledContent("位置") {
                    Text(model.workspaceURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Button("选择工作区…") { model.chooseWorkspace() }
            }
            Section("Codex") {
                if case .connected(let info) = model.connectionState {
                    LabeledContent("连接", value: "已连接")
                    LabeledContent("可执行文件") {
                        Text(info.executablePath).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    }
                    LabeledContent("Codex Home") {
                        Text(info.codexHome).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    }
                } else {
                    LabeledContent("连接", value: model.connectionState.title)
                }
                Button("选择 ChatGPT 或 Codex…") { model.chooseCodexExecutable() }
                Text("通常无需手动选择。Workbench 支持 ChatGPT.app 内置 Codex，也支持单独安装的 Codex CLI。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}

private struct AboutSettingsView: View {
    @Environment(WorkbenchUpdateController.self) private var updateController

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 82, height: 82)
            Text("Workbench").font(.title.bold())
            Text("为 Codex 制作的 macOS 本地工具箱")
                .foregroundStyle(.secondary)
            Text(versionText).font(.caption).foregroundStyle(.secondary)
            Divider().frame(width: 300)
            Toggle(
                "自动检查更新",
                isOn: Binding(
                    get: { updateController.automaticallyChecksForUpdates },
                    set: { updateController.automaticallyChecksForUpdates = $0 }
                )
            )
            .toggleStyle(.switch)
            .frame(width: 300)
            Button("检查更新…") {
                updateController.checkForUpdates()
            }
            Divider().frame(width: 300)
            Text("独立开源项目 · 无遥测 · 无广告 · 无独立账户系统")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "开发版"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "版本 \(version)（\(build)）· macOS 14 及以上"
    }
}
