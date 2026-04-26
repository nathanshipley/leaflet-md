import XCTest
@testable import MarkdownViewerCore

final class MarkdownRendererTests: XCTestCase {
    func testUsesLocalRendererOutput() async {
        let renderer = MarkdownRenderer(
            localRenderer: StubLocalRenderer(result: "<p>local</p>"),
            codeViewRenderer: MarkdownCodeViewRenderer(),
            htmlFactory: HTMLDocumentFactory(githubStyles: "", appStyles: "")
        )

        let rendered = await renderer.render(
            markdown: "# Hello",
            displayMode: .preview,
            context: RenderContext(baseURL: nil, purpose: .preview, title: "README"),
            preferences: .standard
        )

        XCTAssertTrue(rendered.html.contains("<p>local</p>"))
        XCTAssertEqual(rendered.displayMode, .preview)
        XCTAssertNil(rendered.note)
    }

    func testReturnsPlaceholderForEmptyMarkdown() async {
        let renderer = MarkdownRenderer(
            localRenderer: StubLocalRenderer(result: "<p>local</p>"),
            codeViewRenderer: MarkdownCodeViewRenderer(),
            htmlFactory: HTMLDocumentFactory(githubStyles: "", appStyles: "")
        )

        let rendered = await renderer.render(
            markdown: "   \n",
            displayMode: .preview,
            context: RenderContext(baseURL: nil, purpose: .preview, title: "README"),
            preferences: .standard
        )

        XCTAssertTrue(rendered.html.contains("Open an .md file"))
    }

    func testRendersCodeViewWithLineNumbers() async {
        let renderer = MarkdownRenderer(
            localRenderer: StubLocalRenderer(result: "<p>local</p>"),
            codeViewRenderer: MarkdownCodeViewRenderer(),
            htmlFactory: HTMLDocumentFactory(githubStyles: "", appStyles: "")
        )

        let rendered = await renderer.render(
            markdown: "# Heading\n[link](https://example.com)\n",
            displayMode: .code,
            context: RenderContext(baseURL: nil, purpose: .preview, title: "README"),
            preferences: .standard
        )

        XCTAssertEqual(rendered.displayMode, .code)
        XCTAssertTrue(rendered.html.contains("class=\"source-view\""))
        XCTAssertTrue(rendered.html.contains("id=\"L1\""))
        XCTAssertTrue(rendered.html.contains("token-heading"))
        XCTAssertTrue(rendered.html.contains("token-link"))
        XCTAssertNil(rendered.note)
    }

    private struct StubLocalRenderer: LocalMarkdownRendering {
        let result: String

        func render(markdown: String) throws -> String {
            result
        }
    }
}
