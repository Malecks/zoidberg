# Zoidberg Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar capture app that saves text, dictation, images, videos, and links as markdown notes to an Obsidian vault, with optional Claude AI integration for cleanup and organization.

**Architecture:** Single-process Swift + SwiftUI menu bar app using NSStatusItem + NSPopover. Write-first-enhance-async pattern for Claude integration. Protocol-based transcription service for future swappability.

**Tech Stack:** Swift, SwiftUI, AppKit (NSStatusItem/NSPopover), HotKey (SPM package), Speech framework, Foundation FileManager, URLSession for Claude API.

**Spec:** `docs/superpowers/specs/2026-03-13-zoidberg-design.md`

---

## File Structure

```
Zoidberg/
├── Package.swift                          # SPM package manifest (HotKey dependency)
├── Zoidberg/
│   ├── ZoidbergApp.swift                  # App entry point, @main, menu bar setup
│   ├── AppState.swift                     # Shared observable app state
│   ├── Models/
│   │   ├── CaptureSession.swift           # Session model: items, serialization, persistence
│   │   └── CaptureItem.swift              # Enum: .text, .image, .video, .link
│   ├── Views/
│   │   ├── CapturePanel.swift             # Main panel SwiftUI view
│   │   ├── CaptureItemRow.swift           # Row view for each item in the stream
│   │   ├── ToastView.swift                # Save/error toast overlay
│   │   └── SettingsView.swift             # Settings window
│   ├── Services/
│   │   ├── HotkeyManager.swift            # Global hotkey registration
│   │   ├── TranscriptionService.swift     # Protocol + macOS dictation impl
│   │   ├── VaultWriter.swift              # Markdown composition, file I/O
│   │   └── ClaudeService.swift            # Claude API client
│   └── Helpers/
│       ├── Permissions.swift              # Accessibility, mic, speech permission checks
│       └── Settings.swift                 # UserDefaults wrapper for app settings
├── ZoidbergTests/
│   ├── CaptureSessionTests.swift          # Session model tests
│   ├── CaptureItemTests.swift             # Item model tests
│   ├── VaultWriterTests.swift             # Markdown composition + file I/O tests
│   ├── ClaudeServiceTests.swift           # API client tests (mocked HTTP)
│   └── SettingsTests.swift                # Settings persistence tests
└── README.md
```

Each file has one responsibility. Models are pure data, services handle side effects, views handle display. Tests cover models and services — views are tested manually.

---

## Chunk 1: Project Scaffold + CaptureSession Model

### Task 1: Create Xcode Project via SPM

**Files:**
- Create: `Package.swift`
- Create: `Zoidberg/ZoidbergApp.swift`

- [ ] **Step 1: Create the SPM package manifest**

```swift
// Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Zoidberg",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Zoidberg", targets: ["Zoidberg"])
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.1")
    ],
    targets: [
        .executableTarget(
            name: "Zoidberg",
            dependencies: ["HotKey"],
            path: "Zoidberg"
        ),
        .testTarget(
            name: "ZoidbergTests",
            dependencies: ["Zoidberg"],
            path: "ZoidbergTests"
        )
    ]
)
```

- [ ] **Step 2: Create minimal app entry point**

```swift
// Zoidberg/ZoidbergApp.swift
import SwiftUI

@main
struct ZoidbergApp: App {
    var body: some Scene {
        MenuBarExtra("Zoidberg", systemImage: "desktopcomputer.and.arrow.down") {
            Text("Zoidberg")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 3: Create directory structure and empty test file**

```bash
mkdir -p Zoidberg/Models Zoidberg/Views Zoidberg/Services Zoidberg/Helpers ZoidbergTests
```

```swift
// ZoidbergTests/CaptureSessionTests.swift
import XCTest
@testable import Zoidberg

final class CaptureSessionTests: XCTestCase {}
```

- [ ] **Step 4: Verify project builds**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 5: Verify tests run**

Run: `swift test`
Expected: Test suite runs (0 tests, 0 failures).

- [ ] **Step 6: Commit**

```bash
git add Package.swift Zoidberg/ ZoidbergTests/
git commit -m "feat: scaffold Zoidberg project with SPM and HotKey dependency"
```

---

### Task 2: CaptureItem Model

**Files:**
- Create: `Zoidberg/Models/CaptureItem.swift`
- Create: `ZoidbergTests/CaptureItemTests.swift`

- [ ] **Step 1: Write failing tests for CaptureItem**

```swift
// ZoidbergTests/CaptureItemTests.swift
import XCTest
@testable import Zoidberg

final class CaptureItemTests: XCTestCase {
    func testTextItemMarkdown() {
        let item = CaptureItem.text("Hello world")
        XCTAssertEqual(item.toMarkdown(), "Hello world")
    }

    func testImageItemMarkdown() {
        let item = CaptureItem.image(filename: "screenshot.png", originalPath: "/tmp/screenshot.png")
        XCTAssertEqual(item.toMarkdown(), "![screenshot.png](attachments/screenshot.png)")
    }

    func testVideoItemMarkdown() {
        let item = CaptureItem.video(filename: "demo.mov", originalPath: "/tmp/demo.mov")
        XCTAssertEqual(item.toMarkdown(), "[demo.mov](attachments/demo.mov)")
    }

    func testLinkItemMarkdown() {
        let item = CaptureItem.link(URL(string: "https://example.com/docs")!)
        XCTAssertEqual(item.toMarkdown(), "[https://example.com/docs](https://example.com/docs)")
    }

