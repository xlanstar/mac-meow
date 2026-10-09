import SwiftUI

enum Theme {
    static let orange = Color(red: 1.0, green: 0.58, blue: 0.30)
    static let pink = Color(red: 0.97, green: 0.36, blue: 0.49)
    static let accent = LinearGradient(colors: [orange, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let ok = Color(red: 0.20, green: 0.74, blue: 0.42)
}

struct MainView: View {
    @ObservedObject var launcher: Launcher
    @ObservedObject var updater: Updater
    /// 內容實際高度（量測而得）。
    @State private var contentHeight: CGFloat = 0
    /// 螢幕可用高度扣掉標題列，由 `MainWindowAccessor` 回報。
    @State private var maxHeight: CGFloat = .infinity

    var body: some View {
        // 視窗高度跟著內容（.contentSize），但不超過螢幕；放不下時改為捲動。
        ScrollView(.vertical) {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        .modifier(BounceOnlyWhenScrollable())
        .frame(width: 500, height: min(contentHeight, maxHeight))
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .background(Backdrop())
        .background(MainWindowAccessor { maxHeight = $0 })
        .task { launcher.startPolling() }
        .sheet(item: $launcher.bugReport) { context in
            BugReportView(context: context, env: launcher.config.environment)
        }
    }

    private var content: some View {
        VStack(spacing: 14) {
            HeaderView(launcher: launcher)
            if let release = updater.notice {
                UpdateBanner(updater: updater, release: release)
            }
            StatusSummaryCard(launcher: launcher)
            ChecklistCard(launcher: launcher)
            GameSettingsCard(launcher: launcher)
            LogSection(launcher: launcher)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 20)
        .frame(width: 500)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// 內容放得下時不讓觸控板拖出彈性效果（macOS 13.3 起才有 API）。
private struct BounceOnlyWhenScrollable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.3, *) {
            content.scrollBounceBehavior(.basedOnSize)
        } else {
            content
        }
    }
}

// MARK: - 外觀元件

private struct Backdrop: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
    }
}

struct Card: ViewModifier {
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

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Theme.orange)
                    .opacity(isEnabled ? 1 : 0.55)
                    .shadow(color: Theme.orange.opacity(isEnabled ? 0.35 : 0), radius: 8, y: 3)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
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
    @ObservedObject var launcher: Launcher

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 54, height: 54)
            Text("貓貓谷 for Mac")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Spacer()
            Button {
                launcher.reportBug()
            } label: {
                HeaderIcon(symbol: "ladybug.fill")
            }
            .buttonStyle(.plain)
            .help("回報問題")
        }
    }
}

private struct HeaderIcon: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 30)
            .background(Circle().fill(Color.primary.opacity(0.06)))
            .contentShape(Circle())
    }
}

// MARK: - 新版本

private struct UpdateBanner: View {
    @ObservedObject var updater: Updater
    let release: Updater.Release
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

// MARK: - 主要狀態與動作

/// 主卡片顯示的整體狀態摘要（圖示、標題、色調），由 `Launcher` 目前狀態推導。
struct StatusSummary {
    var title: String
    var symbol = "pawprint.fill"
    var tint = Theme.orange
    var busy = false
}

extension Launcher {
    var statusSummary: StatusSummary {
        if case .working = phase {
            return StatusSummary(title: "處理中", busy: true)
        }
        if !status.loaded {
            return StatusSummary(title: "檢查環境中", busy: true)
        }
        if status.game {
            return StatusSummary(title: "遊戲執行中", symbol: "gamecontroller.fill", tint: Theme.ok)
        }
        if status.launcher {
            return StatusSummary(title: "登入器已開啟", symbol: "checkmark.seal.fill", tint: Theme.ok)
        }
        if case .failed = phase {
            return StatusSummary(title: "啟動沒有完成", symbol: "exclamationmark.triangle.fill", tint: .red)
        }
        if Step.checklist.contains(where: { row($0).state == .action }) {
            return StatusSummary(title: "需要設定", symbol: "wrench.and.screwdriver.fill")
        }
        return StatusSummary(title: "準備就緒")
    }
}

private struct StatusSummaryCard: View {
    @ObservedObject var launcher: Launcher

