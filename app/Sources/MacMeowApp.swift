import SwiftUI

@main
struct MacMeowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let launcher = Launcher.shared

    var body: some Scene {
        Window("貓貓谷 for Mac", id: "main") {
            MainView(launcher: launcher)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("遊戲") {
                Button("開始遊戲") { Task { await launcher.start() } }
                    .keyboardShortcut("r")
                Button("全部關閉…") { Task { await launcher.stopAll() } }
                    .keyboardShortcut(".")
                Divider()
                Button("選擇遊戲資料夾…") { Task { await launcher.chooseGameDir() } }
                Button("設定本機網路位址…") { Task { await launcher.setupLoopback() } }
                Divider()
                Button("開啟記錄檔") { launcher.openLog() }
            }
        }

        Settings {
            SettingsView(launcher: launcher)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

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
