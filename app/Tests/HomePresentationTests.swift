import Foundation

func testHomePresentation() {
    var ready = EnvStatus(porcelain: [
        "tunnels_total": "4", "cyder": "/Applications/Cyder.app", "cyder_ready": "1", "game_dir": "/Games/Maple",
        "game_dir_valid": "1", "loopback": "1", "patched": "1", "vb6": "1",
    ])
    func state(_ p: HomePresentation, _ step: Step) -> ChecklistItem.State? {
        p.checklist.first { $0.step == step }?.state
    }

    // 摘要標題（依優先順序）
    func title(_ status: EnvStatus, _ phase: LaunchPhase = .idle) -> String {
        HomePresentation(status: status, phase: phase).summary.title
    }
    var game = ready
    game.game = true
    var launcher = ready
    launcher.launcher = true
    var needsSetup = ready
    needsSetup.loopback = false
    expectEqual(title(ready, .working("啟動中")), "處理中")
    expect(HomePresentation(status: ready, phase: .working("啟動中")).summary.busy)
    expectEqual(title(EnvStatus()), "檢查環境中")
    expectEqual(title(game, .failed("x")), "遊戲執行中")
    expectEqual(title(launcher), "登入器已開啟")
    expectEqual(title(ready, .failed("沒有連線")), "啟動沒有完成")
    expectEqual(title(needsSetup), "需要設定")
    expectEqual(title(ready), "準備就緒")
    expect(HomePresentation(status: ready, phase: .failed("x")).failed)
    expect(!HomePresentation(status: ready).failed)

    // 清單狀態
    expectEqual(Step.checklist.map { state(HomePresentation(status: ready), $0) }, Step.checklist.map { _ in .ok })
    expectEqual(
        HomePresentation(status: EnvStatus()).checklist.map(\.state), Step.checklist.map { _ in .unknown })
    var unpatched = ready
    unpatched.patched = false
    expectEqual(state(HomePresentation(status: unpatched), .patch), .todo)
    expectEqual(state(HomePresentation(status: needsSetup), .loopback), .action)
    expectEqual(state(HomePresentation(status: ready, phase: .working("修補", step: .patch)), .patch), .working)
    expectEqual(state(HomePresentation(status: ready, phase: .failed("失敗", step: .vb6)), .vb6), .failed)
    expectEqual(state(HomePresentation(phase: .working("修補", step: .patch)), .patch), .working)

    // Cyder 放在「下載項目」
    var downloads = ready
    downloads.cyderPath = NSHomeDirectory() + "/Downloads/Cyder.app"
    let cyder = ChecklistItem(.cyder, status: downloads, phase: .idle, gameDirChosen: true)
    expectEqual(cyder.state, .action)
    expectEqual(cyder.action, .revealCyder(NSHomeDirectory() + "/Downloads/Cyder.app"))

    // 遊戲資料夾：選過但缺檔、沒選過、有效
    var invalidDir = ready
    invalidDir.gameDirValid = false
    invalidDir.missingFile = "MapleStory.exe"
    let chosen = ChecklistItem(.gameDir, status: invalidDir, phase: .idle, gameDirChosen: true)
    expectEqual(chosen.detail, "缺少 MapleStory.exe")
    expectEqual(chosen.action, .chooseGameDir(change: false))
    expectEqual(ChecklistItem(.gameDir, status: invalidDir, phase: .idle, gameDirChosen: false).detail, "尚未選擇")
    let valid = ChecklistItem(.gameDir, status: ready, phase: .idle, gameDirChosen: true)
    expectEqual(valid.detail, "/Games/Maple")
    expectEqual(valid.action, .chooseGameDir(change: true))

    // 流程進行中：停用開始與關閉
    ready.launcher = true
    let idle = HomePresentation(status: ready)
    expect(idle.canStart && idle.showsStop && !idle.busy)
    let busy = HomePresentation(status: ready, phase: .working("啟動中"), operation: .launch)
    expect(busy.busy && !busy.canStart && !busy.showsStop)
    expect(!HomePresentation(status: EnvStatus()).canStart, "狀態未載入")

    // 進度文字
    expectEqual(busy.progressLabel, "啟動中…")
    expectEqual(HomePresentation(phase: .working("移除"), operation: .uninstall).progressLabel, "解除安裝中…")
    expectEqual(HomePresentation(status: ready, operation: .launch).progressLabel, nil)
}
