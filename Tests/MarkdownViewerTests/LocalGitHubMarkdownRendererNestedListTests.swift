import XCTest
@testable import MarkdownViewerCore

final class LocalGitHubMarkdownRendererNestedListTests: XCTestCase {
    func testRendersNestedOrderedListsWhenIndentedToContentColumn() throws {
        let markdown = """
        1. First step
           1. Sub-step A
           2. Sub-step B
        2. Second step
        """

        let html = try LocalGitHubMarkdownRenderer().render(markdown: markdown)

        XCTAssertTrue(html.contains("<ol>"))
        XCTAssertTrue(html.contains("First step"))
        XCTAssertTrue(html.contains("Sub-step A"))
        XCTAssertTrue(html.contains("Sub-step B"))
        XCTAssertTrue(html.contains("Second step"))
        XCTAssertTrue(html.contains("<li>First step\n<ol>"))
    }
}
