import Combine

/// 組裝 App 的所有元件（唯一的 shared instance，AppDelegate 與 SwiftUI scene 共用）。
@MainActor
final class AppModel {
    static let shared = AppModel()

    let log = AppLog()
    let config = ConfigStore()
    let status: StatusMonitor
    let launch: LaunchController
    let uninstaller: Uninstaller
    let updater: Updater
    let home: HomeModel

    private var failureAlert: AnyCancellable?

    private init() {
        let status = StatusMonitor(config: config)
        let launch = LaunchController(status: status, config: config, log: log)
        self.status = status
        self.launch = launch
        uninstaller = Uninstaller(launch: launch)
        updater = Updater { launch.operation }
        home = HomeModel(launch: launch)
        // 沒有主視窗顯示失敗，所以流程失敗時直接跳出錯誤對話框
        failureAlert = launch.$phase
            .compactMap(\.failureMessage)
            .sink { [weak self] _ in Task { await self?.showFailure() } }
    }

    func reportBug() {
        BugReportWindow.show(context: BugReportContext(), env: config.config.environment)
    }

    /// 錯誤對話框（失敗時自動顯示，也可從選單「查看錯誤訊息…」再次開啟）。
    func showFailure() async {
        guard let message = launch.phase.failureMessage else { return }
        let choice = await Dialog.ask(
            "啟動沒有完成", message, buttons: ["知道了", "回報此問題…", "開啟記錄檔"], style: .warning)
        switch choice {
        case 0: launch.dismissFailure()
        case 1: reportFailure(message)
        default: log.open()
        }
    }

    /// 從錯誤對話框回報：帶入失敗的步驟與錯誤訊息。
    private func reportFailure(_ message: String) {
        let step = launch.phase.failedStep.map { "在「\($0.title)」步驟" } ?? ""
        BugReportWindow.show(
            context: BugReportContext(category: .launch, details: "啟動\(step)失敗，App 顯示：\n\(message)\n\n"),
            env: config.config.environment)
    }
}
