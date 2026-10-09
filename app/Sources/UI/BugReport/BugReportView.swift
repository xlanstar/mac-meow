import SwiftUI

/// 「回報問題」視窗。
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
            VStack(alignment: .trailing, spacing: 4) {
                Link(destination: AppPaths.knownIssues) {
                    Label("已知問題與解法", systemImage: "book")
                }
                .help("回報前先看看是不是已知問題，以及暫時的解法")
                Link(destination: AppPaths.reportedIssues) {
                    Label("已回報的問題", systemImage: "magnifyingglass")
                }
                .help("再看看是否已經有人回報過同樣的問題")
            }
            .font(.caption)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            FieldSection("問題類型") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(BugCategory.allCases) { category in
                        CategoryChip(category: category, selected: reporter.draft.category == category) {
                            reporter.draft.category = category
                        }
                    }
                }
            }
            FieldSection("標題") {
                TextField("一句話描述問題，例如：按開始遊戲後登入器沒有出現", text: $reporter.draft.title)
                    .textFieldStyle(.plain)
                    .modifier(FieldBox())
            }
            FieldSection("發生了什麼") {
                PlaceholderEditor(
                    text: $reporter.draft.details,
                    placeholder: "看到什麼畫面或錯誤訊息？預期應該發生什麼？", height: 96)
            }
            FieldSection("重現步驟", optional: true) {
                PlaceholderEditor(
                    text: $reporter.draft.steps,
                    placeholder: "1. 開啟 App\n2. 按「開始遊戲」\n3. …", height: 64)
            }
            diagnostics
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $reporter.draft.includeDiagnostics) {
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
            if reporter.draft.includeDiagnostics {
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
                        if reporter.draft.environment == nil { ProgressView().controlSize(.mini) }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var previewText: String {
        guard let environment = reporter.draft.environment else { return "讀取中…" }
        let log = reporter.draft.recentLog.isEmpty ? "（沒有記錄）" : reporter.draft.recentLog
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
            .disabled(reporter.draft.environment == nil)
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
                    Button("在 Finder 中顯示診斷檔") { Workspace.reveal(zip) }
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
