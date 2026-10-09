import SwiftUI

/// 卡片的小標題（「環境檢查」、「遊戲設定」）。
struct CardTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
    }
}

/// 卡片中的一列：左邊圖示、標題（可附說明），右邊放控制項。
struct CardRow<Detail: View, Accessory: View>: View {
    let symbol: String
    let title: String
    var help: String?
    @ViewBuilder var detail: Detail
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if let help {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .help(help)
                    }
                }
                detail
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.vertical, 7)
    }
}

extension CardRow where Detail == EmptyView {
    init(symbol: String, title: String, help: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.init(symbol: symbol, title: title, help: help, detail: { EmptyView() }, accessory: accessory)
    }
}