    var body: some View {
        let summary = launcher.statusSummary
        let status = launcher.status
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle().fill(summary.tint.opacity(0.16))
                    if summary.busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: summary.symbol)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(summary.tint)
                    }
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.title).font(.system(size: 17, weight: .semibold, design: .rounded))
                    if case .failed = launcher.phase {
                        HStack(spacing: 12) {
                            Button("查看詳細記錄") { launcher.showLog = true }
                            Button("回報此問題") { launcher.reportFailure() }
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
        .animation(.easeInOut(duration: 0.2), value: summary.title)
    }

    @ViewBuilder private var actions: some View {
        if launcher.status.running && !launcher.busy {
            HStack(spacing: 10) {
                Button {
                    Task { await launcher.stopAll() }
                } label: {
                    Label("全部關閉", systemImage: "stop.fill")
                }
                .buttonStyle(SecondaryButtonStyle(tint: .red))
                Button {
                    Task { await launcher.restart() }
                } label: {
                    Label("重新啟動", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        } else {
            Button {
                Task { await launcher.start() }
            } label: {
                HStack(spacing: 8) {
                    if launcher.isWorking {
                        ProgressView().controlSize(.small).colorScheme(.dark)
                        Text(launcher.uninstalling ? "解除安裝中…" : "啟動中…")
                    } else {
                        Image(systemName: "play.fill")
                        Text("開始遊戲")
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(launcher.busy || !launcher.status.loaded)
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
                result = (
                    .action, "尚未安裝（免費的 Wine 執行環境）",
                    RowAction(title: "下載") { NSWorkspace.shared.open(AppPaths.cyderDownload) }
                )
            } else if s.cyderInDownloads {
                result = (
                    .action, "請移到「應用程式」資料夾",
                    RowAction(title: "顯示") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: s.cyderPath!)])
                    }
                )
            } else {
                result = (.ok, abbreviate(s.cyderPath!), nil)
            }
        case .prefix:
            result =
                s.cyderReady
                ? (.ok, "已建立", nil)
                : (
                    .todo, "第一次啟動時由 Cyder 建立（約 1–3 分鐘）",
                    s.cyderUsable ? RowAction(title: "開啟 Cyder") { [weak self] in self?.openCyder() } : nil
                )
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
            result =
                s.loopback
                ? (.ok, "已設定，開機自動套用", nil)
                : (
                    .action, "需要管理員權限（只需一次）",
                    RowAction(title: "設定…") { [weak self] in Task { await self?.setupLoopback() } }
                )
        case .patch:
            result = s.patched ? (.ok, "已套用", nil) : (.todo, "啟動時自動套用", nil)
        case .vb6:
            result = s.vb6 ? (.ok, "已安裝", nil) : (.todo, "啟動時自動安裝（約 1–2 分鐘）", nil)
        case .tunnels:
            result =
                s.tunnels >= s.tunnelsTotal
                ? (.ok, "\(s.tunnels)/\(s.tunnelsTotal)", nil)
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
                StepRow(step: step, row: launcher.row(step), disabled: launcher.busy)
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

// MARK: - 遊戲設定

private struct GameSettingsCard: View {
    @ObservedObject var launcher: Launcher

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("遊戲設定")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                if launcher.settingsDirty {
                    Text("下次「開始遊戲」時套用")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: launcher.settingsDirty)
            .padding(.bottom, 6)
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.orange)
                    .frame(width: 22)
                HStack(spacing: 4) {
                    Text("同步機制").font(.system(size: 13, weight: .medium))
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .help("MSync 效能最好。寫入 Cyder 的全域設定，下次「開始遊戲」時套用；Cyder 正在執行時要全部關閉後才會生效。")
                }
                Spacer(minLength: 8)
                Picker("同步機制", selection: $launcher.config.sync) {
                    ForEach(SyncMode.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
            }
            .padding(.vertical, 7)
            Divider()
            GraphicsBackendRow(launcher: launcher)
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "film.stack")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.orange)
                    .frame(width: 22)
                HStack(spacing: 4) {
                    Text("FPS 上限").font(.system(size: 13, weight: .medium))
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .help(
                            "選項與 Cyder 相同，DXMT 與 D3DMetal 都適用；「不限制」時最高為螢幕更新率。寫入 Cyder 的設定，下次「開始遊戲」時套用；Cyder 正在執行時要全部關閉後才會生效。"
                        )
                }
                Spacer(minLength: 8)
                Picker("FPS 上限", selection: $launcher.config.fpsCap) {
                    ForEach(FPSCap.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
            }
            .padding(.vertical, 7)
            Divider()
            ToggleRow(
                symbol: "speedometer", title: "顯示效能 HUD",
                help:
                    "在遊戲畫面顯示 Metal 效能 HUD（FPS 等），DXMT 與 D3DMetal 都適用。寫入 Cyder 的全域設定，下次「開始遊戲」時套用；Cyder 正在執行時要全部關閉後才會生效。",
                isOn: $launcher.config.metalHUD)
            Divider()
            ToggleRow(
                symbol: "xmark.app", title: "遊戲關閉時自動收尾",
                help: "遊戲關閉後，自動關閉登入器、HostShield 等背景程式，Wine 也會跟著結束。不會關閉其他 Cyder 遊戲。",
                isOn: $launcher.config.autoClose)
        }
        .modifier(Card(padding: 14))
    }
}

/// 圖形後端。D3DMetal 能否使用由 play.sh porcelain 的 d3dmetal 判斷；無法使用時 cyder-settings.sh 改寫 DXMT。
private struct GraphicsBackendRow: View {
    @ObservedObject var launcher: Launcher

    /// 狀態已讀取且 D3DMetal 無法使用（狀態尚未讀取時不提示）。
    private var d3dmetalUnavailable: Bool { launcher.status.loaded && !launcher.status.d3dmetalAvailable }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Image(systemName: "display")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.orange)
                    .frame(width: 22)
                HStack(spacing: 4) {
                    Text("圖形後端").font(.system(size: 13, weight: .medium))
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .help(
                            "D3DMetal 是預設值，為 Apple GPTK 的轉譯層，需要 macOS 14 以上，並安裝 CrossOver 或在 Cyder 設定安裝 GPTK；無法使用時自動改用 DXMT。寫入 Cyder 的全域設定，下次「開始遊戲」時套用；Cyder 正在執行時要全部關閉後才會生效。"
                        )
                }
                Spacer(minLength: 8)
                Picker("圖形後端", selection: $launcher.config.graphicsBackend) {
                    ForEach(GraphicsBackend.allCases) { backend in
                        let unavailable = backend == .d3dmetal && d3dmetalUnavailable
                        Text(unavailable ? "\(backend.title)（無法使用）" : backend.title)
                            .tag(backend)
                            .disabled(unavailable)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
            }
            if d3dmetalUnavailable {
                Text(
                    launcher.config.graphicsBackend == .d3dmetal
                        ? "D3DMetal 無法使用，目前改用 DXMT：需要安裝 CrossOver 或在 Cyder 設定安裝 GPTK（macOS 14 以上）"
                        : "D3DMetal 需要安裝 CrossOver 或在 Cyder 設定安裝 GPTK（macOS 14 以上）"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 34)
            }
        }
        .padding(.vertical, 7)
    }
}

