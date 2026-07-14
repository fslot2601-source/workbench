import Foundation

actor CodexBackupService {
    private let fileManager: FileManager
    private let runner: CommandRunning
    private let encoder: JSONEncoder

    init(fileManager: FileManager = .default, runner: CommandRunning = ProcessCommandRunner()) {
        self.fileManager = fileManager
        self.runner = runner
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    }

    func makeDraft(codexHome: URL, userConfig: JSONValue?, options: BackupOptions = BackupOptions()) throws -> BackupDraft {
        let home = codexHome.standardizedFileURL
        guard safeDirectory(home) else { throw BackupError.invalidCodexHome }

        var redactor = BackupRedactor()
        var files: [BackupFile] = []
        var excluded = protectedNames().sorted().map { "\($0) 默认排除" }

        if let userConfig {
            let redacted = redactor.redact(userConfig)
            let data = try encoder.encode(redacted)
            files.append(BackupFile(relativePath: "config.user.redacted.json", content: String(decoding: data, as: UTF8.self)))
        } else {
            excluded.append("config.user.redacted.json 未生成：Codex 未返回用户配置层")
        }

        if options.includeProjectInstructions {
            appendTextFile(home.appending(path: "AGENTS.md"), root: home, into: &files, excluded: &excluded)
        }
        if options.includeAgents {
            appendTextDirectory(home.appending(path: "agents"), root: home, into: &files, excluded: &excluded)
        }
        if options.includeRules {
            appendTextDirectory(home.appending(path: "rules"), root: home, into: &files, excluded: &excluded)
        }
        if options.includeCuratedMemory {
            appendTextFile(home.appending(path: "memories/MEMORY.md"), root: home, into: &files, excluded: &excluded, maxBytes: 256_000)
        } else {
            excluded.append("memories 默认排除；可选仅加入整理后的 MEMORY.md")
        }

        let manifest: JSONValue = .object([
            "createdBy": .string("Workbench"),
            "createdAt": .string(ISO8601DateFormatter().string(from: Date())),
            "codexHome": .string(home.path),
            "notes": .array([
                .string("Secrets are redacted and runtime data is excluded."),
                .string("This backup is a configuration snapshot, not a full restore image.")
            ])
        ])
        let manifestData = try encoder.encode(manifest)
        files.insert(BackupFile(relativePath: "manifest.json", content: String(decoding: manifestData, as: UTF8.self)), at: 0)

        let payload = try payloadJSON(files: files)
        return BackupDraft(
            id: UUID(),
            createdAt: Date(),
            codexHomePath: home.path,
            includedFiles: files.sorted { $0.relativePath < $1.relativePath },
            excludedItems: excluded,
            redactionCount: redactor.redactionCount,
            payload: payload
        )
    }

    func githubConnectionStatus() async throws -> GitHubBackupConnectionState {
        let gh = try await findGitHubCLI()
        let result = try await runner.run(
            executable: gh,
            arguments: ["auth", "status", "--active", "--hostname", "github.com", "--json", "hosts"],
            input: nil,
            timeoutSeconds: 10
        )
        guard result.exitCode == 0,
              let response = try? JSONDecoder().decode(GitHubAuthStatusResponse.self, from: result.stdout),
              let host = response.hosts["github.com"]?.first(where: { $0.active && $0.state == "success" }),
              !host.login.isEmpty
        else {
            return .signedOut
        }
        return .signedIn(account(from: host))
    }

    func loginToGitHub() async throws -> GitHubBackupAccount {
        let gh = try await findGitHubCLI()
        let result = try await runner.run(
            executable: gh,
            arguments: [
                "auth", "login",
                "--hostname", "github.com",
                "--git-protocol", "https",
                "--web",
                "--clipboard",
                "--scopes", "repo"
            ],
            input: nil,
            timeoutSeconds: 300
        )
        guard result.exitCode == 0 else {
            throw BackupError.githubCommandFailed(safeOutput(result.stderr))
        }
        guard case .signedIn(let account) = try await githubConnectionStatus() else {
            throw BackupError.githubNotLoggedIn
        }
        return account
    }

    func listPrivateRepositories(account: GitHubBackupAccount) async throws -> [GitHubBackupRepository] {
        let gh = try await findGitHubCLI()
        let result = try await runner.run(
            executable: gh,
            arguments: [
                "repo", "list", account.login,
                "--limit", "100",
                "--visibility", "private",
                "--no-archived",
                "--json", "nameWithOwner,defaultBranchRef,url,isPrivate"
            ],
            input: nil,
            timeoutSeconds: 20
        )
        guard result.exitCode == 0 else {
            throw BackupError.githubCommandFailed(safeOutput(result.stderr))
        }
        let response = try JSONDecoder().decode([GitHubRepositoryResponse].self, from: result.stdout)
        return response.compactMap { repository in
            guard repository.isPrivate,
                  let branch = repository.defaultBranchRef?.name,
                  !branch.isEmpty
            else { return nil }
            return GitHubBackupRepository(
                nameWithOwner: repository.nameWithOwner,
                defaultBranch: branch,
                url: repository.url
            )
        }
        .sorted {
            let lhsPreferred = $0.nameWithOwner.lowercased().hasSuffix("/skill-lens-backup")
            let rhsPreferred = $1.nameWithOwner.lowercased().hasSuffix("/skill-lens-backup")
            if lhsPreferred != rhsPreferred { return lhsPreferred }
            return $0.nameWithOwner.localizedCaseInsensitiveCompare($1.nameWithOwner) == .orderedAscending
        }
    }

    func createPrivateRepository(name: String, account: GitHubBackupAccount) async throws -> GitHubBackupRepository {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil,
              trimmed != ".",
              trimmed != ".."
        else {
            throw BackupError.invalidRepositoryName
        }
        let repository = "\(account.login)/\(trimmed)"
        let gh = try await findGitHubCLI()
        let create = try await runner.run(
            executable: gh,
            arguments: [
                "repo", "create", repository,
                "--private",
                "--add-readme",
                "--description", "Workbench Codex configuration backups",
                "--disable-issues",
                "--disable-wiki"
            ],
            input: nil,
            timeoutSeconds: 30
        )
        guard create.exitCode == 0 else {
            throw BackupError.githubCommandFailed(safeOutput(create.stderr))
        }

        let view = try await runner.run(
            executable: gh,
            arguments: ["repo", "view", repository, "--json", "nameWithOwner,defaultBranchRef,url,isPrivate"],
            input: nil,
            timeoutSeconds: 15
        )
        guard view.exitCode == 0 else {
            throw BackupError.githubCommandFailed(safeOutput(view.stderr))
        }
        let response = try JSONDecoder().decode(GitHubRepositoryResponse.self, from: view.stdout)
        guard response.isPrivate else { throw BackupError.publicRepositoryRejected }
        guard let branch = response.defaultBranchRef?.name, !branch.isEmpty else {
            throw BackupError.repositoryHasNoDefaultBranch
        }
        return GitHubBackupRepository(
            nameWithOwner: response.nameWithOwner,
            defaultBranch: branch,
            url: response.url
        )
    }

    func listBackupHistory(repository: GitHubBackupRepository) async throws -> [GitHubBackupHistoryRecord] {
        try validate(GitHubBackupTarget(repository: repository.nameWithOwner, branch: repository.defaultBranch))
        let gh = try await findGitHubCLI()
        let result = try await runner.run(
            executable: gh,
            arguments: [
                "api", "--method", "GET", "repos/\(repository.nameWithOwner)/commits",
                "-f", "path=skill-lens/backups",
                "-f", "sha=\(repository.defaultBranch)",
                "-f", "per_page=50"
            ],
            input: nil,
            timeoutSeconds: 20
        )
        guard result.exitCode == 0 else {
            throw BackupError.githubCommandFailed(safeOutput(result.stderr))
        }
        let response = try JSONDecoder().decode([GitHubCommitResponse].self, from: result.stdout)
        return response.compactMap { commit in
            guard let createdAt = ISO8601DateFormatter().date(from: commit.commit.author.date) else { return nil }
            return GitHubBackupHistoryRecord(
                commitSHA: commit.sha,
                createdAt: createdAt,
                message: commit.commit.message,
                htmlURL: commit.htmlURL
            )
        }
    }

    func upload(draft: BackupDraft, target: GitHubBackupTarget) async throws -> GitHubBackupResult {
        try validate(target)
        let gh = try await findGitHubCLI()
        try await verifyPrivateRepo(gh: gh, repository: target.repository)

        let timestamp = ISO8601DateFormatter().string(from: draft.createdAt)
            .replacingOccurrences(of: ":", with: "-")
        let remotePath = "skill-lens/backups/\(timestamp)-\(draft.id.uuidString.lowercased())/backup.json"
        let data = try encoder.encode(draft.payload)
        let content = data.base64EncodedString()
        let body: JSONValue = .object([
            "message": .string("Workbench Codex configuration backup"),
            "branch": .string(target.branch),
            "content": .string(content)
        ])
        let input = try encoder.encode(body)
        let result = try await runner.run(
            executable: gh,
            arguments: ["api", "--method", "PUT", "repos/\(target.repository)/contents/\(remotePath)", "--input", "-"],
            input: input,
            timeoutSeconds: 30
        )
        guard result.exitCode == 0 else { throw BackupError.githubCommandFailed(safeOutput(result.stderr)) }
        let response = try JSONDecoder().decode(GitHubContentsResponse.self, from: result.stdout)
        return GitHubBackupResult(
            path: remotePath,
            commitSHA: response.commit?.sha,
            htmlURL: response.content?.htmlURL
        )
    }

    private func appendTextDirectory(_ url: URL, root: URL, into files: inout [BackupFile], excluded: inout [String]) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        guard safeDirectory(url), contains(url, inside: root) else {
            excluded.append("\(relativePath(url, root: root)) 已跳过：不是安全目录")
            return
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return }
        for case let child as URL in enumerator {
            appendTextFile(child, root: root, into: &files, excluded: &excluded)
        }
    }

    private func appendTextFile(
        _ url: URL,
        root: URL,
        into files: inout [BackupFile],
        excluded: inout [String],
        maxBytes: Int = 128_000
    ) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let relative = relativePath(url, root: root)
        guard contains(url, inside: root), !isProtected(relative) else {
            excluded.append("\(relative) 已跳过：不在备份白名单")
            return
        }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true
        else {
            excluded.append("\(relative) 已跳过：不是普通文件")
            return
        }
        guard (values.fileSize ?? 0) <= maxBytes else {
            excluded.append("\(relative) 已跳过：超过大小限制")
            return
        }
        guard allowedTextExtension(url) else {
            excluded.append("\(relative) 已跳过：不是配置文本")
            return
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            excluded.append("\(relative) 已跳过：无法按 UTF-8 读取")
            return
        }
        guard !BackupRedactor.looksLikeSecret(content) else {
            excluded.append("\(relative) 已跳过：疑似包含凭据")
            return
        }
        files.append(BackupFile(relativePath: relative, content: content))
    }

    private func payloadJSON(files: [BackupFile]) throws -> JSONValue {
        .object([
            "files": .array(files.map { .object(["path": .string($0.relativePath), "content": .string($0.content)]) })
        ])
    }

    private func findGitHubCLI() async throws -> String {
        for path in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"] where fileManager.isExecutableFile(atPath: path) {
            return path
        }
        let result = try await runner.run(executable: "/usr/bin/env", arguments: ["which", "gh"], input: nil, timeoutSeconds: 5)
        guard result.exitCode == 0, let path = String(data: result.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            throw BackupError.githubCLIMissing
        }
        return path
    }

    private func account(from status: GitHubAuthStatusResponse.Account) -> GitHubBackupAccount {
        let storage = status.tokenSource == "keyring" ? "macOS 钥匙串" : "GitHub CLI 凭据存储"
        return GitHubBackupAccount(login: status.login, credentialStorageDescription: storage)
    }

    private func verifyPrivateRepo(gh: String, repository: String) async throws {
        let result = try await runner.run(executable: gh, arguments: ["api", "repos/\(repository)"], input: nil, timeoutSeconds: 15)
        guard result.exitCode == 0 else { throw BackupError.githubCommandFailed(safeOutput(result.stderr)) }
        let response = try JSONDecoder().decode(GitHubRepoResponse.self, from: result.stdout)
        guard response.private == true else { throw BackupError.publicRepositoryRejected }
    }

    private func validate(_ target: GitHubBackupTarget) throws {
        guard target.repository.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil else {
            throw BackupError.invalidRepository
        }
        guard target.branch.range(of: #"^[A-Za-z0-9._/-]+$"#, options: .regularExpression) != nil,
              !target.branch.contains(".."),
              !target.branch.hasPrefix("/"),
              !target.branch.hasSuffix("/")
        else {
            throw BackupError.invalidBranch
        }
    }

    private func safeDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private func allowedTextExtension(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name == "AGENTS.md" { return true }
        switch url.pathExtension.lowercased() {
        case "md", "markdown", "toml", "json", "yaml", "yml": return true
        default: return false
        }
    }

    private func isProtected(_ relativePath: String) -> Bool {
        let first = relativePath.split(separator: "/").first.map(String.init) ?? relativePath
        return protectedNames().contains(first) || relativePath == "auth.json" || relativePath.hasSuffix(".sqlite") || relativePath.hasSuffix(".db")
    }

    private func protectedNames() -> Set<String> {
        ["sessions", "archived_sessions", "logs", "log", "cache", ".tmp", "tmp", "plugins", "skills", "packages", "auth.json", "history.jsonl", "attachments"]
    }

    private func relativePath(_ url: URL, root: URL) -> String {
        let path = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func contains(_ child: URL, inside root: URL) -> Bool {
        let childPath = child.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return childPath == rootPath || childPath.hasPrefix(rootPath + "/")
    }

    private func safeOutput(_ data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? "GitHub CLI returned an error."
        return DiagnosticRedactor.commandSummary(text)
    }
}

struct CommandResult: Sendable {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
}

protocol CommandRunning: Sendable {
    func run(executable: String, arguments: [String], input: Data?, timeoutSeconds: TimeInterval) async throws -> CommandResult
}

struct ProcessCommandRunner: CommandRunning {
    func run(executable: String, arguments: [String], input: Data?, timeoutSeconds: TimeInterval) async throws -> CommandResult {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let stdout = Pipe()
            let stderr = Pipe()
            let stdin = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            if input != nil { process.standardInput = stdin }

            try process.run()
            if let input {
                stdin.fileHandleForWriting.write(input)
                try? stdin.fileHandleForWriting.close()
            }
            let deadline = Date().addingTimeInterval(timeoutSeconds)
            while process.isRunning, Date() < deadline {
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    if process.isRunning {
                        process.terminate()
                        process.waitUntilExit()
                    }
                    throw error
                }
            }
            guard !process.isRunning else {
                process.terminate()
                process.waitUntilExit()
                throw BackupError.githubCommandTimedOut
            }
            return CommandResult(
                exitCode: process.terminationStatus,
                stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
                stderr: stderr.fileHandleForReading.readDataToEndOfFile()
            )
        }.value
    }
}

