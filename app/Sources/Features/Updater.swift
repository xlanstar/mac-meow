import AppKit

/// 檢查與安裝更新：讀取 GitHub 最新正式版，「更新」交給 scripts/update.sh 下載、驗證並取代 App 後重新開啟；
/// App 由 Homebrew 安裝時（`update.sh brew-command`）改為顯示 brew 的更新指令。
/// 偏好設定存在 App 的 UserDefaults（uninstall.sh 會刪除）。
@MainActor
final class Updater: ObservableObject {
    enum InstallState: Equatable {
        /// 連線、驗證或安裝中。
        case working
        /// 下載進度 0–1。
        case downloading(Double)
        /// 網路中斷，等待後從中斷處繼續下載。
        case waiting
    }

    /// 首頁橫幅與選單列提示的新版本；「略過」後清除。
    @Published private(set) var notice: Release?
    @Published private(set) var checking = false
    /// App 由 Homebrew 安裝時的更新指令；nil 表示使用一鍵更新。每次檢查更新時重新判斷。
    @Published private(set) var homebrewCommand: String?
    /// 更新進度；nil 表示沒有在更新。
    @Published private(set) var state: InstallState?
    var installing: Bool { state != nil }

    @Published var automatic: Bool {
        didSet {
            defaults.set(automatic, forKey: Keys.automatic)
            if automatic { Task { await checkInBackground() } }
        }
    }

    private enum Keys {
        static let automatic = "autoCheckUpdates"
        static let skipped = "skippedUpdateVersion"
    }

    private static let checkInterval: UInt64 = 24 * 60 * 60 * 1_000_000_000
    private static let retryInterval: UInt64 = 10 * 60 * 1_000_000_000

    private let defaults = UserDefaults.standard
    /// 正在進行、不能被更新中斷的流程；nil 表示可以更新。
    private let blockingOperation: @MainActor () -> Operation?
    private var loop: Task<Void, Never>?

    init(blockingOperation: @escaping @MainActor () -> Operation?) {
        self.blockingOperation = blockingOperation
        automatic = defaults.object(forKey: Keys.automatic) as? Bool ?? true
    }

    /// App 啟動時呼叫：立即檢查一次，之後每 24 小時一次（App 常駐選單列時也會定期檢查）；
    /// 連不上 GitHub（例如離線）時 10 分鐘後再試。
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                let ok = await self?.checkInBackground() ?? true
                try? await Task.sleep(nanoseconds: ok ? Self.checkInterval : Self.retryInterval)
            }
        }
    }

    /// 選單「檢查更新⋯」：不論是否略過過此版本，都以對話框回報結果。
    func checkNow() async {
        do {
            guard let release = try await fetchNewer() else {
                await Dialog.ask("已是最新版本", "目前版本 \(appVersion)")
                return
            }
            notice = release
            if let command = homebrewCommand { return await showHomebrew(release, command) }
            let choice = await Dialog.ask(
                "有新版本 \(release.version)", "目前版本 \(appVersion)", buttons: ["更新", "稍後"])
            if choice == 0 { await install(release) }
        } catch {
            await Dialog.ask("無法檢查更新", error.localizedDescription, style: .warning)
        }
    }

    /// 「略過」：自動檢查不再提醒這個版本，有更新的版本時才提醒。
    func skip(_ release: Release) {
        defaults.set(release.version, forKey: Keys.skipped)
        notice = nil
    }

    /// 一鍵更新：update.sh prepare 下載並驗證新版（失敗不影響目前版本），
    /// 再啟動 update.sh install 並結束 App，由它取代 App 後重新開啟。
    func install(_ release: Release) async {
        guard !installing else { return }
        if let command = homebrewCommand { return await showHomebrew(release, command) }
        if let operation = blockingOperation() {
            await Dialog.ask(operation.busyTitle, "完成後再更新。")
            return
        }
        state = .working
        defer { state = nil }
        let app = Bundle.main.bundlePath
        do {
            try await prepare(release, app: app)
            try Scripts.spawnInstallUpdate(app: app)
        } catch {
            let choice = await Dialog.ask(
                "更新失敗", error.localizedDescription, buttons: ["手動下載", "好"], style: .warning)
            if choice == 0 { Workspace.open(release.page) }
            return
        }
        // 啟動流程進行中時 AppDelegate 會詢問；取消結束的話 update.sh install 等候逾時後放棄。
        NSApp.terminate(nil)
    }

    func copyHomebrewCommand() {
        if let homebrewCommand { Pasteboard.copy(homebrewCommand) }
    }

    // MARK: -

    /// 自動檢查：失敗時不打擾使用者，回傳 false；略過的版本不提醒。
    @discardableResult
    private func checkInBackground() async -> Bool {
        guard automatic, !checking else { return true }
        do {
            if let release = try await fetchNewer(), release.version != defaults.string(forKey: Keys.skipped) {
                notice = release
            }
            return true
        } catch {
            return false
        }
    }

    /// 比目前版本新的正式版；已是最新時回傳 nil。
    private func fetchNewer() async throws -> Release? {
        checking = true
        defer { checking = false }
        homebrewCommand = await Scripts.homebrewUpdateCommand(app: Bundle.main.bundlePath)
        let release = try await GitHubReleases.latest()
        return release.isNewer(than: appVersion) ? release : nil
    }

    /// Homebrew 安裝的 App 不自行取代，請使用者以 brew 更新（Homebrew 記錄的版本才會一致）。
    private func showHomebrew(_ release: Release, _ command: String) async {
        let choice = await Dialog.ask(
            "有新版本 \(release.version)",
            "目前版本 \(appVersion)。這個 App 是用 Homebrew 安裝的，請在「終端機」執行以下指令更新：\n\n\(command)",
            buttons: ["複製指令", "好"])
        if choice == 0 { copyHomebrewCommand() }
    }

    /// update.sh prepare：進度標記轉成 `state`，失敗時以最後一行錯誤訊息拋出。
    private func prepare(_ release: Release, app: String) async throws {
        let result = await Scripts.prepareUpdate(version: release.version, app: app).collect { event in
            switch event {
            case .progress(let fraction): state = fraction < 1 ? .downloading(fraction) : .working
            case .waiting: state = .waiting
            default: break
            }
        }
        if !result.ok { throw UserFacingError(result.lastError ?? "請稍後再試。") }
    }
}
