import SwiftUI

/// 選單列圖示的選單：App 的全部功能（「回報問題」的表單除外）。有流程進行中時停用會改變狀態的項目。
struct MenuBarContent: View {
    let model: AppModel
    @ObservedObject var home: HomeModel
    @ObservedObject var updater: Updater

    private var launch: LaunchController { model.launch }

    var body: some View {
        let state = home.presentation
        status(state)
        Divider()
        actions(state)
        if let release = updater.notice {
            Divider()
            update(release)
        }
        Divider()
        ChecklistMenu(state: state) { launch.perform($0) }
        GameSettingsMenu(config: model.config, status: model.status)
        Divider()
        help
        about(state)
        Divider()
        Button("結束貓貓谷 for Mac") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder private func status(_ state: HomePresentation) -> some View {
        Text(state.detail ?? state.summary.title)
        if state.showsTunnelMeter {
            Text("\(Step.tunnels.title)：\(state.tunnels)/\(state.tunnelsTotal)")
        }
        if state.failed {
            Button("查看錯誤訊息…") { Task { await model.showFailure() } }
        }
    }

    @ViewBuilder private func actions(_ state: HomePresentation) -> some View {
        if state.showsStop {
            Button("顯示登入器") { launch.showLauncher() }
                .keyboardShortcut("l")
                .disabled(!state.canShowLauncher)
            Button("重新啟動") { Task { await launch.restart() } }
        } else {
            Button(state.progressLabel ?? "開始遊戲") { Task { await launch.start() } }
                .keyboardShortcut("r")
                .disabled(!state.canStart)
        }
        Button("全部關閉…") { Task { await launch.stopAll() } }
            .keyboardShortcut(".")
            .disabled(state.busy)
        // 需要使用者處理的設定；「開始遊戲」也會依序引導
        ForEach(Array(state.setupActions.enumerated()), id: \.offset) { _, action in
            Button(action.title) { launch.perform(action) }
                .disabled(state.busy)
        }
    }

    @ViewBuilder private func update(_ release: Release) -> some View {
        switch updater.state {
        case .downloading(let progress):
            Text("正在下載 \(release.version)…\(Int(progress * 100))%")
        case .waiting:
            Text("正在下載 \(release.version)：等待網路…")
        case .working:
            Text("正在更新到 \(release.version)…")
        case nil:
            // Homebrew 安裝時 install 只顯示 brew 指令的對話框
            Button("更新到 \(release.version)\(updater.homebrewCommand == nil ? "" : "…")") {
                Task { await updater.install(release) }
            }
            Button("略過這個版本") { updater.skip(release) }
        }
        Button("\(release.version) 更新內容") { Workspace.open(release.page) }
    }

    private var help: some View {
        Menu("說明") {
            Button("回報問題…") { model.reportBug() }
            Button("已知問題與解法") { Workspace.open(AppPaths.knownIssues) }
            Button("已回報的問題") { Workspace.open(AppPaths.reportedIssues) }
            Divider()
            Button("開啟記錄檔") { model.log.open() }
            Button("在 Finder 中顯示記錄檔") { model.log.reveal() }
            Button("拷貝這次開啟的記錄") { model.log.copy() }
        }
    }

    private func about(_ state: HomePresentation) -> some View {
        Menu("貓貓谷 for Mac \(appVersion)") {
            Button("檢查更新…") { Task { await updater.checkNow() } }
                .disabled(updater.checking || updater.installing)
            Toggle("自動檢查更新", isOn: $updater.automatic)
            Divider()
            Button("專案網頁") { Workspace.open(AppPaths.repo) }
            Divider()
            Button("解除安裝…") { Task { await model.uninstaller.run() } }
                .disabled(state.busy || updater.installing)
        }
    }
}

/// 選單列圖示：固定為貓掌，不隨狀態改變（狀態看選單第一行）。
struct MenuBarIcon: View {
    var body: some View {
        Image(systemName: "pawprint.fill")
            .accessibilityLabel("貓貓谷 for Mac")
    }
}
