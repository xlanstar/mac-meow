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

    // play.sh 的 progress id → 清單項目
    expectEqual(Step(progressID: "patch"), .patch)
    expectEqual(Step(progressID: "vb6"), .vb6)
    expectEqual(Step(progressID: "launch"), .tunnels)
    expectEqual(Step(progressID: "tunnels"), .tunnels)
    expectEqual(Step(progressID: "cyder"), nil)
    expectEqual(Step(progressID: ""), nil)
}
