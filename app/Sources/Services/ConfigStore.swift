import Foundation

/// App 設定（~/Library/Application Support/MacMeow/config；uninstall.sh 會刪除）。變更時立即存檔。
@MainActor
final class ConfigStore: ObservableObject {
    @Published var config: AppConfig {
        didSet { if config != oldValue { save() } }
    }
    /// 上次成功「開始遊戲」時套用的遊戲設定。
    @Published private(set) var applied: GameSettings

    /// 有尚未套用到 Cyder 的設定變更。
    var settingsDirty: Bool { config.settings != applied }

    init() {
        let text = (try? String(contentsOf: AppPaths.configFile, encoding: .utf8)) ?? ""
        let config = AppConfig(values: parseKeyValues(text.split(separator: "\n")))
        self.config = config
        applied = config.settings
    }

    func markApplied(_ settings: GameSettings) { applied = settings }

    private func save() {
        try? FileManager.default.createDirectory(at: AppPaths.supportDir, withIntermediateDirectories: true)
        try? config.fileContents.write(to: AppPaths.configFile, atomically: true, encoding: .utf8)
    }
}
