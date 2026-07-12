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
}
