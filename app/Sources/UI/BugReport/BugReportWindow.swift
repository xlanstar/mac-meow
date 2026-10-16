import SwiftUI

/// 「回報問題」視窗，App 唯一的視窗。開著時 App 暫時顯示在 Dock 與 ⌘Tab（視窗被擋住時可以切回來），
/// 關閉後回到只在選單列（Info.plist 的 LSUIElement）。
@MainActor
final class BugReportWindow: NSObject, NSWindowDelegate {
    private static let shared = BugReportWindow()
    private var window: NSWindow?

    /// 開啟視窗；已經開著時只帶到前面，不清掉填到一半的內容。
    static func show(context: BugReportContext, env: [String: String]) {
        shared.show(context: context, env: env)
    }

    private func show(context: BugReportContext, env: [String: String]) {
        let window = self.window ?? makeWindow(context: context, env: env)
        self.window = window
        NSApp.setActivationPolicy(.regular)
        bringAppToFront()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(context: BugReportContext, env: [String: String]) -> NSWindow {
        let view = BugReportView(context: context, env: env) { [weak self] in self?.window?.close() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable]
        window.title = "回報問題"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