struct BackupRedactor {
    private(set) var redactionCount = 0

    mutating func redact(_ value: JSONValue, keyPath: [String] = []) -> JSONValue {
        switch value {
        case .object(let object):
            return .object(object.mapValuesWithKeys { key, child in
                if Self.sensitiveKey(key) {
                    redactionCount += 1
                    return .string("[REDACTED]")
                }
                return redact(child, keyPath: keyPath + [key])
            })
        case .array(let values):
            return .array(values.map { redact($0, keyPath: keyPath) })
        case .string(let text):
            if Self.looksLikeSecret(text) {
                redactionCount += 1
                return .string("[REDACTED]")
            }
            return .string(text)
        default:
            return value
        }
    }

    static func sensitiveKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        return ["token", "secret", "password", "apikey", "api_key", "authorization", "cookie", "private_key", "client_secret"].contains { lower.contains($0) }
    }

    static func looksLikeSecret(_ text: String) -> Bool {
        let patterns = [
            #"sk-[A-Za-z0-9_-]{16,}"#,
            #"ghp_[A-Za-z0-9_]{20,}"#,
            #"github_pat_[A-Za-z0-9_]{20,}"#,
            #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
            #"(?i)bearer\s+[A-Za-z0-9._-]{20,}"#,
            #"(?i)[?&](?:access_token|refresh_token|token|api_key|client_secret|signature)=[^&#\s]+"#
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func mapValuesWithKeys(_ transform: (String, JSONValue) -> JSONValue) -> [String: JSONValue] {
        var output: [String: JSONValue] = [:]
        for (key, value) in self { output[key] = transform(key, value) }
        return output
    }
}

private struct GitHubRepoResponse: Decodable {
    let `private`: Bool
}

private struct GitHubAuthStatusResponse: Decodable {
    let hosts: [String: [Account]]

    struct Account: Decodable {
        let active: Bool
        let login: String
        let state: String
        let tokenSource: String?
    }
}

private struct GitHubRepositoryResponse: Decodable {
    let nameWithOwner: String
    let defaultBranchRef: Branch?
    let url: String
    let isPrivate: Bool

    struct Branch: Decodable {
        let name: String
    }
}

private struct GitHubCommitResponse: Decodable {
    let sha: String
    let htmlURL: String
    let commit: Commit

    private enum CodingKeys: String, CodingKey {
        case sha
        case htmlURL = "html_url"
        case commit
    }

    struct Commit: Decodable {
        let message: String
        let author: Author
    }

    struct Author: Decodable {
        let date: String
    }
}

private struct GitHubContentsResponse: Decodable {
    let content: Content?
    let commit: Commit?

    struct Content: Decodable {
        let htmlURL: String?
        private enum CodingKeys: String, CodingKey { case htmlURL = "html_url" }
    }

    struct Commit: Decodable {
        let sha: String?
    }
}

enum BackupError: LocalizedError, Sendable, Equatable {
    case invalidCodexHome
    case invalidRepository
    case invalidRepositoryName
    case invalidBranch
    case githubCLIMissing
    case githubNotLoggedIn
    case repositoryHasNoDefaultBranch
    case publicRepositoryRejected
    case githubCommandTimedOut
    case githubCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidCodexHome: "Codex Home 路径无效，备份已取消。"
        case .invalidRepository: "GitHub 仓库格式应为 owner/name。"
        case .invalidRepositoryName: "仓库名只能包含字母、数字、点、横线和下划线。"
        case .invalidBranch: "分支名包含不支持的字符。"
        case .githubCLIMissing: "没有找到 GitHub CLI。请先安装 gh 并完成登录。"
        case .githubNotLoggedIn: "GitHub 登录没有完成，请重新尝试。"
        case .repositoryHasNoDefaultBranch: "这个仓库还没有默认分支，暂时不能接收备份。"
        case .publicRepositoryRejected: "目标仓库不是私有仓库。为避免暴露个人配置，Workbench 拒绝上传。"
        case .githubCommandTimedOut: "GitHub CLI 响应超时。"
        case .githubCommandFailed(let message): "GitHub CLI 返回错误：\(message)"
        }
    }
}
