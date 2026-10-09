import Combine

/// 組裝 App 的所有元件（唯一的 shared instance，AppDelegate 與 SwiftUI scene 共用）。
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let log = AppLog()
    let config = ConfigStore()
    let status: StatusMonitor
    let launch: LaunchController
    let uninstaller: Uninstaller
    let updater: Updater
    let home: HomeModel

    /// 「回報問題」視窗；非 nil 時在主視窗以 sheet 顯示。
    @Published var bugReport: BugReportContext?

    private init() {
        let status = StatusMonitor(config: config)
        let launch = LaunchController(status: status, config: config, log: log)
        self.status = status
        self.launch = launch
        uninstaller = Uninstaller(launch: launch)
        updater = Updater { launch.operation }
        home = HomeModel(launch: launch)
    }

    func reportBug() { bugReport = BugReportContext() }

    /// 從啟動失敗畫面回報：帶入失敗的步驟與錯誤訊息。
    func reportFailure() {
        guard let message = launch.phase.failureMessage else { return reportBug() }
        let step = launch.phase.failedStep.map { "在「\($0.title)」步驟" } ?? ""
        bugReport = BugReportContext(category: .launch, details: "啟動\(step)失敗，App 顯示：\n\(message)\n\n")
    }
}
