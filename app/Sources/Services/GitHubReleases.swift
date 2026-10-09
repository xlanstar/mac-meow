import Foundation

/// 查詢 GitHub 上的最新正式版（`releases/latest` 不含草稿與預先發行版）。
enum GitHubReleases {
    static func latest() async throws -> Release {
        var request = URLRequest(url: AppPaths.latestRelease, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacMeow/\(appVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UserFacingError("無法連線到 GitHub：\(error.localizedDescription)")
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 200 {
        case 200: return try Release(githubJSON: data)
        case 403, 429: throw UserFacingError("GitHub 暫時限制了查詢次數，請稍後再試。")
        case let code: throw UserFacingError("GitHub 回應錯誤（HTTP \(code)），請稍後再試。")
        }
    }
}
