// ZoidbergTests/SettingsTests.swift
import XCTest
@testable import Zoidberg

final class SettingsTests: XCTestCase {
    override func setUp() {
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

    func testBragPathDefault() {
        XCTAssertEqual(AppSettings.bragPath, NSHomeDirectory() + "/.local/bin/brag")
    }

    func testBragLaterSecondsDefaultAndOverride() {
        XCTAssertEqual(AppSettings.bragLaterSeconds, 3600)
        AppSettings.defaults.set(60.0, forKey: "bragLaterSeconds")
        XCTAssertEqual(AppSettings.bragLaterSeconds, 60)
    }
}
