import Foundation

/// Cyder 的同步機制（設定檔的 SYNC）。
enum SyncMode: String, CaseIterable, Identifiable {
    case msync, esync, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .msync: return "MSync（建議）"
        case .esync: return "ESync"
        case .none: return "關閉"
        }
    }
}

/// Cyder 的圖形後端，依退回順序排列（common.sh 的 GRAPHIC_BACKENDS）。設定檔的 GRAPHICS_BACKEND 只能選 `selectable`。
enum GraphicsBackend: String, CaseIterable, Identifiable {
    case d3dmetal, dxmt, dxvk, wined3d

    static let selectable: [GraphicsBackend] = [.d3dmetal, .dxmt]

    init?(setting value: String) {
        guard let backend = Self(rawValue: value), Self.selectable.contains(backend) else { return nil }
        self = backend
    }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .d3dmetal: return "D3DMetal"
        case .dxmt: return "DXMT"
        case .dxvk: return "DXVK"
        case .wined3d: return "wined3d（Wine 內建，最慢）"
        }
    }

    var title: String { self == .d3dmetal ? "D3DMetal（建議）" : name }

    /// 使用條件（common.sh 的 graphic_backend_available）。
    var requirement: String? {
        switch self {
        case .d3dmetal: return "需要 macOS 14 以上，並安裝 CrossOver 或在 Cyder 設定安裝 GPTK"
        case .dxmt: return "需要 macOS 15 以上，且 Cyder 有 DXMT 元件"
        case .dxvk: return "需要 Cyder 的 DXVK 元件"
        case .wined3d: return nil
        }
    }
}

/// FPS 上限（設定檔的 MAX_FPS）。選項與 Cyder 的 dxvkFrameRate 相同。
enum FPSCap: String, CaseIterable, Identifiable {
    case fps60 = "60"
    case fps120 = "120"
    case fps144 = "144"
    case unlimited
    var id: String { rawValue }
    var title: String { self == .unlimited ? "不限制" : rawValue }
}

/// 「開始遊戲」時寫入 Cyder 的設定；與上次啟動時不同就提示「下次開始遊戲時套用」。
struct GameSettings: Equatable {
    var sync: SyncMode = .msync
    var graphicsBackend: GraphicsBackend = .d3dmetal
    /// Metal 效能 HUD，顯示 FPS（設定檔的 HUD）。
    var metalHUD = false
    var fpsCap: FPSCap = .unlimited
    /// 遊戲關閉時自動關閉登入器與背景程式（設定檔的 AUTO_CLOSE）。
    var autoClose = true
}

/// App 設定，存在 ~/Library/Application Support/MacMeow/config（每行 KEY=VALUE）。
/// scripts/lib/common.sh 的 load_settings 也直接讀同一個設定檔；
/// 傳給 scripts/ 的環境變數名稱為 `MACMEOW_` + KEY（GAME_DIR 不加前綴），會蓋過設定檔的值。
struct AppConfig: Equatable {
    /// nil 表示沒選過，由 common.sh 使用預設資料夾。
    var gameDir: String?
    var settings = GameSettings()

    /// 存檔時的 key 順序。
    private static let keys = ["GAME_DIR", "SYNC", "GRAPHICS_BACKEND", "HUD", "MAX_FPS", "AUTO_CLOSE"]

    init(gameDir: String? = nil, settings: GameSettings = GameSettings()) {
        self.gameDir = gameDir
        self.settings = settings
    }

    /// 由設定檔的 KEY=VALUE 還原；缺少或無效的值使用預設值。
    init(values v: [String: String]) {
        let defaults = GameSettings()
        gameDir = v["GAME_DIR"].flatMap { $0.isEmpty ? nil : $0 }
        settings.sync = v["SYNC"].flatMap(SyncMode.init) ?? defaults.sync
        settings.graphicsBackend =
            v["GRAPHICS_BACKEND"].flatMap(GraphicsBackend.init(setting:)) ?? defaults.graphicsBackend
        settings.metalHUD = v["HUD"].map { $0 == "1" } ?? defaults.metalHUD
        settings.fpsCap = v["MAX_FPS"].flatMap(FPSCap.init) ?? defaults.fpsCap
        settings.autoClose = v["AUTO_CLOSE"].map { $0 != "0" } ?? defaults.autoClose
    }

    /// 設定檔的 KEY=VALUE；GAME_DIR 只在選過時才有。
    var values: [String: String] {
        var v = [
            "SYNC": settings.sync.rawValue,
            "GRAPHICS_BACKEND": settings.graphicsBackend.rawValue,
            "HUD": settings.metalHUD ? "1" : "0",
            "MAX_FPS": settings.fpsCap.rawValue,
            "AUTO_CLOSE": settings.autoClose ? "1" : "0",
        ]
        if let gameDir { v["GAME_DIR"] = gameDir }
        return v
    }

    /// 傳給 scripts/ 的環境變數：`MACMEOW_` + KEY，GAME_DIR 維持原名。
    var environment: [String: String] {
        Dictionary(uniqueKeysWithValues: values.map { ($0 == "GAME_DIR" ? $0 : "MACMEOW_\($0)", $1) })
    }

    /// 設定檔內容（每行 KEY=VALUE）。
    var fileContents: String {
        let v = values
        return Self.keys.compactMap { key in v[key].map { "\(key)=\($0)\n" } }.joined()
    }
}

/// 解析 KEY=VALUE 行（設定檔、play.sh status --porcelain）；沒有 = 的行略過，值可以含 =。
func parseKeyValues<S: Sequence>(_ lines: S) -> [String: String] where S.Element: StringProtocol {
    var values: [String: String] = [:]
    for line in lines {
        guard let eq = line.firstIndex(of: "=") else { continue }
        values[String(line[..<eq])] = String(line[line.index(after: eq)...])
    }
    return values
}
