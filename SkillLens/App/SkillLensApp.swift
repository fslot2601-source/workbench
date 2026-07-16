import AppKit
import SwiftUI

@main
struct SkillLensApp: App {
    @NSApplicationDelegateAdaptor(SkillLensAppDelegate.self) private var appDelegate

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        WorkbenchPreferences.registerDefaults()
    }

    var body: some Scene {
        Settings {
            WorkbenchSettingsView()
                .environment(appDelegate.model)
        }
    }
}

@MainActor
final class SkillLensAppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var mainWindow: NSWindow?
    private var usageRefreshTask: Task<Void, Never>?
    private var statusItem: NSStatusItem?
    private var statusPopover: NSPopover?
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        showMainWindow()
        updateStatusItemVisibility()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateStatusItemVisibility() }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        Task {
            await model.bootstrap()
            startUsageRefreshLoop()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageRefreshTask?.cancel()
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window !== mainWindow
        else { return }
        perform(#selector(applyLegacySettingsTitle(_:)), with: window, afterDelay: 0.5)
    }

    @objc private func applyLegacySettingsTitle(_ window: NSWindow) {
        guard window !== mainWindow, window.title == "诊断" else { return }
        window.title = "Workbench 设置"
    }

    func showMainWindow(destination: SidebarDestination? = nil) {
        if let destination { model.selection = destination }
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = RootView()
            .environment(model)
            .frame(minWidth: 980, minHeight: 640)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Workbench"
        window.identifier = NSUserInterfaceItemIdentifier("dev.skilllens.main-window")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 980, height: 640)
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.center()

        mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateStatusItemVisibility() {
        let shouldShow = UserDefaults.standard.bool(forKey: WorkbenchPreferences.showMenuBarIconKey)
        if !shouldShow {
            statusPopover?.close()
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            statusPopover = nil
            return
        }
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(named: "MenuBarIcon")
            image?.size = NSSize(width: 18, height: 18)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "Workbench"
            button.target = self
            button.action = #selector(toggleStatusPopover(_:))
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(
            width: MenuBarPanelLayout.width,
            height: MenuBarPanelLayout.initialHeight
        )
        popover.contentViewController = NSHostingController(
            rootView: WorkbenchMenuBarView(
                openDestination: { [weak self] destination in
                    self?.statusPopover?.close()
                    self?.showMainWindow(destination: destination)
                },
                contentHeightDidChange: { [weak self] height in
                    self?.resizeStatusPopover(to: height)
                }
            )
            .environment(model)
            .tint(WorkbenchTheme.accent)
        )
        statusItem = item
        statusPopover = popover
    }

    private func resizeStatusPopover(to height: CGFloat) {
        guard let statusPopover,
              abs(statusPopover.contentSize.height - height) >= 1
        else { return }
        statusPopover.contentSize = NSSize(width: MenuBarPanelLayout.width, height: height)
    }

    @objc private func toggleStatusPopover(_ sender: NSStatusBarButton) {
        guard let statusPopover else { return }
        if statusPopover.isShown {
            statusPopover.performClose(sender)
        } else {
            statusPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            statusPopover.contentViewController?.view.window?.makeKey()
        }
    }

    private func startUsageRefreshLoop() {
        guard usageRefreshTask == nil else { return }
        usageRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self else { return }
                guard UserDefaults.standard.bool(forKey: WorkbenchPreferences.showMenuBarIconKey) else { continue }
                let age = self.model.usageRefreshedAt.map { Date().timeIntervalSince($0) } ?? .infinity
                if age >= WorkbenchPreferences.refreshInterval {
                    await self.model.refreshUsage()
                }
            }
        }
    }
}
