import Foundation

/// App 自己的路徑與網址。engine／prefix 路徑、遊戲檔案清單等一律由 scripts/lib/common.sh 定義，這裡不重複。
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

/// Info.plist 的版本號；直接以 swiftc 編譯的開發版為 "dev"。
let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
