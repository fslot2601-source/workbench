import Foundation

actor CodexService {
    nonisolated var events: AsyncStream<AppServerEvent> { transport.events }

    private let transport = AppServerTransport()
    private var serverInfo: CodexServerInfo?

    func connect(executableURL: URL, environment: [String: String] = [:]) async throws -> CodexServerInfo {
        if let serverInfo { return serverInfo }

        do {
            try await transport.start(executableURL: executableURL, environment: environment)
            let response: InitializeResponse = try await transport.request(
                method: "initialize",
                params: .object([
                    "clientInfo": .object([
                        "name": .string("skill_lens"),
                        "title": .string("Skill Lens"),
                        "version": .string(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
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
                executablePath: executableURL.path
            )
            serverInfo = info
            return info
        } catch {
            await transport.stop()
            throw error
        }
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
        let errors = entry.errors.map { "\($0.path)：\($0.message)" }
        return (
            entry.hooks.map(ProtocolMapper.hook).sorted { $0.displayOrder < $1.displayOrder },
            entry.warnings + errors
        )
    }

    func setSkillEnabled(path: String, enabled: Bool) async throws {
        let _: EmptyResponse = try await transport.request(
            method: "skills/config/write",
            params: .object([
                "path": .string(path),
                "enabled": .bool(enabled)
            ])
        )
    }

    func setHookEnabled(key: String, enabled: Bool, cwd: URL) async throws {
        guard Self.isSafeHookKey(key) else { throw CodexServiceError.unsafeHookKey }

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
                        "keyPath": .string("hooks.state.\(key).enabled"),
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
                name: snapshot.limitName ?? snapshot.limitId ?? fallbackID,
                planType: snapshot.planType,
                primary: snapshot.primary.map(Self.rateWindow),
                secondary: snapshot.secondary.map(Self.rateWindow),
                reachedType: snapshot.rateLimitReachedType,
                creditBalance: snapshot.credits?.balance
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

    func listMCPServers(cwd: URL) async throws -> [MCPRecord] {
        let config = try await readConfig(cwd: cwd)
        let configured = config.config.objectValue?["mcp_servers"]?.objectValue ?? [:]

        var inventory: [String: MCPServerStatusWire] = [:]
        var cursor: String?
        repeat {
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
        } while cursor != nil

        let names = Set(configured.keys).union(inventory.keys)
        return names.map { name in
            let values = configured[name]?.objectValue ?? [:]
            let status = inventory[name]
            let enabled = values["enabled"]?.boolValue ?? true
            let url = values["url"]?.stringValue
            let command = values["command"]?.stringValue
            let transport: MCPTransport = url != nil ? .http : (command != nil ? .stdio : .unknown)
            return MCPRecord(
                name: name,
                displayName: status?.serverInfo?.title ?? status?.serverInfo?.name ?? name,
                version: status?.serverInfo?.version,
                description: status?.serverInfo?.description,
                transport: transport,
                endpointSummary: Self.endpointSummary(url: url, command: command),
                isEnabled: enabled,
                isRequired: values["required"]?.boolValue ?? false,
                authStatus: MCPAuthStatus(protocolValue: status?.authStatus),
                startupStatus: !enabled ? .disabled : (status == nil ? .configured : .inventoryAvailable),
                toolCount: status?.tools.count ?? 0,
                resourceCount: status?.resources.count ?? 0,
                resourceTemplateCount: status?.resourceTemplates.count ?? 0,
                startupTimeoutSeconds: values["startup_timeout_sec"]?.numberValue.map(Int.init),
                toolTimeoutSeconds: values["tool_timeout_sec"]?.numberValue.map(Int.init),
                errorMessage: nil
            )
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func setMCPEnabled(name: String, enabled: Bool, cwd: URL) async throws {
        guard Self.isSafeConfigKey(name) else { throw CodexServiceError.unsafeMCPName }
        let before = try await readConfig(cwd: cwd)
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
                "reloadUserConfig": .bool(true)
            ])
        )
        guard response.status == "ok" else { throw CodexServiceError.writeRejected }
        let _: EmptyResponse = try await transport.request(method: "config/mcpServer/reload", params: .null)

        let verified = try await readConfig(cwd: cwd)
        let value = verified.config.objectValue?["mcp_servers"]?.objectValue?[name]?.objectValue?["enabled"]?.boolValue
        guard value == enabled else { throw CodexServiceError.writeVerificationFailed }
    }

    func disconnect() async {
        await transport.stop()
        serverInfo = nil
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

    private static func rateWindow(_ wire: RateLimitWindowWire) -> RateLimitWindowRecord {
        RateLimitWindowRecord(
            usedPercent: wire.usedPercent,
            windowDurationMinutes: wire.windowDurationMins,
            resetsAt: wire.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    private static func endpointSummary(url: String?, command: String?) -> String {
        if let url, let components = URLComponents(string: url), let scheme = components.scheme {
            let host = components.host ?? "未公开主机"
            let port = components.port.map { ":\($0)" } ?? ""
            return "\(scheme)://\(host)\(port)"
        }
        if let command, !command.isEmpty {
            return URL(fileURLWithPath: command).lastPathComponent
        }
        return "未公开"
    }
}

private struct EmptyResponse: Codable, Sendable { }

enum CodexServiceError: LocalizedError, Sendable {
    case unsafeHookKey
    case unsafeMCPName
    case userConfigLayerMissing
    case writeRejected
    case managedHook
    case writeVerificationFailed

    var errorDescription: String? {
        switch self {
        case .unsafeHookKey: "该 Hook 的标识包含不支持的字符，为避免写错配置，Skill Lens 将它保持为只读。"
        case .unsafeMCPName: "该 MCP 名称包含不支持的字符，为避免写错配置，Skill Lens 将它保持为只读。"
        case .userConfigLayerMissing: "Codex 没有返回可写的用户配置层。"
        case .writeRejected: "Codex 没有确认配置写入成功。"
        case .managedHook: "该 Hook 由系统或管理员管理，不能在这里修改。"
        case .writeVerificationFailed: "Codex 接受了写入，但重新读取后 Hook 状态没有生效。"
        }
    }
}
