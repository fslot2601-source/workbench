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
}
