import SwiftUI

/// 有新版本時的首頁橫幅。
struct UpdateBanner: View {
    @ObservedObject var updater: Updater
    let release: Release
    /// Homebrew 安裝時按下「複製指令」後短暫顯示「已複製」。
    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("新版本 \(release.version)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                if let command = updater.homebrewCommand {
                    Text("在終端機執行：\(command)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Link("更新內容", destination: release.page)
                    .font(.caption)
            }
            Spacer(minLength: 8)
            switch updater.state {
            case .downloading(let progress):
                ProgressView(value: progress).tint(Theme.orange).frame(width: 90)
                Text("\(Int(progress * 100))%")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            case .waiting, .working:
                ProgressView().controlSize(.small)
                Text(updater.state == .waiting ? "等待網路…" : "更新中…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case nil:
                Button("略過") { updater.skip(release) }
                    .buttonStyle(.link)
                    .font(.callout)
                if updater.homebrewCommand != nil {
                    Button(copied ? "已複製" : "複製指令") { copy() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.orange)
                } else {
                    Button("更新") { Task { await updater.install(release) } }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.orange)
                }
            }
        }
        .modifier(Card(padding: 14))
    }

    private func copy() {
        updater.copyHomebrewCommand()
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copied = false
        }
    }
}
