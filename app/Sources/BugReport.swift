import SwiftUI

/// 問題回報：在 App 內填寫，送出時以預先填好的網址開啟 GitHub issue 表單（.github/ISSUE_TEMPLATE/bug_report.yml），
/// 不需要後端。環境資訊與診斷檔由 scripts/report.sh 產生（已隱藏家目錄與使用者名稱）。

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

@MainActor
final class BugReporter: ObservableObject {
    enum Stage: Equatable {
        case editing
        case submitting
        case done(zip: URL?)
    }

    @Published var category: BugCategory?
    @Published var title = ""
    @Published var details: String
    @Published var steps = ""
    @Published var includeDiagnostics = true
    /// report.sh 的環境摘要；nil 表示讀取中。
    @Published private(set) var environment: String?
    @Published private(set) var recentLog = ""
    @Published private(set) var stage: Stage = .editing

    private let env: [String: String]
    /// GitHub 對過長的網址會回應錯誤；超過時先刪減記錄，再截短文字（完整內容可用「複製報告」）。
    private let maxURLLength = 7000

    init(context: BugReportContext, env: [String: String]) {
        category = context.category
        details = context.details
        var env = env
        env["MACMEOW_VERSION"] = appVersion
        self.env = env
    }

    var canSubmit: Bool {
        category != nil && !trimmed(title).isEmpty && !trimmed(details).isEmpty && environment != nil
            && stage == .editing
    }

    func load() async {
        async let summary = Shell.collect(Shell.script("report.sh", env: env))
        async let log = Shell.collect(Shell.script("report.sh", ["log", AppPaths.logFile.path, "40"], env: env))
        let (s, l) = await (summary, log)
        environment = s.ok ? s.lines.joined(separator: "\n") : "（無法取得環境資訊：\(s.errors.last ?? "未知錯誤")）"
        recentLog = l.lines.joined(separator: "\n")
    }

    func submit() async {
        guard canSubmit else { return }
        stage = .submitting
        let zip = includeDiagnostics ? await makeBundle() : nil
        if let zip { NSWorkspace.shared.activateFileViewerSelecting([zip]) }
        openIssuePage()
        stage = .done(zip: zip)
    }

    func openIssuePage() { NSWorkspace.shared.open(issueURL()) }

    func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown(), forType: .string)
    }

    // MARK: - 內容

    private var fullTitle: String {
        "[\(category?.title ?? "其他")] \(trimmed(title))"
    }

    /// 給「複製報告」用的完整 Markdown。
    func markdown() -> String {
        var parts = ["## \(fullTitle)", "### 發生了什麼\n\(trimmed(details))"]
        if !trimmed(steps).isEmpty { parts.append("### 重現步驟\n\(trimmed(steps))") }
        parts.append("### MacMeow 版本\n\(appVersion)")
        if includeDiagnostics {
            parts.append("### 環境\n\(environment ?? "")")
            parts.append("### 最近的記錄\n```\n\(recentLog)\n```")
        }
        return parts.joined(separator: "\n\n")
    }

    /// 預先填好欄位的 issue 表單網址；參數名稱對應 bug_report.yml 各欄位的 id。
    func issueURL() -> URL {
        var what = trimmed(details)
        var stepsText = trimmed(steps)
        var logLines = includeDiagnostics ? recentLog.components(separatedBy: "\n") : []
        let note = "\n\n…（內容過長已截短，完整內容請見診斷檔）"

        func build() -> String {
            var items: [(String, String)] = [
                ("template", "bug_report.yml"),
                ("title", fullTitle),
                ("version", appVersion),
                ("what", what),
                ("steps", stepsText),
            ]
            if includeDiagnostics {
                items.append(("environment", environment ?? ""))
                items.append(("log", logLines.joined(separator: "\n")))
            }
            let query = items.filter { !$0.1.isEmpty }.map { "\($0.0)=\(percentEncode($0.1))" }
            return AppPaths.repo.absoluteString + "/issues/new?" + query.joined(separator: "&")
        }

        var url = build()
        while url.count > maxURLLength, !logLines.isEmpty {
            logLines.removeFirst(min(5, logLines.count))
            url = build()
        }
        var cut = false
        while url.count > maxURLLength, stepsText.count > 200 {
            stepsText = String(stepsText.prefix(stepsText.count - 100))
            cut = true
            url = build()
        }
        while url.count > maxURLLength, what.count > 200 {
            what = String(what.prefix(what.count - 100))
            cut = true
            url = build()
        }
        if cut {
            what += note
            url = build()
        }
        return URL(string: url) ?? AppPaths.knownIssues
    }

    private func makeBundle() async -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let out = AppPaths.reportsDir.appendingPathComponent("MacMeow-report-\(formatter.string(from: Date())).zip")
        let result = await Shell.collect(
            Shell.script("report.sh", ["bundle", out.path, AppPaths.logFile.path], env: env))
        return result.ok ? out : nil
    }
}

private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

/// 只保留 RFC 3986 unreserved 字元，其他（含中文、+、&）一律編碼。
private func percentEncode(_ text: String) -> String {
    let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    return text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
}

// MARK: - 畫面

struct BugReportView: View {
    @StateObject private var reporter: BugReporter
    @Environment(\.dismiss) private var dismiss

