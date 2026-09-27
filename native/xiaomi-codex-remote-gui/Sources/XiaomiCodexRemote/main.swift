import AppKit
import SwiftUI
import Foundation

final class XiaomiCodexRemoteAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow?
    private var appState: AppState!

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[Xiaomi Codex Remote] Starting Xiaomi Codex Remote...")

        // 1. Initialize central state (owns all subsystems)
        appState = AppState()

        // 2. Create main window with SwiftUI content
        createMainWindow()

        // 3. Setup menu bar status item
        setupStatusBar()

        // 4. Start all subsystems
        appState.startAll()
    }

    // MARK: - Main Window

    private func createMainWindow() {
        let contentView = MainWindow(state: appState)
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.contentMinSize = NSSize(width: 800, height: 560)
        window.title = "Xiaomi Codex Remote"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.center()
        window.setFrameAutosaveName("XiaomiCodexRemoteMain")
        // Older saved frames may be narrower than the two-column layout.
        if window.contentLayoutRect.width < 800 || window.contentLayoutRect.height < 560 {
            window.setContentSize(NSSize(width: max(window.contentLayoutRect.width, 800),
                                         height: max(window.contentLayoutRect.height, 560)))
        }
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)

        self.mainWindow = window
    }

    @objc private func showMainWindow() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            createMainWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Menu Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let svgString = """
            <svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M15.4837 3.3C15.9081 3.545 16.1203 3.66752 16.2331 3.84653C16.3323 4.004 16.379 4.19093 16.3665 4.38038C16.3522 4.59574 16.2255 4.81527 15.972 5.25427L9.9203 15.7361C9.66685 16.1751 9.54011 16.3947 9.36072 16.5147C9.20291 16.6202 9.01767 16.6733 8.83169 16.6661C8.62028 16.6579 8.40806 16.5354 7.9837 16.2904L5.21246 14.6904C4.78809 14.4454 4.57586 14.3229 4.46308 14.1439C4.36389 13.9864 4.31718 13.7995 4.32969 13.61C4.34393 13.3947 4.47069 13.1751 4.72415 12.7361L10.7758 2.25427C11.0293 1.81527 11.156 1.59572 11.3354 1.47572C11.4932 1.37016 11.6785 1.31715 11.8645 1.32431C12.0759 1.33247 12.2881 1.45501 12.7125 1.70002L15.4837 3.3ZM7.4116 11.3313C6.93331 11.0552 6.314 11.2324 6.02834 11.7272C5.74267 12.222 5.89883 12.847 6.37712 13.1231C6.85541 13.3992 7.47472 13.222 7.76039 12.7272C8.04605 12.2324 7.88989 11.6075 7.4116 11.3313ZM10.8487 10.6281C10.3704 10.3519 9.75111 10.5292 9.46544 11.024L8.30165 13.0397C8.01599 13.5345 8.17214 14.1595 8.65044 14.4356C9.12873 14.7117 9.74804 14.5345 10.0337 14.0397L11.1975 12.024C11.4832 11.5292 11.327 10.9042 10.8487 10.6281ZM8.5754 9.31557C8.0971 9.03943 7.47779 9.21668 7.19213 9.71146C6.90646 10.2062 7.06262 10.8312 7.54091 11.1073C8.0192 11.3835 8.63851 11.2062 8.92418 10.7115C9.20984 10.2167 9.05369 9.59172 8.5754 9.31557ZM12.5464 5.18767C11.4104 4.53183 9.93955 4.95279 9.26109 6.12791C8.58264 7.30302 8.95351 8.7873 10.0895 9.44314C11.2254 10.099 12.6963 9.67802 13.3747 8.50291C14.0532 7.32779 13.6823 5.84351 12.5464 5.18767ZM12.4652 2.45317C12.0766 2.22881 11.5734 2.37282 11.3413 2.77483C11.1092 3.17685 11.2361 3.68463 11.6247 3.90899C12.0133 4.13336 12.5165 3.98935 12.7486 3.58733C12.9807 3.18532 12.8538 2.67754 12.4652 2.45317ZM14.9551 3.89067C14.5664 3.66631 14.0633 3.81032 13.8312 4.21233C13.599 4.61435 13.7259 5.12213 14.1145 5.34649C14.5032 5.57086 15.0063 5.42685 15.2384 5.02483C15.4705 4.62282 15.3437 4.11504 14.9551 3.89067Z" fill="black"/>
            <path d="M12.4004 7.94041C12.0434 8.55889 11.2692 8.78045 10.6714 8.43527C10.0735 8.09009 9.87829 7.30889 10.2354 6.69041C10.5925 6.07193 11.3666 5.85037 11.9645 6.19555C12.5623 6.54073 12.7575 7.32193 12.4004 7.94041Z" fill="black"/>
            <path d="M2.10598 11.0299L3.37977 9.11052C3.40504 9.07244 3.40559 9.02552 3.38122 8.987L2.09152 6.9481C1.89463 6.63684 2.02608 6.2445 2.38368 6.07609C2.73457 5.91084 3.17177 6.02357 3.36482 6.32906L4.92854 8.80359C5.0249 8.95608 5.02374 9.14158 4.92547 9.29313L3.38191 11.6735C3.1804 11.9843 2.72922 12.0922 2.37567 11.9142C2.02167 11.736 1.90067 11.3392 2.10598 11.0299Z" fill="black"/>
            </svg>
            """
            if let data = svgString.data(using: .utf8), let image = NSImage(data: data) {
                image.isTemplate = true
                button.image = image
            } else {
                button.image = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: "Xiaomi Codex Remote")
            }
            button.action = #selector(statusBarClicked)
            button.target = self
        }

        let menu = NSMenu()

        let showItem = NSMenuItem(title: "显示主窗口", action: #selector(showMainWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        // Bridge controls
        let restartItem = NSMenuItem(title: "重启桥接服务", action: #selector(restartBridge), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)

        let launchItem = NSMenuItem(title: "打开 ChatGPT Shim", action: #selector(launchChatGPT), keyEquivalent: "")
        launchItem.target = self
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 Xiaomi Codex Remote", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func statusBarClicked() {
        showMainWindow()
    }

    @objc private func restartBridge() {
        appState.bridge.restart()
    }

    @objc private func launchChatGPT() {
        appState.launchChatGPT()
    }

    @objc private func quitApp() {
        print("[Xiaomi Codex Remote] Stopping and quitting...")
        appState.stopAll()
        NSApplication.shared.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Keep running in menu bar when window is closed
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.stopAll()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Refresh permission indicators and resume monitoring after System Settings.
        appState?.refreshAfterReturningToApp()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }
}

// MARK: - NSWindowDelegate

extension XiaomiCodexRemoteAppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Just hide, don't quit — keep running in menu bar
    }
}

// MARK: - Entry Point

if CommandLine.arguments.contains("--check-runtime") {
    // Packaging smoke check: no hardware access and no ChatGPT launch.
    guard let shim = ChatGPTLauncher().resolveShimPath() else {
        fputs("Bundled shim missing\n", stderr)
        exit(1)
    }
    let bridge = NativeCodexBridge(socketPath: "/tmp/ac-check-\(UUID().uuidString).sock")
    bridge.start()
    guard bridge.state == .running else {
        fputs("Native bridge failed to start\n", stderr)
        exit(1)
    }
    bridge.stop()
    print("Native runtime OK; bundled shim: \(shim)")
} else {
    let app = NSApplication.shared
    let delegate = XiaomiCodexRemoteAppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular) // Show in dock (has a window now)
    app.run()
}
