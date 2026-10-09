func testScriptEvent() {
    func event(_ line: String, isError: Bool = false) -> ScriptEvent { ScriptEvent(line: line, isError: isError) }

    expectEqual(event("@@STEP patch 套用 Wine 修補 (1/2)"), .step(id: "patch", message: "套用 Wine 修補 (1/2)"))
    expectEqual(event("@@STEP vb6"), .step(id: "vb6", message: ""))
    expectEqual(event("@@PROGRESS 25"), .progress(0.25))
    expectEqual(event("@@PROGRESS 150"), .progress(1))
    expectEqual(event("@@PROGRESS -5"), .progress(0))
    expectEqual(event("@@PROGRESS abc"), .output("@@PROGRESS abc"))
    expectEqual(event("@@PROGRESS nan"), .output("@@PROGRESS nan"))
    expectEqual(event("@@WAIT"), .waiting)
    expectEqual(event("@@WAIT", isError: true), .waiting)
    expectEqual(event("一般輸出"), .output("一般輸出"))
    expectEqual(event("錯誤", isError: true), .error("錯誤"))

    expectEqual(ScriptEvent.step(id: "vb6", message: "安裝 VB6").logText, "安裝 VB6")
    expectEqual(ScriptEvent.output("hello").logText, "hello")
    expectEqual(ScriptEvent.error("boom").logText, "! boom")
    expectEqual(ScriptEvent.progress(0.5).logText, nil)
    expectEqual(ScriptEvent.waiting.logText, nil)
    expectEqual(ScriptEvent.exit(0).logText, nil)

    var result = ScriptResult()
    expect(!result.ok)
    let events: [ScriptEvent] = [
        .output("game_dir=/a=b"), .output("/opt/homebrew/bin/brew"), .output("  "),
        .error("第一個錯誤"), .error(""), .step(id: "patch", message: "x"), .progress(1), .exit(0),
    ]
    for event in events { result.append(event) }
    expect(result.ok)
    expectEqual(result.lastLine, "/opt/homebrew/bin/brew")
    expectEqual(result.lastError, "第一個錯誤")
    expectEqual(result.values, ["game_dir": "/a=b"])
    expectEqual(result.output.count, 3)
    result.append(.exit(1))
    expect(!result.ok)
    expectEqual(ScriptResult(output: [" ", ""]).lastLine, nil)
}
