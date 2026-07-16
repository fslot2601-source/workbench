import Foundation
import XCTest
@testable import SkillLens

final class CodexExecutableLocatorTests: XCTestCase {
    func testResolveSelectionAcceptsExecutableFile() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let resolved = try CodexExecutableLocator().resolveSelection(fixture.executable)

        XCTAssertEqual(resolved, fixture.executable.standardizedFileURL)
    }

    func testResolveSelectionFollowsExecutableSymlink() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let link = fixture.root.appending(path: "codex-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.executable)

        let resolved = try CodexExecutableLocator().resolveSelection(link)

        XCTAssertEqual(resolved, fixture.executable.standardizedFileURL)
    }

    func testResolveSelectionFindsCodexInsideChatGPTApplication() throws {
        let fixture = try makeApplicationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let resolved = try CodexExecutableLocator().resolveSelection(fixture.application)

        XCTAssertEqual(resolved, fixture.executable.standardizedFileURL)
    }

    func testLocateExpandsPreferredApplicationPath() throws {
        let fixture = try makeApplicationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let resolved = CodexExecutableLocator().locate(preferredPath: fixture.application.path)

        XCTAssertEqual(resolved, fixture.executable.standardizedFileURL)
    }

    func testResolveSelectionExplainsApplicationWithoutCodex() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "workbench-empty-app-\(UUID().uuidString)", directoryHint: .isDirectory)
        let application = root.appending(path: "ChatGPT.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(try CodexExecutableLocator().resolveSelection(application)) { error in
            guard case CodexExecutableLocatorError.applicationHasNoBundledCodex(let path) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, application.path)
        }
    }

    func testResolveSelectionExplainsNonExecutableFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "workbench-non-executable-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appending(path: "codex")
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(try CodexExecutableLocator().resolveSelection(file)) { error in
            guard case CodexExecutableLocatorError.notExecutable(let path) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, file.path)
        }
    }

    private func makeFixture() throws -> (root: URL, executable: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "workbench-codex-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appending(path: "codex")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (root, executable)
    }

    private func makeApplicationFixture() throws -> (root: URL, application: URL, executable: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "workbench-chatgpt-\(UUID().uuidString)", directoryHint: .isDirectory)
        let application = root.appending(path: "ChatGPT.app", directoryHint: .isDirectory)
        let resources = application.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let executable = resources.appending(path: "codex")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (root, application, executable)
    }
}
