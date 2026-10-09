import Foundation

/// App 的記錄：寫入 ~/Library/Logs/MacMeow/launcher.log，並保留最近的行數給「詳細記錄」顯示。
@MainActor
final class AppLog: ObservableObject {
    struct Line: Identifiable, Equatable {
        /// 遞增，舊記錄被捨棄後也不會與新記錄重複。
        let id: Int
        let text: String
        var isError: Bool { text.hasPrefix("!") || text.hasPrefix("錯誤") }
    }

    private static let maxLines = 1000
    /// 超過這個大小時，App 啟動會從新的記錄檔開始。
    private static let maxFileSize = 2_000_000

    @Published private(set) var lines: [Line] = []
    private var nextID = 0
    private let file = FileHandle.appendingLog(at: AppPaths.logFile, maxSize: AppLog.maxFileSize)
    private let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    func record(_ text: String) {
        // 寫入失敗（例如磁碟已滿）時略過
        try? file?.write(contentsOf: Data("\(timestamp.string(from: Date())) \(text)\n".utf8))
        nextID += 1
        lines.append(Line(id: nextID, text: text))
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
    }

    /// 記錄腳本輸出（進度標記只記錄步驟訊息）。
    func record(_ event: ScriptEvent) {
        if let text = event.logText { record(text) }
    }

    func copy() { Pasteboard.copy(lines.map(\.text).joined(separator: "\n")) }
    func open() { Workspace.open(AppPaths.logFile) }
    func reveal() { Workspace.reveal(AppPaths.logFile) }
}

extension FileHandle {
    /// 開啟記錄檔並移到結尾；檔案超過 `maxSize` 時先刪除重來。
    fileprivate static func appendingLog(at url: URL, maxSize: Int) -> FileHandle? {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxSize {
            try? fm.removeItem(at: url)
        }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        let handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
        return handle
    }
}
