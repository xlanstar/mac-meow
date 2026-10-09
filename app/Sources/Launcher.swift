import AppKit

/// App 的狀態與流程。每個動作都交給 scripts/（play.sh、setup-loopback.sh），這裡只做引導與顯示。
@MainActor
final class Launcher: ObservableObject {
    static let shared = Launcher()

    enum Phase: Equatable {
        case idle
        case working(String)
        case launched
        case failed(String)
    }

    @Published private(set) var status = EnvStatus()
    @Published private(set) var phase: Phase = .idle
    /// 目前正在處理的清單項目（顯示轉圈）。
    @Published private(set) var activeStep: Step?
    @Published private(set) var failedStep: Step?
    @Published private(set) var log: [String] = []
    @Published var showLog = false
    /// 「回報問題」視窗；非 nil 時在主視窗以 sheet 顯示。
    @Published var bugReport: BugReportContext?
    @Published var config = AppConfig.load() {
        didSet {
            guard config != oldValue else { return }
            config.save()
            Task { await refresh() }
        }
    }
    /// 上次成功「開始遊戲」時套用的設定；與 config 不同表示有尚未套用的變更。
    @Published private(set) var applied = AppConfig.load()
    var settingsDirty: Bool {
        config.sync != applied.sync || config.graphics != applied.graphics || config.hud != applied.hud
            || config.frameRate != applied.frameRate
            || config.autoClose != applied.autoClose
    }

    private let logFile = LogFile()
    private var pollTask: Task<Void, Never>?
    private var refreshTask: Task<EnvStatus, Never>?

