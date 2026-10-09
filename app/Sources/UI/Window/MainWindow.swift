import SwiftUI

/// 主視窗：左上角關閉鈕（與 ⌘W）改為隱藏視窗並從 Dock 移除 App 圖示，
/// App 與選單列圖示保持執行；從選單列叫回時再顯示於 Dock。
@MainActor
final class MainWindow: NSObject {
    /// SwiftUI `Window` scene 的 id。
    static let sceneID = "main"
    private static let shared = MainWindow()
    private weak var window: NSWindow?
    /// 視窗被 `hide` 收起（仍存在，只是不在畫面上）。
    private var hidden = false

    fileprivate static func attach(_ window: NSWindow) {
        shared.window = window
        // performClose（⌘W）也會經過關閉鈕，所以只改按鈕動作即可。按鈕的 target 是 weak，由 shared 持有。
        if let close = window.standardWindowButton(.closeButton) {
            close.target = shared
            close.action = #selector(hide(_:))
        }
    }

    @objc private func hide(_ sender: Any?) {
        guard let window else { return }
        hidden = true
        window.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    /// 叫回主視窗：恢復 Dock 圖示並帶到最前面；視窗不存在時以 `openWindow` 重新開啟。
    /// 回傳是否已顯示（沒有 `openWindow` 且視窗已不存在時回傳 false）。
    @discardableResult
    static func show(_ openWindow: OpenWindowAction? = nil) -> Bool {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = shared.window, shared.hidden || window.isVisible || window.isMiniaturized {
            shared.hidden = false
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            return true
        }
        guard let openWindow else { return false }
        openWindow(id: sceneID)
        return true
    }
}

/// 放在主視窗內容的背景，取得所在的 NSWindow 交給 `MainWindow`；
/// 並回報內容區最多可用的高度（螢幕可用區域扣掉標題列），視窗變大時保持在螢幕內。
struct MainWindowAccessor: NSViewRepresentable {
    var onMaxContentHeight: (CGFloat) -> Void = { _ in }

    final class AccessorView: NSView {
        var onMaxContentHeight: (CGFloat) -> Void = { _ in }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let center = NotificationCenter.default
            center.removeObserver(self)
            guard let window else { return }
            MainWindow.attach(window)
            center.addObserver(
                self, selector: #selector(screenChanged), name: NSWindow.didChangeScreenNotification, object: window)
            center.addObserver(
                self, selector: #selector(screenChanged),
                name: NSApplication.didChangeScreenParametersNotification, object: nil)
            center.addObserver(
                self, selector: #selector(windowResized), name: NSWindow.didResizeNotification, object: window)
            // 不在 SwiftUI 版面更新途中改狀態
            DispatchQueue.main.async { [weak self] in self?.screenChanged() }
        }

        @objc private func screenChanged() {
            guard let window, let screen = window.screen ?? NSScreen.main else { return }
            let titleBar = window.frame.height - window.contentLayoutRect.height
            onMaxContentHeight(max(screen.visibleFrame.height - titleBar, 200))
            windowResized()
        }

        /// 內容變高時 AppKit 固定視窗左上角往下長，可能超出螢幕底部（Dock）；往上移回可用區域。
        @objc private func windowResized() {
            guard let window, let screen = window.screen ?? NSScreen.main else { return }
            let visible = screen.visibleFrame
            let frame = window.frame
            let y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
            if y != frame.minY { window.setFrameOrigin(NSPoint(x: frame.minX, y: y)) }
        }
    }

    func makeNSView(context: Context) -> AccessorView {
        let view = AccessorView()
        view.onMaxContentHeight = onMaxContentHeight
        return view
    }

    func updateNSView(_ nsView: AccessorView, context: Context) {
        nsView.onMaxContentHeight = onMaxContentHeight
    }
}
