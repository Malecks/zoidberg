import Foundation

enum BragRoute: Equatable {
    case nudge(days: Int)
    case review
}

enum BragURLRouter {
    static func route(_ url: URL) -> BragRoute? {
        guard url.scheme == "zoidberg" else { return nil }
        switch url.host {
        case "brag-nudge":
            let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "days" })?.value
            return .nudge(days: max(0, raw.flatMap(Int.init) ?? 0))
        case "brag-review":
            return .review
        default:
            return nil
        }
    }
}
