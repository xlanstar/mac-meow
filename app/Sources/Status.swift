import Foundation

/// `scripts/play.sh status --porcelain` 的內容。key 由 play.sh 的 porcelain() 定義。
struct EnvStatus: Equatable {
    var loaded = false
    var cyderPath: String?
    var cyderReady = false
    var gameDir = ""
    var gameDirValid = false
    var missingFile: String?
    var loopback = false
    var patched = false
    var vb6 = false
    var wine = false
    var helpers = false
    var launcher = false
    var game = false
    /// 登入器的 PID（選單「顯示登入器」用）。
    var launcherPid: pid_t?
    var watching = false
    var tunnels = 0
    var tunnelsTotal = 4

    init() {}

    init(porcelain v: [String: String]) {
        func flag(_ key: String) -> Bool { v[key] == "1" }
        func text(_ key: String) -> String? { v[key].flatMap { $0.isEmpty ? nil : $0 } }
        loaded = v["tunnels_total"] != nil
        cyderPath = text("cyder")
        cyderReady = flag("cyder_ready")
        gameDir = v["game_dir"] ?? ""
        gameDirValid = flag("game_dir_valid")
        missingFile = text("missing_file")
        loopback = flag("loopback")
        patched = flag("patched")
        vb6 = flag("vb6")
        wine = flag("wine")
        helpers = flag("helpers")
        launcher = flag("launcher")
        game = flag("game")
        launcherPid = v["launcher_pid"].flatMap { pid_t($0) }
        watching = flag("watching")
        tunnels = Int(v["tunnels"] ?? "") ?? 0
        tunnelsTotal = Int(v["tunnels_total"] ?? "") ?? 4
    }

    /// 放在「下載項目」的 Cyder 會被 App Translocation 搬到隨機路徑，不使用。
    var cyderInDownloads: Bool {
        cyderPath?.hasPrefix(AppPaths.home.appendingPathComponent("Downloads").path + "/") ?? false
    }
    var cyderUsable: Bool { cyderPath != nil && !cyderInDownloads }
    var running: Bool { launcher || game }
}

/// 環境檢查清單的項目；也對應 play.sh 的 progress id。
enum Step: String, CaseIterable, Identifiable {
    case cyder, prefix, gameDir, loopback, patch, vb6, tunnels

    var id: String { rawValue }
    static let checklist: [Step] = [.cyder, .prefix, .gameDir, .loopback, .patch, .vb6]

    var title: String {
        switch self {
        case .cyder: return "Cyder"
        case .prefix: return "Windows 環境"
        case .gameDir: return "遊戲資料夾"
        case .loopback: return "本機網路位址"
        case .patch: return "Wine 修補"
        case .vb6: return "VB6 執行環境"
        case .tunnels: return "連線通道"
        }
    }

    var symbol: String {
        switch self {
        case .cyder: return "shippingbox"
        case .prefix: return "macwindow"
        case .gameDir: return "folder"
        case .loopback: return "network"
        case .patch: return "bandage"
        case .vb6: return "puzzlepiece.extension"
        case .tunnels: return "point.3.connected.trianglepath.dotted"
        }
    }

    /// play.sh 的 `progress <id>` → 清單項目。
    static func fromProgress(_ id: String) -> Step? {
        switch id {
        case "patch": return .patch
        case "vb6": return .vb6
        case "launch", "tunnels": return .tunnels
        default: return nil
        }
    }
}
