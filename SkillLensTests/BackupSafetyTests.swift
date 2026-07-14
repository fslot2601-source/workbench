import Foundation
import XCTest
@testable import SkillLens

final class BackupSafetyTests: XCTestCase {
    func testDraftRedactsConfigAndOnlyIncludesAllowlistedFiles() async throws {
        let home = try makeCodexHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try "safe instructions".write(to: home.appending(path: "AGENTS.md"), atomically: true, encoding: .utf8)
        try "token = ghp_should_not_leak_12345678901234567890\nmode = safe".write(to: home.appending(path: "agents/sample.toml"), atomically: true, encoding: .utf8)
        try "private = true".write(to: home.appending(path: "rules/default.toml"), atomically: true, encoding: .utf8)
        try "do not include".write(to: home.appending(path: "sessions/session.jsonl"), atomically: true, encoding: .utf8)

        let config: JSONValue = .object([
            "model": .string("gpt-5"),
            "api_key": .string("secret-value"),
            "mcp_servers": .object([
                "demo": .object(["url": .string("https://example.test?access_token=query-secret")])
            ])
        ])
        let draft = try await CodexBackupService().makeDraft(codexHome: home, userConfig: config)
        let payload = try jsonString(draft.payload)

        XCTAssertTrue(payload.contains("gpt-5"))
        XCTAssertFalse(payload.contains("secret-value"))
        XCTAssertFalse(payload.contains("query-secret"))
        XCTAssertTrue(payload.contains("[REDACTED]"))
        XCTAssertFalse(payload.contains("ghp_should_not_leak"))
        XCTAssertFalse(payload.contains("session.jsonl"))
        XCTAssertTrue(draft.includedFiles.contains { $0.relativePath == "AGENTS.md" })
        XCTAssertTrue(draft.includedFiles.contains { $0.relativePath == "rules/default.toml" })
        XCTAssertFalse(draft.includedFiles.contains { $0.relativePath == "agents/sample.toml" })
        XCTAssertFalse(draft.includedFiles.contains { $0.relativePath.hasPrefix("sessions/") })
        XCTAssertGreaterThan(draft.redactionCount, 0)
    }

    func testDraftDoesNotFollowSymlink() async throws {
        let home = try makeCodexHome()
        let outside = FileManager.default.temporaryDirectory.appending(path: "skilllens-backup-outside-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: home)
            try? FileManager.default.removeItem(at: outside)
        }
        try "outside-secret".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: home.appending(path: "agents/outside.toml"),
            withDestinationURL: outside
        )

