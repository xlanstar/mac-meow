import SwiftUI

enum Theme {
    static let orange = Color(red: 1.0, green: 0.58, blue: 0.30)
    static let pink = Color(red: 0.97, green: 0.36, blue: 0.49)
    static let accent = LinearGradient(colors: [orange, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let ok = Color(red: 0.20, green: 0.74, blue: 0.42)
}

struct MainView: View {
    @ObservedObject var launcher: Launcher

    var body: some View {
        VStack(spacing: 14) {
            HeaderView()
            HeroCard(launcher: launcher)
            ChecklistCard(launcher: launcher)
            LogSection(launcher: launcher)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 20)
        .frame(width: 500)
        .background(Backdrop())
        .task { launcher.startPolling() }
    }
}

// MARK: - 外觀元件

private struct Backdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(colors: [Theme.orange.opacity(0.30), Theme.pink.opacity(0.12), .clear],
                           startPoint: .topLeading, endPoint: UnitPoint(x: 0.7, y: 0.6))
        }
        .ignoresSafeArea()
    }
}

private struct Card: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Theme.accent)
                    .opacity(isEnabled ? 1 : 0.55)
                    .shadow(color: Theme.pink.opacity(isEnabled ? 0.35 : 0), radius: 8, y: 3)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = .primary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06))
            )
            .contentShape(Rectangle())
    }
}

// MARK: - 標題

private struct HeaderView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text("貓貓谷 for Mac")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("版本 \(appVersion) · 透過 Cyder 執行原版登入器")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SettingsButton()
        }
    }
}

private struct SettingsButton: View {
    var body: some View {
        if #available(macOS 14, *) {
            SettingsLink { icon }.buttonStyle(.plain).help("設定")
        } else {
            Button { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) } label: { icon }
                .buttonStyle(.plain).help("設定")
        }
    }
    private var icon: some View {
        Image(systemName: "gearshape.fill")
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 30)
            .background(Circle().fill(Color.primary.opacity(0.06)))
    }
}

// MARK: - 主要狀態與動作

private struct Hero {
    var title: String
    var detail: String
    var symbol = "pawprint.fill"
    var tint = Theme.orange
    var busy = false
}

extension Launcher {
    fileprivate var hero: Hero {
        if case let .working(message) = phase {
            return Hero(title: "處理中", detail: message, busy: true)
        }
        if !status.loaded {
            return Hero(title: "檢查環境中", detail: "正在讀取 Cyder 與遊戲狀態…", busy: true)
        }
        if status.game {
            return Hero(title: "遊戲執行中", detail: "祝你玩得愉快！關閉遊戲後可以從這裡再次啟動。",
                        symbol: "gamecontroller.fill", tint: Theme.ok)
        }
        if status.launcher {
            return Hero(title: "登入器已開啟", detail: "在貓貓谷登入器按「開始遊戲」即可進入遊戲。",
                        symbol: "checkmark.seal.fill", tint: Theme.ok)
        }
        if case let .failed(message) = phase {
            return Hero(title: "啟動沒有完成", detail: message, symbol: "exclamationmark.triangle.fill", tint: .red)
        }
        if Step.checklist.contains(where: { row($0).state == .action }) {
            return Hero(title: "需要設定", detail: "完成下方標示的項目，或直接按「開始遊戲」由程式一步步引導。",
                        symbol: "wrench.and.screwdriver.fill")
        }
        return Hero(title: "準備就緒", detail: "按「開始遊戲」開啟貓貓谷登入器。")
    }
}

private struct HeroCard: View {
    @ObservedObject var launcher: Launcher