    init(context: BugReportContext, env: [String: String]) {
        _reporter = StateObject(wrappedValue: BugReporter(context: context, env: env))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 14)
            Divider()
            if case .done(let zip) = reporter.stage {
                DoneView(reporter: reporter, zip: zip) { dismiss() }
            } else {
                ScrollView { form.padding(22) }
                Divider()
                footer.padding(.horizontal, 22).padding(.vertical, 14)
            }
        }
        .frame(width: 480, height: 600)
        .task { await reporter.load() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.accent)
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("回報問題").font(.system(size: 18, weight: .bold, design: .rounded))
                Text("會在瀏覽器開啟 GitHub 並自動填好內容（需要 GitHub 帳號）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Link(destination: AppPaths.knownIssues) {
                Label("已知問題", systemImage: "magnifyingglass")
            }
            .font(.caption)
            .help("回報前先看看是否已經有人回報過")
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            FieldSection("問題類型") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(BugCategory.allCases) { category in
                        CategoryChip(category: category, selected: reporter.category == category) {
                            reporter.category = category
                        }
                    }
                }
            }
            FieldSection("標題") {
                TextField("一句話描述問題，例如：按開始遊戲後登入器沒有出現", text: $reporter.title)
                    .textFieldStyle(.plain)
                    .modifier(FieldBox())
            }
            FieldSection("發生了什麼") {
                PlaceholderEditor(
                    text: $reporter.details,
                    placeholder: "看到什麼畫面或錯誤訊息？預期應該發生什麼？", height: 96)
            }
            FieldSection("重現步驟", optional: true) {
                PlaceholderEditor(
                    text: $reporter.steps,
                    placeholder: "1. 開啟 App\n2. 按「開始遊戲」\n3. …", height: 64)
            }
            diagnostics
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $reporter.includeDiagnostics) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("附上診斷資料").font(.system(size: 13, weight: .medium))
                    Text("系統與 Cyder 版本、環境檢查結果、最近的記錄。不含帳號密碼，家目錄與使用者名稱已隱藏。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .tint(Theme.pink)
            if reporter.includeDiagnostics {
                DisclosureGroup {
                    ScrollView {
                        Text(previewText)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(height: 150)
                    .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } label: {
                    HStack(spacing: 6) {
                        Text("檢視將送出的資訊").font(.caption)
                        if reporter.environment == nil { ProgressView().controlSize(.mini) }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var previewText: String {
        guard let environment = reporter.environment else { return "讀取中…" }
        let log = reporter.recentLog.isEmpty ? "（沒有記錄）" : reporter.recentLog
        return "環境\n\(environment)\n\n最近的記錄\n\(log)"
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                reporter.copyReport()
            } label: {
                Label("複製報告", systemImage: "doc.on.doc")
            }
            .help("沒有 GitHub 帳號時，可以複製後貼給協助你的人")
            .disabled(reporter.environment == nil)
            Spacer()
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button {
                Task { await reporter.submit() }
            } label: {
                HStack(spacing: 6) {
                    if reporter.stage == .submitting {
                        ProgressView().controlSize(.small).colorScheme(.dark)
                    } else {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    Text("前往 GitHub 送出")
                }
                .padding(.horizontal, 14)
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(width: 190)
            .disabled(!reporter.canSubmit)
            .keyboardShortcut(.defaultAction)
        }
    }
}

private struct DoneView: View {
    @ObservedObject var reporter: BugReporter
    let zip: URL?
    let close: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.ok)
            VStack(spacing: 4) {
                Text("已在瀏覽器開啟 GitHub").font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("內容已經填好，還差最後幾步：").font(.callout).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                StepLine(number: 1, text: "登入 GitHub（沒有帳號可以免費註冊）")
                if let zip {
                    StepLine(number: 2, text: "把 Finder 中選取的「\(zip.lastPathComponent)」拖到「診斷檔與截圖」欄位")
                    StepLine(number: 3, text: "確認內容後按「Create」送出")
                } else {
                    StepLine(number: 2, text: "確認內容後按「Create」送出")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 30)
            HStack(spacing: 14) {
                if let zip {
                    Button("在 Finder 中顯示診斷檔") { NSWorkspace.shared.activateFileViewerSelecting([zip]) }
                }
                Button("重新開啟網頁") { reporter.openIssuePage() }
                Button("複製報告") { reporter.copyReport() }
            }
            .buttonStyle(.link)
            .font(.callout)
            Spacer()
            Button("完成", action: close)
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 160)
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 20)
        }
    }
}

private struct StepLine: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Theme.accent))
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FieldSection<Content: View>: View {
    let title: String
    var optional = false
    @ViewBuilder let content: Content

    init(_ title: String, optional: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.optional = optional
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 12, weight: .semibold, design: .rounded))
                if optional { Text("（選填）").font(.caption).foregroundStyle(.tertiary) }
            }
            .foregroundStyle(.secondary)
            content
        }
    }
}

private struct CategoryChip: View {
    let category: BugCategory
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.symbol).font(.system(size: 12, weight: .semibold))
                Text(category.title).font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.primary.opacity(0.06)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }
}

private struct FieldBox: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(8)
            .background(
                Color(nsColor: .textBackgroundColor).opacity(0.6),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }
}

private struct PlaceholderEditor: View {
    @Binding var text: String
    let placeholder: String
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: height)
        .modifier(FieldBox())
    }
}
