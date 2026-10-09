import SwiftUI

struct SettingsView: View {
    @ObservedObject var launcher: Launcher

    var body: some View {
        Form {
            Section("遊戲") {
                LabeledContent("遊戲資料夾") {
                    HStack {
                        Text(launcher.status.gameDir.isEmpty ? "尚未選擇" : abbreviate(launcher.status.gameDir))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .help(launcher.status.gameDir)
                        Button("選擇…") { Task { await launcher.chooseGameDir() } }
                            .disabled(launcher.isWorking)
                    }
                }
            }
            Section {
                Picker("同步機制", selection: $launcher.config.sync) {
                    ForEach(SyncMode.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Wine")
            } footer: {
                Text("寫入 Cyder 的全域設定。MSync 效能最好；變更在下次「開始遊戲」時套用，Cyder 正在執行時要全部關閉後才會生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("記錄") {
                LabeledContent("launcher.log") {
                    HStack {
                        Button("開啟") { launcher.openLog() }
                        Button("在 Finder 中顯示") { launcher.revealLog() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 480, height: 345)
    }
}