    func testCodable() throws {
        let item = CaptureItem.text("Test")
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(CaptureItem.self, from: data)
        XCTAssertEqual(decoded.toMarkdown(), "Test")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CaptureItemTests`
Expected: FAIL — `CaptureItem` not defined.

- [ ] **Step 3: Implement CaptureItem**

```swift
// Zoidberg/Models/CaptureItem.swift
import Foundation

enum CaptureItem: Codable, Equatable {
    case text(String)
    case image(filename: String, originalPath: String)
    case video(filename: String, originalPath: String)
    case link(URL)

    func toMarkdown() -> String {
        switch self {
        case .text(let content):
            return content
        case .image(let filename, _):
            return "![\(filename)](attachments/\(filename))"
        case .video(let filename, _):
            return "[\(filename)](attachments/\(filename))"
        case .link(let url):
            return "[\(url.absoluteString)](\(url.absoluteString))"
        }
    }

    /// Returns paths of media files that need to be copied to the vault.
    var mediaFiles: [(filename: String, sourcePath: String)]? {
        switch self {
        case .image(let filename, let path), .video(let filename, let path):
            return [(filename, path)]
        case .text, .link:
            return nil
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CaptureItemTests`
Expected: All 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Zoidberg/Models/CaptureItem.swift ZoidbergTests/CaptureItemTests.swift
git commit -m "feat: add CaptureItem model with markdown serialization"
```

---

### Task 3: CaptureSession Model

**Files:**
- Create: `Zoidberg/Models/CaptureSession.swift`
- Modify: `ZoidbergTests/CaptureSessionTests.swift`

- [ ] **Step 1: Write failing tests for CaptureSession**

```swift
// ZoidbergTests/CaptureSessionTests.swift
import XCTest
@testable import Zoidberg

final class CaptureSessionTests: XCTestCase {
    func testEmptySession() {
        let session = CaptureSession()
        XCTAssertTrue(session.items.isEmpty)
        XCTAssertTrue(session.isEmpty)
    }

    func testAddItems() {
        var session = CaptureSession()
        session.addItem(.text("Hello"))
        session.addItem(.link(URL(string: "https://example.com")!))
        XCTAssertEqual(session.items.count, 2)
        XCTAssertFalse(session.isEmpty)
    }

    func testToMarkdownWithFallbackTitle() {
        var session = CaptureSession()
        session.addItem(.text("Some notes about auth"))
        session.addItem(.image(filename: "screenshot.png", originalPath: "/tmp/screenshot.png"))

        let md = session.toMarkdown(title: nil)

        // Should contain date-based title and the content
        XCTAssertTrue(md.contains("Notes captured on"))
        XCTAssertTrue(md.contains("Some notes about auth"))
        XCTAssertTrue(md.contains("![screenshot.png](attachments/screenshot.png)"))
    }

    func testToMarkdownWithCustomTitle() {
        var session = CaptureSession()
        session.addItem(.text("Auth flow notes"))

        let md = session.toMarkdown(title: "Auth Flow Investigation")

        XCTAssertTrue(md.hasPrefix("# Auth Flow Investigation"))
        XCTAssertTrue(md.contains("Auth flow notes"))
    }

    func testClear() {
        var session = CaptureSession()
        session.addItem(.text("Hello"))
        session.clear()
        XCTAssertTrue(session.isEmpty)
    }

    func testPersistence() throws {
        var session = CaptureSession()
        session.addItem(.text("Persist me"))
        session.addItem(.link(URL(string: "https://example.com")!))

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(CaptureSession.self, from: data)

        XCTAssertEqual(decoded.items.count, 2)
        XCTAssertEqual(decoded.items[0].toMarkdown(), "Persist me")
    }

    func testAllMediaFiles() {
        var session = CaptureSession()
        session.addItem(.text("Hello"))
        session.addItem(.image(filename: "a.png", originalPath: "/tmp/a.png"))
        session.addItem(.video(filename: "b.mov", originalPath: "/tmp/b.mov"))
        session.addItem(.link(URL(string: "https://example.com")!))

        let media = session.allMediaFiles
        XCTAssertEqual(media.count, 2)
        XCTAssertEqual(media[0].filename, "a.png")
        XCTAssertEqual(media[1].filename, "b.mov")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CaptureSessionTests`
Expected: FAIL — `CaptureSession` not defined.

- [ ] **Step 3: Implement CaptureSession**

```swift
// Zoidberg/Models/CaptureSession.swift
import Foundation

struct CaptureSession: Codable {
    private(set) var items: [CaptureItem] = []
    let createdAt: Date

    var isEmpty: Bool { items.isEmpty }

    init() {
        self.createdAt = Date()
    }

    mutating func addItem(_ item: CaptureItem) {
        items.append(item)
    }

    mutating func clear() {
        items.removeAll()
    }

    /// All media files across all items that need to be copied to the vault.
    var allMediaFiles: [(filename: String, sourcePath: String)] {
        items.compactMap { $0.mediaFiles }.flatMap { $0 }
    }

    /// Compose the full markdown note.
    /// - Parameter title: Claude-generated title, or nil for date-based fallback.
    func toMarkdown(title: String?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' h:mm a"
        let dateString = formatter.string(from: createdAt)

        let heading = title ?? "Capture — \(dateString)"
        var lines: [String] = []
        lines.append("# \(heading)")
        lines.append("")
        lines.append("Notes captured on \(dateString)")
        lines.append("")
        lines.append("---")
        lines.append("")

        for item in items {
            lines.append(item.toMarkdown())
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Generate the fallback filename (timestamp with seconds).
    func fallbackFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "\(formatter.string(from: createdAt))-capture.md"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CaptureSessionTests`
Expected: All 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Zoidberg/Models/CaptureSession.swift ZoidbergTests/CaptureSessionTests.swift
git commit -m "feat: add CaptureSession model with markdown composition and persistence"
```

---

## Chunk 2: Settings + VaultWriter

### Task 4: Settings Helper

**Files:**
- Create: `Zoidberg/Helpers/Settings.swift`
- Create: `ZoidbergTests/SettingsTests.swift`

- [ ] **Step 1: Write failing tests for Settings**

```swift
// ZoidbergTests/SettingsTests.swift
import XCTest
@testable import Zoidberg

final class SettingsTests: XCTestCase {
    override func setUp() {
        // Use a test-specific suite to avoid polluting real defaults
        AppSettings.defaults = UserDefaults(suiteName: "com.zoidberg.tests")!
        AppSettings.defaults.removePersistentDomain(forName: "com.zoidberg.tests")
    }

    func testDefaultVaultPath() {
        let path = AppSettings.vaultPath
        XCTAssertTrue(path.hasSuffix("Documents/Obsidian Vault"))
    }

    func testSetVaultPath() {
        AppSettings.vaultPath = "/tmp/test-vault"
        XCTAssertEqual(AppSettings.vaultPath, "/tmp/test-vault")
    }

    func testClaudeApiKeyDefaultsToNil() {
        XCTAssertNil(AppSettings.claudeApiKey)
    }

    func testSetClaudeApiKey() {
        AppSettings.claudeApiKey = "sk-test-key"
        XCTAssertEqual(AppSettings.claudeApiKey, "sk-test-key")
    }

    func testHasClaudeApiKey() {
        XCTAssertFalse(AppSettings.hasClaudeApiKey)
        AppSettings.claudeApiKey = "sk-test"
        XCTAssertTrue(AppSettings.hasClaudeApiKey)
    }

    func testLaunchAtLoginDefaultsFalse() {
        XCTAssertFalse(AppSettings.launchAtLogin)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SettingsTests`
Expected: FAIL — `AppSettings` not defined.

- [ ] **Step 3: Implement Settings**

```swift
// Zoidberg/Helpers/Settings.swift
import Foundation

enum AppSettings {
    static var defaults: UserDefaults = .standard

    static var vaultPath: String {
        get {
            defaults.string(forKey: "vaultPath")
                ?? NSHomeDirectory() + "/Documents/Obsidian Vault"
        }
        set { defaults.set(newValue, forKey: "vaultPath") }
    }

    static var claudeApiKey: String? {
        get { defaults.string(forKey: "claudeApiKey") }
        set { defaults.set(newValue, forKey: "claudeApiKey") }
    }

    static var hasClaudeApiKey: Bool {
        guard let key = claudeApiKey else { return false }
        return !key.isEmpty
    }

    static var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }

    static var togglePanelHotkey: String {
        get { defaults.string(forKey: "togglePanelHotkey") ?? "ctrl+space" }
        set { defaults.set(newValue, forKey: "togglePanelHotkey") }
    }

    static var dictateHotkey: String {
        get { defaults.string(forKey: "dictateHotkey") ?? "ctrl+shift+space" }
        set { defaults.set(newValue, forKey: "dictateHotkey") }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SettingsTests`
Expected: All 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Zoidberg/Helpers/Settings.swift ZoidbergTests/SettingsTests.swift
git commit -m "feat: add AppSettings helper with UserDefaults persistence"
```

---

### Task 5: VaultWriter

**Files:**
- Create: `Zoidberg/Services/VaultWriter.swift`
- Create: `ZoidbergTests/VaultWriterTests.swift`

- [ ] **Step 1: Write failing tests for VaultWriter**

```swift
// ZoidbergTests/VaultWriterTests.swift
import XCTest
@testable import Zoidberg

final class VaultWriterTests: XCTestCase {
    var testVaultPath: String!

    override func setUp() {
        testVaultPath = NSTemporaryDirectory() + "zoidberg-test-vault-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: testVaultPath, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: testVaultPath)
    }

    func testWriteTextOnlySession() throws {
        var session = CaptureSession()
        session.addItem(.text("Hello from test"))

        let writer = VaultWriter(vaultPath: testVaultPath)
        let result = try writer.save(session: session, title: nil, folder: nil)

        // File should exist in Captures/ with fallback name
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.filePath))
        XCTAssertTrue(result.filePath.contains("/Captures/"))
        XCTAssertTrue(result.filePath.hasSuffix("-capture.md"))

        let content = try String(contentsOfFile: result.filePath, encoding: .utf8)
        XCTAssertTrue(content.contains("Hello from test"))
    }

    func testWriteWithCustomTitleAndFolder() throws {
        var session = CaptureSession()
        session.addItem(.text("Auth notes"))

        let writer = VaultWriter(vaultPath: testVaultPath)
        let result = try writer.save(session: session, title: "Auth Flow", folder: "Projects")

        XCTAssertTrue(result.filePath.contains("/Projects/"))
        XCTAssertTrue(result.filePath.contains("Auth Flow.md"))

        let content = try String(contentsOfFile: result.filePath, encoding: .utf8)
        XCTAssertTrue(content.contains("# Auth Flow"))
    }

    func testWriteWithMediaCopiesFiles() throws {
        // Create a fake image file
        let imagePath = NSTemporaryDirectory() + "test-image.png"
        try "fake png data".write(toFile: imagePath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: imagePath) }

        var session = CaptureSession()
        session.addItem(.text("See screenshot:"))
        session.addItem(.image(filename: "test-image.png", originalPath: imagePath))

        let writer = VaultWriter(vaultPath: testVaultPath)
        let result = try writer.save(session: session, title: nil, folder: nil)

        // Check attachment was copied
        let attachmentDir = (result.filePath as NSString).deletingLastPathComponent + "/attachments"
        let attachmentPath = attachmentDir + "/test-image.png"
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachmentPath))
    }

    func testValidateVaultPathFailsForMissingPath() {
        let writer = VaultWriter(vaultPath: "/nonexistent/path/vault")
        XCTAssertThrowsError(try writer.validate()) { error in
            XCTAssertTrue(error is VaultWriterError)
        }
    }

    func testMoveToEnhancedLocation() throws {
        var session = CaptureSession()
        session.addItem(.text("Move me"))

        let writer = VaultWriter(vaultPath: testVaultPath)
        let initial = try writer.save(session: session, title: nil, folder: nil)

        // Now move to enhanced location
        let moved = try writer.moveToEnhancedLocation(
            from: initial.filePath,
            enhancedMarkdown: session.toMarkdown(title: "Better Title"),
            title: "Better Title",
            folder: "Notes"
        )

        // Original should be gone, new file should exist
        XCTAssertFalse(FileManager.default.fileExists(atPath: initial.filePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved))
        XCTAssertTrue(moved.contains("/Notes/"))
        XCTAssertTrue(moved.contains("Better Title.md"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter VaultWriterTests`
Expected: FAIL — `VaultWriter` not defined.

- [ ] **Step 3: Implement VaultWriter**

```swift
// Zoidberg/Services/VaultWriter.swift
import Foundation

enum VaultWriterError: Error, LocalizedError {
    case vaultPathNotFound(String)
    case vaultNotWritable(String)
    case mediaFileMissing(String)

    var errorDescription: String? {
        switch self {
        case .vaultPathNotFound(let path):
            return "Vault path not found: \(path)"
        case .vaultNotWritable(let path):
            return "Vault path not writable: \(path)"
        case .mediaFileMissing(let path):
            return "Media file not found: \(path)"
        }
    }
}

struct SaveResult {
    let filePath: String
}

final class VaultWriter {
    let vaultPath: String
    private let fm = FileManager.default

    init(vaultPath: String) {
        self.vaultPath = vaultPath
    }

    /// Validate that the vault path exists and is writable.
    func validate() throws {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: vaultPath, isDirectory: &isDir), isDir.boolValue else {
            throw VaultWriterError.vaultPathNotFound(vaultPath)
        }
        guard fm.isWritableFile(atPath: vaultPath) else {
            throw VaultWriterError.vaultNotWritable(vaultPath)
        }
    }

    /// Save a capture session immediately with fallback naming.
    /// Returns the path of the written file.
    func save(session: CaptureSession, title: String?, folder: String?) throws -> SaveResult {
        try validate()

        let targetFolder = folder ?? "Captures"
        let folderPath = (vaultPath as NSString).appendingPathComponent(targetFolder)
        try fm.createDirectory(atPath: folderPath, withIntermediateDirectories: true)

        // Determine filename
        let filename: String
        if let title = title {
            filename = sanitizeFilename(title) + ".md"
        } else {
            filename = session.fallbackFilename()
        }

        let filePath = (folderPath as NSString).appendingPathComponent(filename)

        // Copy media files
        if !session.allMediaFiles.isEmpty {
            let attachmentsPath = (folderPath as NSString).appendingPathComponent("attachments")
            try fm.createDirectory(atPath: attachmentsPath, withIntermediateDirectories: true)

            for media in session.allMediaFiles {
                let dest = (attachmentsPath as NSString).appendingPathComponent(media.filename)
                if fm.fileExists(atPath: media.sourcePath) {
                    try? fm.removeItem(atPath: dest) // overwrite if exists
                    try fm.copyItem(atPath: media.sourcePath, toPath: dest)
                }
            }
        }

        // Write markdown
        let markdown = session.toMarkdown(title: title)
        try markdown.write(toFile: filePath, atomically: true, encoding: .utf8)

        return SaveResult(filePath: filePath)
    }

    /// Atomically move a note from its initial location to a Claude-enhanced location.
    /// Writes enhanced content to a temp file, then does an atomic rename.
    func moveToEnhancedLocation(
        from originalPath: String,
        enhancedMarkdown: String,
        title: String,
        folder: String
    ) throws -> String {
        let folderPath = (vaultPath as NSString).appendingPathComponent(folder)
        try fm.createDirectory(atPath: folderPath, withIntermediateDirectories: true)

        let filename = sanitizeFilename(title) + ".md"
        let finalPath = (folderPath as NSString).appendingPathComponent(filename)

        // Write to temp file first
        let tempPath = finalPath + ".tmp"
        try enhancedMarkdown.write(toFile: tempPath, atomically: true, encoding: .utf8)

        // Atomic rename to final path
        try? fm.removeItem(atPath: finalPath) // in case it exists
        try fm.moveItem(atPath: tempPath, toPath: finalPath)

        // Move attachments if they exist
        let originalAttachments = ((originalPath as NSString).deletingLastPathComponent as NSString)
            .appendingPathComponent("attachments")
        if fm.fileExists(atPath: originalAttachments) {
            let newAttachments = (folderPath as NSString).appendingPathComponent("attachments")
            try fm.createDirectory(atPath: newAttachments, withIntermediateDirectories: true)
            if let files = try? fm.contentsOfDirectory(atPath: originalAttachments) {
                for file in files {
                    let src = (originalAttachments as NSString).appendingPathComponent(file)
                    let dst = (newAttachments as NSString).appendingPathComponent(file)
                    try? fm.removeItem(atPath: dst)
                    try fm.moveItem(atPath: src, toPath: dst)
                }
            }
        }

        // Delete original file
        try? fm.removeItem(atPath: originalPath)

        return finalPath
    }

    private func sanitizeFilename(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: illegal).joined(separator: "-")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter VaultWriterTests`
Expected: All 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Zoidberg/Services/VaultWriter.swift ZoidbergTests/VaultWriterTests.swift
git commit -m "feat: add VaultWriter with markdown composition and atomic file moves"
```

---

## Chunk 3: ClaudeService

### Task 6: ClaudeService

**Files:**
- Create: `Zoidberg/Services/ClaudeService.swift`
- Create: `ZoidbergTests/ClaudeServiceTests.swift`

- [ ] **Step 1: Write failing tests for ClaudeService**

```swift
// ZoidbergTests/ClaudeServiceTests.swift
import XCTest
@testable import Zoidberg

final class ClaudeServiceTests: XCTestCase {
    func testDisabledWhenNoApiKey() async {
        let service = ClaudeService(apiKey: nil)
        XCTAssertFalse(service.isEnabled)
    }

    func testEnabledWithApiKey() async {
        let service = ClaudeService(apiKey: "sk-test")
        XCTAssertTrue(service.isEnabled)
    }

    func testParseEnhanceResponse() throws {
        let json = """
        {
            "content": [{"type": "text", "text": "{\\"title\\": \\"Auth Flow Notes\\", \\"folder\\": \\"Projects\\", \\"cleanedText\\": \\"Fixed up text here.\\"}"}]
        }
        """
        let result = try ClaudeService.parseEnhanceResponse(json.data(using: .utf8)!)
        XCTAssertEqual(result.title, "Auth Flow Notes")
        XCTAssertEqual(result.folder, "Projects")
        XCTAssertEqual(result.cleanedText, "Fixed up text here.")
    }

    func testParseEnhanceResponseHandlesMalformed() {
        let badJson = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try ClaudeService.parseEnhanceResponse(badJson))
    }

    func testBuildPrompt() {
        var session = CaptureSession()
        session.addItem(.text("some dictated text"))
        session.addItem(.link(URL(string: "https://example.com")!))

        let prompt = ClaudeService.buildEnhancePrompt(for: session)
        XCTAssertTrue(prompt.contains("some dictated text"))
        XCTAssertTrue(prompt.contains("https://example.com"))
        XCTAssertTrue(prompt.contains("title"))
        XCTAssertTrue(prompt.contains("folder"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ClaudeServiceTests`
Expected: FAIL — `ClaudeService` not defined.

- [ ] **Step 3: Implement ClaudeService**

```swift
// Zoidberg/Services/ClaudeService.swift
import Foundation

struct EnhanceResult {
    let title: String
    let folder: String
    let cleanedText: String?
}

final class ClaudeService {
    let apiKey: String?
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let model = "claude-haiku-4-5-20251001"
    private let timeout: TimeInterval = 30

    var isEnabled: Bool { apiKey != nil && !(apiKey?.isEmpty ?? true) }

    init(apiKey: String?) {
        self.apiKey = apiKey
    }

    /// Enhance a capture session: clean up text, generate title and folder.
    /// Returns nil if Claude is disabled or the call fails.
    func enhance(session: CaptureSession) async -> EnhanceResult? {
        guard isEnabled, let apiKey = apiKey else { return nil }

        let prompt = Self.buildEnhancePrompt(for: session)

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            return try Self.parseEnhanceResponse(data)
        } catch {
            return nil // Fail silently — raw capture is already saved
        }
    }

    static func buildEnhancePrompt(for session: CaptureSession) -> String {
        let content = session.items.map { $0.toMarkdown() }.joined(separator: "\n")

        return """
        You are organizing a quick capture note for an Obsidian vault. \
        The user captured the following content:

        ---
        \(content)
        ---

        Respond with ONLY a JSON object (no markdown fencing) with these fields:
        - "title": A concise, descriptive title for this note (3-8 words)
        - "folder": A folder name for organizing this note (e.g. "Projects", "Ideas", "Research", "Tasks", "Personal")
        - "cleanedText": If the text appears to be dictated (run-on, missing punctuation), \
        clean it up with proper punctuation and paragraph breaks. If the text is already clean, \
        set this to null.
        """
    }

    static func parseEnhanceResponse(_ data: Data) throws -> EnhanceResult {
        // Parse the Anthropic API response to extract the text content
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = response["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw ClaudeServiceError.invalidResponse
        }

        // Parse the JSON from Claude's response text
        guard let jsonData = text.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let title = result["title"] as? String,
              let folder = result["folder"] as? String else {
            throw ClaudeServiceError.invalidResponse
        }

        let cleanedText = result["cleanedText"] as? String

        return EnhanceResult(title: title, folder: folder, cleanedText: cleanedText)
    }
}

enum ClaudeServiceError: Error {
    case invalidResponse
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ClaudeServiceTests`
Expected: All 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Zoidberg/Services/ClaudeService.swift ZoidbergTests/ClaudeServiceTests.swift
git commit -m "feat: add ClaudeService with enhance prompt and response parsing"
```

---

## Chunk 4: AppState + Permissions + HotkeyManager

### Task 7: Permissions Helper

**Files:**
- Create: `Zoidberg/Helpers/Permissions.swift`

This is thin wrapper code around system APIs — no unit tests, verified by manual testing.

- [ ] **Step 1: Implement Permissions helper**

```swift
// Zoidberg/Helpers/Permissions.swift
import Cocoa
import Speech

enum PermissionStatus {
    case granted
    case denied
    case notDetermined
}

enum Permissions {
    /// Check Accessibility permission (required for global hotkeys).
    static func checkAccessibility() -> PermissionStatus {
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        )
        return trusted ? .granted : .denied
    }

    /// Prompt for Accessibility permission.
    static func requestAccessibility() {
        let _ = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )
    }

    /// Check Speech Recognition permission.
    static func checkSpeechRecognition() -> PermissionStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    /// Request Speech Recognition permission.
    static func requestSpeechRecognition() async -> PermissionStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                switch status {
                case .authorized: continuation.resume(returning: .granted)
                default: continuation.resume(returning: .denied)
                }
            }
        }
    }

    /// Open System Settings to a specific privacy pane.
    static func openSystemSettings(for pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

- [ ] **Step 2: Verify project builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Zoidberg/Helpers/Permissions.swift
git commit -m "feat: add Permissions helper for Accessibility and Speech Recognition"
```

---

### Task 8: AppState

**Files:**
- Create: `Zoidberg/AppState.swift`

- [ ] **Step 1: Implement AppState**

AppState is the shared observable object that coordinates between the panel, hotkeys, services, and session persistence.

```swift
// Zoidberg/AppState.swift
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var currentSession = CaptureSession()
    @Published var isDictating = false
    @Published var isDragOver = false
    @Published var toastMessage: String?
    @Published var toastIsError = false
    @Published var lastDiscardedSession: CaptureSession?
    @Published var showUndoDiscard = false

    private var discardTimer: Timer?
    private var toastTimer: Timer?

    private let persistencePath: String = {
        let dir = NSHomeDirectory() + "/Library/Application Support/Zoidberg"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/pending-session.json"
    }()

    init() {
        loadPersistedSession()
    }

    // MARK: - Session Management

    var hasContent: Bool { !currentSession.isEmpty }

    func addItem(_ item: CaptureItem) {
        currentSession.addItem(item)
        persistSession()
    }

    func updateText(_ text: String) {
        // Find and update the last text item, or add a new one
        // For simplicity, we track text as the first item and append media after
        var items = currentSession.items.filter {
            if case .text = $0 { return false }
            return true
        }
        if !text.isEmpty {
            items.insert(.text(text), at: 0)
        }
        currentSession = CaptureSession()
        for item in items {
            currentSession.addItem(item)
        }
        persistSession()
    }

    // MARK: - Save

    func save() {
        let vaultPath = AppSettings.vaultPath
        let writer = VaultWriter(vaultPath: vaultPath)

        do {
            let result = try writer.save(session: currentSession, title: nil, folder: nil)
            showToast("✓ Saved to vault", isError: false)

            // Enhance in background if Claude is enabled
            if AppSettings.hasClaudeApiKey {
                let session = currentSession
                let filePath = result.filePath
                Task.detached {
                    await self.enhanceInBackground(session: session, filePath: filePath, writer: writer)
                }
            }

            clearSession()
        } catch {
            showToast("Failed to save — check vault path in settings", isError: true)
        }
    }

    private func enhanceInBackground(session: CaptureSession, filePath: String, writer: VaultWriter) async {
        let claude = ClaudeService(apiKey: AppSettings.claudeApiKey)
        guard let result = await claude.enhance(session: session) else { return }

        // Rebuild markdown with cleaned text if provided
        var enhancedSession = CaptureSession()
        for item in session.items {
            if case .text = item, let cleaned = result.cleanedText {
                enhancedSession.addItem(.text(cleaned))
            } else {
                enhancedSession.addItem(item)
            }
        }

        let enhancedMarkdown = enhancedSession.toMarkdown(title: result.title)

        try? writer.moveToEnhancedLocation(
            from: filePath,
            enhancedMarkdown: enhancedMarkdown,
            title: result.title,
            folder: result.folder
        )
    }

    // MARK: - Discard

    func discardSession() {
        lastDiscardedSession = currentSession
        showUndoDiscard = true
        clearSession()
        deletePersistence()

        // 30-second undo window
        discardTimer?.invalidate()
        discardTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.lastDiscardedSession = nil
                self?.showUndoDiscard = false
            }
        }
    }

    func undoDiscard() {
        guard let session = lastDiscardedSession else { return }
        currentSession = session
        lastDiscardedSession = nil
        showUndoDiscard = false
        discardTimer?.invalidate()
        persistSession()
    }

    // MARK: - Toast

    private func showToast(_ message: String, isError: Bool) {
        toastMessage = message
        toastIsError = isError
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: isError ? 3 : 1.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.toastMessage = nil
            }
        }
    }

    // MARK: - Persistence

    private func persistSession() {
        guard !currentSession.isEmpty else {
            deletePersistence()
            return
        }
        if let data = try? JSONEncoder().encode(currentSession) {
            try? data.write(to: URL(fileURLWithPath: persistencePath))
        }
    }

    private func loadPersistedSession() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: persistencePath)),
              let session = try? JSONDecoder().decode(CaptureSession.self, from: data) else {
            return
        }
        currentSession = session
    }

    private func clearSession() {
        currentSession = CaptureSession()
        deletePersistence()
    }

    private func deletePersistence() {
        try? FileManager.default.removeItem(atPath: persistencePath)
    }
}
```

- [ ] **Step 2: Verify project builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Zoidberg/AppState.swift
git commit -m "feat: add AppState with session management, save, discard, and persistence"
```

---

### Task 9: HotkeyManager

**Files:**
- Create: `Zoidberg/Services/HotkeyManager.swift`

- [ ] **Step 1: Implement HotkeyManager**

```swift
// Zoidberg/Services/HotkeyManager.swift
import HotKey
import Carbon

final class HotkeyManager {
    private var togglePanelHotKey: HotKey?
    private var dictateHotKey: HotKey?

    var onTogglePanel: (() -> Void)?
    var onToggleDictation: (() -> Void)?

    func register() {
        // Ctrl+Space — toggle panel
        togglePanelHotKey = HotKey(key: .space, modifiers: [.control])
        togglePanelHotKey?.keyDownHandler = { [weak self] in
            self?.onTogglePanel?()
        }

        // Ctrl+Shift+Space — toggle dictation
        dictateHotKey = HotKey(key: .space, modifiers: [.control, .shift])
        dictateHotKey?.keyDownHandler = { [weak self] in
            self?.onToggleDictation?()
        }
    }

    func unregister() {
        togglePanelHotKey = nil
        dictateHotKey = nil
    }
}
```

- [ ] **Step 2: Verify project builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Zoidberg/Services/HotkeyManager.swift
git commit -m "feat: add HotkeyManager with global Ctrl+Space and Ctrl+Shift+Space shortcuts"
```

---

## Chunk 5: TranscriptionService

### Task 10: TranscriptionService

**Files:**
- Create: `Zoidberg/Services/TranscriptionService.swift`

- [ ] **Step 1: Implement TranscriptionService**

```swift
// Zoidberg/Services/TranscriptionService.swift
import Speech
import AVFoundation

protocol TranscriptionDelegate: AnyObject {
    func transcriptionDidUpdate(text: String)
    func transcriptionDidFinish(finalText: String)
    func transcriptionDidFail(error: Error)
}

protocol TranscriptionProvider {
    var isListening: Bool { get }
    var delegate: TranscriptionDelegate? { get set }
    func startListening() throws
    func stopListening()
}

final class MacOSDictationService: NSObject, TranscriptionProvider {
    weak var delegate: TranscriptionDelegate?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private(set) var isListening = false

    func startListening() throws {
        guard Permissions.checkSpeechRecognition() == .granted else {
            throw TranscriptionError.permissionDenied
        }

        // Cancel any existing task
        stopListening()

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            throw TranscriptionError.setupFailed
        }

        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    self.delegate?.transcriptionDidFinish(finalText: text)
                    self.stopListening()
                } else {
                    self.delegate?.transcriptionDidUpdate(text: text)
                }
            }

            if let error = error {
                self.delegate?.transcriptionDidFail(error: error)
                self.stopListening()
            }
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }
}

enum TranscriptionError: Error {
    case permissionDenied
    case setupFailed
}
```

- [ ] **Step 2: Verify project builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Zoidberg/Services/TranscriptionService.swift
git commit -m "feat: add TranscriptionService with SFSpeechRecognizer and swappable protocol"
```

---

## Chunk 6: UI Views

### Task 11: CaptureItemRow View

**Files:**
- Create: `Zoidberg/Views/CaptureItemRow.swift`

- [ ] **Step 1: Implement CaptureItemRow**

```swift
// Zoidberg/Views/CaptureItemRow.swift
import SwiftUI

struct CaptureItemRow: View {
    let item: CaptureItem

    var body: some View {
        switch item {
        case .text:
            // Text items are handled by the main text editor, not shown as rows
            EmptyView()

        case .image(let filename, _):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.darkGray))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(filename)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(8)
            .background(Color(.darkGray).opacity(0.3))
            .cornerRadius(8)

        case .video(let filename, _):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.darkGray))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "video")
                            .foregroundColor(.gray)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(filename)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(8)
            .background(Color(.darkGray).opacity(0.3))
            .cornerRadius(8)

        case .link(let url):
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                Text(url.absoluteString)
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(8)
            .background(Color(.darkGray).opacity(0.3))
            .cornerRadius(8)
        }
    }
}
```

- [ ] **Step 2: Verify project builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Zoidberg/Views/CaptureItemRow.swift
git commit -m "feat: add CaptureItemRow view for media and link display"
```

---

### Task 12: ToastView

**Files:**
- Create: `Zoidberg/Views/ToastView.swift`

- [ ] **Step 1: Implement ToastView**

```swift
// Zoidberg/Views/ToastView.swift
import SwiftUI

struct ToastView: View {
    let message: String
    let isError: Bool

    var body: some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundColor(isError ? .white : Color(.systemGreen))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(isError ? Color.red.opacity(0.9) : Color.green.opacity(0.15))
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
```

- [ ] **Step 2: Verify project builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Zoidberg/Views/ToastView.swift
git commit -m "feat: add ToastView for save/error feedback"
```

---

### Task 13: CapturePanel View

**Files:**
- Create: `Zoidberg/Views/CapturePanel.swift`

- [ ] **Step 1: Implement CapturePanel**

```swift
// Zoidberg/Views/CapturePanel.swift
import SwiftUI

struct CapturePanel: View {
    @ObservedObject var appState: AppState
    @State private var textInput = ""
    @State private var escapeHoldTimer: Timer?
    @State private var isHoldingEscape = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            // Content area
            contentArea

            // Toast
            if let toast = appState.toastMessage {
                ToastView(message: toast, isError: appState.toastIsError)
            }
        }
        .frame(width: 320)
        .background(Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(appState.isDragOver ? Color.blue : Color.clear, lineWidth: 2)
        )
        .onDrop(of: [.fileURL, .url], isTargeted: $appState.isDragOver) { providers in
            handleDrop(providers)
        }
        .onAppear {
            textInput = currentTextContent()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("🤖")
                .font(.system(size: 14))

            Spacer()

            if appState.isDictating {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                        .opacity(isHoldingEscape ? 0.4 : 1)
                    Text("Listening")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
            } else {
                Button(action: { /* toggle dictation handled by hotkey */ }) {
                    Image(systemName: "mic")
                        .foregroundColor(.gray)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }

            Button(action: { appState.save() }) {
                Image(systemName: "checkmark")
                    .foregroundColor(.gray)
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Content

    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Undo discard button
                if appState.showUndoDiscard {
                    Button("Undo discard") {
                        appState.undoDiscard()
                        textInput = currentTextContent()
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
                    .padding(.bottom, 4)
                }

                // Text editor
                TextEditor(text: $textInput)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60, maxHeight: 200)
                    .onChange(of: textInput) { _, newValue in
                        appState.updateText(newValue)
                    }

                // Media items
                ForEach(Array(nonTextItems().enumerated()), id: \.offset) { _, item in
                    CaptureItemRow(item: item)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(minHeight: 120, maxHeight: 300)
        .opacity(appState.isDragOver ? 0.5 : 1)
        .overlay(
            appState.isDragOver ?
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundColor(.blue)
                .padding(8)
            : nil
        )
    }

    // MARK: - Helpers

    private func currentTextContent() -> String {
        for item in appState.currentSession.items {
            if case .text(let content) = item {
                return content
            }
        }
        return ""
    }

    private func nonTextItems() -> [CaptureItem] {
        appState.currentSession.items.filter {
            if case .text = $0 { return false }
            return true
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            // Handle file URLs (images, videos)
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url") { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                    let filename = url.lastPathComponent
                    let path = url.path

                    Task { @MainActor in
                        let ext = url.pathExtension.lowercased()
                        if ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff"].contains(ext) {
                            appState.addItem(.image(filename: filename, originalPath: path))
                        } else if ["mov", "mp4", "m4v", "avi", "mkv"].contains(ext) {
                            appState.addItem(.video(filename: filename, originalPath: path))
                        }
                    }
                }
            }

            // Handle URLs (links)
            if provider.hasItemConformingToTypeIdentifier("public.url") {
                provider.loadItem(forTypeIdentifier: "public.url") { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          url.scheme == "http" || url.scheme == "https" else { return }

                    Task { @MainActor in
                        appState.addItem(.link(url))
                    }
                }
            }
        }
        return true
    }
}
```

- [ ] **Step 2: Verify project builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Zoidberg/Views/CapturePanel.swift
git commit -m "feat: add CapturePanel view with text input, drag-drop, and dictation indicator"
```

---

### Task 14: SettingsView

**Files:**
- Create: `Zoidberg/Views/SettingsView.swift`

- [ ] **Step 1: Implement SettingsView**

```swift
// Zoidberg/Views/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @State private var vaultPath = AppSettings.vaultPath
    @State private var apiKey = AppSettings.claudeApiKey ?? ""
    @State private var launchAtLogin = AppSettings.launchAtLogin

    var body: some View {
        Form {
            Section("Obsidian Vault") {
                HStack {
                    TextField("Vault Path", text: $vaultPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            vaultPath = url.path
                        }
                    }
                }
            }

            Section("Claude API") {
                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Circle()
                        .fill(apiKey.isEmpty ? Color.gray : Color.green)
                        .frame(width: 8, height: 8)
                    Text(apiKey.isEmpty ? "Not configured" : "Connected")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
        .onChange(of: vaultPath) { _, newValue in
            AppSettings.vaultPath = newValue
        }
        .onChange(of: apiKey) { _, newValue in
            AppSettings.claudeApiKey = newValue.isEmpty ? nil : newValue
        }
        .onChange(of: launchAtLogin) { _, newValue in
            AppSettings.launchAtLogin = newValue
        }
    }
}
```

- [ ] **Step 2: Verify project builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Zoidberg/Views/SettingsView.swift
git commit -m "feat: add SettingsView with vault path, API key, and launch at login"
```

---

## Chunk 7: App Integration + Wiring

### Task 15: Wire Everything Together in ZoidbergApp

**Files:**
- Modify: `Zoidberg/ZoidbergApp.swift`

- [ ] **Step 1: Update ZoidbergApp to wire all components**

Replace the contents of `Zoidberg/ZoidbergApp.swift`:

```swift
// Zoidberg/ZoidbergApp.swift
import SwiftUI

@main
struct ZoidbergApp: App {
    @StateObject private var appState = AppState()
    private let hotkeyManager = HotkeyManager()
    @State private var settingsWindow: NSWindow?

    var body: some Scene {
        MenuBarExtra {
            CapturePanel(appState: appState)
        } label: {
            Image(systemName: "cpu")
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        // Check Accessibility permission on launch
        if Permissions.checkAccessibility() == .denied {
            Permissions.requestAccessibility()
        }

        // Register hotkeys
        hotkeyManager.onTogglePanel = {
            // MenuBarExtra handles its own toggle via the system button
            // For programmatic toggle, we need NSStatusItem access
            // This will be refined — for now the menu bar click works
        }

        hotkeyManager.onToggleDictation = { [hotkeyManager] in
            // Dictation toggle will be wired to TranscriptionService
        }

        hotkeyManager.register()
    }
}
```

> **Note:** The global hotkey → popover toggle wiring requires accessing the `NSStatusItem` directly, which `MenuBarExtra` doesn't expose cleanly. In Task 16, we'll refactor to use `NSStatusItem` + `NSPopover` directly via an AppDelegate for full control.

- [ ] **Step 2: Verify project builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Zoidberg/ZoidbergApp.swift
git commit -m "feat: wire app entry point with MenuBarExtra and hotkey registration"
```

---

### Task 16: Refactor to NSStatusItem + NSPopover for Hotkey Control

**Files:**
- Modify: `Zoidberg/ZoidbergApp.swift`

`MenuBarExtra` doesn't give us programmatic control to open/close the popover from a global hotkey. We need to use `NSStatusItem` + `NSPopover` directly.

- [ ] **Step 1: Refactor ZoidbergApp to AppDelegate pattern**

Replace `Zoidberg/ZoidbergApp.swift`:

```swift
// Zoidberg/ZoidbergApp.swift
import SwiftUI

@main
struct ZoidbergApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window opened via right-click menu
        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let appState = AppState()
    private let hotkeyManager = HotkeyManager()
    private let transcriptionService = MacOSDictationService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Use a robot-like SF Symbol. "face.dashed" or custom asset in production.
            button.image = NSImage(systemSymbolName: "desktopcomputer.and.arrow.down", accessibilityDescription: "Zoidberg")
            // TODO: Replace with custom robot icon asset for final build
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: CapturePanel(appState: appState)
        )

        // Setup transcription delegate
        transcriptionService.delegate = self

        // Check Accessibility
        if Permissions.checkAccessibility() == .denied {
            Permissions.requestAccessibility()
        }

        // Register hotkeys
        hotkeyManager.onTogglePanel = { [weak self] in
            self?.togglePopover()
        }
        hotkeyManager.onToggleDictation = { [weak self] in
            self?.toggleDictation()
        }
        hotkeyManager.register()
    }

    @objc private func togglePopover() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            guard let button = statusItem.button else { return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func toggleDictation() {
        if !popover.isShown {
            togglePopover()
        }

        if transcriptionService.isListening {
            transcriptionService.stopListening()
            Task { @MainActor in
                appState.isDictating = false
            }
        } else {
            Task { @MainActor in
                if Permissions.checkSpeechRecognition() == .notDetermined {
                    let _ = await Permissions.requestSpeechRecognition()
                }
                guard Permissions.checkSpeechRecognition() == .granted else {
                    Permissions.openSystemSettings(for: "Privacy_SpeechRecognition")
                    return
                }
                do {
                    try transcriptionService.startListening()
                    appState.isDictating = true
                } catch {
                    appState.isDictating = false
                }
            }
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Zoidberg", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // Reset so left-click works again
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - TranscriptionDelegate

extension AppDelegate: TranscriptionDelegate {
    func transcriptionDidUpdate(text: String) {
        Task { @MainActor in
            appState.updateText(text)
        }
    }

    func transcriptionDidFinish(finalText: String) {
        Task { @MainActor in
            appState.updateText(finalText)
            appState.isDictating = false
        }
    }

    func transcriptionDidFail(error: Error) {
        Task { @MainActor in
            appState.isDictating = false
        }
    }
}
```

- [ ] **Step 2: Verify project builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Run the app manually to verify**

Run: `swift run`
Expected: Robot icon appears in menu bar. Clicking it opens the capture panel. Right-clicking shows Settings/Quit menu. Ctrl+Space toggles the panel.

- [ ] **Step 4: Commit**

```bash
git add Zoidberg/ZoidbergApp.swift
git commit -m "refactor: use NSStatusItem + NSPopover for full hotkey and menu control"
```

---

### Task 17: Add Escape Key Handling (Tap vs Hold)

**Files:**
- Create: `Zoidberg/Helpers/EscapeKeyMonitor.swift`
- Modify: `Zoidberg/Views/CapturePanel.swift`

SwiftUI's `onKeyPress` does not support key-down/key-up phases, so we use `NSEvent` local monitors to detect hold duration.

- [ ] **Step 1: Create EscapeKeyMonitor helper**

```swift
// Zoidberg/Helpers/EscapeKeyMonitor.swift
import Cocoa

/// Monitors Escape key press duration to distinguish tap from hold.
final class EscapeKeyMonitor {
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var holdTimer: Timer?
    private var didTriggerHold = false

    var onTap: (() -> Void)?
    var onHold: (() -> Void)?

    /// Hold duration in seconds before triggering discard.
    var holdDuration: TimeInterval = 1.5

    func start() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, // Escape key
                  !event.isARepeat else { return event }
            self?.handleKeyDown()
            return nil // consume the event
        }

        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.handleKeyUp()
            return nil
        }
    }

    func stop() {
        if let m = keyDownMonitor { NSEvent.removeMonitor(m) }
        if let m = keyUpMonitor { NSEvent.removeMonitor(m) }
        keyDownMonitor = nil
        keyUpMonitor = nil
        holdTimer?.invalidate()
        holdTimer = nil
    }

    private func handleKeyDown() {
        didTriggerHold = false
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdDuration, repeats: false) { [weak self] _ in
            self?.didTriggerHold = true
            self?.onHold?()
        }
    }

    private func handleKeyUp() {
        holdTimer?.invalidate()
        holdTimer = nil
        if !didTriggerHold {
            onTap?()
        }
        didTriggerHold = false
    }

    deinit {
        stop()
    }
}
```

- [ ] **Step 2: Wire EscapeKeyMonitor into AppDelegate**

In `Zoidberg/ZoidbergApp.swift`, add to `AppDelegate`:

```swift
private let escapeMonitor = EscapeKeyMonitor()
```

In `applicationDidFinishLaunching`, add:

```swift
escapeMonitor.onTap = { [weak self] in
    self?.popover.performClose(nil)
}
escapeMonitor.onHold = { [weak self] in
    guard let self = self else { return }
    Task { @MainActor in
        self.appState.discardSession()
    }
}
escapeMonitor.start()
```

- [ ] **Step 3: Verify project builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Zoidberg/Helpers/EscapeKeyMonitor.swift Zoidberg/ZoidbergApp.swift
git commit -m "feat: add escape tap (minimize) and hold (discard) via NSEvent monitors"
```

---

### Task 18: Add Info.plist for LSUIElement (hide dock icon)

**Files:**
- Create: `Zoidberg/Info.plist`

Menu bar apps should not show a dock icon.

- [ ] **Step 1: Create Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Zoidberg needs microphone access to transcribe your voice notes.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Zoidberg uses speech recognition to transcribe your dictated notes.</string>
</dict>
</plist>
```

- [ ] **Step 2: Update Package.swift to include Info.plist**

Add to the executable target in Package.swift:

```swift
.executableTarget(
    name: "Zoidberg",
    dependencies: ["HotKey"],
    path: "Zoidberg",
    resources: [.copy("Info.plist")]
)
```

> **Note:** For a proper macOS app bundle, this will need to be built via Xcode or xcodebuild with the plist set as INFOPLIST_FILE. For development with `swift run`, the plist won't be picked up automatically. When ready to distribute, create an Xcode project wrapping this SPM package.

- [ ] **Step 3: Commit**

```bash
git add Zoidberg/Info.plist Package.swift
git commit -m "feat: add Info.plist for LSUIElement and privacy descriptions"
```

---

### Task 19: Add .gitignore and README

**Files:**
- Create: `.gitignore`

- [ ] **Step 1: Create .gitignore**

```
.build/
.swiftpm/
*.xcodeproj
xcuserdata/
DerivedData/
.DS_Store
.superpowers/
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: add .gitignore for Swift project"
```

---

### Task 20: End-to-End Manual Test

- [ ] **Step 1: Build and run**

Run: `swift build && swift run`

- [ ] **Step 2: Manual test checklist**

1. Verify menu bar icon appears in menu bar
2. Click menu bar icon → capture panel opens
3. Type text in the panel
4. Click away → panel closes, reopen → text is still there
5. Right-click menu bar icon → Settings and Quit appear
6. Open Settings → verify vault path, API key fields
7. Drag an image file from Finder onto the panel → image row appears
8. Drag a URL from browser onto the panel → link row appears
9. Press Cmd+Enter → toast appears, note saved to vault
10. Check `~/Documents/Obsidian Vault/Captures/` for the markdown file
11. Press Ctrl+Space → panel toggles
12. Hold Escape for 1.5s → session discards with feedback
13. Reopen panel → "Undo discard" button appears

- [ ] **Step 3: Fix any issues found during testing**

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "fix: address issues found during end-to-end testing"
```
