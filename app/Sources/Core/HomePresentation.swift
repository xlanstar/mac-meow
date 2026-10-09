/// 首頁與選單列要顯示的內容，由環境狀態與流程階段推導（不含畫面與動作）。
struct HomePresentation: Equatable {
    let summary: StatusSummary
    let checklist: [ChecklistItem]
    /// 有流程進行中（包含它顯示的對話框）；會改變狀態的動作都停用。
    let busy: Bool
    let canStart: Bool
    /// 顯示「全部關閉／重新啟動」而不是「開始遊戲」。
    let showsStop: Bool
    let canShowLauncher: Bool
    /// 腳本執行中時「開始遊戲」按鈕顯示的文字。
    let progressLabel: String?
    /// 顯示失敗訊息的後續動作（查看記錄、回報、知道了）。
    let failed: Bool
    let showsTunnelMeter: Bool
    let tunnels: Int
    let tunnelsTotal: Int

    init(
        status: EnvStatus = EnvStatus(), phase: LaunchPhase = .idle, operation: Operation? = nil,
        gameDirChosen: Bool = false
    ) {
        checklist = Step.checklist.map { ChecklistItem($0, status: status, phase: phase, gameDirChosen: gameDirChosen) }
        summary = StatusSummary(status: status, phase: phase, needsSetup: checklist.contains { $0.state == .action })
        busy = operation != nil
        canStart = status.loaded && !busy
        showsStop = status.running && !busy
        canShowLauncher = status.launcherPid != nil
        progressLabel = phase.isWorking ? (operation == .uninstall ? "解除安裝中…" : "啟動中…") : nil
        failed = phase.failureMessage != nil
        showsTunnelMeter = status.helpers || status.tunnels > 0 || phase.activeStep == .tunnels
        tunnels = status.tunnels
        tunnelsTotal = status.tunnelsTotal
    }
}

/// 主卡片的整體狀態。
struct StatusSummary: Equatable {
    enum Tone { case accent, ok, error }

    let title: String
    let symbol: String
    let tone: Tone
    /// 顯示轉圈而不是圖示。
    let busy: Bool

    init(title: String, symbol: String = "pawprint.fill", tone: Tone = .accent, busy: Bool = false) {
        self.title = title
        self.symbol = symbol
        self.tone = tone
        self.busy = busy
    }

    init(status: EnvStatus, phase: LaunchPhase, needsSetup: Bool) {
        if phase.isWorking {
            self.init(title: "處理中", busy: true)
        } else if !status.loaded {
            self.init(title: "檢查環境中", busy: true)
        } else if status.game {
            self.init(title: "遊戲執行中", symbol: "gamecontroller.fill", tone: .ok)
        } else if status.launcher {
            self.init(title: "登入器已開啟", symbol: "checkmark.seal.fill", tone: .ok)
        } else if phase.failureMessage != nil {
            self.init(title: "啟動沒有完成", symbol: "exclamationmark.triangle.fill", tone: .error)
        } else if needsSetup {
            self.init(title: "需要設定", symbol: "wrench.and.screwdriver.fill")
        } else {
            self.init(title: "準備就緒")
        }
    }
}

/// 環境檢查清單的一列。
struct ChecklistItem: Equatable, Identifiable {
    enum State: Equatable {
        case ok
        /// 「開始遊戲」時自動處理。
        case todo
        /// 需要使用者處理。
        case action
        case working, failed, unknown
    }

    let step: Step
    var state: State
    let detail: String
    let action: ChecklistAction?

    var id: Step { step }

    init(_ step: Step, state: State, detail: String, action: ChecklistAction? = nil) {
        self.step = step
        self.state = state
        self.detail = detail
        self.action = action
    }

    init(_ step: Step, status s: EnvStatus, phase: LaunchPhase, gameDirChosen: Bool) {
        switch step {
        case .cyder:
            if let path = s.cyderPath {
                self.init(
                    step, state: s.cyderInDownloads ? .action : .ok,
                    detail: s.cyderInDownloads ? "請移到「應用程式」資料夾" : path.abbreviatingHome,
                    action: s.cyderInDownloads ? .revealCyder(path) : nil)
            } else {
                self.init(step, state: .action, detail: "尚未安裝（免費的 Wine 執行環境）", action: .downloadCyder)
            }
        case .prefix:
            self.init(
                step, state: s.cyderReady ? .ok : .todo,
                detail: s.cyderReady ? "已建立" : "第一次啟動時由 Cyder 建立（約 1–3 分鐘）",
                action: s.cyderReady || !s.cyderUsable ? nil : .openCyder)
        case .gameDir:
            let detail =
                s.gameDirValid
                ? s.gameDir.abbreviatingHome
                : gameDirChosen ? "缺少 \(s.missingFile ?? "必要檔案")" : "尚未選擇"
            self.init(
                step, state: s.gameDirValid ? .ok : .action, detail: detail,
                action: .chooseGameDir(change: s.gameDirValid))
        case .loopback:
            self.init(
                step, state: s.loopback ? .ok : .action,
                detail: s.loopback ? "已設定，開機自動套用" : "需要管理員權限（只需一次）",
                action: s.loopback ? nil : .setupLoopback)
        case .patch:
            self.init(step, state: s.patched ? .ok : .todo, detail: s.patched ? "已套用" : "啟動時自動套用")
        case .vb6:
            self.init(step, state: s.vb6 ? .ok : .todo, detail: s.vb6 ? "已安裝" : "啟動時自動安裝（約 1–2 分鐘）")
        case .tunnels:
            self.init(
                step, state: s.tunnels >= s.tunnelsTotal ? .ok : .todo, detail: "\(s.tunnels)/\(s.tunnelsTotal)")
        }
        if !s.loaded { state = .unknown }
        if phase.activeStep == step { state = .working }
        if phase.failedStep == step { state = .failed }
    }
}

/// 清單列上的按鈕；由 `LaunchController.perform(_:)` 執行。
enum ChecklistAction: Equatable {
    case downloadCyder
    case revealCyder(String)
    case openCyder
    /// `change`：已選過有效的資料夾（按鈕顯示「更改…」）。
    case chooseGameDir(change: Bool)
    case setupLoopback

    var title: String {
        switch self {
        case .downloadCyder: return "下載"
        case .revealCyder: return "顯示"
        case .openCyder: return "開啟 Cyder"
        case .chooseGameDir(let change): return change ? "更改…" : "選擇…"
        case .setupLoopback: return "設定…"
        }
    }
}
