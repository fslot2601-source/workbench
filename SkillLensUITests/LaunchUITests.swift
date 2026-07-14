import XCTest

final class LaunchUITests: XCTestCase {
    @MainActor
    func testLaunchShowsSingleUsableWindow() throws {
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15), "Workbench 主窗口没有出现。")
        XCTAssertEqual(app.windows.count, 1, "启动后只能存在一个主窗口。")
        XCTAssertTrue(app.staticTexts["总览"].waitForExistence(timeout: 10), "主界面没有完成渲染。")

        if let path = ProcessInfo.processInfo.environment["SKILLLENS_UI_SCREENSHOT_PATH"], !path.isEmpty {
            let screenshot = window.screenshot()
            try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: path), options: .atomic)
        }

        app.typeKey("1", modifierFlags: [.command, .shift])
        XCTAssertEqual(app.windows.count, 1, "显示主窗口命令不应创建重复窗口。")
    }

    @MainActor
    func testEveryPrimaryScreenIsReachableFromSidebar() {
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15), "Workbench 主窗口没有出现。")
        let sidebar = app.descendants(matching: .any)["primary-sidebar"].firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5), "主侧栏没有出现。")
        let initialSidebarFrame = sidebar.frame

        let destinations = [
            (id: "dashboard", title: "总览"),
            (id: "skills", title: "Skills"),
            (id: "hooks", title: "Hooks"),
            (id: "memory", title: "Memory"),
            (id: "usage", title: "用量"),
            (id: "mcp", title: "MCP"),
            (id: "storage", title: "存储"),
            (id: "backup", title: "备份"),
            (id: "history", title: "变更记录"),
            (id: "diagnostics", title: "自检"),
        ]

        for destination in destinations {
            let sidebarItem = app.descendants(matching: .any)["sidebar-\(destination.id)"].firstMatch
            XCTAssertTrue(sidebarItem.waitForExistence(timeout: 5), "侧栏缺少 \(destination.title)。")
            sidebarItem.click()
            XCTAssertEqual(sidebarItem.value as? String, "已选择", "无法打开 \(destination.title) 页面。")
            XCTAssertEqual(app.windows.count, 1, "切换到 \(destination.title) 时不应创建额外窗口。")
            XCTAssertEqual(
                sidebar.frame.minX,
                initialSidebarFrame.minX,
                accuracy: 1,
                "切换到 \(destination.title) 时侧栏横向位置发生变化。"
            )
            XCTAssertEqual(
                sidebar.frame.width,
                initialSidebarFrame.width,
                accuracy: 1,
                "切换到 \(destination.title) 时侧栏宽度发生变化。"
            )
        }
    }

    @MainActor
    func testMCPStatusCenterOpensInTheMainWindow() throws {
        let app = XCUIApplication()
        app.launchEnvironment["SKILLLENS_START_DESTINATION"] = "mcp"
        app.launch()
        defer { app.terminate() }

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15), "Workbench 主窗口没有出现。")
        XCTAssertEqual(
            app.descendants(matching: .any)["sidebar-mcp"].firstMatch.value as? String,
            "已选择",
            "MCP 状态中心没有打开。"
        )
        XCTAssertTrue(app.staticTexts["配置、连接与工具状态"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.windows.count, 1, "打开 MCP 时不应创建额外窗口。")

        if let path = ProcessInfo.processInfo.environment["SKILLLENS_UI_SCREENSHOT_PATH"], !path.isEmpty {
            let screenshot = window.screenshot()
            try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    @MainActor
    func testStorageColumnsVisualSnapshot() throws {
        let app = XCUIApplication()
        app.launchEnvironment["SKILLLENS_START_DESTINATION"] = "storage"
        app.launch()
        defer { app.terminate() }

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15), "Workbench 主窗口没有出现。")
        XCTAssertTrue(app.staticTexts["本机 Codex Home"].waitForExistence(timeout: 10), "存储页面没有打开。")

        window.click()
        app.typeKey(XCUIKeyboardKey.end, modifierFlags: [])

        let screenshot = window.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "skilllens-storage-aligned"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
