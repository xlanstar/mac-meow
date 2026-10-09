import Foundation

/// 極簡測試工具：`expect` 記錄失敗並繼續，`finishTests()` 印出摘要並以結束碼回報。
/// 失敗訊息寫到 stderr（tools/release.sh check 會丟掉 stdout）。
private var checkCount = 0
private var failureCount = 0

func expect(
    _ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "",
    file: StaticString = #fileID, line: UInt = #line
) {
    checkCount += 1
    guard !condition() else { return }
    failureCount += 1
    FileHandle.standardError.write(Data("\(file):\(line): 失敗 \(message())\n".utf8))
}

func expectEqual<T: Equatable>(
    _ actual: T, _ expected: T, file: StaticString = #fileID, line: UInt = #line
) {
    expect(actual == expected, "\n  實際：\(actual)\n  預期：\(expected)", file: file, line: line)
}

/// 執行 `body` 並回傳拋出的錯誤訊息；沒有拋出錯誤時為 nil。
func errorMessage(_ body: () throws -> Void) -> String? {
    do {
        try body()
        return nil
    } catch {
        return error.localizedDescription
    }
}

func finishTests() -> Never {
    if failureCount == 0 {
        print("Core 測試：\(checkCount) 項檢查全部通過")
        exit(0)
    }
    FileHandle.standardError.write(Data("Core 測試：\(checkCount) 項檢查中 \(failureCount) 項失敗\n".utf8))
    exit(1)
}
