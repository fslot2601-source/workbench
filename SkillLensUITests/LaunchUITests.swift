import XCTest

final class LaunchUITests: XCTestCase {
    @MainActor
    func testLaunchShowsSingleUsableWindow() throws {
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15), "Skill Lens 主窗口没有出现。")
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

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15), "Skill Lens 主窗口没有出现。")

        let destinations = [
            (id: "dashboard", title: "总览"),
            (id: "skills", title: "Skills"),
            (id: "hooks", title: "Hooks"),
            (id: "usage", title: "用量"),
            (id: "mcp", title: "MCP"),
            (id: "storage", title: "存储"),
            (id: "history", title: "变更记录"),
            (id: "diagnostics", title: "诊断"),
        ]

        for destination in destinations {
            let sidebarItem = app.descendants(matching: .any)["sidebar-\(destination.id)"].firstMatch
            XCTAssertTrue(sidebarItem.waitForExistence(timeout: 5), "侧栏缺少 \(destination.title)。")
            sidebarItem.click()
            let screen = app.descendants(matching: .any)["screen-\(destination.id)"].firstMatch
            XCTAssertTrue(
                screen.waitForExistence(timeout: 10),
                "无法打开 \(destination.title) 页面。"
            )
            XCTAssertEqual(app.windows.count, 1, "切换到 \(destination.title) 时不应创建额外窗口。")
        }
    }
}
