import Foundation

func testIssueDraft() {
    let repo = URL(string: "https://github.com/xlanstar/mac-meow")!
    let draft = IssueDraft(
        category: .launch, title: "  按開始沒反應 ", details: "A&B+C 貓", environment: "macOS 15", recentLog: "第一行\n第二行")

    // isComplete、fullTitle
    expect(draft.isComplete)
    var incomplete = draft
    incomplete.title = "  "
    expect(!incomplete.isComplete, "標題空白")
    incomplete = draft
    incomplete.category = nil
    expect(!incomplete.isComplete, "沒選類型")
    incomplete = draft
    incomplete.environment = nil
    expect(!incomplete.isComplete, "環境摘要讀取中")
    expectEqual(draft.fullTitle, "[無法啟動] 按開始沒反應")
    expectEqual(incomplete.fullTitle, "[無法啟動] 按開始沒反應")
    var other = draft
    other.category = nil
    expectEqual(other.fullTitle, "[其他] 按開始沒反應")

    // markdown：沒有重現步驟時不放該段；不附診斷時不放環境與記錄
    let markdown = draft.markdown(version: "0.4.0")
    expect(markdown.hasPrefix("## [無法啟動] 按開始沒反應\n\n### 發生了什麼\nA&B+C 貓"))
    expect(markdown.contains("### MacMeow 版本\n0.4.0"))
    expect(markdown.contains("### 環境\nmacOS 15") && markdown.contains("```\n第一行\n第二行\n```"))
    expect(!markdown.contains("### 重現步驟"))
    var noDiagnostics = draft
    noDiagnostics.includeDiagnostics = false
    noDiagnostics.steps = "1. 開啟 App"
    let noDiagMarkdown = noDiagnostics.markdown(version: "0.4.0")
    expect(noDiagMarkdown.contains("### 重現步驟\n1. 開啟 App"))
    expect(!noDiagMarkdown.contains("### 環境") && !noDiagMarkdown.contains("第一行"))

    expectEqual(
        IssueDraft.blankIssueURL(repo: repo).absoluteString,
        "https://github.com/xlanstar/mac-meow/issues/new?template=bug_report.yml")

    // issueURL：只保留 unreserved 字元，中文、&、+ 都編碼；空白欄位不放
    let url = draft.issueURL(repo: repo, version: "0.4.0")?.absoluteString ?? ""
    expect(url.hasPrefix("https://github.com/xlanstar/mac-meow/issues/new?template=bug_report.yml&title="))
    expect(url.contains("&what=A%26B%2BC%20%E8%B2%93&"), url)
    expect(url.contains("&environment=macOS%2015&log=%E7%AC%AC"), url)
    expect(!url.contains("steps="), "空白的重現步驟不放")
    let noDiagURL = noDiagnostics.issueURL(repo: repo, version: "0.4.0")?.absoluteString ?? ""
    expect(!noDiagURL.contains("environment=") && !noDiagURL.contains("log="), noDiagURL)

    // 過長：先刪最舊的記錄
    var longLog = draft
    longLog.recentLog = (0..<300).map { "log line \($0)" }.joined(separator: "\n")
    let logURL = longLog.issueURL(repo: repo, version: "0.4.0", maxLength: 2000)?.absoluteString ?? ""
    expect(logURL.count <= 2000, "長度 \(logURL.count)")
    expect(logURL.contains("log%20line%20299") && !logURL.contains("log%20line%200%0A"), "保留最新的記錄")
    expect(!logURL.contains("%E6%88%AA%E7%9F%AD"), "只刪記錄時不加截短說明")

    // 記錄刪完仍過長：截短文字並加上說明
    var longText = longLog
    longText.details = String(repeating: "貓", count: 1000)
    longText.steps = String(repeating: "步", count: 1000)
    // 中文編碼後每字 9 字元；文字至少保留 200 字，所以用預設上限
    let textURL = longText.issueURL(repo: repo, version: "0.4.0")?.absoluteString ?? ""
    expect(textURL.count <= 7000, "長度 \(textURL.count)")
    expect(!textURL.contains("log="), "記錄先全部刪除")
    expect(textURL.contains("%E6%88%AA%E7%9F%AD"), "加上「截短」說明")
    let fullText = longText.issueURL(repo: repo, version: "0.4.0", maxLength: 100_000)?.absoluteString ?? ""
    expect(fullText.contains("log=") && !fullText.contains("%E6%88%AA%E7%9F%AD"), "未超過上限時不截短")
}
