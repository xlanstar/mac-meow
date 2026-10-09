import SwiftUI

/// 可展開的「詳細記錄」。
struct LogSection: View {
    @ObservedObject var log: AppLog
    @Binding var isExpanded: Bool
    // 箭頭旋轉用獨立狀態驅動：withAnimation 只影響依賴此狀態的旋轉，
    // 不會連帶把視窗改變大小時的位置變化也做成動畫。
    @State private var chevronOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // 不用 withAnimation：視窗依內容改變高度時，若整個 VStack 一起做動畫，
                // 上方卡片會從舊位置滑動，而新插入的面板直接出現在最終位置，兩者短暫重疊。
                // 版面與視窗大小一次到位，只對箭頭與面板本身做淡入。
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(chevronOpen ? 90 : 0))
                        Text("詳細記錄").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                if isExpanded {
                    Button("複製") { log.copy() }
                    Button("在 Finder 中顯示") { log.reveal() }
                }
            }
            .buttonStyle(.link)
            .font(.caption)

            if isExpanded {
                LogPanel(lines: log.lines)
            }
        }
        .onAppear { chevronOpen = isExpanded }
        .onChange(of: isExpanded) { open in
            withAnimation(.easeInOut(duration: 0.2)) { chevronOpen = open }
        }
    }
}

private struct LogPanel: View {
    let lines: [AppLog.Line]
    @State private var appeared = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if lines.isEmpty {
                        Text("這次開啟還沒有記錄。完整記錄：~/Library/Logs/MacMeow/launcher.log")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(lines) { line in
                        Text(line.text)
                            .foregroundStyle(line.isError ? Color.red : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
            }
            .frame(height: 170)
            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            // 以最後一行的 id 判斷：記錄達到上限後行數不再變動
            .onChange(of: lines.last?.id) { id in
                if let id { proxy.scrollTo(id, anchor: .bottom) }
            }
            .onAppear {
                if let id = lines.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.2)) { appeared = true } }
    }
}
