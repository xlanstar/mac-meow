import Foundation

/// 啟動、關閉與個別設定的流程。每個動作都交給 scripts/，這裡只做引導、對話框與進度顯示。
/// 對外的動作同一時間只執行一個（`operation`），流程中的對話框也算在內。
@MainActor
final class LaunchController: ObservableObject {
    @Published private(set) var phase: LaunchPhase = .idle
    @Published private(set) var operation: Operation?
    var busy: Bool { operation != nil }

    let status: StatusMonitor
    let config: ConfigStore
    let log: AppLog

    private static let prefixTimeout: TimeInterval = 360
    private static let prefixPollInterval: UInt64 = 2_000_000_000
    /// Cyder 建好 Windows 環境後還會寫入設定，稍等一下再繼續。
    private static let prefixSettleDelay: UInt64 = 5_000_000_000

    init(status: StatusMonitor, config: ConfigStore, log: AppLog) {
        self.status = status
        self.config = config
        self.log = log
    }

    // MARK: - 對外動作

    func start() async {
        await exclusive(.launch) { await launch() }
    }

    func restart() async {
        guard await stopAll() else { return }
        await start()
    }

    @discardableResult
    func stopAll() async -> Bool {
        await exclusive(.stop) {
            let choice = await Dialog.ask(
                "要關閉貓貓谷嗎？",
                "會關閉 Cyder 內所有正在執行的 Windows 程式，包含遊戲、登入器，以及其他 Cyder 遊戲。",
                buttons: ["全部關閉", "取消"], destructive: true)
            return choice == 0 ? await stop() : false
        } ?? false
    }

    func setupLoopback() async {
        await exclusive(.loopback) { _ = await installLoopback() }
    }

    func chooseGameDir() async {
        await exclusive(.chooseGameDir) { _ = await pickGameDir() }
    }

    func perform(_ action: ChecklistAction) {
        switch action {
        case .downloadCyder: Workspace.open(AppPaths.cyderDownload)
        case .revealCyder(let path): Workspace.reveal(URL(fileURLWithPath: path))
        case .openCyder: openCyder()
        case .chooseGameDir: Task { await chooseGameDir() }
        case .setupLoopback: Task { await setupLoopback() }
        }
    }

    func showLauncher() {
        if let pid = status.status.launcherPid { Workspace.activate(pid: pid) }
    }

    func openCyder() {
        if let path = status.status.cyderPath { Workspace.openApp(at: path) }
    }

    func dismissFailure() {
        if phase.failureMessage != nil { phase = .idle }
    }

    // MARK: - 給其他流程使用（呼叫者需已取得 operation）

    /// 沒有其他流程進行中時執行 `body`；否則回傳 nil。
    @discardableResult
    func exclusive<T>(_ operation: Operation, _ body: () async -> T) async -> T? {
        guard self.operation == nil else { return nil }
        self.operation = operation
        defer { self.operation = nil }
        return await body()
    }

    /// 顯示進度並執行腳本，輸出寫進記錄；結束後回到閒置。
    func runLogged(_ message: String, header: String, _ events: AsyncStream<ScriptEvent>) async -> ScriptResult {
        phase = .working(message)
        log.record("===== \(header) =====")
        let result = await events.collect(log.record)
        phase = .idle
        return result
    }

    /// 不詢問直接關閉所有 Windows 程式（play.sh stop）。
    func stop() async -> Bool {
        let result = await runLogged("正在關閉…", header: "全部關閉", Scripts.stop(env: config.config.environment))
        await status.refresh()
        guard result.ok else {
            fail(result.lastError ?? "關閉失敗。")
            return false
        }
        return true
    }

    // MARK: - 啟動流程

    private func launch() async {
        log.record("===== 啟動 =====")
        phase = .working("檢查環境…")
        var s = await status.refresh()
        guard s.loaded else { return fail("無法讀取目前的環境狀態，請稍後再試。") }

        guard s.cyderUsable, let cyder = s.cyderPath else {
            phase = .idle
            return await promptInstallCyder(inDownloads: s.cyderInDownloads)
        }
        if !s.gameDirValid {
            phase = .idle
            guard await pickGameDir() else { return }
            phase = .working("檢查環境…")
            s = await status.refresh()
        }
        // 記住實際使用的資料夾（沒選過時為 common.sh 的預設資料夾）
        if config.config.gameDir != s.gameDir { config.config.gameDir = s.gameDir }

        if s.running {
            guard await closeRunningSession() else { return }
        }
        if !s.cyderReady {
            guard await createPrefix(cyder: cyder) else { return }
        }
        if !s.loopback {
            guard await installLoopback() else { return }
        }
        await runPlay()
    }

    /// 已有登入器或遊戲在執行：詢問是否全部關閉後重新啟動。回傳是否繼續啟動。
    private func closeRunningSession() async -> Bool {
        var buttons = ["好", "全部關閉後重新啟動"]
        if status.status.launcherPid != nil { buttons.append("顯示登入器") }
        let choice = await Dialog.ask("貓貓谷已經在執行中", "登入器或遊戲視窗仍開著。", buttons: buttons)
        guard choice == 1 else {
            phase = .idle
            if choice == 2 { showLauncher() }
            return false
        }
        return await stop()
    }

