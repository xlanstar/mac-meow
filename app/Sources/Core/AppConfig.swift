import Foundation

/// Cyder 的同步機制（傳給 play.sh 的 SYNC）。
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

/// Cyder 的圖形後端（傳給 play.sh 的 GRAPHICS_BACKEND）。D3DMetal 能否使用由 play.sh porcelain 的 d3dmetal 判斷。
enum GraphicsBackend: String, CaseIterable, Identifiable {
    case d3dmetal, dxmt
    var id: String { rawValue }
    var title: String {
        switch self {
        case .d3dmetal: return "D3DMetal（建議）"
        case .dxmt: return "DXMT"
        }
    }
}

/// FPS 上限（傳給 play.sh 的 MAX_FPS）。選項與 Cyder 的 dxvkFrameRate 相同。
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
    /// Metal 效能 HUD，顯示 FPS（play.sh 的 HUD）。
    var metalHUD = false
    var fpsCap: FPSCap = .unlimited
    /// 遊戲關閉時自動關閉登入器與背景程式（play.sh 的 AUTO_CLOSE）。
    var autoClose = true
}

/// App 設定。存檔與傳給 scripts/ 的環境變數使用同一組 KEY=VALUE。
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

    /// 由 KEY=VALUE 還原；缺少或無效的值使用預設值。
    /// MAPLE_SYNC 是 0.3.0 以前的 key，下次存檔時改寫成 SYNC。
    init(values v: [String: String]) {
        let defaults = GameSettings()
        gameDir = v["GAME_DIR"].flatMap { $0.isEmpty ? nil : $0 }
        settings.sync = (v["SYNC"] ?? v["MAPLE_SYNC"]).flatMap(SyncMode.init) ?? defaults.sync
        settings.graphicsBackend = v["GRAPHICS_BACKEND"].flatMap(GraphicsBackend.init) ?? defaults.graphicsBackend
        settings.metalHUD = v["HUD"].map { $0 == "1" } ?? defaults.metalHUD
        settings.fpsCap = v["MAX_FPS"].flatMap(FPSCap.init) ?? defaults.fpsCap
        settings.autoClose = v["AUTO_CLOSE"].map { $0 != "0" } ?? defaults.autoClose
    }

    /// 傳給 scripts/ 的環境變數。
    var environment: [String: String] {
        var env = [
            "SYNC": settings.sync.rawValue,
            "GRAPHICS_BACKEND": settings.graphicsBackend.rawValue,
            "HUD": settings.metalHUD ? "1" : "0",
            "MAX_FPS": settings.fpsCap.rawValue,
            "AUTO_CLOSE": settings.autoClose ? "1" : "0",
        ]
        if let gameDir { env["GAME_DIR"] = gameDir }
        return env
    }

    /// 設定檔內容（每行 KEY=VALUE）。
    var fileContents: String {
        let env = environment
        return Self.keys.compactMap { key in env[key].map { "\(key)=\($0)\n" } }.joined()
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