    var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }
    /// 「解除安裝⋯」進行中（含對話框）；這段期間不能開始遊戲、更新或設定網路位址。
    @Published private(set) var uninstalling = false
    /// 有流程在進行：啟動、關閉或解除安裝。
    var busy: Bool { isWorking || uninstalling }

    // MARK: - 狀態

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    @discardableResult
    func refresh() async -> EnvStatus {
        if let refreshTask { return await refreshTask.value }
        let env = config.environment
        let task = Task.detached { await Launcher.queryStatus(env: env) }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        if result.loaded { status = result }
        return result.loaded ? result : status
    }

    nonisolated static func queryStatus(env: [String: String]) async -> EnvStatus {
        let result = await Shell.collect(Shell.script("play.sh", ["status", "--porcelain"], env: env))
        return EnvStatus(porcelain: result.values)
    }

    // MARK: - 啟動流程

    func start() async {
        guard !busy else { return }
        failedStep = nil
        phase = .working("檢查環境…")
        record("===== 啟動 =====")
        var s = await refresh()

        // 1. Cyder
        guard s.cyderUsable, let cyder = s.cyderPath else {
            phase = .idle
            await promptInstallCyder(inDownloads: s.cyderInDownloads)
            return
        }

        // 2. 遊戲資料夾（優先：上次選擇 → 預設 ~/Games/MapleStory → 請使用者選擇）
        if !s.gameDirValid {
            phase = .idle
            guard await chooseGameDir() else { return }
            phase = .working("檢查環境…")
            s = await refresh()
        }
        if config.gameDir != s.gameDir { config.gameDir = s.gameDir }

        // 3. 已在執行
        if s.running {
            var buttons = ["好", "全部關閉後重新啟動"]
            if s.launcherPid != nil { buttons.append("顯示登入器") }
            let choice = await Dialog.ask("貓貓谷已經在執行中", "登入器或遊戲視窗仍開著。", buttons: buttons)
            guard choice == 1 else {
                phase = .idle
                if choice == 2 { showLauncher() }
                return
            }
            guard await stopAll(confirm: false) else { return }
        }

        // 4. 第一次使用：讓 Cyder 建立 Windows 環境
        if !s.cyderReady {
            activeStep = .prefix
            phase = .working("第一次使用：正在讓 Cyder 建立 Windows 環境（約 1–3 分鐘）…")
            record("開啟 Cyder 以建立 Windows 環境")
            openApp(cyder)
            let deadline = Date().addingTimeInterval(360)
            while !(await refresh()).cyderReady {
                guard Date() < deadline else {
                    return fail(.prefix, "Cyder 的 Windows 環境尚未建立完成。請開啟 Cyder 等它初始化完畢後，再按一次「開始遊戲」。")
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            activeStep = nil
        }

        // 5. 本機網路位址（需要管理員權限，只需一次）
        if !s.loopback {
            guard await setupLoopback() else { return }
        }

        // 6. play.sh：修補、VB6、Cyder 設定、啟動認證器並等待通道
        phase = .working("正在啟動貓貓谷…")
        let launched = config
        var env = config.environment
        env["MACMEOW_PROGRESS"] = "1"
        var lastError: String?
        var exitCode: Int32 = -1
        for await event in Shell.script("play.sh", env: env) {
            switch event {
            case .line(let line, let isError):
                if line.hasPrefix("@@STEP ") {
                    let parts = line.dropFirst(7).split(separator: " ", maxSplits: 1)
                    let message = parts.count > 1 ? String(parts[1]) : ""
                    activeStep = Step.fromProgress(parts.first.map(String.init) ?? "")
                    phase = .working(message)
                    record(message)
                } else {
                    record(isError ? "! \(line)" : line)
                    if isError, !line.trimmingCharacters(in: .whitespaces).isEmpty { lastError = line }
                }
            case .exit(let code):
                exitCode = code
            }
        }
        let lastStep = activeStep
        activeStep = nil
        await refresh()
        if exitCode == 0 {
            phase = .launched
            applied = launched
            record("完成：登入器已啟動")
        } else {
            fail(lastStep, lastError ?? "啟動沒有完成。")
        }
    }

    func restart() async {
        guard await stopAll() else { return }
        await start()
    }

    /// 關閉 Cyder shared bottle 內所有 Windows 程式（play.sh stop）。
    @discardableResult
    func stopAll(confirm: Bool = true) async -> Bool {
        if confirm {
            let choice = await Dialog.ask(
                "要關閉貓貓谷嗎？",
                "會關閉 Cyder 內所有正在執行的 Windows 程式，包含遊戲、登入器，以及其他 Cyder 遊戲。",
                buttons: ["全部關閉", "取消"], destructive: true)
            guard choice == 0 else { return false }
        }
        phase = .working("正在關閉…")
        record("===== 全部關閉 =====")
        let result = await run(Shell.script("play.sh", ["stop"], env: config.environment))
        await refresh()
        guard result.ok else {
            fail(nil, result.errors.last ?? "關閉失敗。")
            return false
        }
        phase = .idle
        return true
    }

    // MARK: - 個別設定

    /// 以管理員權限執行 setup-loopback.sh install。
    @discardableResult
    func setupLoopback() async -> Bool {
        guard !uninstalling else { return false }
        let choice = await Dialog.ask(
            "設定本機網路位址",
            "貓貓谷的連線元件會使用 127.x.x.1 這類本機位址，macOS 預設沒有開啟。\n\n接下來會要求輸入電腦密碼，以加入這些本機位址並設定開機自動套用（只需一次）。",
            buttons: ["繼續", "取消"])
        guard choice == 0 else {
            if isWorking { phase = .idle }
            return false
        }
        let wasWorking = isWorking
        activeStep = .loopback
        failedStep = nil
        phase = .working("正在設定本機網路位址…")
        record("設定本機網路位址（管理員權限）")
        let result = await run(
            Shell.stream(
                "/usr/bin/osascript",
                [
                    "-e", "on run argv",
                    "-e",
                    "do shell script \"/bin/bash \" & quoted form of (item 1 of argv) & \" install\" with administrator privileges",
                    "-e", "end run",
                    AppPaths.script("setup-loopback.sh"),
                ]))
        let s = await refresh()
        activeStep = nil
        guard s.loopback else {
            fail(.loopback, result.ok ? "網路設定失敗。" : "網路設定沒有完成（可能取消了密碼輸入）。")
            return false
        }
        if !wasWorking { phase = .idle }
        return true
    }

    /// 請使用者選擇遊戲資料夾；以 play.sh 檢查檔案是否齊全後才儲存。
    @discardableResult
    func chooseGameDir() async -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "選擇"
        panel.message = "選擇楓之谷遊戲資料夾（內含 MapleStory.exe，以及貓貓谷登入器的檔案）"
        panel.directoryURL = URL(fileURLWithPath: status.gameDir.isEmpty ? AppPaths.home.path : status.gameDir)
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        var env = config.environment
        env["GAME_DIR"] = url.path
        let s = await Launcher.queryStatus(env: env)
        guard s.gameDirValid else {
            await Dialog.ask(
                "這個資料夾缺少必要檔案",
                "「\(abbreviate(url.path))」缺少 \(s.missingFile ?? "必要檔案")。\n\n資料夾內需要有 MapleStory.exe，以及貓貓谷登入器的檔案（認證器.exe、貓貓TMS登入器.exe、HostShield.exe、XCGUI.dll）。請把登入器壓縮檔的內容解壓縮到遊戲資料夾。",
                style: .warning)
            return false
        }
        config.gameDir = url.path
        record("遊戲資料夾：\(url.path)")
        return true
    }

    func promptInstallCyder(inDownloads: Bool) async {
        if inDownloads {
            await Dialog.ask(
                "請把 Cyder 移到「應用程式」",
                "Cyder.app 目前在「下載項目」資料夾，macOS 會把它放到隔離位置執行，路徑不穩定。\n\n請把 Cyder.app 拖到「應用程式」資料夾，再按一次「開始遊戲」。")
        } else {
            let choice = await Dialog.ask(
                "需要先安裝 Cyder",
                "Cyder 是免費的 Wine 執行環境。請下載後把 Cyder.app 拖到「應用程式」資料夾，開啟一次讓它建立 Windows 環境，再回來按「開始遊戲」。",
                buttons: ["開啟下載頁", "取消"])
            if choice == 0 { NSWorkspace.shared.open(AppPaths.cyderDownload) }
        }
    }

    /// 把登入器帶到前景；Wine 會在程式被啟用時還原縮到最小的視窗。
    func showLauncher() {
        guard let pid = status.launcherPid,
            let app = NSRunningApplication(processIdentifier: pid)
        else { return }
        app.activate(options: [.activateAllWindows])
    }

    func openCyder() {
        if let path = status.cyderPath { openApp(path) }
    }

    private func openApp(_ path: String) {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: path),
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil)
    }

    // MARK: - 解除安裝

    /// 「解除安裝⋯」。Homebrew 安裝的 App 改為提示 brew 指令（cask 的 uninstall 區塊執行同一支 uninstall.sh）；
    /// 其餘執行 uninstall.sh system（還原修補與設定、移除本機網路位址），成功後以 uninstall.sh stage 把
    /// purge 複製到暫存資料夾（~/.Trash 受隱私權保護，App 無法從垃圾桶執行腳本），把 App 移到垃圾桶，
    /// 再啟動 purge <PID> 並結束 App：設定與記錄等 App 結束後才刪除，App 結束時寫回的也會一併刪除。
    func uninstall() async {
        guard !busy else { return }
        uninstalling = true
        defer { uninstalling = false }
        let app = Bundle.main.bundleURL
        let brew = await Shell.collect(Shell.script("uninstall.sh", ["brew-command", app.path]))
        if brew.ok, let command = brew.lines.last(where: { !$0.isEmpty }) {
            let choice = await Dialog.ask(
                "請用 Homebrew 解除安裝",
                "這個 App 是用 Homebrew 安裝的，請在「終端機」執行以下指令（會自動結束 App）。會一併還原 Cyder 的修補與設定、移除本機網路位址（需要密碼），並刪除 App 的設定與記錄：\n\n\(command)",
                buttons: ["複製指令", "取消"])
            if choice == 0 {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }
            return
        }

        let stopNote = status.running ? "會先關閉 Cyder 內所有正在執行的 Windows 程式（包含其他 Cyder 遊戲），再" : "會"
        let choice = await Dialog.ask(
            "要解除安裝貓貓谷 for Mac 嗎？",
            "\(stopNote)還原 Cyder engine 的修補與 Cyder 設定的原值、加回遊戲資料夾的下載隔離標記、移除本機網路位址（需要密碼），並刪除 App 的設定與記錄，最後把 App 移到垃圾桶。\n\n遊戲、Cyder 與其設定不會被刪除。",
            buttons: ["解除安裝", "取消"], destructive: true)
        guard choice == 0 else { return }
        if status.running {
            guard await stopAll(confirm: false) else { return }
        }

        failedStep = nil
        phase = .working("正在解除安裝…")
        record("===== 解除安裝 =====")
        let result = await run(Shell.script("uninstall.sh", ["system"], env: config.environment))
        phase = .idle
        guard result.ok else {
            await refresh()
            await Dialog.ask(
                "解除安裝沒有完成",
                "\(result.errors.last ?? "部分步驟失敗。")\n\n處理後可以再執行一次「解除安裝⋯」，已完成的步驟不會重複。",
                style: .warning)
            return
        }

        // 複製失敗時不移動 App，改從 App 內執行 purge
        let staged = await Shell.collect(Shell.script("uninstall.sh", ["stage"]))
        let purge = staged.ok ? staged.lines.last(where: { !$0.isEmpty }) : nil
        var trashed = false
        if purge != nil {
            trashed = (try? await NSWorkspace.shared.recycle([app])) != nil
        }
        let message: String
        if trashed {
            message = "App 已移到垃圾桶。"
        } else if app.path.contains("/AppTranslocation/") || app.path.hasPrefix("/Volumes/") {
            message = "App 是從下載位置或磁碟映像直接開啟的，請在 App 結束後刪除你下載的 MacMeow.app。"
        } else {
            message = "無法把 App 移到垃圾桶，請在 App 結束後手動刪除「\(abbreviate(app.path))」。"
        }
        await Dialog.ask("已解除安裝", "\(message)按「好」後結束。")
        // 在對話框之後才啟動：purge 等到 App 結束才刪除設定
        do {
            try Shell.spawn(
                path: purge ?? AppPaths.script("uninstall.sh"),
                ["purge", String(ProcessInfo.processInfo.processIdentifier)])
        } catch {
            record("錯誤：無法刪除 App 的設定與記錄：\(error.localizedDescription)")
        }
        uninstalling = false
        NSApp.terminate(nil)
    }

    // MARK: - 記錄

    func openLog() { NSWorkspace.shared.open(AppPaths.logFile) }
    func revealLog() { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.logFile]) }
    func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(log.joined(separator: "\n"), forType: .string)
    }

    // MARK: - 回報問題

    func reportBug() {
        bugReport = BugReportContext()
    }

    /// 從啟動失敗畫面回報：帶入失敗的步驟與錯誤訊息。
    func reportFailure() {
        guard case .failed(let message) = phase else { return reportBug() }
        let step = failedStep.map { "在「\($0.title)」步驟" } ?? ""
        bugReport = BugReportContext(category: .launch, details: "啟動\(step)失敗，App 顯示：\n\(message)\n\n")
    }

    func dismissFailure() {
        if case .failed = phase { phase = .idle }
        failedStep = nil
    }

    private func record(_ line: String) {
        logFile.write(line)
        log.append(line)
        if log.count > 1000 { log.removeFirst(log.count - 1000) }
    }

    private func fail(_ step: Step?, _ message: String) {
        failedStep = step
        activeStep = nil
        phase = .failed(message)
        record("錯誤：\(message)")
    }

    /// 執行並把輸出寫進記錄。
    private func run(_ events: AsyncStream<ShellEvent>) async -> ShellResult {
        var result = ShellResult()
        for await event in events {
            switch event {
            case .line(let line, let isError):
                record(isError ? "! \(line)" : line)
                if isError { result.errors.append(line) } else { result.lines.append(line) }
            case .exit(let code):
                result.status = code
            }
        }
        return result
    }
}

/// NSAlert（有視窗時以 sheet 顯示）。回傳按下的按鈕索引。
@MainActor
enum Dialog {
    @discardableResult
    static func ask(
        _ title: String, _ message: String, buttons: [String] = ["好"],
        style: NSAlert.Style = .informational, destructive: Bool = false
    ) async -> Int {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        for title in buttons { alert.addButton(withTitle: title) }
        if destructive { alert.buttons.first?.hasDestructiveAction = true }
        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) {
            response = await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            }
        } else {
            response = alert.runModal()
        }
        return response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }
}
