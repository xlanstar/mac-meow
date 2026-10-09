import Foundation

enum ShellEvent {
    case line(String, isError: Bool)
    case exit(Int32)
}

struct ShellResult {
    var status: Int32 = -1
    var lines: [String] = []
    var errors: [String] = []
    var ok: Bool { status == 0 }

    /// 解析 key=value 輸出（play.sh status --porcelain）。
    var values: [String: String] {
        var dict: [String: String] = [:]
        for line in lines {
            guard let eq = line.firstIndex(of: "=") else { continue }
            dict[String(line[..<eq])] = String(line[line.index(after: eq)...])
        }
        return dict
    }
}

/// 執行外部程式並逐行回報輸出。所有實際動作都在 scripts/ 內；App 只負責呼叫與顯示。
enum Shell {
    /// 執行打包在 App 內的 scripts/<name>。
    static func script(_ name: String, _ args: [String] = [], env: [String: String] = [:]) -> AsyncStream<ShellEvent> {
        stream("/bin/bash", [AppPaths.script(name)] + args, env: env)
    }

    /// 啟動 scripts/<name> 後不等待也不讀取輸出；App 結束後仍繼續執行（update.sh install）。
    static func spawn(_ name: String, _ args: [String] = []) throws {
        try spawn(path: AppPaths.script(name), args)
    }

    /// 同 `spawn(_:_:)`，但指定腳本路徑（解除安裝時 App 已移到垃圾桶，`AppPaths.scripts` 不再有效）。
    static func spawn(path: String, _ args: [String] = []) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [path] + args
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    static func stream(_ executable: String, _ args: [String], env: [String: String] = [:]) -> AsyncStream<ShellEvent> {
        AsyncStream { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let status = runBlocking(executable, args, env: env) { line, isError in
                    continuation.yield(.line(line, isError: isError))
                }
                continuation.yield(.exit(status))
                continuation.finish()
            }
        }
    }

    static func collect(_ events: AsyncStream<ShellEvent>) async -> ShellResult {
        var result = ShellResult()
        for await event in events {
            switch event {
            case .line(let line, let isError):
                if isError { result.errors.append(line) } else { result.lines.append(line) }
            case .exit(let status):
                result.status = status
            }
        }
        return result
    }

    private static func runBlocking(
        _ executable: String, _ args: [String], env: [String: String],
        onLine: @escaping (String, Bool) -> Void
    ) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        let group = DispatchGroup()
        for (pipe, isError) in [(out, false), (err, true)] {
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

        do {
            try process.run()
        } catch {
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            onLine("無法執行 \(executable)：\(error.localizedDescription)", true)
            return -1
        }
        process.waitUntilExit()
        // 背景子程序（例如 wineserver）可能繼承輸出而不關閉；程序結束後最多再等 2 秒讀完剩餘輸出。
        if group.wait(timeout: .now() + 2) == .timedOut {
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
        }
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
            lines.append(decode(data[data.startIndex..<newline]))
            data.removeSubrange(data.startIndex...newline)
        }
        return lines
    }

    func flush() -> [String] {
        defer { data.removeAll() }
        return data.isEmpty ? [] : [decode(data)]
    }

    /// winetricks 等會用 \r 更新同一行，只保留最後一段。
    private func decode(_ bytes: Data) -> String {
        let text = String(decoding: bytes, as: UTF8.self)
        let parts = text.split(separator: "\r", omittingEmptySubsequences: true)
        return parts.last.map(String.init) ?? ""
    }
}
