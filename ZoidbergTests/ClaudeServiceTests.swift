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
}
