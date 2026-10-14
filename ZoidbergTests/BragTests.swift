import XCTest
import UserNotifications
@testable import Zoidberg

final class BragRouterTests: XCTestCase {
    func testNudgeWithDays() {
        XCTAssertEqual(BragURLRouter.route(URL(string: "zoidberg://brag-nudge?days=3")!), .nudge(days: 3))
    }
    func testNudgeWithoutOrBadDaysIsZero() {
        XCTAssertEqual(BragURLRouter.route(URL(string: "zoidberg://brag-nudge")!), .nudge(days: 0))
        XCTAssertEqual(BragURLRouter.route(URL(string: "zoidberg://brag-nudge?days=-2")!), .nudge(days: 0))
        XCTAssertEqual(BragURLRouter.route(URL(string: "zoidberg://brag-nudge?days=x")!), .nudge(days: 0))
    }
    func testReview() {
        XCTAssertEqual(BragURLRouter.route(URL(string: "zoidberg://brag-review")!), .review)
    }
    func testJunkIgnored() {
        XCTAssertNil(BragURLRouter.route(URL(string: "zoidberg://something-else")!))
        XCTAssertNil(BragURLRouter.route(URL(string: "https://brag-nudge?days=1")!))
    }
}

final class BragContentTests: XCTestCase {
    func testReviewContent() {
        let c = BragContent.review(days: 3)
        XCTAssertEqual(c.title, "Brag review")
        XCTAssertEqual(c.body, "3 days captured since your last review")
        XCTAssertEqual(c.categoryIdentifier, BragIDs.reviewCategory)
        XCTAssertEqual(c.threadIdentifier, "brag")
        XCTAssertEqual(c.userInfo["days"] as? Int, 3)
        XCTAssertEqual(BragContent.review(days: 1).body, "1 day captured since your last review")
    }
    func testResultContentCarriesOpenURL() {
        let c = BragContent.result(.success(message: "wrote /v/Brag/2026-W42.md", notePath: "/v/Brag/2026-W42.md"))
        XCTAssertEqual(c.title, "Brag notes updated")
        XCTAssertEqual(c.categoryIdentifier, BragIDs.resultCategory)
        XCTAssertEqual(c.userInfo["open"] as? String, "obsidian://open?path=/v/Brag/2026-W42.md")
        XCTAssertNil(BragContent.result(.alreadyRunning).userInfo["open"])
    }
}

final class BragUpdateResultTests: XCTestCase {
    func testExitZeroWithWroteIsSuccess() {
        let r = BragUpdateResult.from(CommandResult(exitCode: 0, stdout: "wrote /Users/a/Documents/Obsidian Vault/Brag/2026-W42.md (1 warnings)\n", stderr: ""))
        XCTAssertEqual(r, .success(message: "wrote /Users/a/Documents/Obsidian Vault/Brag/2026-W42.md (1 warnings)",
                                   notePath: "/Users/a/Documents/Obsidian Vault/Brag/2026-W42.md"))
        XCTAssertEqual(r.openURL?.absoluteString, "obsidian://open?path=/Users/a/Documents/Obsidian%20Vault/Brag/2026-W42.md")
    }
    func testExitZeroWithoutWroteIsAlreadyRunning() {
        XCTAssertEqual(BragUpdateResult.from(CommandResult(exitCode: 0, stdout: "", stderr: "")), .alreadyRunning)
    }
    func testNonZeroIsFailureWithFirstStderrLine() {
        let r = BragUpdateResult.from(CommandResult(exitCode: 1, stdout: "", stderr: "\ngather failed: claude -p exited 1: auth\nmore\n"))
        XCTAssertEqual(r, .failure(message: "gather failed: claude -p exited 1: auth"))
        XCTAssertEqual(r.openURL, URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/brag-tracker.log"))
        XCTAssertEqual(BragUpdateResult.from(CommandResult(exitCode: 2, stdout: "", stderr: "")), .failure(message: "brag exited with code 2"))
    }
}

final class CommandRunnerTests: XCTestCase {
    func testRunnerEnvironmentIncludesHomebrewAndLocalBin() {
        let env = ProcessCommandRunner.environment(base: ["PATH": "/usr/bin:/bin", "HOME": "/Users/a"], home: "/Users/a")
        XCTAssertTrue(env["PATH"]!.hasPrefix("/opt/homebrew/bin:/Users/a/.local/bin:"))
        XCTAssertEqual(env["HOME"], "/Users/a")
    }
    func testProcessRunnerCapturesOutputAndExit() async {
        let r = await ProcessCommandRunner().run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"])
        XCTAssertEqual(r, CommandResult(exitCode: 3, stdout: "out\n", stderr: "err\n"))
    }
    func testProcessRunnerMissingExecutable() async {
        let r = await ProcessCommandRunner().run("/nope/brag", ["gather"])
        XCTAssertEqual(r.exitCode, -1)
        XCTAssertFalse(r.stderr.isEmpty)
    }
}
final class FakeRunner: CommandRunner {
    var calls: [[String]] = []
    var result = CommandResult(exitCode: 0, stdout: "wrote /v/Brag/2026-W42.md\n", stderr: "")
    var onRun: (() async -> Void)?
    func run(_ executable: String, _ args: [String]) async -> CommandResult {
        calls.append(args)
        await onRun?()
        return result
    }
}

final class FakePoster: NotificationPosting {
    var granted = true
    var posted: [(title: String, category: String, after: TimeInterval?, userInfo: [AnyHashable: Any])] = []
    func post(_ content: UNNotificationContent, after seconds: TimeInterval?) async -> Bool {
        guard granted else { return false }
        posted.append((content.title, content.categoryIdentifier, seconds, content.userInfo))
        return true
    }
}

@MainActor
final class BragControllerTests: XCTestCase {
    var runner: FakeRunner!
    var poster: FakePoster!
    var fallback: FallbackChoice = .skip
    var alerts: [Int] = []
    var messages: [String] = []
    var opened: [URL] = []
    var scheduled: [TimeInterval] = []
    var exists = true

