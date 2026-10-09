import Foundation

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var isBlank: Bool { trimmed.isEmpty }
    /// 把家目錄縮寫成 ~。
    var abbreviatingHome: String { (self as NSString).abbreviatingWithTildeInPath }
}
