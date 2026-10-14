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
