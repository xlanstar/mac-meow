import Foundation

func testRelease() {
    let page = URL(string: "https://github.com/xlanstar/mac-meow/releases/tag/v0.10.0")!
    func release(_ version: String) -> Release { Release(version: version, page: page) }

    expect(release("0.10.0").isNewer(than: "0.9.1"))
    expect(!release("0.9.1").isNewer(than: "0.10.0"))
    expect(!release("0.10.0").isNewer(than: "0.10.0"))
    expect(!release("99.0.0").isNewer(than: "dev"), "開發版不提示更新")

    func json(tag: String, assets: [String]) -> Data {
        let object: [String: Any] = [
            "tag_name": tag, "html_url": page.absoluteString, "assets": assets.map { ["name": $0] },
        ]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    let latest = try? Release(
        githubJSON: json(tag: "v0.10.0", assets: ["MacMeow-0.10.0.dmg", "MacMeow-0.10.0.dmg.sha256"]))
    expectEqual(latest, release("0.10.0"))

    let missing = errorMessage { _ = try Release(githubJSON: json(tag: "v0.10.0", assets: ["MacMeow-0.9.1.dmg"])) }
    expect(missing?.contains("0.10.0 尚未提供下載") == true, "\(missing ?? "沒有錯誤")")

    let bad = errorMessage { _ = try Release(githubJSON: Data("not json".utf8)) }
    expect(bad?.contains("無法解讀") == true, "\(bad ?? "沒有錯誤")")
}
