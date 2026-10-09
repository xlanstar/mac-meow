import SwiftUI

@main
struct MacMeowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        Window("貓貓谷 for Mac", id: MainWindow.sceneID) {
            MainView(model: model, updater: model.updater, home: model.home)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands { AppCommands(model: model) }

        // 關閉視窗只會縮到 Dock，選單列圖示讓 App 隨時可以叫回主視窗。
        MenuBarExtra("貓貓谷 for Mac", systemImage: "pawprint.fill") {
            MenuBarContent(model: model, home: model.home, updater: model.updater)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel { .shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.status.startPolling()
        model.updater.start()
    }

    /// 主視窗關閉鈕只會隱藏視窗；選單列圖示仍在，所以沒有視窗時也不結束。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// 隱藏時再次從 Finder／Launchpad 開啟 App：叫回原本的主視窗；視窗已不存在時交給 SwiftUI 重新開啟。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        flag || !MainWindow.show()
    }

    /// 腳本執行中（例如安裝 VB6、解除安裝）就結束 App，腳本會因輸出中斷而停在一半，先確認。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.launch.phase.isWorking, let operation = model.launch.operation else { return .terminateNow }
        let quit = Dialog.confirmNow(
            operation.busyTitle, "現在結束可能讓設定只做一半。確定要結束嗎？", confirm: "結束", cancel: "繼續等待")
        return quit ? .terminateNow : .terminateCancel
    }
}
