import SwiftUI

/// 「遊戲設定」：寫入 Cyder 的設定，下次「開始遊戲」時由 play.sh 套用。
struct GameSettingsCard: View {
    @ObservedObject var config: ConfigStore
    @ObservedObject var status: StatusMonitor

    private static let appliesNextLaunch = "寫入 Cyder 的全域設定，下次「開始遊戲」時套用；Cyder 正在執行時要全部關閉後才會生效。"

    private var settings: Binding<GameSettings> { $config.config.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            CardRow(
                symbol: "arrow.triangle.2.circlepath", title: "同步機制",
                help: "MSync 效能最好。\(Self.appliesNextLaunch)"
            ) {
                MenuPicker("同步機制", selection: settings.sync, options: SyncMode.allCases) { Text($0.title) }
            }
            Divider()
            GraphicsBackendRow(
                selection: settings.graphicsBackend,
                d3dmetalUnavailable: status.status.loaded && !status.status.d3dmetalAvailable,
                help:
                    "D3DMetal 是預設值，為 Apple GPTK 的轉譯層，需要 macOS 14 以上，並安裝 CrossOver 或在 Cyder 設定安裝 GPTK；無法使用時自動改用 DXMT。\(Self.appliesNextLaunch)"
            )
            Divider()
            CardRow(
                symbol: "film.stack", title: "FPS 上限",
                help:
                    "選項與 Cyder 相同，DXMT 與 D3DMetal 都適用；「不限制」時最高為螢幕更新率。寫入 Cyder 的設定，下次「開始遊戲」時套用；Cyder 正在執行時要全部關閉後才會生效。"
            ) {
                MenuPicker("FPS 上限", selection: settings.fpsCap, options: FPSCap.allCases) { Text($0.title) }
            }
            Divider()
            CardRow(
                symbol: "speedometer", title: "顯示效能 HUD",
                help: "在遊戲畫面顯示 Metal 效能 HUD（FPS 等），DXMT 與 D3DMetal 都適用。\(Self.appliesNextLaunch)"
            ) {
                SettingToggle("顯示效能 HUD", isOn: settings.metalHUD)
            }
            Divider()
            CardRow(
                symbol: "xmark.app", title: "遊戲關閉時自動收尾",
                help: "遊戲關閉後，自動關閉登入器、HostShield 等背景程式，Wine 也會跟著結束。不會關閉其他 Cyder 遊戲。"
            ) {
                SettingToggle("遊戲關閉時自動收尾", isOn: settings.autoClose)
            }
        }
        .modifier(Card(padding: 14))
    }

    private var header: some View {
        HStack(spacing: 8) {
            CardTitle("遊戲設定")
            if config.settingsDirty {
                Text("下次「開始遊戲」時套用")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: config.settingsDirty)
        .padding(.bottom, 6)
    }
}

/// 圖形後端。D3DMetal 無法使用時（cyder-settings.sh 會改寫 DXMT）停用該選項並說明原因。
private struct GraphicsBackendRow: View {
    @Binding var selection: GraphicsBackend
    /// 狀態已讀取且 D3DMetal 無法使用（狀態尚未讀取時不提示）。
    let d3dmetalUnavailable: Bool
    let help: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardRow(symbol: "display", title: "圖形後端", help: help) {
                MenuPicker("圖形後端", selection: $selection, options: GraphicsBackend.allCases) { backend in
                    let unavailable = backend == .d3dmetal && d3dmetalUnavailable
                    Text(unavailable ? "\(backend.title)（無法使用）" : backend.title).disabled(unavailable)
                }
            }
            if d3dmetalUnavailable {
                Text(
                    selection == .d3dmetal
                        ? "D3DMetal 無法使用，目前改用 DXMT：需要安裝 CrossOver 或在 Cyder 設定安裝 GPTK（macOS 14 以上）"
                        : "D3DMetal 需要安裝 CrossOver 或在 Cyder 設定安裝 GPTK（macOS 14 以上）"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 34)
                .padding(.bottom, 7)
            }
        }
    }
}

/// 卡片列右側的選單式 Picker。
private struct MenuPicker<Option: Hashable, Label: View>: View {
    let title: String
    @Binding var selection: Option
    let options: [Option]
    @ViewBuilder let label: (Option) -> Label

    init(
        _ title: String, selection: Binding<Option>, options: [Option],
        @ViewBuilder label: @escaping (Option) -> Label
    ) {
        self.title = title
        _selection = selection
        self.options = options
        self.label = label
    }

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { label($0).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .fixedSize()
    }
}

/// 卡片列右側的開關。
private struct SettingToggle: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        Toggle(title, isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Theme.orange)
    }
}