    var body: some View {
        let hero = launcher.hero
        let status = launcher.status
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle().fill(hero.tint.opacity(0.16))
                    if hero.busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: hero.symbol)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(hero.tint)
                    }
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(hero.title).font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text(hero.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if case .failed = launcher.phase {
                        HStack(spacing: 12) {
                            Button("查看詳細記錄") { withAnimation { launcher.showLog = true } }
                            Button("知道了") { launcher.dismissFailure() }
                        }
                        .buttonStyle(.link)
                        .font(.callout)
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }

            if status.helpers || status.tunnels > 0 || launcher.activeStep == .tunnels {
                TunnelMeter(count: status.tunnels, total: status.tunnelsTotal)
            }

            actions
        }
        .modifier(Card(padding: 18))
        .animation(.easeInOut(duration: 0.2), value: hero.title)
    }

    @ViewBuilder private var actions: some View {
        if launcher.status.running && !launcher.isWorking {
            HStack(spacing: 10) {
                Button { Task { await launcher.stopAll() } } label: {
                    Label("全部關閉", systemImage: "stop.fill")
                }
                .buttonStyle(SecondaryButtonStyle(tint: .red))
                Button { Task { await launcher.restart() } } label: {
                    Label("重新啟動", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        } else {
            Button { Task { await launcher.start() } } label: {
                HStack(spacing: 8) {
                    if launcher.isWorking {
                        ProgressView().controlSize(.small).colorScheme(.dark)
                        Text("啟動中…")
                    } else {
                        Image(systemName: "play.fill")
                        Text("開始遊戲")
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(launcher.isWorking || !launcher.status.loaded)
            .keyboardShortcut(.defaultAction)
        }
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
            Text("連線通道").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(0..<max(total, 1), id: \.self) { i in
                    Capsule()
                        .fill(i < count ? Theme.ok : Color.primary.opacity(0.12))
                        .frame(width: 26, height: 6)
                }
            }
            Text("\(count)/\(total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(count >= total ? Theme.ok : .secondary)
            Spacer()
        }
        .animation(.easeInOut, value: count)
    }
}

// MARK: - 環境檢查清單

enum RowState: Equatable { case ok, todo, action, working, failed, unknown }

struct RowAction {
    var title: String
    var run: () -> Void
}

extension Launcher {
    func row(_ step: Step) -> (state: RowState, detail: String, action: RowAction?) {
        let s = status
        var result: (state: RowState, detail: String, action: RowAction?)
        switch step {
        case .cyder:
            if s.cyderPath == nil {
                result = (.action, "尚未安裝（免費的 Wine 執行環境）",
                          RowAction(title: "下載") { NSWorkspace.shared.open(AppPaths.cyderDownload) })
            } else if s.cyderInDownloads {
                result = (.action, "請移到「應用程式」資料夾",
                          RowAction(title: "顯示") {
                              NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: s.cyderPath!)])
                          })
            } else {
                result = (.ok, abbreviate(s.cyderPath!), nil)
            }
        case .prefix:
            result = s.cyderReady
                ? (.ok, "已建立", nil)
                : (.todo, "第一次啟動時由 Cyder 建立（約 1–3 分鐘）",
                   s.cyderUsable ? RowAction(title: "開啟 Cyder") { [weak self] in self?.openCyder() } : nil)
        case .gameDir:
            let choose = RowAction(title: s.gameDirValid ? "更改…" : "選擇…") { [weak self] in
                Task { await self?.chooseGameDir() }
            }
            if s.gameDirValid {
                result = (.ok, abbreviate(s.gameDir), choose)
            } else if config.gameDir == nil {
                result = (.action, "尚未選擇", choose)
            } else {
                result = (.action, "缺少 \(s.missingFile ?? "必要檔案")", choose)
            }
        case .loopback:
            result = s.loopback
                ? (.ok, "已設定，開機自動套用", nil)
                : (.action, "需要管理員權限（只需一次）",
                   RowAction(title: "設定…") { [weak self] in Task { await self?.setupLoopback() } })
        case .patch:
            result = s.patched ? (.ok, "已套用", nil) : (.todo, "啟動時自動套用", nil)
        case .vb6:
            result = s.vb6 ? (.ok, "已安裝", nil) : (.todo, "啟動時自動安裝（約 1–2 分鐘）", nil)
        case .tunnels:
            result = s.tunnels >= s.tunnelsTotal ? (.ok, "\(s.tunnels)/\(s.tunnelsTotal)", nil)
                                                 : (.todo, "\(s.tunnels)/\(s.tunnelsTotal)", nil)
        }
        if !s.loaded { result.state = .unknown }
        if activeStep == step { result.state = .working }
        if failedStep == step { result.state = .failed }
        return result
    }
}

private struct ChecklistCard: View {
    @ObservedObject var launcher: Launcher

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("環境檢查")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
            ForEach(Array(Step.checklist.enumerated()), id: \.element) { index, step in
                if index > 0 { Divider().padding(.leading, 34) }
                StepRow(step: step, row: launcher.row(step), disabled: launcher.isWorking)
            }
        }
        .modifier(Card(padding: 14))
    }
}

private struct StepRow: View {
    let step: Step
    let row: (state: RowState, detail: String, action: RowAction?)
    let disabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: step.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.title).font(.system(size: 13, weight: .medium))
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(row.state == .action || row.state == .failed ? Color.orange : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.detail)
            }
            Spacer(minLength: 8)
            if let action = row.action {
                Button(action.title, action: action.run)
                    .controlSize(.small)
                    .disabled(disabled)
            }
            StateBadge(state: row.state).frame(width: 18)
        }
        .padding(.vertical, 7)
    }
}

private struct StateBadge: View {
    let state: RowState

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

// MARK: - 記錄

private struct LogSection: View {
    @ObservedObject var launcher: Launcher

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { launcher.showLog.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(launcher.showLog ? 90 : 0))
                        Text("詳細記錄").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                if launcher.showLog {
                    Button("複製") { launcher.copyLog() }
                    Button("在 Finder 中顯示") { launcher.revealLog() }
                }
            }
            .buttonStyle(.link)
            .font(.caption)

            if launcher.showLog {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            if launcher.log.isEmpty {
                                Text("這次開啟還沒有記錄。完整記錄：~/Library/Logs/MacMeow/launcher.log")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(Array(launcher.log.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .foregroundStyle(line.hasPrefix("!") || line.hasPrefix("錯誤") ? Color.red : .primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                    }
                    .frame(height: 170)
                    .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onChange(of: launcher.log.count) { count in
                        if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                    }
                    .onAppear {
                        if !launcher.log.isEmpty { proxy.scrollTo(launcher.log.count - 1, anchor: .bottom) }
                    }
                }
                .transition(.opacity)
            }
        }
    }
}
