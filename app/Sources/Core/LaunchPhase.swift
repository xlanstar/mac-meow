/// 首頁顯示的流程階段。
enum LaunchPhase: Equatable {
    case idle
    /// 腳本執行中；`step` 是清單上正在處理的項目（顯示轉圈）。
    case working(String, step: Step? = nil)
    /// 流程失敗；`step` 是失敗的清單項目。
    case failed(String, step: Step? = nil)

    var isWorking: Bool {
        if case .working = self { return true }
        return false
    }

    var activeStep: Step? {
        if case .working(_, let step) = self { return step }
        return nil
    }

    var failedStep: Step? {
        if case .failed(_, let step) = self { return step }
        return nil
    }

    var failureMessage: String? {
        if case .failed(let message, _) = self { return message }
        return nil
    }
}

/// 需要獨占的流程；同一時間只執行一個（包含它顯示的對話框）。
enum Operation: Equatable {
    case launch, stop, loopback, chooseGameDir, uninstall

    /// 流程進行中時，阻擋結束 App 或更新的提示標題。
    var busyTitle: String {
        switch self {
        case .launch: return "正在啟動貓貓谷"
        case .stop: return "正在關閉貓貓谷"
        case .loopback: return "正在設定本機網路位址"
        case .chooseGameDir: return "正在選擇遊戲資料夾"
        case .uninstall: return "正在解除安裝"
        }
    }
}
