# Zoidberg Brag Front End Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zoidberg posts a clickable "Brag review" notification when it receives `zoidberg://brag-nudge`, and gets two menu-bar actions, "Brag: Update now" and "Brag: Review…". Both drive the `brag` CLI. `brag nudge` is changed to send its nudge through Zoidberg.

**Architecture:**
- **Pure logic:** new Swift units hold everything that can be unit-tested with `swift test`: URL routing, notification content, mapping a CLI run to a result, and a `BragController` that takes its runner and notification poster as protocol parameters.
- **System glue:** only a thin layer in `AppDelegate` touches the system: `UNUserNotificationCenter`, `NSMenu`, `NSAlert`, `SMAppService`.
- **brag-tracker:** keeps everything else. It gains `review --in-terminal` and a Zoidberg-first `nudge`.

**Tech Stack:** Swift 5 mode with Xcode 26.6 / Swift 6.3 toolchain, macOS 14+, AppKit + SwiftUI, UserNotifications, ServiceManagement, XCTest via SwiftPM (`swift test`), Xcode project for the app bundle (`xcodebuild -target Zoidberg`). brag-tracker uses Python 3.13 stdlib with `unittest`.

**Spec:** `docs/superpowers/specs/2026-10-14-brag-front-end-design.md`

## Global Constraints

- **Scope:** no manual "log a win" capture and no unreviewed-count badge. Zoidberg never runs gather or review logic itself; it only runs `brag gather` and `brag review --in-terminal`.
- **URL scheme `zoidberg`:** hosts are `brag-nudge`, with query `days=<int>`, and `brag-review`. Unknown URLs are ignored.
- **Notification categories:**
  - `BRAG_REVIEW`, with actions `BRAG_REVIEW_NOW` ("Review now") and `BRAG_LATER` ("Later")
  - `BRAG_RESULT`, with no actions
  - thread id `brag`
- **Review notification:** title "Brag review"; body "N days captured since your last review" ("1 day …" when N is 1).
- **Result notifications:**
  - "Brag notes updated": body is the CLI's `wrote …` line; click opens `obsidian://open?path=<path>`.
  - "Brag update failed": body is the first stderr line; click opens `~/Library/Logs/brag-tracker.log`.
  - "A gather is already running": no click action.
  - "brag CLI not found at <path>": no click action.
- **Settings (UserDefaults, no UI):**
  - `AppSettings.bragPath`, default `~/.local/bin/brag`
  - `AppSettings.bragLaterSeconds`, default `3600`
- **Child-process PATH:** child processes get `PATH=/opt/homebrew/bin:~/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin`. An app launched from Finder has a minimal PATH, and `brag`'s `#!/usr/bin/env python3` must resolve to Homebrew's 3.13.
- **Launch at login:** the existing toggle now really calls `SMAppService.mainApp.register()` / `unregister()`.
- **Install location:** `~/Applications/Zoidberg.app`. The app isn't sandboxed and there are no new entitlements.
- **brag-tracker changes:**
  - `config.json` gains `"front_end": "zoidberg"`.
  - `nudge` uses `open -g "zoidberg://brag-nudge?days=N"` when the front end is `zoidberg` and the app exists at `~/Applications/Zoidberg.app` or `/Applications/Zoidberg.app`. Otherwise it uses the dialog.
  - The dialog runs inside `tell application (path to frontmost application as text)`.
  - Logging distinguishes `timed out`, `error …` and button choices.
- **Commits:** every commit ends with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. Don't push either repo.

## Review Focus

1. **Zoidberg isn't running when the nudge fires.** `open -g zoidberg://…` cold-launches it, and the URL must still be handled after `applicationDidFinishLaunching`. Pinned by the cold-launch manual check in Task 6, Step 4.
2. **Notifications are denied or never granted.** The nudge must still reach Alex through a frontmost `NSAlert`, and Later must work without notifications. Pinned in Task 3 by `testNudgeFallsBackWhenNotificationsDenied` and `testFallbackLaterReschedulesWithoutNotifications`.
3. **A notification is clicked after Zoidberg has restarted** (it sat in Notification Center over a relaunch). The `days` value travels in `userInfo`, so the new process handles it correctly. Pinned in Task 3 by `testLaterFromDeliveredNotificationKeepsDays`.
4. **Launched from Finder with a minimal PATH, or `brag` is missing.** `brag`'s python must still resolve, and a missing CLI must produce a clear notification. Pinned by `testRunnerEnvironmentIncludesHomebrewAndLocalBin` (Task 2) and `testMissingBragPostsNotFound` (Task 3).
5. **A second Update while a gather is running,** either from Zoidberg or because launchd's 18:00 run holds the lock. Expected: the second click is ignored, and the lock case shows "A gather is already running". Pinned by `testUpdateNowIgnoredWhileRunning` (Task 3) and `testExitZeroWithoutWroteIsAlreadyRunning` (Task 2).

