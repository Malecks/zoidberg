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
