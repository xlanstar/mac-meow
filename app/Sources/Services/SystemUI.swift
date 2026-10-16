import AppKit

/// NSAlert，一律以獨立的對話框顯示：App 只在選單列，沒有可以掛 sheet 的主視窗。
@MainActor
enum Dialog {
    /// 回傳按下的按鈕索引。
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
        bringAppToFront()
        let response = alert.runModal()
        return response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }

    /// 同步詢問（`applicationShouldTerminate` 等需要立即回答的地方）；回傳是否按下 `confirm`。
    static func confirmNow(_ title: String, _ message: String, confirm: String, cancel: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: cancel)
        alert.addButton(withTitle: confirm)
        bringAppToFront()
        return alert.runModal() == .alertSecondButtonReturn
    }
}

/// 選單列 App 沒有 Dock 圖示，不會因為顯示對話框就到前景；不先啟用的話對話框會被其他 App 擋住。
@MainActor
func bringAppToFront() {
    NSApp.activate(ignoringOtherApps: true)
}

@MainActor
enum Pasteboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

@MainActor
enum Workspace {
    static func open(_ url: URL) { NSWorkspace.shared.open(url) }

    static func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    static func openApp(at path: String) {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    /// 把程式帶到前景；Wine 會在程式被啟用時還原縮到最小的視窗。
    static func activate(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
    }

    /// 讓使用者選一個資料夾；取消時回傳 nil。
    static func chooseFolder(message: String, startingAt directory: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "選擇"
        panel.message = message
        panel.directoryURL = URL(fileURLWithPath: directory)
        bringAppToFront()
        return panel.runModal() == .OK ? panel.url : nil
    }
}