        let draft = try await CodexBackupService().makeDraft(codexHome: home, userConfig: nil)
        XCTAssertFalse(draft.includedFiles.contains { $0.relativePath.contains("outside") })
        XCTAssertFalse(try jsonString(draft.payload).contains("outside-secret"))
    }

    func testUploadRequiresPrivateRepositoryAndUsesFixedArguments() async throws {
        let home = try makeCodexHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try "safe".write(to: home.appending(path: "AGENTS.md"), atomically: true, encoding: .utf8)

        let calls = CallRecorder()
        let runner = ClosureCommandRunner { executable, arguments, input in
            await calls.append(executable: executable, arguments: arguments, input: input)
            if executable == "/usr/bin/env" {
                return CommandResult(exitCode: 0, stdout: Data("/bin/gh\n".utf8), stderr: Data())
            }
            if arguments == ["api", "repos/me/private"] {
                return CommandResult(exitCode: 0, stdout: Data(#"{"private":true}"#.utf8), stderr: Data())
            }
            return CommandResult(
                exitCode: 0,
                stdout: Data(#"{"content":{"html_url":"https://github.com/me/private/blob/main/backup.json"},"commit":{"sha":"abc123"}}"#.utf8),
                stderr: Data()
            )
        }
        let service = CodexBackupService(runner: runner)
        let draft = try await service.makeDraft(codexHome: home, userConfig: nil)
        let result = try await service.upload(draft: draft, target: GitHubBackupTarget(repository: "me/private", branch: "main"))

        XCTAssertEqual(result.commitSHA, "abc123")
        let recorded = await calls.values
        XCTAssertTrue(recorded.contains { $0.arguments == ["api", "repos/me/private"] })
        let uploadCall = try XCTUnwrap(recorded.first { $0.arguments.contains("--method") })
        XCTAssertEqual(uploadCall.arguments.prefix(3), ["api", "--method", "PUT"])
        XCTAssertTrue(uploadCall.arguments[3].hasPrefix("repos/me/private/contents/skill-lens/backups/"))
        XCTAssertEqual(uploadCall.arguments.suffix(2), ["--input", "-"])
        let lastInput = await calls.lastInput()
        XCTAssertNotNil(lastInput)
    }

    func testUploadRejectsPublicRepository() async throws {
        let runner = ClosureCommandRunner { executable, arguments, _ in
            if executable == "/usr/bin/env" {
                return CommandResult(exitCode: 0, stdout: Data("/bin/gh\n".utf8), stderr: Data())
            }
            if arguments == ["api", "repos/me/public"] {
                return CommandResult(exitCode: 0, stdout: Data(#"{"private":false}"#.utf8), stderr: Data())
            }
            return CommandResult(exitCode: 0, stdout: Data(), stderr: Data())
        }
        let service = CodexBackupService(runner: runner)
        let draft = BackupDraft(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 0),
            codexHomePath: "/tmp/codex",
            includedFiles: [],
            excludedItems: [],
            redactionCount: 0,
            payload: .object(["files": .array([])])
        )

        do {
            _ = try await service.upload(draft: draft, target: GitHubBackupTarget(repository: "me/public", branch: "main"))
            XCTFail("Expected publicRepositoryRejected")
        } catch BackupError.publicRepositoryRejected {
            XCTAssertTrue(true)
        }
    }

    func testGitHubStatusReadsAccountWithoutRequestingToken() async throws {
        let calls = CallRecorder()
        let runner = ClosureCommandRunner { executable, arguments, input in
            await calls.append(executable: executable, arguments: arguments, input: input)
            if arguments == ["which", "gh"] {
                return CommandResult(exitCode: 0, stdout: Data("/bin/gh\n".utf8), stderr: Data())
            }
            let response = #"{"hosts":{"github.com":[{"active":true,"gitProtocol":"https","login":"alice","state":"success","tokenSource":"keyring"}]}}"#
            return CommandResult(exitCode: 0, stdout: Data(response.utf8), stderr: Data())
        }
        let service = CodexBackupService(runner: runner)

        let status = try await service.githubConnectionStatus()

        XCTAssertEqual(
            status,
            .signedIn(GitHubBackupAccount(login: "alice", credentialStorageDescription: "macOS 钥匙串"))
        )
        let recorded = await calls.values
        XCTAssertTrue(recorded.contains { $0.arguments == ["auth", "status", "--active", "--hostname", "github.com", "--json", "hosts"] })
        XCTAssertFalse(recorded.contains { $0.arguments.contains("--show-token") })
    }

    func testPrivateRepositoryListExcludesPublicAndEmptyRepositories() async throws {
        let runner = ClosureCommandRunner { _, arguments, _ in
            if arguments == ["which", "gh"] {
                return CommandResult(exitCode: 0, stdout: Data("/bin/gh\n".utf8), stderr: Data())
            }
            let response = #"[{"nameWithOwner":"alice/other","defaultBranchRef":{"name":"main"},"url":"https://github.com/alice/other","isPrivate":true},{"nameWithOwner":"alice/skill-lens-backup","defaultBranchRef":{"name":"trunk"},"url":"https://github.com/alice/skill-lens-backup","isPrivate":true},{"nameWithOwner":"alice/empty","defaultBranchRef":null,"url":"https://github.com/alice/empty","isPrivate":true},{"nameWithOwner":"alice/public","defaultBranchRef":{"name":"main"},"url":"https://github.com/alice/public","isPrivate":false}]"#
            return CommandResult(exitCode: 0, stdout: Data(response.utf8), stderr: Data())
        }
        let service = CodexBackupService(runner: runner)
        let account = GitHubBackupAccount(login: "alice", credentialStorageDescription: "macOS 钥匙串")

        let repositories = try await service.listPrivateRepositories(account: account)

        XCTAssertEqual(repositories.map(\.nameWithOwner), ["alice/skill-lens-backup", "alice/other"])
        XCTAssertEqual(repositories.first?.defaultBranch, "trunk")
    }

    func testCreateRepositoryAlwaysUsesPrivateInitializedRepository() async throws {
        let calls = CallRecorder()
        let runner = ClosureCommandRunner { executable, arguments, input in
            await calls.append(executable: executable, arguments: arguments, input: input)
            if arguments == ["which", "gh"] {
                return CommandResult(exitCode: 0, stdout: Data("/bin/gh\n".utf8), stderr: Data())
            }
            if arguments.first == "repo", arguments.dropFirst().first == "create" {
                return CommandResult(exitCode: 0, stdout: Data(), stderr: Data())
            }
            let response = #"{"nameWithOwner":"alice/skill-lens-backup","defaultBranchRef":{"name":"main"},"url":"https://github.com/alice/skill-lens-backup","isPrivate":true}"#
            return CommandResult(exitCode: 0, stdout: Data(response.utf8), stderr: Data())
        }
        let service = CodexBackupService(runner: runner)
        let account = GitHubBackupAccount(login: "alice", credentialStorageDescription: "macOS 钥匙串")

        let repository = try await service.createPrivateRepository(name: "skill-lens-backup", account: account)

        XCTAssertEqual(repository.nameWithOwner, "alice/skill-lens-backup")
        let recorded = await calls.values
        let create = try XCTUnwrap(recorded.first { $0.arguments.prefix(2) == ["repo", "create"] })
        XCTAssertEqual(create.arguments.prefix(3), ["repo", "create", "alice/skill-lens-backup"])
        XCTAssertTrue(create.arguments.contains("--private"))
        XCTAssertTrue(create.arguments.contains("--add-readme"))
        XCTAssertFalse(create.arguments.contains("--public"))
    }

    func testCreateRepositoryRejectsUnsafeNameBeforeCallingGitHub() async throws {
        let calls = CallRecorder()
        let runner = ClosureCommandRunner { executable, arguments, input in
            await calls.append(executable: executable, arguments: arguments, input: input)
            return CommandResult(exitCode: 0, stdout: Data(), stderr: Data())
        }
        let service = CodexBackupService(runner: runner)
        let account = GitHubBackupAccount(login: "alice", credentialStorageDescription: "macOS 钥匙串")

        do {
            _ = try await service.createPrivateRepository(name: "../unsafe", account: account)
            XCTFail("Expected invalidRepositoryName")
        } catch BackupError.invalidRepositoryName {
            XCTAssertTrue(true)
        }
        let recorded = await calls.values
        XCTAssertTrue(recorded.isEmpty)
    }

    func testBackupHistoryComesFromRepositoryCommits() async throws {
        let calls = CallRecorder()
        let runner = ClosureCommandRunner { executable, arguments, input in
            await calls.append(executable: executable, arguments: arguments, input: input)
            if arguments == ["which", "gh"] {
                return CommandResult(exitCode: 0, stdout: Data("/bin/gh\n".utf8), stderr: Data())
            }
            let response = #"[{"sha":"eeab68db12345678","html_url":"https://github.com/alice/skill-lens-backup/commit/eeab68db","commit":{"message":"Workbench Codex configuration backup","author":{"date":"2026-07-14T07:07:43Z"}}}]"#
            return CommandResult(exitCode: 0, stdout: Data(response.utf8), stderr: Data())
        }
        let service = CodexBackupService(runner: runner)
        let repository = GitHubBackupRepository(
            nameWithOwner: "alice/skill-lens-backup",
            defaultBranch: "main",
            url: "https://github.com/alice/skill-lens-backup"
        )

        let records = try await service.listBackupHistory(repository: repository)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.commitSHA, "eeab68db12345678")
        XCTAssertEqual(records.first?.message, "Workbench Codex configuration backup")
        let recorded = await calls.values
        XCTAssertTrue(recorded.contains { call in
            call.arguments == [
                "api", "--method", "GET", "repos/alice/skill-lens-backup/commits",
                "-f", "path=skill-lens/backups",
                "-f", "sha=main",
                "-f", "per_page=50"
            ]
        })
    }

    private func makeCodexHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "skilllens-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appending(path: "agents"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appending(path: "rules"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appending(path: "sessions"), withIntermediateDirectories: true)
        return home
    }

    private func jsonString(_ value: JSONValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

private actor CallRecorder {
    struct Value: Sendable {
        let executable: String
        let arguments: [String]
    }

    private(set) var values: [Value] = []
    private(set) var inputs: [Data?] = []

    func append(executable: String, arguments: [String], input: Data?) {
        values.append(Value(executable: executable, arguments: arguments))
        inputs.append(input)
    }

    func lastInput() -> Data? {
        inputs.last ?? nil
    }
}

private struct ClosureCommandRunner: CommandRunning {
    let handler: @Sendable (String, [String], Data?) async throws -> CommandResult

    func run(executable: String, arguments: [String], input: Data?, timeoutSeconds: TimeInterval) async throws -> CommandResult {
        try await handler(executable, arguments, input)
    }
}
