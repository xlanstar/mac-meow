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

    private let logFile = LogFile()
    private var pollTask: Task<Void, Never>?
    private var refreshTask: Task<EnvStatus, Never>?

    var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

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
        guard !isWorking else { return }
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
            let choice = await Dialog.ask("貓貓谷已經在執行中", "登入器或遊戲視窗仍開著。",
                                          buttons: ["好", "全部關閉後重新啟動"])
            guard choice == 1 else { phase = .idle; return }
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
        var env = config.environment
        env["MACMEOW_PROGRESS"] = "1"
        var lastError: String?
        var exitCode: Int32 = -1
        for await event in Shell.script("play.sh", env: env) {
            switch event {
            case let .line(line, isError):
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
            case let .exit(code):
                exitCode = code
            }
        }
        let lastStep = activeStep
        activeStep = nil
        await refresh()
        if exitCode == 0 {
            phase = .launched
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
        let result = await run(Shell.stream("/usr/bin/osascript", [
            "-e", "on run argv",
            "-e", "do shell script \"/bin/bash \" & quoted form of (item 1 of argv) & \" install\" with administrator privileges",
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
            await Dialog.ask("請把 Cyder 移到「應用程式」",
                             "Cyder.app 目前在「下載項目」資料夾，macOS 會把它放到隔離位置執行，路徑不穩定。\n\n請把 Cyder.app 拖到「應用程式」資料夾，再按一次「開始遊戲」。")
        } else {
            let choice = await Dialog.ask("需要先安裝 Cyder",
                                          "Cyder 是免費的 Wine 執行環境。請下載後把 Cyder.app 拖到「應用程式」資料夾，開啟一次讓它建立 Windows 環境，再回來按「開始遊戲」。",
                                          buttons: ["開啟下載頁", "取消"])
            if choice == 0 { NSWorkspace.shared.open(AppPaths.cyderDownload) }
        }
    }

    func openCyder() {
        if let path = status.cyderPath { openApp(path) }
    }

    private func openApp(_ path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                           configuration: NSWorkspace.OpenConfiguration(),
                                           completionHandler: nil)
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
        guard case let .failed(message) = phase else { return reportBug() }
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
            case let .line(line, isError):
                record(isError ? "! \(line)" : line)
                if isError { result.errors.append(line) } else { result.lines.append(line) }
            case let .exit(code):
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
    static func ask(_ title: String, _ message: String, buttons: [String] = ["好"],
                    style: NSAlert.Style = .informational, destructive: Bool = false) async -> Int {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        buttons.forEach { alert.addButton(withTitle: $0) }
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