---

## File Structure

```
zoidberg/
  Zoidberg/Info.plist                         # + CFBundleURLTypes (zoidberg)
  Zoidberg/ZoidbergApp.swift                  # AppDelegate: URL handling, UN delegate, menu items
  Zoidberg/Helpers/Settings.swift             # + bragPath, bragLaterSeconds
  Zoidberg/Helpers/LoginItem.swift            # NEW: SMAppService wrapper behind a protocol
  Zoidberg/Views/SettingsView.swift           # launchAtLogin toggle → LoginItem.set
  Zoidberg/Services/CommandRunner.swift       # NEW: CommandResult, CommandRunner, ProcessCommandRunner
  Zoidberg/Services/BragURLRouter.swift       # NEW: BragRoute + URL parsing
  Zoidberg/Services/BragNotifications.swift   # NEW: ids, content builders, BragUpdateResult, NotificationPosting, SystemNotificationPoster
  Zoidberg/Services/BragController.swift      # NEW: @MainActor orchestration
  Zoidberg.xcodeproj/project.pbxproj          # register the 5 new files
  ZoidbergTests/ClaudeServiceTests.swift      # drop 3 stale tests (pre-existing breakage)
  ZoidbergTests/BragTests.swift               # NEW
  ZoidbergTests/SettingsTests.swift           # + brag settings tests
brag-tracker/
  config.json, lib/bragtracker/nudge.py, bin/brag, tests/test_nudge.py
```

---

### Task 1: Restore a green baseline, brag settings, and project wiring

**Files:**
- Modify: `ZoidbergTests/ClaudeServiceTests.swift`, `Zoidberg/Helpers/Settings.swift`, `ZoidbergTests/SettingsTests.swift`, `Zoidberg.xcodeproj/project.pbxproj`, `.gitignore`
- Create: empty `Zoidberg/Services/CommandRunner.swift`, `Zoidberg/Services/BragURLRouter.swift`, `Zoidberg/Services/BragNotifications.swift`, `Zoidberg/Services/BragController.swift`, `Zoidberg/Helpers/LoginItem.swift` (later tasks fill them in)

**Interfaces:**
- Produces:
  - `AppSettings.bragPath: String` (default `NSHomeDirectory() + "/.local/bin/brag"`)
  - `AppSettings.bragLaterSeconds: Double` (default `3600`)
  - the five new files, registered in the Xcode target

- [ ] **Step 1: Confirm the baseline is broken**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`

Expected: `ClaudeServiceTests.swift: error: type 'ClaudeService' has no member 'parseEnhanceResponse'`. These are pre-existing. The `cleanup` refactor removed the enhance API, and the tests weren't updated.

- [ ] **Step 2: Delete the three stale tests**

Remove `testParseEnhanceResponse`, `testParseEnhanceResponseHandlesMalformed` and `testBuildPrompt` from `ZoidbergTests/ClaudeServiceTests.swift`. Keep `testDisabledWhenNoApiKey` and `testEnabledWithApiKey`.

Run: `swift test 2>&1 | tail -3`
Expected: `Executed N tests, with 0 failures`. If any other existing test fails, stop and record it as a ruling before continuing.

- [ ] **Step 3: Write the failing settings tests** (add to `SettingsTests`)

```swift
    func testBragPathDefault() {
        XCTAssertEqual(AppSettings.bragPath, NSHomeDirectory() + "/.local/bin/brag")
    }

    func testBragLaterSecondsDefaultAndOverride() {
        XCTAssertEqual(AppSettings.bragLaterSeconds, 3600)
        AppSettings.defaults.set(60.0, forKey: "bragLaterSeconds")
        XCTAssertEqual(AppSettings.bragLaterSeconds, 60)
    }
