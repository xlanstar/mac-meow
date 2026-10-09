import Foundation

/// scripts/ 輸出的一行，或執行結束。進度標記由 common.sh 的 `progress`（@@STEP）
/// 與 update.sh（@@PROGRESS、@@WAIT）輸出，只在這裡解析。
enum ScriptEvent: Equatable {
    /// `@@STEP <id> <訊息>`：play.sh 進入新步驟。
    case step(id: String, message: String)
    /// `@@PROGRESS <0-100>`：下載進度，轉為 0–1。
    case progress(Double)
    /// `@@WAIT`：網路中斷，等待後繼續。
    case waiting
    case output(String)
    case error(String)
    case exit(Int32)

    init(line: String, isError: Bool) {
        if line.hasPrefix("@@STEP ") {
            let parts = line.dropFirst(7).split(separator: " ", maxSplits: 1)
            self = .step(id: parts.first.map(String.init) ?? "", message: parts.count > 1 ? String(parts[1]) : "")
        } else if line.hasPrefix("@@PROGRESS "), let percent = Double(line.dropFirst(11)), percent.isFinite {
            self = .progress(min(max(percent / 100, 0), 1))
        } else if line == "@@WAIT" {
            self = .waiting
        } else {
            self = isError ? .error(line) : .output(line)
        }
    }

    /// 寫進記錄的文字；進度標記以外的標記不記錄。
    var logText: String? {
        switch self {
        case .step(_, let message): return message
        case .output(let line): return line
        case .error(let line): return "! \(line)"
        case .progress, .waiting, .exit: return nil
        }
    }
}

/// 一次執行的完整輸出。
struct ScriptResult: Equatable {
    var status: Int32 = -1
    var output: [String] = []
    var errors: [String] = []

    var ok: Bool { status == 0 }
    /// 最後一行非空白的輸出（腳本以此回傳單一值，例如 brew 指令或路徑）。
    var lastLine: String? { output.last { !$0.isBlank } }
    /// 最後一行非空白的錯誤訊息。
    var lastError: String? { errors.last { !$0.isBlank } }
    /// 輸出的 KEY=VALUE（play.sh status --porcelain）。
    var values: [String: String] { parseKeyValues(output) }

    mutating func append(_ event: ScriptEvent) {
        switch event {
        case .output(let line): output.append(line)
        case .error(let line): errors.append(line)
        case .exit(let code): status = code
        case .step, .progress, .waiting: break
        }
    }
}

extension AsyncStream where Element == ScriptEvent {
    /// 讀完所有輸出；`onEvent` 在主執行緒逐一收到每個事件（更新進度、寫記錄）。
    @MainActor
    func collect(_ onEvent: (ScriptEvent) -> Void = { _ in }) async -> ScriptResult {
        var result = ScriptResult()
        for await event in self {
            onEvent(event)
            result.append(event)
        }
        return result
    }
}
