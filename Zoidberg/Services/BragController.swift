import Foundation
import UserNotifications

enum FallbackChoice { case reviewNow, later, skip }

@MainActor
final class BragController {
    private let runner: CommandRunner
    private let notifications: NotificationPosting
    private let fileExists: (String) -> Bool
    private let fallbackAlert: (Int) -> FallbackChoice
    private let showMessage: (String, String) -> Void
    private let openURL: (URL) -> Void
    private let scheduleLater: (TimeInterval, @escaping () -> Void) -> Void

    private(set) var isUpdating = false
    var onUpdatingChanged: ((Bool) -> Void)?

    init(runner: CommandRunner,
         notifications: NotificationPosting,
         fileExists: @escaping (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
         fallbackAlert: @escaping (Int) -> FallbackChoice,
         showMessage: @escaping (String, String) -> Void,
         openURL: @escaping (URL) -> Void,
         scheduleLater: @escaping (TimeInterval, @escaping () -> Void) -> Void) {
        self.runner = runner
        self.notifications = notifications
        self.fileExists = fileExists
        self.fallbackAlert = fallbackAlert
        self.showMessage = showMessage
        self.openURL = openURL
        self.scheduleLater = scheduleLater
    }

    private var bragPath: String { AppSettings.bragPath }

    func handle(_ route: BragRoute) async {
        switch route {
        case .nudge(let days): await nudge(days: days)
        case .review: await reviewNow()
        }
    }

    func nudge(days: Int) async {
        if await notifications.post(BragContent.review(days: days), after: nil) { return }
        switch fallbackAlert(days) {
        case .reviewNow:
            await reviewNow()
        case .later:
            scheduleLater(AppSettings.bragLaterSeconds) { [weak self] in
                Task { @MainActor in await self?.nudge(days: days) }
            }
        case .skip:
            break
        }
    }

    func reviewNow() async {
        guard fileExists(bragPath) else { return await postResult(.notFound(path: bragPath)) }
        let r = await runner.run(bragPath, ["review", "--in-terminal"])
        if r.exitCode != 0 { await postResult(BragUpdateResult.from(r)) }
    }

    func updateNow() async {
        guard !isUpdating else { return }
        guard fileExists(bragPath) else { return await postResult(.notFound(path: bragPath)) }
        setUpdating(true)
        let r = await runner.run(bragPath, ["gather"])
        setUpdating(false)
        await postResult(BragUpdateResult.from(r))
    }

    func didReceive(action: String, category: String, userInfo: [AnyHashable: Any]) async {
        switch category {
        case BragIDs.reviewCategory:
            if action == BragIDs.laterAction {
                let days = userInfo["days"] as? Int ?? 0
                if !(await notifications.post(BragContent.review(days: days), after: AppSettings.bragLaterSeconds)) {
                    scheduleLater(AppSettings.bragLaterSeconds) { [weak self] in
                        Task { @MainActor in await self?.nudge(days: days) }
                    }
                }
            } else if action == BragIDs.reviewAction || action == UNNotificationDefaultActionIdentifier {
                await reviewNow()
            }
        case BragIDs.resultCategory:
            if action == UNNotificationDefaultActionIdentifier,
               let s = userInfo["open"] as? String, let url = URL(string: s) {
                openURL(url)
            }
        default:
            break
        }
    }

    private func setUpdating(_ value: Bool) {
        isUpdating = value
        onUpdatingChanged?(value)
    }

    private func postResult(_ r: BragUpdateResult) async {
        let content = BragContent.result(r)
        if !(await notifications.post(content, after: nil)) {
            showMessage(content.title, content.body)
        }
    }
}