    override func setUp() async throws {
        AppSettings.defaults = UserDefaults(suiteName: "com.zoidberg.tests.brag")!
        AppSettings.defaults.removePersistentDomain(forName: "com.zoidberg.tests.brag")
        runner = FakeRunner(); poster = FakePoster()
        alerts = []; messages = []; opened = []; scheduled = []; fallback = .skip; exists = true
    }

    func make() -> BragController {
        BragController(runner: runner, notifications: poster, fileExists: { [unowned self] _ in self.exists },
                       fallbackAlert: { [unowned self] days in self.alerts.append(days); return self.fallback },
                       showMessage: { [unowned self] title, _ in self.messages.append(title) },
                       openURL: { [unowned self] url in self.opened.append(url) },
                       scheduleLater: { [unowned self] seconds, _ in self.scheduled.append(seconds) })
    }

    func testNudgePostsReviewNotification() async {
        await make().handle(.nudge(days: 2))
        XCTAssertEqual(poster.posted.map(\.title), ["Brag review"])
        XCTAssertNil(poster.posted[0].after)
    }

    func testReviewNowRunsBragReviewInTerminal() async {
        await make().didReceive(action: BragIDs.reviewAction, category: BragIDs.reviewCategory, userInfo: ["days": 2])
        await make().didReceive(action: UNNotificationDefaultActionIdentifier, category: BragIDs.reviewCategory, userInfo: [:])
        XCTAssertEqual(runner.calls, [["review", "--in-terminal"], ["review", "--in-terminal"]])
    }

    func testLaterFromDeliveredNotificationKeepsDays() async {
        await make().didReceive(action: BragIDs.laterAction, category: BragIDs.reviewCategory, userInfo: ["days": 4])
        XCTAssertEqual(poster.posted.count, 1)
        XCTAssertEqual(poster.posted[0].after, 3600)
        XCTAssertEqual(poster.posted[0].userInfo["days"] as? Int, 4)
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testNudgeFallsBackWhenNotificationsDenied() async {
        poster.granted = false; fallback = .reviewNow
        await make().handle(.nudge(days: 3))
        XCTAssertEqual(alerts, [3])
        XCTAssertEqual(runner.calls, [["review", "--in-terminal"]])
    }

    func testFallbackLaterReschedulesWithoutNotifications() async {
        poster.granted = false; fallback = .later
        AppSettings.bragLaterSeconds = 60
        await make().handle(.nudge(days: 1))
        XCTAssertEqual(scheduled, [60])
    }

    func testUpdateNowPostsResultAndResultClickOpensNote() async {
        let c = make()
        await c.updateNow()
        XCTAssertEqual(runner.calls, [["gather"]])
        XCTAssertEqual(poster.posted.map(\.title), ["Brag notes updated"])
        await c.didReceive(action: UNNotificationDefaultActionIdentifier, category: BragIDs.resultCategory,
                           userInfo: poster.posted[0].userInfo)
        XCTAssertEqual(opened.map(\.absoluteString), ["obsidian://open?path=/v/Brag/2026-W42.md"])
        XCTAssertFalse(c.isUpdating)
    }

    func testUpdateNowIgnoredWhileRunning() async {
        let c = make()
        runner.onRun = { [unowned c] in await c.updateNow() }   // re-entrant click while running
        await c.updateNow()
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testMissingBragPostsNotFound() async {
        exists = false
        await make().updateNow()
        await make().reviewNow()
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertEqual(poster.posted.map(\.title), ["brag CLI not found", "brag CLI not found"])
    }

    func testResultFallsBackToMessageWhenDenied() async {
        poster.granted = false
        await make().updateNow()
        XCTAssertEqual(messages, ["Brag notes updated"])
    }
}
