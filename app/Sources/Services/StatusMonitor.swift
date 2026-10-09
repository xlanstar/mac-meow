import Combine
import Foundation

/// 環境狀態（`play.sh status --porcelain`）：定期查詢，設定改變時立即重新查詢。
@MainActor
final class StatusMonitor: ObservableObject {
    private static let pollInterval: UInt64 = 3_000_000_000

    @Published private(set) var status = EnvStatus()

    private let config: ConfigStore
    /// 進行中的查詢與其環境變數；只有環境相同時才共用結果。
    private var pending: (env: [String: String], task: Task<EnvStatus, Never>)?
    private var pollTask: Task<Void, Never>?
    private var configChange: AnyCancellable?

    init(config: ConfigStore) {
        self.config = config
        // @Published 在設定改變之前送出；在下一個 Task 才查詢，讀到的是新設定
        configChange = config.$config.map(\.environment).removeDuplicates().dropFirst()
            .sink { [weak self] _ in Task { await self?.refresh() } }
    }

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: Self.pollInterval)
            }
        }
    }

    /// 查詢目前設定下的狀態。查詢期間設定改變（例如換了遊戲資料夾）時捨棄舊結果重新查詢；
    /// 查詢失敗時保留並回傳上一次的狀態。
    @discardableResult
    func refresh() async -> EnvStatus {
        let env = config.config.environment
        let task: Task<EnvStatus, Never>
        if let pending, pending.env == env {
            task = pending.task
        } else {
            task = Task { await Scripts.status(env: env) }
            pending = (env, task)
        }
        let result = await task.value
        if pending?.task == task { pending = nil }
        guard env == config.config.environment else { return await refresh() }
        // 只在內容改變時更新，避免每次輪詢都重繪畫面
        if result.loaded, result != status { status = result }
        return status
    }
}