```

Run: `swift test --filter SettingsTests 2>&1 | grep -E "error:|Executed"`
Expected: a compile error, `type 'AppSettings' has no member 'bragPath'`.

- [ ] **Step 4: Implement the settings** (append inside `enum AppSettings`)

```swift
    static var bragPath: String {
        get { defaults.string(forKey: "bragPath") ?? NSHomeDirectory() + "/.local/bin/brag" }
        set { defaults.set(newValue, forKey: "bragPath") }
    }

    static var bragLaterSeconds: Double {
        get { (defaults.object(forKey: "bragLaterSeconds") as? Double) ?? 3600 }
        set { defaults.set(newValue, forKey: "bragLaterSeconds") }
    }
```

Run: `swift test --filter SettingsTests 2>&1 | tail -2`
Expected: 0 failures.

- [ ] **Step 5: Create the five empty files and register them in the Xcode project**

```bash
for f in Services/CommandRunner Services/BragURLRouter Services/BragNotifications Services/BragController Helpers/LoginItem; do printf 'import Foundation\n' > "Zoidberg/$f.swift"; done
grep -cE "A1003[0-9]|B1003[0-9]" Zoidberg.xcodeproj/project.pbxproj   # expect 0 (IDs free)
python3 - <<'EOF'
p = "Zoidberg.xcodeproj/project.pbxproj"
s = open(p).read()
files = [("A10030", "B10030", "CommandRunner.swift", "B10011 /* HotkeyManager.swift */,"),
         ("A10031", "B10031", "BragURLRouter.swift", "B10011 /* HotkeyManager.swift */,"),
         ("A10032", "B10032", "BragNotifications.swift", "B10011 /* HotkeyManager.swift */,"),
         ("A10033", "B10033", "BragController.swift", "B10011 /* HotkeyManager.swift */,"),
         ("A10034", "B10034", "LoginItem.swift", "B10016 /* EscapeKeyMonitor.swift */,")]
for a, b, name, anchor in files:
    s = s.replace("/* End PBXBuildFile section */",
        f"\t\t{a} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {b} /* {name} */; }};\n/* End PBXBuildFile section */")
    s = s.replace("/* End PBXFileReference section */",
        f"\t\t{b} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};\n/* End PBXFileReference section */")
    s = s.replace(f"\t\t\t\t{anchor}\n", f"\t\t\t\t{anchor}\n\t\t\t\t{b} /* {name} */,\n", 1)
    s = s.replace("\t\t\t\tA10016 /* EscapeKeyMonitor.swift in Sources */,\n",
                  f"\t\t\t\tA10016 /* EscapeKeyMonitor.swift in Sources */,\n\t\t\t\t{a} /* {name} in Sources */,\n", 1)
