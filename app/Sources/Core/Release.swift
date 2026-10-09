import Foundation

/// 顯示給使用者的錯誤訊息。
struct UserFacingError: LocalizedError, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// GitHub 上的正式版。
struct Release: Equatable {
    var version: String
    /// GitHub Release 頁面（更新內容）。
    var page: URL

    /// 逐段數字比較（0.10.0 > 0.9.1）；版本號不是數字的開發版（"dev"）排在正式版之後，不會提示更新。
    func isNewer(than current: String) -> Bool {
        version.compare(current, options: .numeric) == .orderedDescending
    }

    /// 解讀 `releases/latest` 的回應。還沒上傳 update.sh 要下載的 dmg（命名同 tools/release.sh）時視為尚未發佈。
    init(githubJSON data: Data) throws {
        struct Payload: Decodable {
            struct Asset: Decodable { let name: String }
            let tagName: String
            let htmlUrl: URL
            let assets: [Asset]
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(Payload.self, from: data) else {
            throw UserFacingError("GitHub 回應的內容無法解讀，請稍後再試。")
        }
        let version = payload.tagName.hasPrefix("v") ? String(payload.tagName.dropFirst()) : payload.tagName
        guard payload.assets.contains(where: { $0.name == "MacMeow-\(version).dmg" }) else {
            throw UserFacingError("新版本 \(version) 尚未提供下載，請稍後再試。")
        }
        self.init(version: version, page: payload.htmlUrl)
    }

    init(version: String, page: URL) {
        self.version = version
        self.page = page
    }
}
