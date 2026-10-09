import SwiftUI

/// 主卡片：整體狀態、連線通道與主要動作。
struct StatusCard: View {
    let state: HomePresentation
    let launch: LaunchController
    let onShowLog: () -> Void
    let onReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                SummaryIcon(summary: state.summary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.summary.title).font(.system(size: 17, weight: .semibold, design: .rounded))
                    if state.failed { failureActions }
                }
                Spacer(minLength: 0)
            }
            if state.showsTunnelMeter {
                TunnelMeter(count: state.tunnels, total: state.tunnelsTotal)
            }
            actions
        }
        .modifier(Card(padding: 18))
        .animation(.easeInOut(duration: 0.2), value: state.summary.title)
    }

    private var failureActions: some View {
        HStack(spacing: 12) {
            Button("查看詳細記錄", action: onShowLog)
            Button("回報此問題", action: onReport)
            Button("知道了") { launch.dismissFailure() }
        }
        .buttonStyle(.link)
        .font(.callout)
        .padding(.top, 2)
    }

    @ViewBuilder private var actions: some View {
        if state.showsStop {
            HStack(spacing: 10) {
                Button {
                    Task { await launch.stopAll() }
                } label: {
                    Label("全部關閉", systemImage: "stop.fill")
                }
                .buttonStyle(SecondaryButtonStyle(tint: .red))
                Button {
                    Task { await launch.restart() }
                } label: {
                    Label("重新啟動", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        } else {
            Button {
                Task { await launch.start() }
            } label: {
                HStack(spacing: 8) {
                    if let progress = state.progressLabel {
                        ProgressView().controlSize(.small).colorScheme(.dark)
                        Text(progress)
                    } else {
                        Image(systemName: "play.fill")
                        Text("開始遊戲")
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!state.canStart)
            .keyboardShortcut(.defaultAction)
        }
    }
}

private struct SummaryIcon: View {
    let summary: StatusSummary

    var body: some View {
        let tint = Theme.color(summary.tone)
        ZStack {
            Circle().fill(tint.opacity(0.16))
            if summary.busy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: summary.symbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 46, height: 46)
    }
}

private struct TunnelMeter: View {
    let count: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: Step.tunnels.symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Step.tunnels.title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(0..<max(total, 1), id: \.self) { i in
                    Capsule()
                        .fill(i < count ? Theme.ok : Color.primary.opacity(0.12))
                        .frame(maxWidth: .infinity)
                        .frame(height: 6)
                }
            }
            .frame(maxWidth: .infinity)
            Text("\(count)/\(total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(count >= total ? Theme.ok : .secondary)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut, value: count)
    }
}
