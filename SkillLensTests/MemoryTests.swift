import Foundation
import XCTest
@testable import SkillLens

final class MemoryTests: XCTestCase {
    func testPreviewAcceptsUTF8CharacterTruncatedAtReadBoundary() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let memories = home.appending(path: "memories")
        try FileManager.default.createDirectory(at: memories, withIntermediateDirectories: true)
        try Data("abcd中文\n后续内容".utf8).write(to: memories.appending(path: "MEMORY.md"))

        let service = CodexMemoryService(maxPreviewBytes: 5)
        let snapshot = await service.scan(codexHome: home)

        XCTAssertEqual(snapshot.records.first?.status, .available)
        XCTAssertEqual(snapshot.records.first?.preview, "abcd")
    }

    func testPreviewStillRejectsInvalidUTF8InsideFile() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let memories = home.appending(path: "memories")
        try FileManager.default.createDirectory(at: memories, withIntermediateDirectories: true)
        try Data([0x61, 0xFF, 0x62]).write(to: memories.appending(path: "MEMORY.md"))

        let service = CodexMemoryService(maxPreviewBytes: 8)
        let snapshot = await service.scan(codexHome: home)

        XCTAssertEqual(snapshot.records.first?.status, .unreadable)
        XCTAssertNil(snapshot.records.first?.preview)
    }

    func testScanClassifiesMemorySourcesAndHidesRawMaterialByDefault() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let memory = home.appending(path: "memories")
        try write("# Core\nLong term context", to: memory.appending(path: "MEMORY.md"))
        try write("# Summary\nIndex", to: memory.appending(path: "memory_summary.md"))
        try write("# Raw\nGenerated", to: memory.appending(path: "raw_memories.md"))
        try write("# Rollout\nRecent", to: memory.appending(path: "rollout_summaries/run.md"))
        try write("# Note\nAd hoc", to: memory.appending(path: "extensions/ad_hoc/notes/note.md"))
        try write("# Chronicle\nTimeline", to: memory.appending(path: "extensions/chronicle/resources/today.md"))

        let snapshot = await CodexMemoryService().scan(codexHome: home)
        XCTAssertEqual(snapshot.count(in: .curated), 1)
        XCTAssertEqual(snapshot.count(in: .summary), 1)
        XCTAssertEqual(snapshot.count(in: .raw), 1)
        XCTAssertEqual(snapshot.count(in: .rollout), 1)
        XCTAssertEqual(snapshot.count(in: .adHoc), 1)
        XCTAssertEqual(snapshot.count(in: .chronicle), 1)
        XCTAssertEqual(snapshot.visibleRecords.count, 4)
        XCTAssertTrue(snapshot.records(in: .raw).allSatisfy(\.isCollapsedByDefault))
        XCTAssertNil(snapshot.records(in: .raw).first?.preview)
    }

    func testScanSkipsSymlinkedMemoryFilesAndDirectories() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let outside = FileManager.default.temporaryDirectory.appending(path: "skilllens-memory-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try write("secret outside", to: outside.appending(path: "outside.md"))
        let memory = home.appending(path: "memories")
        try FileManager.default.createSymbolicLink(
            at: memory.appending(path: "outside.md"),
            withDestinationURL: outside.appending(path: "outside.md")
        )
        try FileManager.default.createSymbolicLink(at: memory.appending(path: "outside-dir"), withDestinationURL: outside)
        try write("safe", to: memory.appending(path: "MEMORY.md"))

        let snapshot = await CodexMemoryService().scan(codexHome: home)
        XCTAssertEqual(snapshot.records.map(\.relativePath), ["MEMORY.md"])
        XCTAssertFalse(snapshot.warnings.isEmpty)
    }

    func testScanReturnsWarningWhenMemoryDirectoryIsMissing() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "skilllens-no-memory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let snapshot = await CodexMemoryService().scan(codexHome: home)
        XCTAssertTrue(snapshot.records.isEmpty)
        XCTAssertFalse(snapshot.warnings.isEmpty)
    }

    func testSummaryBecomesReadableActiveKnowledge() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let memory = home.appending(path: "memories")
        try write(
            """
            # Summary

            ## User Profile

            The user builds native macOS tools for Codex.

            ## User preferences

            - Prefer Chinese explanations.

            ## General Tips

            - Verify volatile state live.

            ## What's in Memory

            ### /Users/edmond/Documents/New project and ChatGPT Work / 设计 Codex Skills 可视化

            - SkillLens Memory redesign
              - Readable memory entries and source evidence.
            """,
            to: memory.appending(path: "memory_summary.md")
        )

        let snapshot = await CodexMemoryService().scan(codexHome: home)

        XCTAssertEqual(snapshot.activeItems.count, 4)
        XCTAssertTrue(snapshot.activeItems.allSatisfy { $0.origin == .activeSummary })
        XCTAssertEqual(Set(snapshot.activeItems.map(\.category)), [.profile, .preference, .experience, .project])
        XCTAssertTrue(snapshot.activeItems.allSatisfy { $0.sources.first?.relativePath == "memory_summary.md" })
        XCTAssertTrue(snapshot.activeItems.filter { $0.category != .project }.allSatisfy { $0.applicability.kind == .global })
        let projectItem = try XCTUnwrap(snapshot.activeItems.first { $0.category == .project })
        XCTAssertEqual(projectItem.applicability.kind, .project)
        XCTAssertEqual(projectItem.applicability.projects.map(\.name), ["New project", "设计 Codex Skills 可视化"])
        XCTAssertEqual(projectItem.applicability.projects.first?.path, "/Users/edmond/Documents/New project")
    }

    func testCuratedMemoryBecomesCategorizedDurableKnowledgeWithEvidence() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let memory = home.appending(path: "memories")
        try write("# Rollout\nVerified implementation", to: memory.appending(path: "rollout_summaries/run.md"))
        try write(
            """
            # Task Group: SkillLens Memory

            scope: Readable Codex memory and source traceability.
            applies_to: cwd=/Users/edmond/Documents/New project and ChatGPT Work / “设计 Codex Skills 可视化”; reuse_rule=recheck live state

            - rollout_summaries/run.md (verified source)

            ## User preferences

            - Keep Memory read-only in Workbench.

            ## Reusable knowledge

            - Live state overrides recalled context.

            ## Failures and how to do differently

            - Do not present raw files as active memories.
            """,
            to: memory.appending(path: "MEMORY.md")
        )

        let snapshot = await CodexMemoryService().scan(codexHome: home)

        XCTAssertEqual(snapshot.durableItems.count, 4)
        XCTAssertEqual(Set(snapshot.durableItems.map(\.category)), [.project, .preference, .experience, .caution])
        XCTAssertTrue(snapshot.durableItems.allSatisfy { !$0.isActive && $0.origin == .consolidated })
        XCTAssertTrue(snapshot.durableItems.allSatisfy { item in
            item.sources.contains { $0.relativePath == "MEMORY.md" }
                && item.sources.contains { $0.relativePath == "rollout_summaries/run.md" }
        })
        XCTAssertTrue(snapshot.durableItems.allSatisfy { $0.applicability.kind == .project })
        XCTAssertTrue(snapshot.durableItems.allSatisfy {
            $0.applicability.projects.map(\.name) == ["New project", "设计 Codex Skills 可视化"]
        })
    }

    func testActiveAndDurableDuplicateMergesIntoOneActiveItem() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let memory = home.appending(path: "memories")
        try write(
            """
            ## User preferences
            - Prefer direct Chinese explanations.
            """,
            to: memory.appending(path: "memory_summary.md")
        )
        try write(
            """
            # Task Group: Communication
            ## User preferences
            - Prefer direct Chinese explanations.
            """,
            to: memory.appending(path: "MEMORY.md")
        )

        let snapshot = await CodexMemoryService().scan(codexHome: home)

        let matches = snapshot.items.filter { $0.content == "Prefer direct Chinese explanations." }
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.isActive, true)
        XCTAssertEqual(Set(matches.first?.sources.map(\.relativePath) ?? []), ["memory_summary.md", "MEMORY.md"])
        XCTAssertEqual(matches.first?.applicability.kind, .global)
        XCTAssertEqual(matches.first?.applicability.projects.map(\.name), ["Communication"])
    }

    func testOnlyUserNotesBecomeManualKnowledgeAndSensitiveOrRawMaterialStaysOut() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let memory = home.appending(path: "memories")
        try write("- This instruction file is implementation metadata.", to: memory.appending(path: "extensions/ad_hoc/instructions.md"))
        try write(
            """
            # User note
            - Remember the stable product boundary.
            - api_key: should-never-appear
            """,
            to: memory.appending(path: "extensions/ad_hoc/notes/note.md")
        )
        try write("- Raw speculation should not appear.", to: memory.appending(path: "raw_memories.md"))

        let snapshot = await CodexMemoryService().scan(codexHome: home)

        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.items.first?.category, .manual)
        XCTAssertEqual(snapshot.items.first?.content, "Remember the stable product boundary.")
        XCTAssertEqual(snapshot.items.first?.applicability.kind, .unspecified)
        XCTAssertEqual(snapshot.items.first?.applicability.kind.title, "待确认范围")
        XCTAssertFalse(snapshot.items.contains { $0.content.contains("should-never-appear") })
        XCTAssertFalse(snapshot.items.contains { $0.content.contains("Raw speculation") })
        XCTAssertFalse(snapshot.items.contains { $0.content.contains("implementation metadata") })

        let item = try XCTUnwrap(snapshot.items.first)
        let globalInstruction = MemoryInstructionBuilder.makeGlobal(for: item)
        XCTAssertTrue(globalInstruction.contains("明确整理为全局记忆"))
        XCTAssertTrue(globalInstruction.contains(item.content))
        XCTAssertTrue(globalInstruction.contains("extensions/ad_hoc/notes/note.md：第 2 行"))

        let projectURL = URL(fileURLWithPath: "/Users/example/Documents/Example Project")
        let projectInstruction = MemoryInstructionBuilder.associate(item, with: projectURL)
        XCTAssertTrue(projectInstruction.contains("关联项目：Example Project"))
        XCTAssertTrue(projectInstruction.contains("项目路径：/Users/example/Documents/Example Project"))

        let removalInstruction = MemoryInstructionBuilder.remove(item)
        XCTAssertTrue(removalInstruction.contains("当前生效摘要和长期记忆中移除"))
        XCTAssertTrue(removalInstruction.contains("只处理这一条"))
    }

    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "skilllens-memory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appending(path: "memories/rollout_summaries"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appending(path: "memories/extensions/ad_hoc/notes"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appending(path: "memories/extensions/chronicle/resources"), withIntermediateDirectories: true)
        return home
    }

    private func write(_ string: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try string.write(to: url, atomically: true, encoding: .utf8)
    }
}

private extension MemorySnapshot {
    func count(in kind: MemoryKind) -> Int {
        records(in: kind).count
    }

    func records(in kind: MemoryKind) -> [MemoryRecord] {
        records.filter { $0.kind == kind }
    }
}
