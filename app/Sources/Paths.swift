import Foundation

/// App 自己的路徑。engine／prefix 路徑、遊戲檔案清單等一律由 scripts/lib/common.sh 定義，這裡不重複。
enum AppPaths {
    static let home = URL(fileURLWithPath: NSHomeDirectory())
    static let supportDir = home.appendingPathComponent("Library/Application Support/MacMeow")
    static let configFile = supportDir.appendingPathComponent("config")
    static let logDir = home.appendingPathComponent("Library/Logs/MacMeow")
    static let logFile = logDir.appendingPathComponent("launcher.log")
    /// 回報問題時產生的診斷檔（scripts/report.sh bundle）。
    static let reportsDir = logDir.appendingPathComponent("reports")
    /// app/build-app.sh 打包進 Contents/Resources/scripts 的使用者腳本。
    static let scripts = Bundle.main.resourceURL!.appendingPathComponent("scripts")
    static let cyderDownload = URL(string: "https://github.com/dspp779/CyderBits/releases")!
    /// 與 scripts/lib/common.sh 的 MACMEOW_REPO 一致（update.sh 從該 repo 下載新版）。
    static let repo = URL(string: "https://github.com/xlanstar/mac-meow")!
    static let knownIssues = URL(string: "https://github.com/xlanstar/mac-meow/issues?q=is%3Aissue")!
    /// 檢查更新：最新正式版（不含草稿與預先發行版）。
    static let latestRelease = URL(string: "https://api.github.com/repos/xlanstar/mac-meow/releases/latest")!

    static func script(_ name: String) -> String { scripts.appendingPathComponent(name).path }
}

/// 把家目錄縮寫成 ~。
func abbreviate(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }

var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
}

/// Cyder 的同步機制（傳給 play.sh 的 MAPLE_SYNC）。
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

/// Cyder 的圖形後端（傳給 play.sh 的 MAPLE_GFX）。D3DMetal 能否使用由 play.sh porcelain 的 d3dmetal 判斷。
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

/// FPS 上限（傳給 play.sh 的 MAPLE_FPS）。選項與 Cyder 的 dxvkFrameRate 相同。
enum FrameRateCap: String, CaseIterable, Identifiable {
    case fps60 = "60"
    case fps120 = "120"
    case fps144 = "144"
    case unlimited
    var id: String { rawValue }
    var title: String { self == .unlimited ? "不限制" : rawValue }
}

/// ~/Library/Application Support/MacMeow/config（KEY=VALUE；uninstall.sh 會刪除）。
struct AppConfig: Equatable {
    var gameDir: String?
    var sync: SyncMode = .msync
    var graphics: GraphicsBackend = .d3dmetal
    /// Metal 效能 HUD，顯示 FPS（play.sh 的 MAPLE_HUD）。
    var hud = false
    var frameRate: FrameRateCap = .unlimited
    /// 遊戲關閉時自動關閉登入器與背景程式（play.sh 的 AUTO_CLOSE）。
    var autoClose = true

    static func load() -> AppConfig {
        var config = AppConfig()
        guard let text = try? String(contentsOf: AppPaths.configFile, encoding: .utf8) else { return config }
        for line in text.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let value = String(line[line.index(after: eq)...])
            switch line[..<eq] {
            case "GAME_DIR": config.gameDir = value.isEmpty ? nil : value
            case "MAPLE_SYNC": config.sync = SyncMode(rawValue: value) ?? .msync
            case "MAPLE_GFX": config.graphics = GraphicsBackend(rawValue: value) ?? .d3dmetal
            case "MAPLE_HUD": config.hud = value == "1"
            case "MAPLE_FPS": config.frameRate = FrameRateCap(rawValue: value) ?? .unlimited
            case "AUTO_CLOSE": config.autoClose = value != "0"
            default: break
            }
        }
        return config
    }

    func save() {
        var text = ""
        if let gameDir { text += "GAME_DIR=\(gameDir)\n" }
        text += "MAPLE_SYNC=\(sync.rawValue)\n"
        text += "MAPLE_GFX=\(graphics.rawValue)\n"
        text += "MAPLE_HUD=\(hud ? 1 : 0)\n"
        text += "MAPLE_FPS=\(frameRate.rawValue)\n"
        text += "AUTO_CLOSE=\(autoClose ? 1 : 0)\n"
        try? FileManager.default.createDirectory(at: AppPaths.supportDir, withIntermediateDirectories: true)
        try? text.write(to: AppPaths.configFile, atomically: true, encoding: .utf8)
    }

    /// 傳給 scripts/ 的環境變數；沒選過資料夾時讓 common.sh 用預設值。
    var environment: [String: String] {
        var env = [
            "MAPLE_SYNC": sync.rawValue,
            "MAPLE_GFX": graphics.rawValue,
            "MAPLE_HUD": hud ? "1" : "0",
            "MAPLE_FPS": frameRate.rawValue,
            "AUTO_CLOSE": autoClose ? "1" : "0",
        ]
        if let gameDir { env["GAME_DIR"] = gameDir }
        return env
    }
}

/// ~/Library/Logs/MacMeow/launcher.log
final class LogFile {
    private let handle: FileHandle?
    private let formatter = DateFormatter()

    init() {
        let fm = FileManager.default
        let path = AppPaths.logFile.path
        try? fm.createDirectory(at: AppPaths.logDir, withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? Int, size > 2_000_000 {
            try? fm.removeItem(atPath: path)
        }
        if !fm.fileExists(atPath: path) { fm.createFile(atPath: path, contents: nil) }
        handle = FileHandle(forWritingAtPath: path)
        handle?.seekToEndOfFile()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    }

    func write(_ line: String) {
        handle?.write(Data("\(formatter.string(from: Date())) \(line)\n".utf8))
    }
}