private struct ToggleRow: View {
    let symbol: String
    let title: String
    let help: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.orange)
                .frame(width: 22)
            HStack(spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .help(help)
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.orange)
        }
        .padding(.vertical, 7)
    }
}

// MARK: - 記錄

private struct LogSection: View {
    @ObservedObject var launcher: Launcher
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
                    launcher.showLog.toggle()
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
                if launcher.showLog {
                    Button("複製") { launcher.copyLog() }
                    Button("在 Finder 中顯示") { launcher.revealLog() }
                }
            }
            .buttonStyle(.link)
            .font(.caption)

            if launcher.showLog {
                LogPanel(launcher: launcher)
            }
        }
        .onAppear { chevronOpen = launcher.showLog }
        .onChange(of: launcher.showLog) { open in
            withAnimation(.easeInOut(duration: 0.2)) { chevronOpen = open }
        }
    }
}

private struct LogPanel: View {
    @ObservedObject var launcher: Launcher
    @State private var appeared = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if launcher.log.isEmpty {
                        Text("這次開啟還沒有記錄。完整記錄：~/Library/Logs/MacMeow/launcher.log")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(launcher.log) { line in
                        Text(line.text)
                            .foregroundStyle(
                                line.text.hasPrefix("!") || line.text.hasPrefix("錯誤") ? Color.red : .primary
                            )
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
            .onChange(of: launcher.log.last?.id) { id in
                if let id { proxy.scrollTo(id, anchor: .bottom) }
            }
            .onAppear {
                if let id = launcher.log.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.2)) { appeared = true } }
    }
}
