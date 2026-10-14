import Foundation
import UserNotifications

enum BragIDs {
    static let reviewCategory = "BRAG_REVIEW"
    static let resultCategory = "BRAG_RESULT"
    static let reviewAction = "BRAG_REVIEW_NOW"
    static let laterAction = "BRAG_LATER"
    static let thread = "brag"
}

enum BragUpdateResult: Equatable {
    case success(message: String, notePath: String?)
    case alreadyRunning
    case failure(message: String)
    case notFound(path: String)

    static func from(_ r: CommandResult) -> BragUpdateResult {
        let firstLine: (String) -> String? = { text in
            text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        }
        guard r.exitCode == 0 else {
            return .failure(message: firstLine(r.stderr) ?? "brag exited with code \(r.exitCode)")
        }
        guard let line = r.stdout.split(separator: "\n").map(String.init).first(where: { $0.hasPrefix("wrote ") }) else {
            return .alreadyRunning
        }
        var path = String(line.dropFirst("wrote ".count))
        if let range = path.range(of: " (") { path = String(path[..<range.lowerBound]) }
        return .success(message: line, notePath: path)
    }

    var openURL: URL? {
        switch self {
        case .success(_, let notePath?):
            var c = URLComponents()
            c.scheme = "obsidian"
            c.host = "open"
            c.queryItems = [URLQueryItem(name: "path", value: notePath)]
            return c.url
        case .failure:
            return URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/brag-tracker.log")
        default:
            return nil
        }
    }
}

enum BragContent {
    static func review(days: Int) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = "Brag review"
        c.body = days == 1 ? "1 day captured since your last review" : "\(days) days captured since your last review"
        c.categoryIdentifier = BragIDs.reviewCategory
        c.threadIdentifier = BragIDs.thread
        c.userInfo = ["days": days]
        c.sound = .default
        return c
    }

    static func result(_ r: BragUpdateResult) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        switch r {
        case .success(let message, _):
            c.title = "Brag notes updated"; c.body = message
        case .alreadyRunning:
            c.title = "A gather is already running"; c.body = "It'll update this week's note when it finishes."
        case .failure(let message):
            c.title = "Brag update failed"; c.body = message
        case .notFound(let path):
            c.title = "brag CLI not found"; c.body = "Nothing at \(path)"
        }
        c.categoryIdentifier = BragIDs.resultCategory
        c.threadIdentifier = BragIDs.thread
        if let url = r.openURL { c.userInfo = ["open": url.absoluteString] }
        return c
    }
}
