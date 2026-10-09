import Foundation

/// 執行外部程式並逐行回報輸出。
enum ProcessRunner {
    /// 執行並以 `ScriptEvent` 回報每一行輸出，最後是 `.exit`。取消讀取時終止程式。
    static func stream(_ executable: String, _ args: [String], env: [String: String] = [:]) -> AsyncStream<ScriptEvent>
    {
        AsyncStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
            continuation.onTermination = { _ in
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let status = run(process) { line, isError in
                    continuation.yield(ScriptEvent(line: line, isError: isError))
                }
                continuation.yield(.exit(status))
                continuation.finish()
            }
        }
    }

    /// 啟動後不等待也不讀取輸出；App 結束後仍繼續執行（update.sh install、uninstall.sh purge）。
    static func spawn(_ executable: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    /// 執行到結束並回傳結束碼；輸出逐行交給 `onLine`（在背景執行緒呼叫）。
    private static func run(_ process: Process, onLine: @escaping (String, Bool) -> Void) -> Int32 {
        process.standardInput = FileHandle.nullDevice
        let pipes = [(Pipe(), false), (Pipe(), true)]
        process.standardOutput = pipes[0].0
        process.standardError = pipes[1].0

        let group = DispatchGroup()
        for (pipe, isError) in pipes {
            let buffer = LineBuffer()
            group.enter()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    for line in buffer.flush() { onLine(line, isError) }
                    group.leave()
                } else {
                    for line in buffer.append(data) { onLine(line, isError) }
                }
            }
        }
        func stopReading() {
            for (pipe, _) in pipes { pipe.fileHandleForReading.readabilityHandler = nil }
        }

        do {
            try process.run()
        } catch {
            stopReading()
            onLine("無法執行 \(process.executableURL?.path ?? "")：\(error.localizedDescription)", true)
            return -1
        }
        process.waitUntilExit()
        // 背景子程序（例如 wineserver）可能繼承輸出而不關閉；程序結束後最多再等 2 秒讀完剩餘輸出。
        if group.wait(timeout: .now() + 2) == .timedOut { stopReading() }
        return process.terminationStatus
    }
}

/// 把分段讀到的資料切成行（UTF-8）。
private final class LineBuffer {
    private var data = Data()

    func append(_ chunk: Data) -> [String] {
        data.append(chunk)
        var lines: [String] = []
        while let newline = data.firstIndex(of: 0x0A) {
            lines.append(Self.decode(data[data.startIndex..<newline]))
            data.removeSubrange(data.startIndex...newline)
        }
        return lines
    }

    func flush() -> [String] {
        defer { data.removeAll() }
        return data.isEmpty ? [] : [Self.decode(data)]
    }

    /// winetricks 等會用 \r 更新同一行，只保留最後一段。
    private static func decode(_ bytes: Data) -> String {
        let text = String(decoding: bytes, as: UTF8.self)
        return text.split(separator: "\r").last.map(String.init) ?? ""
    }
}
