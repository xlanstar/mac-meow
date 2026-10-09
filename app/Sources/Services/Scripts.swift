import Foundation

/// 打包在 App 內的 scripts/ 的所有呼叫。所有實際動作都在腳本內，App 只負責呼叫與顯示；
/// 指令與輸出格式見各腳本開頭的說明。
enum Scripts {
    // MARK: - play.sh

    /// `play.sh status --porcelain`；讀取失敗時 `loaded` 為 false。
    @MainActor
    static func status(env: [String: String]) async -> EnvStatus {
        EnvStatus(porcelain: await run("play.sh", ["status", "--porcelain"], env: env).collect().values)
    }

    /// `play.sh`：修補、VB6、Cyder 設定、啟動認證器並等待通道；以 @@STEP 回報進度。
    static func play(env: [String: String]) -> AsyncStream<ScriptEvent> {
        run("play.sh", env: env.merging(["MACMEOW_PROGRESS": "1"]) { _, new in new })
    }

    /// `play.sh stop`：關閉 Cyder shared bottle 內所有 Windows 程式。
    static func stop(env: [String: String]) -> AsyncStream<ScriptEvent> {
        run("play.sh", ["stop"], env: env)
    }

    // MARK: - setup-loopback.sh

    /// 以管理員權限（系統密碼對話框）執行 `setup-loopback.sh install`。
    static func installLoopback() -> AsyncStream<ScriptEvent> {
        ProcessRunner.stream(
            "/usr/bin/osascript",
            [
                "-e", "on run argv",
                "-e",
                "do shell script \"/bin/bash \" & quoted form of (item 1 of argv) & \" install\" with administrator privileges",
                "-e", "end run",
                AppPaths.script("setup-loopback.sh"),
            ])
    }

    // MARK: - uninstall.sh

    /// App 由 Homebrew 安裝時，解除安裝用的 brew 指令；否則 nil。
    @MainActor
    static func uninstallBrewCommand(app: URL) async -> String? {
        let result = await run("uninstall.sh", ["brew-command", app.path]).collect()
        return result.ok ? result.lastLine : nil
    }

    /// `uninstall.sh system`：還原修補與設定、移除本機網路位址。
    static func uninstallSystem(env: [String: String]) -> AsyncStream<ScriptEvent> {
        run("uninstall.sh", ["system"], env: env)
    }

    /// `uninstall.sh stage`：把 purge 複製到 App 外的暫存資料夾，回傳其路徑。
    @MainActor
    static func stageUninstall() async -> String? {
        let result = await run("uninstall.sh", ["stage"]).collect()
        return result.ok ? result.lastLine : nil
    }

    /// 啟動 `uninstall.sh purge <PID>`：等 App 結束後刪除設定與記錄。
    /// `script` 為 `stageUninstall()` 的路徑；nil 時使用 App 內的腳本。
    static func spawnPurge(script: String?) throws {
        try ProcessRunner.spawn("/bin/bash", [script ?? AppPaths.script("uninstall.sh"), "purge", currentPID])
    }

    // MARK: - update.sh

    /// `update.sh brew-command`：App 由 Homebrew 安裝時，更新用的 brew 指令；否則 nil。
    @MainActor
    static func homebrewUpdateCommand(app: String) async -> String? {
        let result = await run("update.sh", ["brew-command", app]).collect()
        return result.ok ? result.lastLine : nil
    }

    /// `update.sh prepare`：下載並驗證新版（網址由 update.sh 依版本號組成）；以 @@PROGRESS、@@WAIT 回報進度。
    static func prepareUpdate(version: String, app: String) -> AsyncStream<ScriptEvent> {
        run("update.sh", ["prepare", version, app])
    }

    /// 啟動 `update.sh install`：等 App 結束後取代 App 並重新開啟。
    static func spawnInstallUpdate(app: String) throws {
        try ProcessRunner.spawn("/bin/bash", [AppPaths.script("update.sh"), "install", app, currentPID])
    }

    // MARK: - report.sh

    /// 環境摘要（已隱藏家目錄與使用者名稱）。
    static func reportSummary(env: [String: String]) -> AsyncStream<ScriptEvent> {
        run("report.sh", env: env)
    }

    /// App 記錄的最後 `lines` 行（已隱藏個人資訊）。
    static func reportLog(lines: Int, env: [String: String]) -> AsyncStream<ScriptEvent> {
        run("report.sh", ["log", AppPaths.logFile.path, String(lines)], env: env)
    }

    /// 把診斷檔打包成 `output`（zip）。
    static func reportBundle(to output: URL, env: [String: String]) -> AsyncStream<ScriptEvent> {
        run("report.sh", ["bundle", output.path, AppPaths.logFile.path], env: env)
    }

    // MARK: -

    private static var currentPID: String { String(ProcessInfo.processInfo.processIdentifier) }

    private static func run(_ name: String, _ args: [String] = [], env: [String: String] = [:])
        -> AsyncStream<ScriptEvent>
    {
        ProcessRunner.stream("/bin/bash", [AppPaths.script(name)] + args, env: env)
    }
}
