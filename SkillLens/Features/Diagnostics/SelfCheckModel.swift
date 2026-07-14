import Foundation

extension AppModel {
    var selfCheckRecords: [SelfCheckRecord] {
        [
            connectionSelfCheck,
            workspaceSelfCheck,
            skillsSelfCheck,
            hooksSelfCheck,
            memorySelfCheck,
            usageSelfCheck,
            mcpSelfCheck,
            storageSelfCheck,
            backupSelfCheck
        ]
    }

    var failedSelfCheckCount: Int {
        selfCheckRecords.filter { $0.status.isFailure }.count
    }

    var warningSelfCheckCount: Int {
        selfCheckRecords.filter { $0.status == .warning }.count
    }

    var selfCheckReport: String {
        let lines = selfCheckRecords.map { record in
            "[\(record.status.title)] \(record.title)：\(DiagnosticRedactor.sanitize(record.detail))"
        }
        return ([
            "Workbench 自检报告",
            "时间：\(Date().formatted(date: .numeric, time: .standard))",
            "工作区：\(DiagnosticRedactor.pathSummary(workspaceURL.path))",
            ""
        ] + lines).joined(separator: "\n")
    }

    func runSelfCheck() async {
        await refreshOverview(forceReload: false)
        await refreshGitHubBackupState()
    }

    private var connectionSelfCheck: SelfCheckRecord {
        switch connectionState {
        case .idle:
            check(.connection, "Codex 连接", .notChecked, "尚未连接 Codex。", "连接后才能读取 Skills、Hooks、用量和 MCP。", .diagnostics)
        case .locating:
            check(.connection, "Codex 连接", .checking, "正在查找 Codex 可执行文件。", "检测完成前部分数据可能为空。", .diagnostics)
        case .connecting:
            check(.connection, "Codex 连接", .checking, "正在连接 Codex App Server。", "检测完成前部分数据可能为空。", .diagnostics)
        case .connected(let info):
            check(.connection, "Codex 连接", .passed, "已连接 \(info.userAgent)。", "Workbench 可以读取当前 Codex 的本地状态。", .diagnostics)
        case .failed(let message):
            check(.connection, "Codex 连接", .failed, DiagnosticRedactor.sanitize(message), "Skills、Hooks、用量和 MCP 无法更新。", .diagnostics)
        }
    }

