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

    func testUnexpectedExitEmitsScopedEventAndAllowsRestart() async throws {
        let crashingExecutable = try makeCrashingServer()
        let healthyExecutable = try makeServer(delaySeconds: 0)
        defer {
            try? FileManager.default.removeItem(at: crashingExecutable.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: healthyExecutable.deletingLastPathComponent())
        }
        let transport = AppServerTransport()
        let exitEvent = Task<AppServerEvent?, Never> {
            for await event in transport.events where event.method == "client/processExited" {
                return event
            }
            return nil
        }

        let firstConnectionID = try await transport.start(executableURL: crashingExecutable)
        do {
            let _: TransportFixtureResponse = try await transport.request(method: "crash")
            XCTFail("Expected the fake App Server to exit")
        } catch {
            XCTAssertTrue(error is AppServerTransportError)
        }

        let event = try await waitForEvent(exitEvent)
        XCTAssertEqual(event.connectionID, firstConnectionID)
        let runningAfterExit = await transport.isRunning()
        XCTAssertFalse(runningAfterExit)

        let secondConnectionID = try await transport.start(executableURL: healthyExecutable)
        XCTAssertNotEqual(secondConnectionID, firstConnectionID)
        let response: TransportFixtureResponse = try await transport.request(method: "recovered")
        XCTAssertTrue(response.ok)
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

    private func makeCrashingServer() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "skilllens-transport-crash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appending(path: "fake-codex")
        let script = #"""
        #!/bin/sh
        while IFS= read -r line; do
          case "$line" in
            *'"id":'*) exit 17 ;;
          esac
        done
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }

    private func waitForEvent(_ task: Task<AppServerEvent?, Never>) async throws -> AppServerEvent {
        try await withThrowingTaskGroup(of: AppServerEvent?.self) { group in
            group.addTask { await task.value }
            group.addTask {
                try await Task.sleep(for: .seconds(3))
                throw TransportTestError.timedOut
            }
            guard let value = try await group.next(), let event = value else {
                throw TransportTestError.timedOut
            }
            group.cancelAll()
            return event
        }
    }
}

private struct TransportFixtureResponse: Codable, Sendable {
    let ok: Bool
}

private enum TransportTestError: Error {
    case timedOut
}
