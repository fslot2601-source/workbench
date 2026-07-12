import Foundation
import XCTest
@testable import SkillLens

final class AppServerTransportTests: XCTestCase {
    func testStopAndImmediateRestartIgnoresOldProcessCallbacks() async throws {
        let executable = try makeServer(delaySeconds: 0)
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let transport = AppServerTransport()

        try await transport.start(executableURL: executable)
        let first: TransportFixtureResponse = try await transport.request(method: "first")
        XCTAssertTrue(first.ok)
        await transport.stop()

        try await transport.start(executableURL: executable)
        let second: TransportFixtureResponse = try await transport.request(method: "second")
        XCTAssertTrue(second.ok)
        let runningAfterRestart = await transport.isRunning()
        XCTAssertTrue(runningAfterRestart)
        await transport.stop()
    }

    func testCancellingRequestDoesNotLeavePendingContinuation() async throws {
        let executable = try makeServer(delaySeconds: 10)
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let transport = AppServerTransport()
        try await transport.start(executableURL: executable)

        let request = Task {
            try await transport.request(method: "slow", as: TransportFixtureResponse.self)
        }
        try await Task.sleep(for: .milliseconds(50))
        request.cancel()

        do {
            _ = try await request.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            let stillRunning = await transport.isRunning()
            XCTAssertTrue(stillRunning)
        }
        await transport.stop()
    }

    private func makeServer(delaySeconds: Int) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "skilllens-transport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appending(path: "fake-codex")
        let script = #"""
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf "%s" "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
          if [ -n "$id" ]; then
            sleep \#(delaySeconds)
            printf '{"id":%s,"result":{"ok":true}}\n' "$id"
          fi
        done
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }
}

private struct TransportFixtureResponse: Codable, Sendable {
    let ok: Bool
}
