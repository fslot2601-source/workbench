import Foundation

actor CodexService {
    nonisolated var events: AsyncStream<AppServerEvent> { transport.events }

    private let transport = AppServerTransport()
    private var serverInfo: CodexServerInfo?
    private var connectionAttempt: ConnectionAttempt?

    func connect(executableURL: URL, environment: [String: String] = [:]) async throws -> CodexServerInfo {
        if let serverInfo, await transport.isRunning() { return serverInfo }
        if serverInfo != nil {
            await transport.stop()
            self.serverInfo = nil
            connectionAttempt = nil
        }
        if let connectionAttempt {
            return try await finishConnection(connectionAttempt)
        }

        let id = UUID()
        let clientVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let task = Task { [transport] in
            try await transport.start(
                executableURL: executableURL,
                environment: environment,
                connectionID: id
            )
            let response: InitializeResponse = try await transport.request(
                method: "initialize",
                params: .object([
                    "clientInfo": .object([
                        "name": .string("skill_lens"),
                        "title": .string("Workbench"),
                        "version": .string(clientVersion)
                    ]),
                    "capabilities": .object([
                        "experimentalApi": .bool(false),
                        "requestAttestation": .bool(false)
                    ])
                ])
            )
            try await transport.sendNotification(method: "initialized", params: .object([:]))

            let info = CodexServerInfo(
                userAgent: response.userAgent,
                codexHome: response.codexHome,
                platformFamily: response.platformFamily,
                platformOS: response.platformOS,
                executablePath: executableURL.path,
                connectionID: id
            )
            return info
        }
        let attempt = ConnectionAttempt(id: id, task: task)
        connectionAttempt = attempt
        return try await finishConnection(attempt)
    }

    func listSkills(cwd: URL, forceReload: Bool = false) async throws -> [SkillRecord] {
        let response: SkillsListResponse = try await transport.request(
            method: "skills/list",
            params: .object([
                "cwds": .array([.string(cwd.path)]),
                "forceReload": .bool(forceReload)
            ])
        )
        guard let entry = response.data.first(where: { $0.cwd == cwd.path }) ?? response.data.first else {
            return []
        }
        return entry.skills
            .map { ProtocolMapper.skill($0, errors: entry.errors) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func listHooks(cwd: URL) async throws -> (hooks: [HookRecord], warnings: [String]) {
        let response: HooksListResponse = try await transport.request(
            method: "hooks/list",
            params: .object(["cwds": .array([.string(cwd.path)])])
        )
        guard let entry = response.data.first(where: { $0.cwd == cwd.path }) ?? response.data.first else {
            return ([], [])
        }
        let errors = entry.errors.map {
            "\(DiagnosticRedactor.pathSummary($0.path))：\(DiagnosticRedactor.sanitize($0.message))"
        }
        return (
            entry.hooks.map(ProtocolMapper.hook).sorted { $0.displayOrder < $1.displayOrder },
            entry.warnings.map(DiagnosticRedactor.sanitize) + errors
        )
    }

    func setSkillEnabled(_ skill: SkillRecord, enabled: Bool, cwd: URL) async throws {
        _ = try validatedSkillURL(skill, cwd: cwd)
        let _: EmptyResponse = try await transport.request(
            method: "skills/config/write",
            params: .object([
                "path": .string(skill.path),
                "enabled": .bool(enabled)
            ])
        )
    }

    func setSkillInvocationPolicy(
        _ skill: SkillRecord,
        policy: SkillInvocationPolicy,
        cwd: URL
    ) throws -> SkillMetadataMutation {
        let skillURL = try validatedSkillURL(skill, cwd: cwd)
        return try SkillMetadataResolver.writeInvocationPolicy(
            skillPath: skillURL.path,
            policy: policy
        )
    }

    func restoreSkillInvocationPolicy(_ mutation: SkillMetadataMutation) throws {
        try SkillMetadataResolver.restore(mutation)
    }

    func setHookEnabled(_ hook: HookRecord, enabled: Bool, cwd: URL) async throws {
        guard !hook.isEffectivelyManaged else { throw CodexServiceError.managedHook }
        guard Self.isSafeHookKey(hook.key) else { throw CodexServiceError.unsafeHookKey }

        let before: ConfigReadResponse = try await transport.request(
            method: "config/read",
            params: .object([
                "cwd": .string(cwd.path),
                "includeLayers": .bool(true)
            ])
        )
        guard let userLayer = before.layers?.first(where: { $0.sourceType == "user" }) else {
            throw CodexServiceError.userConfigLayerMissing
        }

        let response: ConfigBatchWriteResponse = try await transport.request(
            method: "config/batchWrite",
            params: .object([
                "edits": .array([
                    .object([
                        "keyPath": .string("hooks.state.\(hook.key).enabled"),
                        "value": .bool(enabled),
                        "mergeStrategy": .string("upsert")
                    ])
                ]),
                "expectedVersion": .string(userLayer.version),
                "reloadUserConfig": .bool(true)
            ])
        )
        guard response.status == "ok" else { throw CodexServiceError.writeRejected }
    }

    func readRateLimits() async throws -> (records: [RateLimitRecord], resetCredits: Int?) {
        let response: AccountRateLimitsResponse = try await transport.request(
            method: "account/rateLimits/read",
            params: .null
        )
        let snapshots: [(String, RateLimitSnapshotWire)]
        if let byID = response.rateLimitsByLimitId, !byID.isEmpty {
            snapshots = byID.sorted { $0.key < $1.key }
        } else {
            snapshots = [(response.rateLimits.limitId ?? "codex", response.rateLimits)]
        }
        let records = snapshots.map { fallbackID, snapshot in
            RateLimitRecord(
                id: snapshot.limitId ?? fallbackID,
                name: DiagnosticRedactor.sanitize(snapshot.limitName ?? snapshot.limitId ?? fallbackID),
                planType: snapshot.planType.map(DiagnosticRedactor.sanitize),
                primary: snapshot.primary.map(Self.rateWindow),
                secondary: snapshot.secondary.map(Self.rateWindow),
                reachedType: snapshot.rateLimitReachedType.map(DiagnosticRedactor.sanitize),
                creditBalance: snapshot.credits?.balance.map(DiagnosticRedactor.sanitize)
            )
        }
        return (records, response.rateLimitResetCredits?.availableCount)
    }

    func readTokenUsage() async throws -> (summary: TokenUsageSummary, daily: [DailyTokenUsage]) {
        let response: AccountTokenUsageResponse = try await transport.request(
            method: "account/usage/read",
            params: .null
        )
        return (
            TokenUsageSummary(
                lifetimeTokens: response.summary.lifetimeTokens,
                peakDailyTokens: response.summary.peakDailyTokens,
                longestRunningTurnSeconds: response.summary.longestRunningTurnSec,
                currentStreakDays: response.summary.currentStreakDays,
                longestStreakDays: response.summary.longestStreakDays
            ),
            response.dailyUsageBuckets?.map {
                DailyTokenUsage(startDate: $0.startDate, tokens: $0.tokens)
            } ?? []
        )
    }

    func listConfiguredMCPServers(cwd: URL) async throws -> MCPListResult {
        let config = try await readConfig(cwd: cwd)
        let configured = config.config.objectValue?["mcp_servers"]?.objectValue ?? [:]
        let checkedAt = Date()
        let servers: [MCPRecord] = configured.map { name, value in
            let values = value.objectValue ?? [:]
            let enabled = values["enabled"]?.boolValue ?? true
            let required = values["required"]?.boolValue ?? false
            let permission = Self.mcpModificationPermission(name: name, config: config, required: required)
            let url = values["url"]?.stringValue
            let command = values["command"]?.stringValue
            let transport: MCPTransport = url != nil ? .http : (command != nil ? .stdio : .unknown)
            return MCPRecord(
                name: name,
                displayName: DiagnosticRedactor.sanitize(name),
                version: nil,
                description: nil,
                transport: transport,
                endpointSummary: Self.endpointSummary(url: url, command: command),
                isConfigured: true,
                isEnabled: enabled,
                isRequired: required,
                authStatus: .unknown,
                startupStatus: enabled ? .configured : .disabled,
                inventoryStatus: .notReported,
                tools: [],
                resources: [],
                startupTimeoutSeconds: values["startup_timeout_sec"]?.numberValue.map(Int.init),
                toolTimeoutSeconds: values["tool_timeout_sec"]?.numberValue.map(Int.init),
                configurationIssue: Self.mcpConfigurationIssue(url: url, command: command),
                errorMessage: nil,
                checkedAt: checkedAt,
                workspacePath: cwd.path,
                canModify: permission.allowed,
                readOnlyReason: permission.reason
            )
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        return MCPListResult(servers: servers, statusWarning: nil, checkedAt: checkedAt)
    }

    func listMCPServers(cwd: URL) async throws -> MCPListResult {
        let config = try await readConfig(cwd: cwd)
        let configured = config.config.objectValue?["mcp_servers"]?.objectValue ?? [:]
        let checkedAt = Date()

        var inventory: [String: MCPServerStatusWire] = [:]
        var statusWarning: String?
        do {
            var cursor: String?
            var seenCursors: Set<String> = []
            var pageCount = 0
            repeat {
                pageCount += 1
                guard pageCount <= 20 else { throw CodexServiceError.invalidMCPPagination }
                let response: MCPServerStatusListResponse = try await transport.request(
                    method: "mcpServerStatus/list",
                    params: .object([
                        "cursor": cursor.map(JSONValue.string) ?? .null,
                        "detail": .string("full"),
                        "limit": .number(100),
                        "threadId": .null
                    ])
                )
                for item in response.data { inventory[item.name] = item }
                cursor = response.nextCursor
                if let cursor, !seenCursors.insert(cursor).inserted {
                    throw CodexServiceError.invalidMCPPagination
                }
            } while cursor != nil
        } catch {
            statusWarning = "能力状态检测没有完成：\(DiagnosticRedactor.commandSummary(error.localizedDescription))"
        }

        let names = Set(configured.keys).union(inventory.keys)
        let servers: [MCPRecord] = names.map { name -> MCPRecord in
            let values = configured[name]?.objectValue ?? [:]
            let status = inventory[name]
            let isConfigured = configured[name] != nil
            let enabled = values["enabled"]?.boolValue ?? true
            let required = values["required"]?.boolValue ?? false
            let permission = Self.mcpModificationPermission(name: name, config: config, required: required)
            let url = values["url"]?.stringValue
            let command = values["command"]?.stringValue
            let transport: MCPTransport = url != nil ? .http : (command != nil ? .stdio : .unknown)
            let tools = status?.tools.values.map {
                MCPToolRecord(
                    name: DiagnosticRedactor.sanitize($0.name),
                    title: $0.title.map(DiagnosticRedactor.sanitize),
                    description: $0.description.map(DiagnosticRedactor.sanitize)
                )
            }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending } ?? []
            let resources = (status?.resources.map {
                MCPResourceRecord(
                    name: DiagnosticRedactor.sanitize($0.name),
                    title: $0.title.map(DiagnosticRedactor.sanitize),
                    description: $0.description.map(DiagnosticRedactor.sanitize),
                    kind: .resource
                )
            } ?? []) + (status?.resourceTemplates.map {
                MCPResourceRecord(
                    name: DiagnosticRedactor.sanitize($0.name),
                    title: $0.title.map(DiagnosticRedactor.sanitize),
                    description: $0.description.map(DiagnosticRedactor.sanitize),
                    kind: .template
                )
            } ?? [])
            let inventoryStatus: MCPInventoryStatus
            if status != nil {
                inventoryStatus = .available
            } else if let statusWarning {
                inventoryStatus = .unavailable(statusWarning)
            } else {
                inventoryStatus = .notReported
            }
            let displayName = DiagnosticRedactor.sanitize(status?.serverInfo?.title ?? status?.serverInfo?.name ?? name)
            let version = status?.serverInfo?.version.map(DiagnosticRedactor.sanitize)
            let description = status?.serverInfo?.description.map(DiagnosticRedactor.sanitize)
            let endpoint = Self.endpointSummary(url: url, command: command)
            let startupStatus: MCPStartupStatus = !enabled ? .disabled : (status == nil ? .configured : .inventoryAvailable)
            let startupTimeout = values["startup_timeout_sec"]?.numberValue.map(Int.init)
            let toolTimeout = values["tool_timeout_sec"]?.numberValue.map(Int.init)
            let configurationIssue = isConfigured ? Self.mcpConfigurationIssue(url: url, command: command) : nil
            let authStatus = MCPAuthStatus(protocolValue: status?.authStatus)
            let workspacePath = cwd.path
            let canModify = permission.allowed
            let readOnlyReason = permission.reason
            let sortedResources = resources.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            return MCPRecord(
                name: name,
                displayName: displayName,
                version: version,
                description: description,
                transport: transport,
                endpointSummary: endpoint,
                isConfigured: isConfigured,
                isEnabled: enabled,
                isRequired: required,
                authStatus: authStatus,
                startupStatus: startupStatus,
                inventoryStatus: inventoryStatus,
                tools: tools,
                resources: sortedResources,
                startupTimeoutSeconds: startupTimeout,
                toolTimeoutSeconds: toolTimeout,
                configurationIssue: configurationIssue,
                errorMessage: nil,
                checkedAt: checkedAt,
                workspacePath: workspacePath,
                canModify: canModify,
                readOnlyReason: readOnlyReason
            )
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        return MCPListResult(servers: servers, statusWarning: statusWarning, checkedAt: checkedAt)
    }

    func setMCPEnabled(name: String, enabled: Bool, cwd: URL) async throws {
        guard Self.isSafeConfigKey(name) else { throw CodexServiceError.unsafeMCPName }
        let before = try await readConfig(cwd: cwd)
        let required = before.config.objectValue?["mcp_servers"]?.objectValue?[name]?.objectValue?["required"]?.boolValue ?? false
        guard Self.mcpModificationPermission(name: name, config: before, required: required).allowed else {
            throw CodexServiceError.protectedMCP
        }
        guard let userLayer = before.layers?.first(where: { $0.sourceType == "user" }) else {
            throw CodexServiceError.userConfigLayerMissing
        }
        let response: ConfigBatchWriteResponse = try await transport.request(
            method: "config/batchWrite",
            params: .object([
                "edits": .array([
                    .object([
                        "keyPath": .string("mcp_servers.\(name).enabled"),
                        "value": .bool(enabled),
                        "mergeStrategy": .string("upsert")
                    ])
                ]),
                "expectedVersion": .string(userLayer.version),
                // 单项开关只落盘。Codex 的热更新与 MCP reload 都是全局操作，
                // 在这里触发会让其他 MCP 一起重启并短暂改变状态。
                "reloadUserConfig": .bool(false)
            ])
        )
        guard response.status == "ok" else { throw CodexServiceError.writeRejected }

        let verified = try await readConfig(cwd: cwd)
        let value = verified.config.objectValue?["mcp_servers"]?.objectValue?[name]?.objectValue?["enabled"]?.boolValue
        guard value == enabled else { throw CodexServiceError.writeVerificationFailed }
    }

    func reloadAllMCPServers() async throws {
        let _: EmptyResponse = try await transport.request(method: "config/mcpServer/reload", params: .null)
    }

    func readUserConfig(cwd: URL) async throws -> JSONValue? {
        let config = try await readConfig(cwd: cwd)
        return config.layers?.first(where: { $0.sourceType == "user" })?.config
    }

    func disconnect() async {
        connectionAttempt?.task.cancel()
        connectionAttempt = nil
        await transport.stop()
        serverInfo = nil
    }

    func isConnected() async -> Bool {
        guard serverInfo != nil else { return false }
        return await transport.isRunning()
    }

    static func isSafeHookKey(_ key: String) -> Bool {
        isSafeConfigKey(key)
    }

    static func isSafeConfigKey(_ key: String) -> Bool {
        !key.isEmpty && key.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }

    private func readConfig(cwd: URL) async throws -> ConfigReadResponse {
        try await transport.request(
            method: "config/read",
            params: .object([
                "cwd": .string(cwd.path),
                "includeLayers": .bool(true)
            ])
        )
    }

    private func finishConnection(_ attempt: ConnectionAttempt) async throws -> CodexServerInfo {
        do {
            let info = try await attempt.task.value
            guard connectionAttempt?.id == attempt.id else { throw CancellationError() }
            serverInfo = info
            // Keep the completed attempt until disconnect or a detected process exit so
            // every waiter on the same attempt observes the same successful result.
            return info
        } catch {
            if connectionAttempt?.id == attempt.id {
                connectionAttempt = nil
                serverInfo = nil
                await transport.stop()
            }
            throw error
        }
    }

    static func mcpModificationPermission(
        name: String,
        config: ConfigReadResponse,
        required: Bool
    ) -> (allowed: Bool, reason: String?) {
        guard isSafeConfigKey(name) else { return (false, "名称包含不支持的字符，因此保持只读。") }
        guard !required else { return (false, "这是 Codex 启动必需的 MCP，不能在这里停用。") }
        let layers = config.layers ?? []
        let definingLayers = layers.filter {
            $0.config.objectValue?["mcp_servers"]?.objectValue?[name] != nil
        }
        guard definingLayers.contains(where: { $0.sourceType == "user" }) else {
            return (false, "这个 MCP 不属于可写的个人配置层。")
        }
        guard !definingLayers.contains(where: { $0.sourceType != "user" }) else {
            return (false, "这个 MCP 同时由系统或管理员配置，Workbench 将它保持为只读。")
        }
        return (true, nil)
    }

    private static func rateWindow(_ wire: RateLimitWindowWire) -> RateLimitWindowRecord {
        RateLimitWindowRecord(
            usedPercent: wire.usedPercent,
            windowDurationMinutes: wire.windowDurationMins,
            resetsAt: wire.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    static func endpointSummary(url: String?, command: String?) -> String {
        if let url, let components = URLComponents(string: url), let scheme = components.scheme {
            let host = components.host ?? "未公开主机"
            let port = components.port.map { ":\($0)" } ?? ""
            return "\(scheme)://\(host)\(port)"
        }
        if let executable = command.flatMap(executableToken) {
            return URL(fileURLWithPath: executable).lastPathComponent
        }
        return "未公开"
    }

    static func mcpConfigurationIssue(url: String?, command: String?) -> String? {
        if let url {
            guard let components = URLComponents(string: url),
                  let scheme = components.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  components.host?.isEmpty == false
            else { return "远程地址不是有效的 HTTP 或 HTTPS URL。" }
            return nil
        }
        if let command {
            guard let executable = executableToken(command) else { return "本地启动命令为空。" }
            if executable.hasPrefix("/") {
                guard FileManager.default.fileExists(atPath: executable) else { return "本地启动器文件不存在。" }
                guard FileManager.default.isExecutableFile(atPath: executable) else { return "本地启动器没有执行权限。" }
            }
            return nil
        }
        return "配置缺少远程地址或本地启动命令。"
    }

    private static func executableToken(_ command: String) -> String? {
        let value = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let quote = value.first, quote == "\"" || quote == "'" {
            let remainder = value.dropFirst()
            guard let end = remainder.firstIndex(of: quote) else { return nil }
            return String(remainder[..<end])
        }
        return value.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }

    private func validatedSkillURL(_ skill: SkillRecord, cwd: URL) throws -> URL {
        guard skill.canModify else { throw CodexServiceError.protectedSkill }
        guard let serverInfo else { throw AppServerTransportError.notStarted }
        let skillURL = URL(fileURLWithPath: skill.path).resolvingSymlinksInPath().standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
        let codexHome = URL(fileURLWithPath: serverInfo.codexHome).resolvingSymlinksInPath()
        let allowedRoots: [URL]
        switch skill.scope {
        case .user:
            allowedRoots = [
                codexHome.appending(path: "skills").resolvingSymlinksInPath(),
                codexHome.appending(path: "plugins").resolvingSymlinksInPath(),
                home.appending(path: ".agents/skills").resolvingSymlinksInPath()
            ]
        case .repo:
            allowedRoots = [cwd.resolvingSymlinksInPath()]
        default:
            throw CodexServiceError.protectedSkill
        }
        guard allowedRoots.contains(where: { Self.contains(skillURL, inside: $0) }) else {
            throw CodexServiceError.skillOutsideAllowedRoots
        }
        let values = try skillURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw CodexServiceError.invalidSkillFile
        }
        return skillURL
    }

    private static func contains(_ child: URL, inside root: URL) -> Bool {
        let childPath = child.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return childPath == rootPath || childPath.hasPrefix(rootPath + "/")
    }
}

private struct ConnectionAttempt: Sendable {
    let id: UUID
    let task: Task<CodexServerInfo, Error>
}

private struct EmptyResponse: Codable, Sendable { }

enum CodexServiceError: LocalizedError, Sendable {
    case unsafeHookKey
    case unsafeMCPName
    case userConfigLayerMissing
    case writeRejected
    case managedHook
    case writeVerificationFailed
    case protectedSkill
    case skillOutsideAllowedRoots
    case invalidSkillFile
    case protectedMCP
    case invalidMCPPagination

    var errorDescription: String? {
        switch self {
        case .unsafeHookKey: "该 Hook 的标识包含不支持的字符，为避免写错配置，Workbench 将它保持为只读。"
        case .unsafeMCPName: "该 MCP 名称包含不支持的字符，为避免写错配置，Workbench 将它保持为只读。"
        case .userConfigLayerMissing: "Codex 没有返回可写的用户配置层。"
        case .writeRejected: "Codex 没有确认配置写入成功。"
        case .managedHook: "该 Hook 由系统或管理员管理，不能在这里修改。"
        case .writeVerificationFailed: "Codex 接受了写入，但重新读取后配置状态没有生效。"
        case .protectedSkill: "系统、管理员或来源未知的 Skill 不能在这里修改。"
        case .skillOutsideAllowedRoots: "Skill 路径不在当前工作区或个人 Codex 目录内，已拒绝修改。"
        case .invalidSkillFile: "Skill 配置不是可安全修改的普通文件，已拒绝修改。"
        case .protectedMCP: "这个 MCP 不属于可安全修改的个人配置，已保持只读。"
        case .invalidMCPPagination: "Codex 返回了异常的 MCP 分页信息，读取已停止。"
        }
    }
}
