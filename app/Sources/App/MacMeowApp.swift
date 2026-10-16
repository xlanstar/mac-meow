import SwiftUI

/// 只在選單列的 App（Info.plist 的 LSUIElement）：沒有主視窗與 Dock 圖示，功能都在選單列圖示的選單裡。
@main
struct MacMeowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model, home: model.home, updater: model.updater)
        } label: {
            MenuBarIcon(home: model.home)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel { .shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.status.startPolling()
        model.updater.start()
    }

    /// 「回報問題」視窗關閉後仍留在選單列。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// 腳本執行中（例如安裝 VB6、解除安裝）就結束 App，腳本會因輸出中斷而停在一半，先確認。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.launch.phase.isWorking, let operation = model.launch.operation else { return .terminateNow }
        let quit = Dialog.confirmNow(
            operation.busyTitle, "現在結束可能讓設定只做一半。確定要結束嗎？", confirm: "結束", cancel: "繼續等待")
        return quit ? .terminateNow : .terminateCancel
    }
}
