import Foundation
import XCTest
@testable import SkillLens

final class SafetyTests: XCTestCase {
    func testHookKeyValidationRejectsConfigPathInjection() {
        XCTAssertTrue(CodexService.isSafeHookKey("plugin-hook_01"))
        XCTAssertFalse(CodexService.isSafeHookKey("safe.enabled.other"))
        XCTAssertFalse(CodexService.isSafeHookKey("../../config"))
        XCTAssertFalse(CodexService.isSafeHookKey(""))
    }

    func testDiagnosticRedactorMasksSecrets() {
        let command = "API_TOKEN=secret-value tool --api-key another-secret --safe value"
        let redacted = DiagnosticRedactor.commandSummary(command)

        XCTAssertFalse(redacted.contains("secret-value"))
        XCTAssertFalse(redacted.contains("another-secret"))
        XCTAssertTrue(redacted.contains("--safe value"))
    }

    func testDiagnosticRedactorMasksBearerJSONAndQuerySecrets() {
        let raw = #"Bearer abc.def.ghi {"api_key":"json-secret"} https://example.test?a=1&access_token=query-secret"#
        let redacted = DiagnosticRedactor.commandSummary(raw)

        XCTAssertFalse(redacted.contains("abc.def.ghi"))
        XCTAssertFalse(redacted.contains("json-secret"))
        XCTAssertFalse(redacted.contains("query-secret"))
    }

    func testDiagnosticRedactorMasksQuotedEqualsHeadersAndURLUserInfo() {
        let raw = #"tool --token=plain --client-secret "quoted value" --header "Authorization: Bearer header-secret" CLIENT_PRIVATE_KEY='private value' https://user:password@example.test/path"#
        let redacted = DiagnosticRedactor.sanitize(raw)

        for secret in ["plain", "quoted value", "header-secret", "private value", "password"] {
            XCTAssertFalse(redacted.contains(secret), "Leaked \(secret)")
        }
    }

    func testDependencySummaryNeverReturnsURLQueryOrCommandArguments() {
        XCTAssertEqual(
            DiagnosticRedactor.dependencyValue(type: "url", value: "https://api.example.test/path?token=secret"),
            "https://api.example.test"
        )
        XCTAssertEqual(
            DiagnosticRedactor.dependencyValue(type: "command", value: "/usr/local/bin/tool --token secret"),
            "tool"
        )
    }

    func testMCPCommandSummaryKeepsOnlyExecutableName() {
        let summary = CodexService.endpointSummary(
            url: nil,
            command: #"/usr/local/bin/mcp-tool --token "secret value""#
        )
        XCTAssertEqual(summary, "mcp-tool")
        XCTAssertFalse(summary.contains("secret"))
    }

    func testMCPModificationRequiresOnlyUserLayerAndNotRequired() {
        let serverConfig: JSONValue = .object([
            "mcp_servers": .object(["sample": .object(["enabled": .bool(true)])])
        ])
        let user = ConfigLayerWire(
            name: .object(["type": .string("user")]),
            version: "1",
            config: serverConfig
        )
        let managed = ConfigLayerWire(
            name: .object(["type": .string("mdm")]),
            version: "2",
            config: serverConfig
        )
        let userOnly = ConfigReadResponse(config: serverConfig, origins: nil, layers: [user])
        XCTAssertTrue(CodexService.mcpModificationPermission(name: "sample", config: userOnly, required: false).allowed)
        XCTAssertFalse(CodexService.mcpModificationPermission(name: "sample", config: userOnly, required: true).allowed)

        let managedOverride = ConfigReadResponse(config: serverConfig, origins: nil, layers: [user, managed])
        XCTAssertFalse(CodexService.mcpModificationPermission(name: "sample", config: managedOverride, required: false).allowed)
    }

    func testMetadataResolverReadsExplicitOnlyPolicy() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let skillDirectory = root.appendingPathComponent("sample", isDirectory: true)
        let agentsDirectory = skillDirectory.appendingPathComponent("agents", isDirectory: true)
        try FileManager.default.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
        let skillURL = skillDirectory.appendingPathComponent("SKILL.md")
        let metadataURL = agentsDirectory.appendingPathComponent("openai.yaml")
        try "---\nname: sample\ndescription: test\n---\n".write(to: skillURL, atomically: true, encoding: .utf8)
        try "policy:\n  allow_implicit_invocation: false\n".write(to: metadataURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(
            SkillMetadataResolver.invocationPolicy(skillPath: skillURL.path),
            .explicitOnly
        )
    }

    func testMetadataResolverIgnoresOversizedMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let skillDirectory = root.appending(path: "sample")
        let agentsDirectory = skillDirectory.appending(path: "agents")
        try FileManager.default.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
        let skillURL = skillDirectory.appending(path: "SKILL.md")
        try Data().write(to: skillURL)
        try Data(repeating: 65, count: 300_000).write(to: agentsDirectory.appending(path: "openai.yaml"))
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(SkillMetadataResolver.invocationPolicy(skillPath: skillURL.path), .automaticAllowed)
    }
}
