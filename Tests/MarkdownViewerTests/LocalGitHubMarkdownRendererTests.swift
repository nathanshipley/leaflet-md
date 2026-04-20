import XCTest
@testable import MarkdownViewerCore

final class LocalGitHubMarkdownRendererTests: XCTestCase {
    func testFixtureProducesBlockAndTableMarkup() throws {
        let fixtureURL = Bundle.module.url(forResource: "showcase", withExtension: "md")!
        let markdown = try String(contentsOf: fixtureURL, encoding: .utf8)
        let html = try LocalGitHubMarkdownRenderer().render(markdown: markdown)

        XCTAssertTrue(html.contains("<h1>"))
        XCTAssertTrue(html.contains("<table"))
        XCTAssertTrue(html.contains("<blockquote"))
        XCTAssertTrue(html.contains("<pre"))
    }

    func testSimpleListDoesNotWrapEachItemInParagraphMarkup() throws {
        let html = try LocalGitHubMarkdownRenderer().render(markdown: "- one\n- two\n")

        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertTrue(html.contains("<li>one</li>"))
        XCTAssertFalse(html.contains("<li><p>"))
    }
}
