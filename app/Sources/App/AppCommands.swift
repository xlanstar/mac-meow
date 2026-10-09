import SwiftUI

/// 選單列的 App、遊戲與說明選單。需要觀察狀態的項目獨立成 View。
struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(after: .appInfo) {
            UpdateCommands(updater: model.updater)
            Divider()
            UninstallButton(model: model, home: model.home, updater: model.updater)
        }
        CommandMenu("遊戲") {
            GameCommands(launch: model.launch, home: model.home, log: model.log)
        }
        CommandGroup(replacing: .help) {
            Button("回報問題…") { model.reportBug() }
            Button("已知問題") { Workspace.open(AppPaths.knownIssues) }
            Divider()
            Button("專案網頁") { Workspace.open(AppPaths.repo) }
        }
    }
}

/// 「檢查更新⋯」與「自動檢查更新」。
private struct UpdateCommands: View {
    @ObservedObject var updater: Updater

    var body: some View {
        Button("檢查更新…") { Task { await updater.checkNow() } }
            .disabled(updater.checking || updater.installing)
        Toggle("自動檢查更新", isOn: $updater.automatic)
    }
}

/// 「解除安裝⋯」：有流程進行中或正在更新時不可用。
private struct UninstallButton: View {
    let model: AppModel
    @ObservedObject var home: HomeModel
    @ObservedObject var updater: Updater

    var body: some View {
        Button("解除安裝…") { Task { await model.uninstaller.run() } }
            .disabled(home.presentation.busy || updater.installing)
    }
}

/// 「遊戲」選單：有流程進行中時停用會改變狀態的項目。
private struct GameCommands: View {
    let launch: LaunchController
    @ObservedObject var home: HomeModel
    let log: AppLog

    var body: some View {
        let state = home.presentation
        Button("開始遊戲") { Task { await launch.start() } }
            .keyboardShortcut("r")
            .disabled(!state.canStart)
        Button("全部關閉…") { Task { await launch.stopAll() } }
            .keyboardShortcut(".")
            .disabled(state.busy)
        Button("顯示登入器") { launch.showLauncher() }
            .keyboardShortcut("l")
            .disabled(!state.canShowLauncher)
        Divider()
        Button("選擇遊戲資料夾…") { Task { await launch.chooseGameDir() } }
            .disabled(state.busy)
        Button("設定本機網路位址…") { Task { await launch.setupLoopback() } }
            .disabled(state.busy)
        Divider()
        Button("開啟記錄檔") { log.open() }
    }
}

/// 選單列圖示的選單。
struct MenuBarContent: View {
    let model: AppModel
    @ObservedObject var home: HomeModel
    @ObservedObject var updater: Updater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let state = home.presentation
        Text(state.summary.title)
        Divider()
        if let release = updater.notice {
            // Homebrew 安裝時 install 只顯示 brew 指令的對話框
            Button("更新到 \(release.version)\(updater.homebrewCommand == nil ? "" : "…")") {
                showMainWindow { await updater.install(release) }
            }
            .disabled(updater.installing)
            Divider()
        }
        Button("顯示主視窗") { MainWindow.show(openWindow) }
        if state.showsStop {
            Button("全部關閉…") { showMainWindow { await model.launch.stopAll() } }
        } else {
            Button("開始遊戲") { showMainWindow { await model.launch.start() } }
                .disabled(!state.canStart)
        }
        Divider()
        Button("結束貓貓谷 for Mac") { NSApp.terminate(nil) }
    }

    /// 先叫回主視窗，讓接下來的對話框以 sheet 顯示在主視窗上。
    private func showMainWindow(then action: @escaping () async -> Void) {
        MainWindow.show(openWindow)
        Task { await action() }
    }
}
