import Combine

/// 首頁與選單列共用的顯示內容，在狀態、流程或設定改變時重新推導。
@MainActor
final class HomeModel: ObservableObject {
    @Published private(set) var presentation = HomePresentation()

    init(launch: LaunchController) {
        // @Published 在值改變之前送出新值，所以合併的是改變後的狀態
        launch.status.$status
            .combineLatest(launch.$phase, launch.$operation, launch.config.$config.map { $0.gameDir != nil })
            .map { HomePresentation(status: $0, phase: $1, operation: $2, gameDirChosen: $3) }
            .removeDuplicates()
            .assign(to: &$presentation)
    }
}
