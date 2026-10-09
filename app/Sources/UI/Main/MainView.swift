import SwiftUI

/// 主視窗。高度跟著內容（.contentSize），但不超過螢幕；放不下時改為捲動。
struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: Updater
    @ObservedObject var home: HomeModel
    /// 內容實際高度（量測而得）。
    @State private var contentHeight: CGFloat = 0
    /// 螢幕可用高度扣掉標題列，由 `MainWindowAccessor` 回報。
    @State private var maxHeight: CGFloat = .infinity
    @State private var showLog = false

    private static let width: CGFloat = 500

    var body: some View {
        ScrollView(.vertical) {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        .modifier(BounceOnlyWhenScrollable())
        .frame(width: Self.width, height: min(contentHeight, maxHeight))
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .background(MainWindowAccessor { maxHeight = $0 })
        .sheet(item: $model.bugReport) { context in
            BugReportView(context: context, env: model.config.config.environment)
        }
    }

    private var content: some View {
        VStack(spacing: 14) {
            HeaderView(onReport: model.reportBug)
            if let release = updater.notice {
                UpdateBanner(updater: updater, release: release)
            }
            StatusCard(
                state: home.presentation, launch: model.launch,
                onShowLog: { showLog = true }, onReport: model.reportFailure)
            ChecklistCard(state: home.presentation, launch: model.launch)
            GameSettingsCard(config: model.config, status: model.status)
            LogSection(log: model.log, isExpanded: $showLog)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 20)
        .frame(width: Self.width)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// 內容放得下時不讓觸控板拖出彈性效果（macOS 13.3 起才有 API）。
private struct BounceOnlyWhenScrollable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.3, *) {
            content.scrollBounceBehavior(.basedOnSize)
        } else {
            content
        }
    }
}

private struct HeaderView: View {
    let onReport: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 54, height: 54)
            Text("貓貓谷 for Mac")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Spacer()
            Button(action: onReport) {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("回報問題")
        }
    }
}
