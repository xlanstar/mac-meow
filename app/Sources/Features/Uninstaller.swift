import AppKit

/// 「解除安裝⋯」。Homebrew 安裝的 App 改為提示 brew 指令（cask 的 uninstall 區塊執行同一支 uninstall.sh）；
/// 其餘執行 uninstall.sh system（還原修補與設定、移除本機網路位址），成功後以 uninstall.sh stage 把
/// purge 複製到暫存資料夾（~/.Trash 受隱私權保護，App 無法從垃圾桶執行腳本），把 App 移到垃圾桶，
/// 再啟動 purge <PID> 並結束 App：設定與記錄等 App 結束後才刪除，App 結束時寫回的也會一併刪除。
@MainActor
final class Uninstaller {
    private let launch: LaunchController

    init(launch: LaunchController) {
        self.launch = launch
    }

    func run() async {
        await launch.exclusive(.uninstall) { await uninstall() }
    }

    private func uninstall() async {
        let app = Bundle.main.bundleURL
        if let command = await Scripts.uninstallBrewCommand(app: app) {
            return await showHomebrew(command)
        }
        let running = launch.status.status.running
        guard await confirm(stopsRunningPrograms: running) else { return }
        if running {
            guard await launch.stop() else { return }
        }

        let result = await launch.runLogged(
            "正在解除安裝…", header: "解除安裝", Scripts.uninstallSystem(env: launch.config.config.environment))
        guard result.ok else {
            await launch.status.refresh()
            await Dialog.ask(
                "解除安裝沒有完成",
                "\(result.lastError ?? "部分步驟失敗。")\n\n處理後可以再執行一次「解除安裝⋯」，已完成的步驟不會重複。",
                style: .warning)
            return
        }

        // 複製失敗時不移動 App，改從 App 內執行 purge
        let purge = await Scripts.stageUninstall()
        var trashed = false
        if purge != nil { trashed = (try? await NSWorkspace.shared.recycle([app])) != nil }
        await Dialog.ask("已解除安裝", "\(Self.removalNote(app: app, trashed: trashed))按「好」後結束。")
        // 在對話框之後才啟動：purge 等到 App 結束才刪除設定
        do {
            try Scripts.spawnPurge(script: purge)
        } catch {
            launch.log.record("錯誤：無法刪除 App 的設定與記錄：\(error.localizedDescription)")
        }
        NSApp.terminate(nil)
    }

    private func showHomebrew(_ command: String) async {
        let choice = await Dialog.ask(
            "請用 Homebrew 解除安裝",
            "這個 App 是用 Homebrew 安裝的，請在「終端機」執行以下指令（會自動結束 App）。會一併還原 Cyder 的修補與設定、移除本機網路位址（需要密碼），並刪除 App 的設定與記錄：\n\n\(command)",
            buttons: ["複製指令", "取消"])
        if choice == 0 { Pasteboard.copy(command) }
    }

    private func confirm(stopsRunningPrograms: Bool) async -> Bool {
        let stopNote = stopsRunningPrograms ? "會先關閉 Cyder 內所有正在執行的 Windows 程式（包含其他 Cyder 遊戲），再" : "會"
        let choice = await Dialog.ask(
            "要解除安裝貓貓谷 for Mac 嗎？",
            "\(stopNote)還原 Cyder engine 的修補與 Cyder 設定的原值、加回遊戲資料夾的下載隔離標記、移除本機網路位址（需要密碼），並刪除 App 的設定與記錄，最後把 App 移到垃圾桶。\n\n遊戲、Cyder 與其設定不會被刪除。",
            buttons: ["解除安裝", "取消"], destructive: true)
        return choice == 0
    }

    private static func removalNote(app: URL, trashed: Bool) -> String {
        if trashed { return "App 已移到垃圾桶。" }
        if app.path.contains("/AppTranslocation/") || app.path.hasPrefix("/Volumes/") {
            return "App 是從下載位置或磁碟映像直接開啟的，請在 App 結束後刪除你下載的 MacMeow.app。"
        }
        return "無法把 App 移到垃圾桶，請在 App 結束後手動刪除「\(app.path.abbreviatingHome)」。"
    }
}