    private var workspaceSelfCheck: SelfCheckRecord {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: workspaceURL.path, isDirectory: &isDirectory)
        let readable = FileManager.default.isReadableFile(atPath: workspaceURL.path)
        if exists, isDirectory.boolValue, readable {
            return check(.workspace, "当前工作区", .passed, "工作区存在且可读取。", "项目级 Skills、Hooks 和 MCP 会按此目录解析。", .dashboard)
        }
        return check(.workspace, "当前工作区", .failed, "工作区不存在、不是文件夹或无法读取。", "项目级配置可能显示错误或过期结果。", .dashboard)
    }

    private var skillsSelfCheck: SelfCheckRecord {
        if isRefreshing { return check(.skills, "Skills", .checking, "正在读取 Skills。", "稍后会显示真实状态。", .skills) }
        if let skillsError { return check(.skills, "Skills", .failed, skillsError, "Skills 清单和状态可能不完整。", .skills) }
        if hasCompletedInitialRefresh { return check(.skills, "Skills", .passed, "已读取 \(skills.count) 个 Skill。", "清单来自当前 Codex 和工作区。", .skills) }
        return check(.skills, "Skills", .notChecked, "尚未读取 Skills。", "运行自检后会读取。", .skills)
    }

    private var hooksSelfCheck: SelfCheckRecord {
        if isRefreshing { return check(.hooks, "Hooks", .checking, "正在读取 Hooks。", "稍后会显示真实状态。", .hooks) }
        if let hooksError { return check(.hooks, "Hooks", .failed, hooksError, "Hook 配置和触发链可能不完整。", .hooks) }
        if !hookWarnings.isEmpty { return check(.hooks, "Hooks", .warning, "已读取 \(hooks.count) 个 Hook，另有 \(hookWarnings.count) 条需要确认。", "警告不等于 Hook 已损坏，可进入页面查看原因。", .hooks) }
        if hasCompletedInitialRefresh { return check(.hooks, "Hooks", .passed, "已读取 \(hooks.count) 个 Hook。", "当前没有发现配置异常。", .hooks) }
        return check(.hooks, "Hooks", .notChecked, "尚未读取 Hooks。", "运行自检后会读取。", .hooks)
    }

    private var memorySelfCheck: SelfCheckRecord {
        if isScanningMemory { return check(.memory, "Memory", .checking, "正在扫描 Codex Memory。", "稍后会显示来源与适用范围。", .memory) }
        if let memoryError { return check(.memory, "Memory", .failed, memoryError, "Memory 内容暂时无法展示。", .memory) }
        if let snapshot = memorySnapshot {
            if !snapshot.warnings.isEmpty { return check(.memory, "Memory", .warning, "已识别 \(snapshot.items.count) 条记忆，另有 \(snapshot.warnings.count) 条解析提醒。", "提醒不代表记忆未生效，可检查范围和来源。", .memory) }
            return check(.memory, "Memory", .passed, "已识别 \(snapshot.items.count) 条记忆。", "可查看内容、来源和适用范围。", .memory)
        }
        return check(.memory, "Memory", .notChecked, "尚未扫描 Memory。", "运行自检后会扫描。", .memory)
    }

    private var usageSelfCheck: SelfCheckRecord {
        if isRefreshingUsage { return check(.usage, "账户用量", .checking, "正在读取官方账户用量。", "不会用本地日志伪造数据。", .usage) }
        let hasData = !rateLimits.isEmpty || tokenUsageSummary != nil
        if let usageError {
            return check(.usage, "账户用量", .warning, usageError, hasData ? "部分用量可用，缺失部分不会显示为 0。" : "当前登录方式可能不提供官方用量接口，不代表 Codex 故障。", .usage)
        }
        if hasData { return check(.usage, "账户用量", .passed, "官方账户用量可读取。", "状态栏会按设置定时更新。", .usage) }
        return check(.usage, "账户用量", .notChecked, "尚无官方用量数据。", "运行自检后会尝试读取。", .usage)
    }

    private var mcpSelfCheck: SelfCheckRecord {
        if isRefreshingMCP || isReloadingAllMCP { return check(.mcp, "MCP", .checking, "正在检测配置、连接和工具清单。", "稍后会显示每个服务的真实状态。", .mcp) }
        let problems = mcpServers.filter(\.hasProblem)
        if !problems.isEmpty { return check(.mcp, "MCP", .failed, "\(problems.count) 个 MCP 存在真实异常：\(problems.prefix(2).map(\.displayName).joined(separator: "、"))。", "对应服务可能无法向 Codex 暴露工具或资源。", .mcp) }
        if let mcpError { return check(.mcp, "MCP", .warning, mcpError, "状态读取不完整，但不能据此断定所有 MCP 故障。", .mcp) }
        if let mcpWarning { return check(.mcp, "MCP", .warning, mcpWarning, "部分能力仍待确认。", .mcp) }
        if !mcpServers.isEmpty { return check(.mcp, "MCP", .passed, "已检测 \(mcpServers.count) 个 MCP，没有发现真实异常。", "停用项不会被误报为问题。", .mcp) }
        return check(.mcp, "MCP", .notChecked, "尚未发现或读取 MCP 配置。", "没有配置也不等于故障。", .mcp)
    }

    private var storageSelfCheck: SelfCheckRecord {
        if isScanningStorage { return check(.storage, "本地存储", .checking, "正在扫描 Codex 本地数据。", "不会自动删除内容。", .storage) }
        if let storageError { return check(.storage, "本地存储", .failed, storageError, "存储占用和安全清理建议暂时不可用。", .storage) }
        if !storageRecords.isEmpty {
            let total = storageRecords.reduce(Int64(0)) { $0 + $1.sizeBytes }
            let text = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            return check(.storage, "本地存储", .passed, "已扫描 \(storageRecords.count) 类数据，共 \(text)。", "受保护数据不会开放清理。", .storage)
        }
        return check(.storage, "本地存储", .notChecked, "尚未扫描本地存储。", "运行自检后会扫描。", .storage)
    }

    private var backupSelfCheck: SelfCheckRecord {
        if isRefreshingGitHubBackup || isLoggingIntoGitHub { return check(.backup, "GitHub 备份", .checking, "正在检查 GitHub 登录状态。", "不会自动上传配置。", .backup) }
        if let backupError { return check(.backup, "GitHub 备份", .warning, backupError, "备份是可选功能，不影响 Codex 使用。", .backup) }
        switch githubBackupConnection {
        case .notChecked:
            return check(.backup, "GitHub 备份", .notChecked, "尚未检查 GitHub 备份。", "这是可选功能。", .backup)
        case .checking:
            return check(.backup, "GitHub 备份", .checking, "正在检查 GitHub 登录状态。", "不会自动上传配置。", .backup)
        case .cliMissing:
            return check(.backup, "GitHub 备份", .warning, "未安装 GitHub CLI。", "只影响可选的 GitHub 备份。", .backup)
        case .signedOut:
            return check(.backup, "GitHub 备份", .warning, "尚未登录 GitHub。", "只影响可选的 GitHub 备份。", .backup)
        case .signedIn(let account):
            return check(.backup, "GitHub 备份", .passed, "已登录 GitHub：\(account.login)。", "只有手动确认时才会上传。", .backup)
        }
    }

    private func check(
        _ kind: SelfCheckKind,
        _ title: String,
        _ status: SelfCheckStatus,
        _ detail: String,
        _ impact: String,
        _ destination: SidebarDestination?
    ) -> SelfCheckRecord {
        SelfCheckRecord(kind: kind, title: title, status: status, detail: DiagnosticRedactor.sanitize(detail), impact: impact, destination: destination)
    }
}
