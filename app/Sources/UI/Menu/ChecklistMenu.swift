import SwiftUI

/// 「環境檢查」子選單：每一項的狀態，以及各項可以手動執行的動作。
struct ChecklistMenu: View {
    let state: HomePresentation
    let perform: (ChecklistAction) -> Void

    var body: some View {
        Menu("環境檢查") {
            ForEach(state.checklist) { item in
                Text("\(Self.mark(item.state))  \(item.step.title)：\(item.detail)")
            }
            if state.checklist.contains(where: { $0.state == .todo }) {
                Text("○ 表示按「開始遊戲」時自動處理")
            }
            let actions = state.checklist.compactMap(\.action)
            if !actions.isEmpty {
                Divider()
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    Button(action.title) { perform(action) }
                        .disabled(state.busy)
                }
            }
        }
    }

    /// 選單項目不一定顯示圖示，狀態以文字符號表示。
    private static func mark(_ state: ChecklistItem.State) -> String {
        switch state {
        case .ok: return "✓"
        case .todo: return "○"
        case .action: return "⚠︎"
        case .working: return "…"
        case .failed: return "✗"
        case .unknown: return "－"
        }
    }
}
