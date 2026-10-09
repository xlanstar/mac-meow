import AppKit

/// 檢查與安裝更新：讀取 GitHub 最新正式版（`releases/latest` 不含草稿與預先發行版），
/// 「更新」交給 scripts/update.sh 下載、驗證並取代 App 後重新開啟；
/// App 由 Homebrew 安裝時（`update.sh homebrew`）改為顯示 brew 的更新指令。
/// 偏好設定存在 App 的 UserDefaults（`tw.macmeow.launcher`，uninstall.sh 會刪除）。
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    struct Release: Equatable {
        var version: String
        /// GitHub Release 頁面（更新內容）。
        var page: URL
    }

    struct UpdateError: LocalizedError {
        var errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// 首頁橫幅與選單列提示的新版本；「略過」後清除。
    @Published private(set) var notice: Release?
    @Published private(set) var checking = false
    enum InstallState: Equatable {
        /// 連線、驗證或安裝中。
        case working
        /// 下載進度 0–1。
        case downloading(Double)
        /// 網路中斷，等待後從中斷處繼續下載。
        case waiting
    }

    /// App 由 Homebrew 安裝時的更新指令（`update.sh homebrew` 輸出）；nil 表示使用一鍵更新。每次檢查更新時重新判斷。
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

    private let defaults = UserDefaults.standard
    private var loop: Task<Void, Never>?

    private init() {
        automatic = defaults.object(forKey: Keys.automatic) as? Bool ?? true
    }

    /// App 啟動時呼叫：立即檢查一次，之後每 24 小時一次（App 常駐選單列時也會定期檢查）；
    /// 連不上 GitHub（例如離線）時 10 分鐘後再試。
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                let ok = await self?.checkInBackground() ?? true
                let minutes: UInt64 = ok ? 24 * 60 : 10
                try? await Task.sleep(nanoseconds: minutes * 60_000_000_000)
            }
        }
    }

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

    /// 選單「檢查更新⋯」：不論是否略過過此版本，都以對話框回報結果。
    func checkNow() async {
        do {
            guard let release = try await fetchNewer() else {
                await Dialog.ask("已是最新版本", "目前版本 \(appVersion)")
                return
            }
            notice = release
            if let command = homebrewCommand {
                await showHomebrew(release, command)
                return
            }
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

    // MARK: - 安裝

    /// 一鍵更新：update.sh prepare 下載並驗證新版（失敗不影響目前版本），
    /// 再啟動 update.sh install 並結束 App，由它取代 App 後重新開啟。
    func install(_ release: Release) async {
        guard !installing else { return }
        if let command = homebrewCommand {
            await showHomebrew(release, command)
            return
        }
        guard !Launcher.shared.isWorking else {
            await Dialog.ask("遊戲啟動中", "完成後再更新。")
            return
        }
        state = .working
        defer { state = nil }
        let app = Bundle.main.bundlePath
        do {
            try await prepare(release, app: app)
            try Shell.spawn("update.sh", ["install", app, String(ProcessInfo.processInfo.processIdentifier)])
        } catch {
            let choice = await Dialog.ask(
                "更新失敗", error.localizedDescription, buttons: ["手動下載", "好"], style: .warning)
            if choice == 0 { NSWorkspace.shared.open(release.page) }
            return
        }
        // 啟動流程進行中時 AppDelegate 會詢問；取消結束的話 update.sh install 等候逾時後放棄。
        NSApp.terminate(nil)
    }

    // MARK: - Homebrew

    /// Homebrew 安裝的 App 不自行取代，請使用者以 brew 更新（Homebrew 記錄的版本才會一致）。
    private func showHomebrew(_ release: Release, _ command: String) async {
        let choice = await Dialog.ask(
            "有新版本 \(release.version)",
            "目前版本 \(appVersion)。這個 App 是用 Homebrew 安裝的，請在「終端機」執行以下指令更新：\n\n\(command)",
            buttons: ["複製指令", "好"])
        if choice == 0 { copyHomebrewCommand() }
    }

    func copyHomebrewCommand() {
        guard let command = homebrewCommand else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    private func refreshInstallSource() async {
        let result = await Shell.collect(Shell.script("update.sh", ["homebrew", Bundle.main.bundlePath]))
        homebrewCommand = result.ok ? result.lines.last(where: { !$0.isEmpty }) : nil
    }

    /// update.sh prepare：把「@@PROGRESS <百分比>」與「@@WAIT」轉成 `state`，失敗時以最後一行錯誤訊息拋出。
    private func prepare(_ release: Release, app: String) async throws {
        var lastError = "請稍後再試。"
        // 下載網址由 update.sh 依版本號組成，不從 API 回應傳入
        let args = ["prepare", release.version, app]
        for await event in Shell.script("update.sh", args) {
            switch event {
            case .line(let line, let isError):
                if line.hasPrefix("@@PROGRESS "), let percent = Double(line.dropFirst(11)) {
                    state = percent < 100 ? .downloading(percent / 100) : .working
                } else if line == "@@WAIT" {
                    state = .waiting
                } else if isError, !line.isEmpty {
                    lastError = line
                }
            case .exit(let code):
                if code != 0 { throw UpdateError(lastError) }
            }
        }
    }

    // MARK: - GitHub API

    /// 比目前版本新的正式版；已是最新時回傳 nil。
    private func fetchNewer() async throws -> Release? {
        checking = true
        defer { checking = false }
        await refreshInstallSource()
        let release = try await Updater.latest()
        // 逐段數字比較（0.10.0 > 0.9.1）；版本號不是數字的開發版（"dev"）排在正式版之後，不會提示更新
        return release.version.compare(appVersion, options: .numeric) == .orderedDescending ? release : nil
    }

    private struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
        }
        let tagName: String
        let htmlUrl: URL
        let assets: [Asset]
    }

    nonisolated private static func latest() async throws -> Release {
        var request = URLRequest(url: AppPaths.latestRelease, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacMeow/\(appVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UpdateError("無法連線到 GitHub：\(error.localizedDescription)")
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 200 {
        case 200: break
        case 403, 429: throw UpdateError("GitHub 暫時限制了查詢次數，請稍後再試。")
        case let code: throw UpdateError("GitHub 回應錯誤（HTTP \(code)），請稍後再試。")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(Payload.self, from: data) else {
            throw UpdateError("GitHub 回應的內容無法解讀，請稍後再試。")
        }
        let version = payload.tagName.hasPrefix("v") ? String(payload.tagName.dropFirst()) : payload.tagName
        // update.sh 下載的附件（命名同 tools/release.sh）；還沒上傳完成的 Release 先不提示
        guard payload.assets.contains(where: { $0.name == "MacMeow-\(version).dmg" }) else {
            throw UpdateError("新版本 \(version) 尚未提供下載，請稍後再試。")
        }
        return Release(version: version, page: payload.htmlUrl)
    }
}
