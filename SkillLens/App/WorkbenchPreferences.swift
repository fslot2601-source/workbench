import Foundation

enum WorkbenchPreferences {
    static let showMenuBarIconKey = "workbench.showMenuBarIcon"
    static let menuBarRefreshMinutesKey = "workbench.menuBarRefreshMinutes"
    static let showMenuBarTokenActivityKey = "workbench.showMenuBarTokenActivity"
    static let showMenuBarStorageKey = "workbench.showMenuBarStorage"

    static let defaultRefreshMinutes = 10
    static let supportedRefreshMinutes = [5, 10, 30]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showMenuBarIconKey: true,
            menuBarRefreshMinutesKey: defaultRefreshMinutes,
            showMenuBarTokenActivityKey: true,
            showMenuBarStorageKey: true
        ])
    }

    static var refreshInterval: TimeInterval {
        let value = UserDefaults.standard.integer(forKey: menuBarRefreshMinutesKey)
        let minutes = supportedRefreshMinutes.contains(value) ? value : defaultRefreshMinutes
        return TimeInterval(minutes * 60)
    }
}
