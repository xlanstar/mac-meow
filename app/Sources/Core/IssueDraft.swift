import Foundation

/// 問題回報的類型（顯示在 issue 標題）。
enum BugCategory: String, CaseIterable, Identifiable {
    case launch, connection, crash, performance, app, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .launch: return "無法啟動"
        case .connection: return "連線／登入"
        case .crash: return "閃退／凍結"
        case .performance: return "卡頓／畫面"
        case .app: return "App 介面"
        case .other: return "其他"
        }
    }

    var symbol: String {
        switch self {
        case .launch: return "exclamationmark.triangle"
        case .connection: return "wifi.exclamationmark"
        case .crash: return "xmark.octagon"
        case .performance: return "speedometer"
        case .app: return "macwindow"
        case .other: return "ellipsis.bubble"
        }
    }
}

/// 開啟回報視窗時帶入的內容（例如啟動失敗的訊息）。
struct BugReportContext: Identifiable {
    let id = UUID()
    var category: BugCategory?
    var details = ""
}

/// 回報內容，送出時轉成預先填好的 GitHub issue 表單網址（.github/ISSUE_TEMPLATE/bug_report.yml）。
struct IssueDraft: Equatable {
    var category: BugCategory?
    var title = ""
    var details = ""
    var steps = ""
    var includeDiagnostics = true
    /// report.sh 的環境摘要；nil 表示讀取中。
    var environment: String?
    var recentLog = ""

    var isComplete: Bool { category != nil && !title.isBlank && !details.isBlank && environment != nil }

    var fullTitle: String { "[\(category?.title ?? BugCategory.other.title)] \(title.trimmed)" }

    /// 「複製報告」的完整 Markdown。
    func markdown(version: String) -> String {
        var parts = ["## \(fullTitle)", "### 發生了什麼\n\(details.trimmed)"]
        if !steps.isBlank { parts.append("### 重現步驟\n\(steps.trimmed)") }
        parts.append("### MacMeow 版本\n\(version)")
        if includeDiagnostics {
            parts.append("### 環境\n\(environment ?? "")")
            parts.append("### 最近的記錄\n```\n\(recentLog)\n```")
        }
        return parts.joined(separator: "\n\n")
    }

    /// 預先填好欄位的 issue 表單網址；參數名稱對應 bug_report.yml 各欄位的 id。
    /// GitHub 對過長的網址會回應錯誤：超過 `maxLength` 時先刪減記錄，再截短文字（完整內容可用「複製報告」）。
    func issueURL(repo: URL, version: String, maxLength: Int = 7000) -> URL? {
        var what = details.trimmed
        var stepsText = steps.trimmed
        var logLines = includeDiagnostics ? recentLog.components(separatedBy: "\n") : []
        /// 文字被截短時附加說明；長度檢查包含這段說明。
        var cut = false

        func build() -> String {
            var items = [
                ("template", "bug_report.yml"), ("title", fullTitle), ("version", version),
                ("what", cut ? what + "\n\n…（內容過長已截短，完整內容請見診斷檔）" : what), ("steps", stepsText),
            ]
            if includeDiagnostics {
                items += [("environment", environment ?? ""), ("log", logLines.joined(separator: "\n"))]
            }
            let query = items.filter { !$0.1.isEmpty }.map { "\($0.0)=\(Self.percentEncode($0.1))" }
            return repo.absoluteString + "/issues/new?" + query.joined(separator: "&")
        }

        while build().count > maxLength, !logLines.isEmpty {
            logLines.removeFirst(min(5, logLines.count))
        }
        while build().count > maxLength, stepsText.count > 200 {
            stepsText = String(stepsText.prefix(stepsText.count - 100))
            cut = true
        }
        while build().count > maxLength, what.count > 200 {
            what = String(what.prefix(what.count - 100))
            cut = true
        }
        let url = build()
        return URL(string: url)
    }

    /// 只保留 RFC 3986 unreserved 字元，其他（含中文、+、&）一律編碼。
    private static func percentEncode(_ text: String) -> String {
        let unreserved = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}
