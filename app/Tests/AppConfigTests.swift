func testAppConfig() {
    // values → environment → fileContents 來回轉換
    let settings = GameSettings(sync: .esync, graphicsBackend: .dxmt, metalHUD: true, fpsCap: .fps144, autoClose: false)
    let config = AppConfig(gameDir: "/Games/貓貓谷", settings: settings)
    expectEqual(
        config.fileContents,
        "GAME_DIR=/Games/貓貓谷\nSYNC=esync\nGRAPHICS_BACKEND=dxmt\nHUD=1\nMAX_FPS=144\nAUTO_CLOSE=0\n")
    expectEqual(AppConfig(values: config.environment), config)
    expectEqual(AppConfig(values: parseKeyValues(config.fileContents.split(separator: "\n"))), config)

    // 0.3.0 以前的 MAPLE_SYNC；SYNC 優先
    expectEqual(AppConfig(values: ["MAPLE_SYNC": "none"]).settings.sync, SyncMode.none)
    expectEqual(AppConfig(values: ["SYNC": "esync", "MAPLE_SYNC": "none"]).settings.sync, .esync)
    expect(!AppConfig(values: ["MAPLE_SYNC": "esync"]).fileContents.contains("MAPLE_SYNC"))

    // 缺少或無效的值使用預設值
    expectEqual(AppConfig(values: [:]), AppConfig())
    let invalid = ["SYNC": "fsync", "GRAPHICS_BACKEND": "vulkan", "HUD": "yes", "MAX_FPS": "30", "AUTO_CLOSE": "1"]
    expectEqual(AppConfig(values: invalid), AppConfig())

    // 空的 GAME_DIR 視為沒選過，不寫入環境變數與設定檔
    expectEqual(AppConfig(values: ["GAME_DIR": ""]).gameDir, nil)
    expectEqual(AppConfig().environment["GAME_DIR"], nil)
    expect(!AppConfig().fileContents.contains("GAME_DIR"))

    // parseKeyValues：值可以含 =，沒有 = 的行略過
    expectEqual(
        parseKeyValues(["A=1", "沒有等號", "", "URL=a=b=c", "EMPTY="]),
        ["A": "1", "URL": "a=b=c", "EMPTY": ""])
}
