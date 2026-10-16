import SwiftUI

/// 「遊戲設定」子選單：寫入 Cyder 的設定，下次「開始遊戲」時由 play.sh 套用。
/// 各選項的說明見 README 的「遊戲設定」。
struct GameSettingsMenu: View {
    @ObservedObject var config: ConfigStore
    @ObservedObject var status: StatusMonitor

    private var settings: Binding<GameSettings> { $config.config.settings }

    var body: some View {
        Menu(config.settingsDirty ? "遊戲設定（下次開始遊戲時套用）" : "遊戲設定") {
            OptionMenu("同步機制", selection: settings.sync, options: SyncMode.allCases) { $0.title }
            OptionMenu("圖形後端", selection: settings.graphicsBackend, options: GraphicsBackend.selectable) {
                status.status.isUnavailable($0) ? "\($0.title)（無法使用）" : $0.title
            }
            if let note = status.status.graphicsFallbackNote(for: config.config.settings.graphicsBackend) {
                Text(note)
            }
            OptionMenu("FPS 上限", selection: settings.fpsCap, options: FPSCap.allCases) { $0.title }
            Toggle("顯示效能 HUD", isOn: settings.metalHUD)
            Toggle("遊戲關閉時自動收尾", isOn: settings.autoClose)
            Divider()
            Text("變更會在下次「開始遊戲」時套用")
            Text("Cyder 正在執行時，要全部關閉後才會生效")
        }
    }
}

/// 標題顯示目前選項的子選單，內含勾選式的選項。
private struct OptionMenu<Option: Hashable>: View {
    let title: String
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> String

    init(_ title: String, selection: Binding<Option>, options: [Option], label: @escaping (Option) -> String) {
        self.title = title
        _selection = selection
        self.options = options
        self.label = label
    }

    var body: some View {
        Menu("\(title)：\(label(selection))") {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }
}
