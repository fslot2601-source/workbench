import AppKit
import SwiftUI

@MainActor
private enum AppEnvironment {
    static let model = AppModel()
}

@main
struct SkillLensApp: App {
    @NSApplicationDelegateAdaptor(SkillLensAppDelegate.self) private var appDelegate
    @State private var model = AppEnvironment.model

    init() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            SkillLensWindowManager.shared.showMainWindow()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 640)
                .task { await model.bootstrap() }
        }
        .defaultSize(width: 1180, height: 760)

        Settings {
            DiagnosticsView()
                .environment(model)
                .frame(width: 620, height: 460)
        }
    }
}

@MainActor
final class SkillLensAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            SkillLensWindowManager.shared.showMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { SkillLensWindowManager.shared.showMainWindow() }
        return true
    }
}

@MainActor
private final class SkillLensWindowManager {
    static let shared = SkillLensWindowManager()
    private var mainWindowController: NSWindowController?

    func showMainWindow() {
        if let existing = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if let window = mainWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = RootView()
            .environment(AppEnvironment.model)
            .frame(minWidth: 980, minHeight: 640)
            .task { await AppEnvironment.model.bootstrap() }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Skill Lens"
        window.contentViewController = NSHostingController(rootView: rootView)
        window.center()
        window.setFrameAutosaveName("SkillLensMainWindow")
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        mainWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
