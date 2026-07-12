import AppKit
import SwiftUI

@main
struct SkillLensApp: App {
    @NSApplicationDelegateAdaptor(SkillLensAppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    init() {
        MainWindowRecovery.schedule()
    }

    var body: some Scene {
        WindowGroup("Skill Lens", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 640)
                .background(MainWindowMarker())
                .task { await model.bootstrap() }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            MainWindowCommands()
        }

        Settings {
            DiagnosticsView()
                .environment(model)
                .frame(width: 620, height: 460)
        }
    }
}

private struct MainWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("显示主窗口") {
                if let window = MainWindowLocator.window {
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                } else {
                    openWindow(id: "main")
                }
            }
            .keyboardShortcut("1", modifiers: [.command, .shift])
        }
    }
}

final class SkillLensAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainWindowRecovery.schedule()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowRecovery.schedule()
        return true
    }
}

@MainActor
private enum MainWindowRecovery {
    private static var generation = 0

    static func schedule() {
        generation += 1
        attempt(remaining: 12, generation: generation)
    }

    private static func attempt(remaining: Int, generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard generation == self.generation else { return }
            if let window = MainWindowLocator.window {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            if let item = findMenuItem(titled: "显示主窗口", in: NSApp.mainMenu),
               let action = item.action
            {
                NSApp.sendAction(action, to: item.target, from: item)
                return
            }
            if remaining > 1 {
                attempt(remaining: remaining - 1, generation: generation)
            }
        }
    }

    private static func findMenuItem(titled title: String, in menu: NSMenu?) -> NSMenuItem? {
        guard let menu else { return nil }
        for item in menu.items {
            if item.title == title { return item }
            if let match = findMenuItem(titled: title, in: item.submenu) { return match }
        }
        return nil
    }
}

@MainActor
private enum MainWindowLocator {
    static let identifier = NSUserInterfaceItemIdentifier("dev.skilllens.main-window")

    static var window: NSWindow? {
        NSApp.windows.first { $0.identifier == identifier }
    }
}

private struct MainWindowMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> MarkerView {
        MarkerView()
    }

    func updateNSView(_ nsView: MarkerView, context: Context) {}

    final class MarkerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.identifier = MainWindowLocator.identifier
        }
    }
}
