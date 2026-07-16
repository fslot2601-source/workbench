import XCTest
@testable import SkillLens

final class MenuBarPanelLayoutTests: XCTestCase {
    func testPanelShrinksToMeasuredContentHeight() {
        XCTAssertEqual(MenuBarPanelLayout.height(for: 376.2), 377)
    }

    func testPanelKeepsMinimumUsableHeight() {
        XCTAssertEqual(
            MenuBarPanelLayout.height(for: 180),
            MenuBarPanelLayout.minimumHeight
        )
    }

    func testPanelCapsLargeContentAndLetsScrollViewHandleTheRest() {
        XCTAssertEqual(
            MenuBarPanelLayout.height(for: 900),
            MenuBarPanelLayout.maximumHeight
        )
    }
}
