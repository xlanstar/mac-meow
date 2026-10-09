import SwiftUI

@main
struct MacMeowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let launcher = Launcher.shared
    private let updater = Updater.shared

    var body: some Scene {
        Window("貓貓谷 for Mac", id: "main") {
            MainView(launcher: launcher, updater: updater)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                UpdateCommands(updater: updater)
            }
            CommandMenu("遊戲") {
                Button("開始遊戲") { Task { await launcher.start() } }
                    .keyboardShortcut("r")
                Button("全部關閉…") { Task { await launcher.stopAll() } }
                    .keyboardShortcut(".")
                ShowLauncherButton(launcher: launcher)
                Divider()
                Button("選擇遊戲資料夾…") { Task { await launcher.chooseGameDir() } }
                Button("設定本機網路位址…") { Task { await launcher.setupLoopback() } }
                Divider()
                Button("開啟記錄檔") { launcher.openLog() }
            }
            CommandGroup(replacing: .help) {
                Button("回報問題…") { launcher.reportBug() }
                Button("已知問題") { NSWorkspace.shared.open(AppPaths.knownIssues) }
                Divider()
                Button("專案網頁") { NSWorkspace.shared.open(AppPaths.repo) }
            }
        }

        // 關閉視窗只會縮到 Dock，選單列圖示讓 App 隨時可以叫回主視窗。
        MenuBarExtra("貓貓谷 for Mac", systemImage: "pawprint.fill") {
            MenuBarContent(launcher: launcher, updater: updater)
        }
    }
}

/// 主視窗：左上角關閉鈕（與 ⌘W）改為隱藏視窗並從 Dock 移除 App 圖示，
/// App 與選單列圖示保持執行；從選單列叫回時再顯示於 Dock。
@MainActor
final class MainWindow: NSObject {
    private static let shared = MainWindow()
    private weak var window: NSWindow?
    /// 視窗被 `hide` 收起（仍存在，只是不在畫面上）。
    private var hidden = false

    fileprivate static func attach(_ window: NSWindow) {
        shared.window = window
        // performClose（⌘W）也會經過關閉鈕，所以只改按鈕動作即可。按鈕的 target 是 weak，由 shared 持有。
        if let close = window.standardWindowButton(.closeButton) {
            close.target = shared
            close.action = #selector(hide(_:))
        }
    }

    @objc private func hide(_ sender: Any?) {
        guard let window else { return }
        hidden = true
        window.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    /// 叫回主視窗：恢復 Dock 圖示並帶到最前面；視窗不存在時以 `openWindow` 重新開啟。
    /// 回傳是否已顯示（沒有 `openWindow` 且視窗已不存在時回傳 false）。
    @discardableResult
    static func show(_ openWindow: OpenWindowAction? = nil) -> Bool {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = shared.window, shared.hidden || window.isVisible || window.isMiniaturized {
            shared.hidden = false
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            return true
        }
        guard let openWindow else { return false }
        openWindow(id: "main")
        return true
    }
}

/// 放在主視窗內容的背景，取得所在的 NSWindow 交給 `MainWindow`。
struct MainWindowAccessor: NSViewRepresentable {
    final class AccessorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { MainWindow.attach(window) }
        }
    }

    func makeNSView(context: Context) -> AccessorView { AccessorView() }
    func updateNSView(_ nsView: AccessorView, context: Context) {}
}

/// 選單列圖示的選單。
private struct MenuBarContent: View {
    @ObservedObject var launcher: Launcher
    @ObservedObject var updater: Updater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(launcher.statusSummary.title)
        Divider()
        if let release = updater.notice {
            // Homebrew 安裝時 install 只顯示 brew 指令的對話框
            Button("更新到 \(release.version)\(updater.homebrewCommand == nil ? "" : "…")") {
                MainWindow.show(openWindow)
                Task { await updater.install(release) }
            }
            .disabled(updater.installing)
            Divider()
        }
        Button("顯示主視窗") { MainWindow.show(openWindow) }
        if launcher.status.running && !launcher.isWorking {
            Button("全部關閉…") {
                MainWindow.show(openWindow)
                Task { await launcher.stopAll() }
            }
        } else {
            Button("開始遊戲") {
                MainWindow.show(openWindow)
                Task { await launcher.start() }
            }
            .disabled(launcher.isWorking || !launcher.status.loaded)
        }
        Divider()
        Button("結束貓貓谷 for Mac") { NSApp.terminate(nil) }
    }
}

/// App 選單的「檢查更新⋯」與「自動檢查更新」。
private struct UpdateCommands: View {
    @ObservedObject var updater: Updater

    var body: some View {
        Button("檢查更新…") { Task { await updater.checkNow() } }
            .disabled(updater.checking || updater.installing)
        Toggle("自動檢查更新", isOn: $updater.automatic)
    }
}

/// 選單「顯示登入器」：登入器執行中才可用（需要觀察狀態，所以獨立成 View）。
private struct ShowLauncherButton: View {
    @ObservedObject var launcher: Launcher

    var body: some View {
        Button("顯示登入器") { launcher.showLauncher() }
            .keyboardShortcut("l")
            .disabled(launcher.status.launcherPid == nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Updater.shared.start()
    }

    /// 主視窗關閉鈕只會隱藏視窗；選單列圖示仍在，所以沒有視窗時也不結束。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// 隱藏時再次從 Finder／Launchpad 開啟 App：叫回原本的主視窗；視窗已不存在時交給 SwiftUI 重新開啟。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        flag || !MainWindow.show()
    }

    /// 啟動流程進行中（例如安裝 VB6）就結束 App，play.sh 會因輸出中斷而停在一半，先確認。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Launcher.shared.isWorking else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "正在啟動貓貓谷"
        alert.informativeText = "現在結束可能讓設定只做一半。確定要結束嗎？"
        alert.addButton(withTitle: "繼續等待")
        alert.addButton(withTitle: "結束")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
