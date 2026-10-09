import Foundation

/// 問題回報：在 App 內填寫，送出時以預先填好的網址開啟 GitHub issue 表單，不需要後端。
/// 環境資訊與診斷檔由 scripts/report.sh 產生（已隱藏家目錄與使用者名稱）。
@MainActor
final class BugReporter: ObservableObject {
    enum Stage: Equatable {
        case editing
        case submitting
        case done(zip: URL?)
    }

    private static let recentLogLines = 40

    @Published var draft: IssueDraft
    @Published private(set) var stage: Stage = .editing

    private let env: [String: String]

    init(context: BugReportContext, env: [String: String]) {
        draft = IssueDraft(category: context.category, details: context.details)
        self.env = env.merging(["MACMEOW_VERSION": appVersion]) { _, new in new }
    }

    var canSubmit: Bool { draft.isComplete && stage == .editing }

    func load() async {
        async let summary = Scripts.reportSummary(env: env).collect()
        async let log = Scripts.reportLog(lines: Self.recentLogLines, env: env).collect()
        let (s, l) = await (summary, log)
        draft.environment =
            s.ok ? s.output.joined(separator: "\n") : "（無法取得環境資訊：\(s.lastError ?? "未知錯誤")）"
        draft.recentLog = l.output.joined(separator: "\n")
    }

    func submit() async {
        guard canSubmit else { return }
        stage = .submitting
        let zip = draft.includeDiagnostics ? await makeBundle() : nil
        if let zip { Workspace.reveal(zip) }
        openIssuePage()
        stage = .done(zip: zip)
    }

    func openIssuePage() {
        Workspace.open(draft.issueURL(repo: AppPaths.repo, version: appVersion) ?? AppPaths.knownIssues)
    }

    func copyReport() { Pasteboard.copy(draft.markdown(version: appVersion)) }

    private func makeBundle() async -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let zip = AppPaths.reportsDir.appendingPathComponent("MacMeow-report-\(formatter.string(from: Date())).zip")
        return await Scripts.reportBundle(to: zip, env: env).collect().ok ? zip : nil
    }
}
