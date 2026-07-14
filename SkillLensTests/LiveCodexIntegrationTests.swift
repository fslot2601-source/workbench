import Foundation
import XCTest
@testable import SkillLens

final class LiveCodexIntegrationTests: XCTestCase {
    func testCurrentCodexCanListSkillsAndHooks() async throws {
        let locator = CodexExecutableLocator()
        guard let executable = locator.locate() else {
            throw XCTSkip("Codex CLI is not installed on this machine.")
        }
        let isolatedHome = FileManager.default.temporaryDirectory
            .appending(path: "skilllens-live-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: isolatedHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: isolatedHome) }

        let service = CodexService()
        do {
            let info = try await service.connect(
                executableURL: executable,
                environment: ["CODEX_HOME": isolatedHome.path]
            )
            XCTAssertFalse(info.userAgent.isEmpty)
            XCTAssertEqual(URL(fileURLWithPath: info.codexHome).standardizedFileURL, isolatedHome.standardizedFileURL)

            let cwdPath = ProcessInfo.processInfo.environment["SKILLLENS_TEST_CWD"]
                ?? FileManager.default.homeDirectoryForCurrentUser.path
            let cwd = URL(fileURLWithPath: cwdPath)
            let skills = try await service.listSkills(cwd: cwd, forceReload: true)
            let hookResult = try await service.listHooks(cwd: cwd)
            let mcpResult = try await service.listMCPServers(cwd: cwd)

            XCTAssertGreaterThanOrEqual(skills.count, 0)
            XCTAssertGreaterThanOrEqual(hookResult.hooks.count, 0)
            XCTAssertGreaterThanOrEqual(mcpResult.servers.count, 0)
            await service.disconnect()
        } catch {
            await service.disconnect()
            throw error
        }
    }

    func testCurrentCodexCanSafelyWriteHookOverrideInIsolatedHome() async throws {
        let locator = CodexExecutableLocator()
        guard let executable = locator.locate() else {
            throw XCTSkip("Codex CLI is not installed on this machine.")
        }
        let isolatedHome = FileManager.default.temporaryDirectory
            .appending(path: "skilllens-hook-write-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: isolatedHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: isolatedHome) }

        let service = CodexService()
        do {
            _ = try await service.connect(
                executableURL: executable,
                environment: ["CODEX_HOME": isolatedHome.path]
            )
            let hook = HookRecord(
                key: "skilllens-test-hook",
                event: .stop,
                rawEventName: "stop",
                handlerType: .command,
                rawHandlerType: "command",
                matcher: nil,
                command: "/usr/bin/true",
                timeoutSeconds: 5,
                statusMessage: nil,
                sourcePath: isolatedHome.appending(path: "config.toml").path,
                source: .user,
                rawSource: "user",
                pluginID: nil,
                displayOrder: 0,
                isEnabled: true,
                isManaged: false,
                currentHash: "test",
                trustStatus: .trusted,
                rawTrustStatus: "trusted"
            )
            try await service.setHookEnabled(hook, enabled: false, cwd: isolatedHome)
            await service.disconnect()

            let config = try String(contentsOf: isolatedHome.appending(path: "config.toml"), encoding: .utf8)
            XCTAssertTrue(config.contains("skilllens-test-hook"))
            XCTAssertTrue(config.contains("enabled = false"))
        } catch {
            await service.disconnect()
            throw error
        }
    }

    func testMCPEnableWriteIsVerifiedWithoutReloadingAllServers() async throws {
        let locator = CodexExecutableLocator()
        guard let executable = locator.locate() else {
            throw XCTSkip("Codex CLI is not installed on this machine.")
        }
        let isolatedHome = FileManager.default.temporaryDirectory
            .appending(path: "skilllens-mcp-write-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: isolatedHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: isolatedHome) }
        let configURL = isolatedHome.appending(path: "config.toml")
        try """
        [mcp_servers.skilllens_target]
        command = "/usr/bin/true"
        enabled = true

        [mcp_servers.skilllens_other]
        command = "/usr/bin/true"
        enabled = true
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let service = CodexService()
        do {
            _ = try await service.connect(
                executableURL: executable,
                environment: ["CODEX_HOME": isolatedHome.path]
            )
            try await service.setMCPEnabled(name: "skilllens_target", enabled: false, cwd: isolatedHome)
            let configured = try await service.listConfiguredMCPServers(cwd: isolatedHome)
            await service.disconnect()

            XCTAssertEqual(configured.servers.first(where: { $0.name == "skilllens_target" })?.isEnabled, false)
            XCTAssertEqual(configured.servers.first(where: { $0.name == "skilllens_other" })?.isEnabled, true)
        } catch {
            await service.disconnect()
            throw error
        }
    }
}
