import Foundation

func testEnvStatus() {
    let empty = EnvStatus(porcelain: [:])
    expect(!empty.loaded)
    expectEqual(empty.tunnelsTotal, 4)
    expectEqual(empty.launcherPid, nil)

    let status = EnvStatus(porcelain: [
        "tunnels_total": "4", "tunnels": "3", "launcher": "1", "launcher_pid": "4321", "game": "0",
        "cyder": "/Applications/Cyder.app", "game_dir": "/Games/Maple", "game_dir_valid": "1", "missing_file": "",
    ])
    expect(status.loaded)
    expectEqual(status.tunnels, 3)
    expectEqual(status.launcherPid, 4321)
    expect(status.launcher && !status.game && status.running)
    expectEqual(status.missingFile, nil)
    expect(!status.cyderInDownloads && status.cyderUsable)
    expectEqual(EnvStatus(porcelain: ["launcher_pid": "abc"]).launcherPid, nil)

    let downloads = EnvStatus(porcelain: ["tunnels_total": "4", "cyder": NSHomeDirectory() + "/Downloads/Cyder.app"])
    expect(downloads.cyderInDownloads && !downloads.cyderUsable)

    // 圖形後端（porcelain 的 graphic_backends、graphic_backend）
    expect(!empty.isUnavailable(.d3dmetal))  // 尚未讀取時不提示
    expectEqual(empty.graphicsFallbackNote(for: .d3dmetal), nil)
    let macOS14 = EnvStatus(porcelain: [
        "tunnels_total": "4", "graphic_backends": "dxvk wined3d", "graphic_backend": "dxvk",
    ])
    expectEqual(macOS14.availableGraphicsBackends, [.dxvk, .wined3d])
    expect(macOS14.isUnavailable(.d3dmetal) && macOS14.isUnavailable(.dxmt) && !macOS14.isUnavailable(.dxvk))
    expectEqual(
        macOS14.graphicsFallbackNote(for: .d3dmetal),
        "D3DMetal 無法使用（需要 macOS 14 以上，並安裝 CrossOver 或在 Cyder 設定安裝 GPTK），目前改用 DXVK")
    expectEqual(macOS14.graphicsFallbackNote(for: .dxmt), "DXMT 無法使用（需要 macOS 15 以上，且 Cyder 有 DXMT 元件），目前改用 DXVK")
    let allAvailable = EnvStatus(porcelain: [
        "tunnels_total": "4", "graphic_backends": "d3dmetal dxmt dxvk wined3d", "graphic_backend": "d3dmetal",
    ])
    expectEqual(allAvailable.graphicsFallbackNote(for: .d3dmetal), nil)
    // 剛換設定、狀態仍是上一個設定的結果（退回的後端不會排在前面）時不提示
    let stale = EnvStatus(porcelain: [
        "tunnels_total": "4", "graphic_backends": "d3dmetal dxvk wined3d", "graphic_backend": "d3dmetal",
    ])
    expectEqual(stale.graphicsFallbackNote(for: .dxmt), nil)
    expectEqual(EnvStatus(porcelain: ["graphic_backends": "vulkan dxmt"]).availableGraphicsBackends, [.dxmt])

    // play.sh 的 progress id → 清單項目
    expectEqual(Step(progressID: "patch"), .patch)
    expectEqual(Step(progressID: "vb6"), .vb6)
    expectEqual(Step(progressID: "launch"), .tunnels)
    expectEqual(Step(progressID: "tunnels"), .tunnels)
    expectEqual(Step(progressID: "cyder"), nil)
    expectEqual(Step(progressID: ""), nil)
}