    /// 第一次使用：開啟 Cyder，等它建立 Windows 環境。
    private func createPrefix(cyder: String) async -> Bool {
        phase = .working("第一次使用：正在讓 Cyder 建立 Windows 環境（約 1–3 分鐘）…", step: .prefix)
        log.record("開啟 Cyder 以建立 Windows 環境")
        Workspace.openApp(at: cyder)
        let deadline = Date().addingTimeInterval(Self.prefixTimeout)
        while !(await status.refresh()).cyderReady {
            guard Date() < deadline else {
                fail("Cyder 的 Windows 環境尚未建立完成。請開啟 Cyder 等它初始化完畢後，再按一次「開始遊戲」。", step: .prefix)
                return false
            }
            try? await Task.sleep(nanoseconds: Self.prefixPollInterval)
        }
        try? await Task.sleep(nanoseconds: Self.prefixSettleDelay)
        return true
    }

    /// play.sh：修補、VB6、Cyder 設定、啟動認證器並等待通道。
    private func runPlay() async {
        phase = .working("正在啟動貓貓谷…")
        let settings = config.config.settings
        let result = await Scripts.play(env: config.config.environment).collect { event in
            if case .step(let id, let message) = event { phase = .working(message, step: Step(progressID: id)) }
            log.record(event)
        }
        let lastStep = phase.activeStep
        await status.refresh()
        guard result.ok else { return fail(result.lastError ?? "啟動沒有完成。", step: lastStep) }
        phase = .idle
        config.markApplied(settings)
        log.record("完成：登入器已啟動")
    }

    // MARK: - 個別設定

    /// 以管理員權限執行 setup-loopback.sh install。回傳是否已設定完成。
    private func installLoopback() async -> Bool {
        let choice = await Dialog.ask(
            "設定本機網路位址",
            "貓貓谷的連線元件會使用 127.x.x.1 這類本機位址，macOS 預設沒有開啟。\n\n接下來會要求輸入電腦密碼，以加入這些本機位址並設定開機自動套用（只需一次）。",
            buttons: ["繼續", "取消"])
        guard choice == 0 else {
            if phase.isWorking { phase = .idle }
            return false
        }
        phase = .working("正在設定本機網路位址…", step: .loopback)
        log.record("設定本機網路位址（管理員權限）")
        let result = await Scripts.installLoopback().collect(log.record)
        guard await status.refresh().loopback else {
            fail(result.ok ? "網路設定失敗。" : "網路設定沒有完成（可能取消了密碼輸入）。", step: .loopback)
            return false
        }
        phase = .idle
        return true
    }

    /// 請使用者選擇遊戲資料夾；以 play.sh 檢查檔案是否齊全後才儲存。
    private func pickGameDir() async -> Bool {
        let current = status.status.gameDir
        guard
            let url = Workspace.chooseFolder(
                message: "選擇楓之谷遊戲資料夾（內含 MapleStory.exe，以及貓貓谷登入器的檔案）",
                startingAt: current.isEmpty ? AppPaths.home.path : current)
        else { return false }

        var env = config.config.environment
        env["GAME_DIR"] = url.path
        let s = await Scripts.status(env: env)
        guard s.gameDirValid else {
            await Dialog.ask(
                "這個資料夾缺少必要檔案",
                "「\(url.path.abbreviatingHome)」缺少 \(s.missingFile ?? "必要檔案")。\n\n資料夾內需要有 MapleStory.exe，以及貓貓谷登入器的檔案（認證器.exe、貓貓TMS登入器.exe、HostShield.exe、XCGUI.dll）。請把登入器壓縮檔的內容解壓縮到遊戲資料夾。",
                style: .warning)
            return false
        }
        config.config.gameDir = url.path
        log.record("遊戲資料夾：\(url.path)")
        return true
    }

    private func promptInstallCyder(inDownloads: Bool) async {
        if inDownloads {
            await Dialog.ask(
                "請把 Cyder 移到「應用程式」",
                "Cyder.app 目前在「下載項目」資料夾，macOS 會把它放到隔離位置執行，路徑不穩定。\n\n請把 Cyder.app 拖到「應用程式」資料夾，再按一次「開始遊戲」。")
        } else {
            let choice = await Dialog.ask(
                "需要先安裝 Cyder",
                "Cyder 是免費的 Wine 執行環境。請下載後把 Cyder.app 拖到「應用程式」資料夾，開啟一次讓它建立 Windows 環境，再回來按「開始遊戲」。",
                buttons: ["開啟下載頁", "取消"])
            if choice == 0 { Workspace.open(AppPaths.cyderDownload) }
        }
    }

    private func fail(_ message: String, step: Step? = nil) {
        phase = .failed(message, step: step)
        log.record("錯誤：\(message)")
    }
}
