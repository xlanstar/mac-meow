import SwiftUI

/// 「環境檢查」清單。
struct ChecklistCard: View {
    let state: HomePresentation
    let launch: LaunchController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle("環境檢查").padding(.bottom, 6)
            ForEach(state.checklist) { item in
                if item.step != state.checklist.first?.step { Divider().padding(.leading, 34) }
                ChecklistRow(item: item, disabled: state.busy) { launch.perform($0) }
            }
        }
        .modifier(Card(padding: 14))
    }
}

private struct ChecklistRow: View {
    let item: ChecklistItem
    let disabled: Bool
    let perform: (ChecklistAction) -> Void

    var body: some View {
        CardRow(symbol: item.step.symbol, title: item.step.title) {
            Text(item.detail)
                .font(.caption)
                .foregroundStyle(item.state == .action || item.state == .failed ? Color.orange : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(item.detail)
        } accessory: {
            if let action = item.action {
                Button(action.title) { perform(action) }
                    .controlSize(.small)
                    .disabled(disabled)
            }
            StateBadge(state: item.state).frame(width: 18)
        }
    }
}

private struct StateBadge: View {
    let state: ChecklistItem.State

    var body: some View {
        switch state {
        case .working:
            ProgressView().controlSize(.mini)
        case .ok:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok)
        case .todo:
            Image(systemName: "circle.dotted").foregroundStyle(.secondary)
                .help("按「開始遊戲」時自動處理")
        case .action:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .unknown:
            Image(systemName: "ellipsis.circle").foregroundStyle(.tertiary)
        }
    }
}