open(p, "w").write(s)
EOF
printf 'build/\n' >> .gitignore
xcodebuild -project Zoidberg.xcodeproj -target Zoidberg -configuration Debug SYMROOT=build build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | head -5
```

Expected: the ID grep prints `0`, then `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add ZoidbergTests/ClaudeServiceTests.swift ZoidbergTests/SettingsTests.swift Zoidberg/Helpers/Settings.swift Zoidberg/Services/*.swift Zoidberg/Helpers/LoginItem.swift Zoidberg.xcodeproj/project.pbxproj .gitignore
git commit -m "Restore green tests, add brag settings and register brag source files

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Command runner, URL router, notification content and result mapping

**Files:**
- Modify: `Zoidberg/Services/CommandRunner.swift`, `Zoidberg/Services/BragURLRouter.swift`, `Zoidberg/Services/BragNotifications.swift`
- Test: `ZoidbergTests/BragTests.swift`

**Interfaces:**
- Produces:
  - `struct CommandResult: Equatable { exitCode: Int32; stdout: String; stderr: String }`
  - `protocol CommandRunner { func run(_ executable: String, _ args: [String]) async -> CommandResult }`
  - `struct ProcessCommandRunner: CommandRunner`, plus `static func environment(base: [String: String], home: String) -> [String: String]`
  - `enum BragRoute: Equatable { case nudge(days: Int), review }`
  - `enum BragURLRouter { static func route(_ url: URL) -> BragRoute? }`
  - `enum BragIDs`, with constants `reviewCategory`, `resultCategory`, `reviewAction`, `laterAction`, `thread`
  - `enum BragUpdateResult: Equatable { case success(message: String, notePath: String?), alreadyRunning, failure(message: String), notFound(path: String) }`, with `static func from(_ r: CommandResult) -> BragUpdateResult` and `var openURL: URL?`
  - `enum BragContent`, with `static func review(days: Int) -> UNMutableNotificationContent` and `static func result(_ r: BragUpdateResult) -> UNMutableNotificationContent`

- [ ] **Step 1: Write the failing tests `ZoidbergTests/BragTests.swift`**

```swift
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
```

Run: `swift test --filter "Brag|CommandRunner" 2>&1 | grep -E "error:|Executed" | head -3`
Expected: compile errors, e.g. `cannot find 'BragURLRouter' in scope`.

- [ ] **Step 2: Implement `Zoidberg/Services/CommandRunner.swift`**

```swift
import Foundation

struct CommandResult: Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

protocol CommandRunner {
    func run(_ executable: String, _ args: [String]) async -> CommandResult
}

struct ProcessCommandRunner: CommandRunner {
    static func environment(base: [String: String], home: String) -> [String: String] {
        var env = base
        env["PATH"] = "/opt/homebrew/bin:\(home)/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOME"] = home
        return env
    }

    func run(_ executable: String, _ args: [String]) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                process.environment = Self.environment(base: ProcessInfo.processInfo.environment, home: NSHomeDirectory())
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: CommandResult(exitCode: -1, stdout: "", stderr: error.localizedDescription))
                    return
                }
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                continuation.resume(returning: CommandResult(exitCode: process.terminationStatus,
                                                             stdout: String(decoding: outData, as: UTF8.self),
                                                             stderr: String(decoding: errData, as: UTF8.self)))
            }
        }
    }
}
```

- [ ] **Step 3: Implement `Zoidberg/Services/BragURLRouter.swift`**

```swift
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
```

- [ ] **Step 4: Implement `Zoidberg/Services/BragNotifications.swift`** (content and results only; the poster comes in Task 3)

```swift
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
```

Note: in `testResultContentCarriesOpenURL`, the path `/v/Brag/2026-W42.md` has no spaces, so the encoded URL equals the raw string.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `swift test 2>&1 | tail -3`
Expected: 0 failures, including the new Router, Content, UpdateResult and CommandRunner tests.

- [ ] **Step 6: Commit**

```bash
git add Zoidberg/Services/CommandRunner.swift Zoidberg/Services/BragURLRouter.swift Zoidberg/Services/BragNotifications.swift ZoidbergTests/BragTests.swift
git commit -m "Add brag URL routing, notification content and CLI result mapping

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: BragController and the notification poster

**Files:**
- Modify: `Zoidberg/Services/BragController.swift`, `Zoidberg/Services/BragNotifications.swift` (append the poster)
- Test: `ZoidbergTests/BragTests.swift` (append)

**Interfaces:**
- Consumes: everything Task 2 produces, plus `AppSettings.bragPath` and `bragLaterSeconds`.
- Produces:
  - `protocol NotificationPosting { func post(_ content: UNNotificationContent, after seconds: TimeInterval?) async -> Bool }`
  - `final class SystemNotificationPoster: NotificationPosting`, with `func registerCategories()`
  - `enum FallbackChoice { case reviewNow, later, skip }`
  - `@MainActor final class BragController`, with:
    - `init(runner:notifications:fileExists:fallbackAlert:showMessage:openURL:scheduleLater:)`
    - `isUpdating: Bool`, `onUpdatingChanged: ((Bool) -> Void)?`
    - `handle(_: BragRoute) async`, `nudge(days:) async`, `reviewNow() async`, `updateNow() async`
    - `didReceive(action: String, category: String, userInfo: [AnyHashable: Any]) async`

- [ ] **Step 1: Write the failing tests** (append to `BragTests.swift`)

```swift
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
```

Run: `swift test --filter BragControllerTests 2>&1 | grep -E "error:|Executed" | head -3`
Expected: a compile error, `cannot find 'BragController' in scope` or `cannot find type 'NotificationPosting'`.

- [ ] **Step 2: Append the poster to `Zoidberg/Services/BragNotifications.swift`**

```swift
protocol NotificationPosting {
    func post(_ content: UNNotificationContent, after seconds: TimeInterval?) async -> Bool
}

final class SystemNotificationPoster: NotificationPosting {
    private var center: UNUserNotificationCenter { .current() }

    func registerCategories() {
        let review = UNNotificationCategory(
            identifier: BragIDs.reviewCategory,
            actions: [UNNotificationAction(identifier: BragIDs.reviewAction, title: "Review now", options: []),
                      UNNotificationAction(identifier: BragIDs.laterAction, title: "Later", options: [])],
            intentIdentifiers: [])
        let result = UNNotificationCategory(identifier: BragIDs.resultCategory, actions: [], intentIdentifiers: [])
        center.setNotificationCategories([review, result])
    }

    func post(_ content: UNNotificationContent, after seconds: TimeInterval?) async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }
        let trigger = seconds.map { UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0), repeats: false) }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }
}
```

The spec says Review now uses `.foreground`. This plan uses no options, because the click opens Ghostty, not a Zoidberg window. Bringing the windowless `LSUIElement` app forward does nothing useful.

- [ ] **Step 3: Implement `Zoidberg/Services/BragController.swift`**

```swift
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
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test 2>&1 | tail -3`
Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Zoidberg/Services/BragController.swift Zoidberg/Services/BragNotifications.swift ZoidbergTests/BragTests.swift
git commit -m "Add BragController and system notification poster

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Wire it into the app (URL scheme, notification delegate, menu, launch at login)

**Files:**
- Modify: `Zoidberg/Info.plist`, `Zoidberg/ZoidbergApp.swift`, `Zoidberg/Helpers/LoginItem.swift`, `Zoidberg/Views/SettingsView.swift`
- Test: `ZoidbergTests/BragTests.swift` (append the LoginItem and menu-title tests)

**Interfaces:**
- Consumes:
  - `BragController`, `SystemNotificationPoster`, `ProcessCommandRunner`, `BragURLRouter`, `FallbackChoice`
- Produces:
  - `protocol LoginItemService { func register() throws; func unregister() throws }`
  - `enum LoginItem { static func set(_ enabled: Bool, service: LoginItemService) -> Bool }`
  - `enum BragMenu { static func updateTitle(isUpdating: Bool) -> String }`

- [ ] **Step 1: Write the failing tests** (append)

```swift
final class FakeLoginService: LoginItemService {
    var registered: Bool? = nil
    var fail = false
    func register() throws { if fail { throw NSError(domain: "t", code: 1) }; registered = true }
    func unregister() throws { if fail { throw NSError(domain: "t", code: 1) }; registered = false }
}

final class LoginItemTests: XCTestCase {
    func testSetRegistersAndUnregisters() {
        let s = FakeLoginService()
        XCTAssertTrue(LoginItem.set(true, service: s)); XCTAssertEqual(s.registered, true)
        XCTAssertTrue(LoginItem.set(false, service: s)); XCTAssertEqual(s.registered, false)
    }
    func testFailureReported() {
        let s = FakeLoginService(); s.fail = true
        XCTAssertFalse(LoginItem.set(true, service: s))
    }
}

final class BragMenuTests: XCTestCase {
    func testUpdateTitle() {
        XCTAssertEqual(BragMenu.updateTitle(isUpdating: false), "Brag: Update now")
        XCTAssertEqual(BragMenu.updateTitle(isUpdating: true), "Brag: Updating…")
    }
}
```

Run: `swift test --filter "LoginItemTests|BragMenuTests" 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find type 'LoginItemService'`.

- [ ] **Step 2: Implement `Zoidberg/Helpers/LoginItem.swift`**

```swift
import Foundation
import ServiceManagement
import os

protocol LoginItemService {
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

enum LoginItem {
    private static let log = Logger(subsystem: "com.malecks.zoidberg", category: "login-item")

    @discardableResult
    static func set(_ enabled: Bool, service: LoginItemService = SMAppService.mainApp) -> Bool {
        do {
            if enabled { try service.register() } else { try service.unregister() }
            return true
        } catch {
            log.error("launch at login \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
            return false
        }
    }
}

enum BragMenu {
    static func updateTitle(isUpdating: Bool) -> String {
        isUpdating ? "Brag: Updating…" : "Brag: Update now"
    }
}
```

- [ ] **Step 3: Apply the toggle in `SettingsView.swift`**

Change the existing `.onChange(of: launchAtLogin)` body so it also calls `LoginItem.set`:

```swift
        .onChange(of: launchAtLogin) { _, newValue in
            AppSettings.launchAtLogin = newValue
            LoginItem.set(newValue)
        }
```

Read the surrounding lines first, keep any other statements already in that closure, and only add the `LoginItem.set(newValue)` line.

- [ ] **Step 4: Register the URL scheme in `Zoidberg/Info.plist`** (add inside `<dict>`)

```xml
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.malecks.zoidberg.brag</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>zoidberg</string>
            </array>
        </dict>
    </array>
```

- [ ] **Step 5: Wire up `AppDelegate` in `Zoidberg/ZoidbergApp.swift`**

1. Add `import UserNotifications` at the top.
2. Add stored properties to `AppDelegate`:

```swift
    private let bragPoster = SystemNotificationPoster()
    private lazy var brag = BragController(
        runner: ProcessCommandRunner(),
        notifications: bragPoster,
        fallbackAlert: { days in
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Brag review"
            alert.informativeText = days == 1 ? "1 day captured since your last review" : "\(days) days captured since your last review"
            alert.addButton(withTitle: "Review now")
            alert.addButton(withTitle: "Later")
            alert.addButton(withTitle: "Skip")
            switch alert.runModal() {
            case .alertFirstButtonReturn: return .reviewNow
            case .alertSecondButtonReturn: return .later
            default: return .skip
            }
        },
        showMessage: { title, body in
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = body
            alert.runModal()
        },
        openURL: { NSWorkspace.shared.open($0) },
        scheduleLater: { seconds, work in DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work) })
```

3. At the start of `applicationDidFinishLaunching`, add:

```swift
        UNUserNotificationCenter.current().delegate = self
        bragPoster.registerCategories()
        if AppSettings.launchAtLogin { LoginItem.set(true) }
```

4. Add URL handling and the delegate conformance (put the extension at the bottom of the file):

```swift
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let route = BragURLRouter.route(url) else { continue }
            Task { await brag.handle(route) }
        }
    }
```

```swift
extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        let info = response.notification.request.content.userInfo
        Task { @MainActor in
            await self.brag.didReceive(action: action, category: category, userInfo: info)
            completionHandler()
        }
    }
}
```

5. Put the brag items at the top of `showContextMenu()`, before the `Settings...` item:

```swift
        let update = NSMenuItem(title: BragMenu.updateTitle(isUpdating: brag.isUpdating),
                                action: brag.isUpdating ? nil : #selector(bragUpdateNow), keyEquivalent: "")
        update.target = self
        menu.addItem(update)
        let review = NSMenuItem(title: "Brag: Review…", action: #selector(bragReview), keyEquivalent: "")
        review.target = self
        menu.addItem(review)
        menu.addItem(.separator())
```

and add the actions:

```swift
    @objc private func bragUpdateNow() { Task { await brag.updateNow() } }
    @objc private func bragReview() { Task { await brag.reviewNow() } }
```

If Swift 5 mode reports a Sendable warning on capturing `info` or `completionHandler`, that's acceptable: warnings, not errors. If it reports an error, wrap the captured values in a small `@unchecked Sendable` struct and record that as a ruling.

- [ ] **Step 6: Run the tests, then build the app**

Run: `swift test 2>&1 | tail -3`
Expected: 0 failures.

Run: `xcodebuild -project Zoidberg.xcodeproj -target Zoidberg -configuration Debug SYMROOT=build build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | head -5`
Expected: `** BUILD SUCCEEDED **`.

Run: `/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes:0" build/Debug/Zoidberg.app/Contents/Info.plist`
Expected: `zoidberg`.

- [ ] **Step 7: Commit**

```bash
git add Zoidberg/Info.plist Zoidberg/ZoidbergApp.swift Zoidberg/Helpers/LoginItem.swift Zoidberg/Views/SettingsView.swift ZoidbergTests/BragTests.swift
git commit -m "Wire brag URL scheme, notifications, menu items and launch at login

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: brag-tracker, with Zoidberg-first nudge and `review --in-terminal`

**Gate:** the developer-1e review fix pass must be merged into brag-tracker `main`. Run `cd ~/Developer/brag-tracker && git status --short && git log --oneline -5`. Proceed only if the working tree is clean, and no other Claude session is busy in that repo (check with `ListAgents`). Otherwise stop and report. Re-read `lib/bragtracker/nudge.py`, `bin/brag` and `tests/test_nudge.py` before editing. The fix pass may have changed them, so adapt the edits below to the merged code and record any adaptation as a ruling. Work on a new branch: `git switch -c zoidberg-front-end`.

**Files:**
- Modify: `~/Developer/brag-tracker/config.json`, `lib/bragtracker/nudge.py`, `bin/brag`
- Test: `~/Developer/brag-tracker/tests/test_nudge.py`

**Interfaces:**
- Produces:
  - `nudge.zoidberg_installed() -> bool`
  - `nudge.send_to_zoidberg(days: int) -> bool`
  - `nudge.show_dialog(text) -> str`, which now returns a button title, `"timed out"` or `"error: …"`
  - `run_nudge(cfg, again=False, force=False, dialog=show_dialog, opener=open_review, later=schedule_later, zoidberg=send_to_zoidberg, installed=zoidberg_installed) -> str`
  - `parse_dialog(returncode: int, stdout: str, stderr: str) -> str`
  - CLI flag `brag review --in-terminal`

- [ ] **Step 1: Write the failing tests** (append to `tests/test_nudge.py`)

First, add `cfg["front_end"] = "dialog"` inside the existing `make_cfg()` in `tests/test_nudge.py`, just before `return cfg`. `config.json` now defaults to `zoidberg`, and without this the existing `NudgeTest` cases would fire a real `open zoidberg://…` once Zoidberg is installed. `FrontEndTest` sets `zoidberg` explicitly.

```python
class FrontEndTest(unittest.TestCase):
    def setUp(self):
        self.cfg = make_cfg()
        self.cfg["front_end"] = "zoidberg"
        weeknote.upsert_day_section(self.cfg["vault_dir"], date(2026, 10, 14), "### Shipped / code\n- x")
        self.events = []

    def nudge(self, installed=True, sent=True, choice="Skip", **kw):
        return nudge.run_nudge(self.cfg, dialog=lambda t: (self.events.append("dialog"), choice)[1],
                               opener=lambda c: self.events.append("open"), later=lambda c: self.events.append("later"),
                               zoidberg=lambda days: (self.events.append(("zoidberg", days)), sent)[1],
                               installed=lambda: installed, **kw)

    def test_uses_zoidberg_when_installed(self):
        self.assertEqual(self.nudge(), "sent to zoidberg")
        self.assertEqual(self.events, [("zoidberg", 1)])

    def test_falls_back_to_dialog_when_not_installed_or_send_fails(self):
        self.nudge(installed=False)
        self.nudge(sent=False)
        self.assertEqual(self.events, ["dialog", ("zoidberg", 1), "dialog"])

    def test_front_end_dialog_forces_dialog(self):
        self.cfg["front_end"] = "dialog"
        self.nudge()
        self.assertEqual(self.events, ["dialog"])

    def test_parse_dialog_distinguishes_timeout_and_error(self):
        self.assertEqual(nudge.parse_dialog(0, "button returned:Review now, gave up:false\n", ""), "Review now")
        self.assertEqual(nudge.parse_dialog(0, "button returned:, gave up:true\n", ""), "timed out")
        self.assertEqual(nudge.parse_dialog(1, "", "execution error: Not authorized (-1743)\n"), "error: execution error: Not authorized (-1743)")
```

Run: `PYTHONPATH=lib python3 -m unittest tests/test_nudge.py 2>&1 | tail -3`
Expected: errors, `run_nudge() got an unexpected keyword argument 'zoidberg'` and `module ... has no attribute 'parse_dialog'`.

- [ ] **Step 2: Implement in `lib/bragtracker/nudge.py`**

Add these, and replace `show_dialog`:

```python
from pathlib import Path

ZOIDBERG_APPS = [Path.home() / "Applications" / "Zoidberg.app", Path("/Applications/Zoidberg.app")]


def zoidberg_installed() -> bool:
    return any(p.exists() for p in ZOIDBERG_APPS)


def send_to_zoidberg(days: int) -> bool:
    r = subprocess.run(["open", "-g", f"zoidberg://brag-nudge?days={days}"], capture_output=True, text=True)
    return r.returncode == 0


def parse_dialog(returncode: int, stdout: str, stderr: str) -> str:
    if returncode != 0:
        return "error: " + (stderr.strip().splitlines() or ["osascript failed"])[0]
    if "gave up:true" in stdout:
        return "timed out"
    m = re.search(r"button returned:([^,\n]*)", stdout)
    return m.group(1).strip() if m and m.group(1).strip() else "timed out"


def show_dialog(text: str) -> str:
    buttons = ", ".join(json.dumps(b) for b in BUTTONS)
    script = ("tell application (path to frontmost application as text) to "
              f"display dialog {json.dumps(text)} with title \"Brag review\" "
              f"buttons {{{buttons}}} default button \"Review now\" giving up after 3600")
    r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    return parse_dialog(r.returncode, r.stdout, r.stderr)
```

Then change `run_nudge` to:

```python
def run_nudge(cfg, again=False, force=False, dialog=show_dialog, opener=open_review, later=schedule_later,
              zoidberg=send_to_zoidberg, installed=zoidberg_installed) -> str:
    notes = weeknote.list_unreviewed(cfg["vault_dir"])
    days = sum(weeknote.count_days(p) for p in notes)
    if days == 0 and not force:
        return "nothing"
    if cfg.get("front_end", "zoidberg") == "zoidberg" and installed() and zoidberg(days):
        return "sent to zoidberg"
    choice = dialog(f"Time to review your brag notes — {days} day(s) captured since your last review.")
    if choice == "Review now":
        opener(cfg)
    elif choice.startswith("Later") and not again:
        later(cfg)
    return choice
```

- [ ] **Step 3: Add `"front_end": "zoidberg"` to `config.json`, and `--in-terminal` to `bin/brag`**

In `bin/brag`, replace `sub.add_parser("review", ...)` with:

```python
    r = sub.add_parser("review", help="interactive weekly review; adds approved highlights to Notion")
    r.add_argument("--in-terminal", action="store_true", help="open the configured terminal running `brag review`")
```

and the review dispatch with:

```python
    if args.cmd == "review":
        if args.in_terminal:
            nudge.open_review(cfg)
            return 0
        return review.run_review(cfg)
```

- [ ] **Step 4: Run all the tests**

Run: `PYTHONPATH=lib python3 -m unittest discover -s tests 2>&1 | grep -E "^Ran|^OK|^FAILED"`
Expected: `OK`.

- [ ] **Step 5: Commit, then merge into brag-tracker main**

```bash
git add config.json lib/bragtracker/nudge.py bin/brag tests/test_nudge.py
git commit -m "Send the Friday nudge through Zoidberg; add review --in-terminal

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git switch main && git merge --ff-only zoidberg-front-end
```

---

### Task 6: Install and check end to end

**Files:** none (install and manual checks). Record results in the ledger.

- [ ] **Step 1: Release build and install**

```bash
cd ~/Developer/zoidberg
xcodebuild -project Zoidberg.xcodeproj -target Zoidberg -configuration Release SYMROOT=build build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | head -3
pkill -x Zoidberg || true
mkdir -p ~/Applications && rm -rf ~/Applications/Zoidberg.app && cp -R build/Release/Zoidberg.app ~/Applications/
codesign -dv ~/Applications/Zoidberg.app 2>&1 | grep -E "Authority|Identifier" | head -3
open ~/Applications/Zoidberg.app
```

Expected:
- `** BUILD SUCCEEDED **`
- `Identifier=com.malecks.zoidberg`, signed by "Apple Development: …"
- the Zoidberg icon appears in the menu bar

- [ ] **Step 2: Check the notification and the review click-through** (needs Alex at the screen)

Run: `open -g "zoidberg://brag-nudge?days=2"`

Expected:
- **First time only:** macOS asks to allow Zoidberg's notifications. Alex clicks Allow.
- A "Brag review — 2 days captured…" notification appears.
- Clicking **Review now** opens Ghostty running `brag review`. Alex can exit right away and answer **n** to "mark reviewed".

- [ ] **Step 3: Check Later and the menu items**

```bash
defaults write com.malecks.zoidberg bragLaterSeconds 60
open -g "zoidberg://brag-nudge?days=2"
```

Then:
1. Alex clicks **Later**. Expected: the notification comes back about 60 s later.
2. Run `defaults delete com.malecks.zoidberg bragLaterSeconds`.
3. Right-click the menu-bar icon. Expected: "Brag: Update now" and "Brag: Review…" sit above Settings….
4. Choose **Update now**. Expected: the item reads "Brag: Updating…" (greyed out) on the next right-click. After about 3–5 min, "Brag notes updated" appears, and clicking it opens the week note in Obsidian.

- [ ] **Step 4: Cold launch and launchd end to end**

```bash
pkill -x Zoidberg
launchctl kickstart -k gui/$(id -u)/com.alexmathers.brag-tracker.nudge
sleep 5; tail -2 ~/Library/Logs/brag-tracker.log; pgrep -x Zoidberg
```

Expected:
- Zoidberg relaunches (it shows up in `pgrep`).
- The log shows `nudge: sent to zoidberg`.
- The review notification appears.

- [ ] **Step 5: Launch at login, and the persistent style**

Alex turns on Zoidberg Settings → Launch at login, then checks that Zoidberg appears in System Settings → General → Login Items. Then, in System Settings → Notifications → Zoidberg, Alex sets the style to **Persistent** (or "Alerts").

Record pass/fail for Steps 2–5 in the ledger.
