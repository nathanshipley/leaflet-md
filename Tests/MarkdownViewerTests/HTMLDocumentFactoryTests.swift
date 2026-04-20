import XCTest
@testable import MarkdownViewerCore

final class HTMLDocumentFactoryTests: XCTestCase {
    func testWrapsRenderedBodyInMarkdownArticle() {
        let factory = HTMLDocumentFactory(
            githubStyles: ".github { color: red; }",
            appStyles: ".app { color: blue; }"
        )

        let html = factory.makeDocument(
            bodyHTML: "<h1>Hello</h1>",
            title: "README",
            containerClass: "preview-shell",
            contentClass: "markdown-body",
            contentTag: "article"
        )

        XCTAssertTrue(html.contains("<article class=\"markdown-body\">"))
        XCTAssertTrue(html.contains("<h1>Hello</h1>"))
        XCTAssertTrue(html.contains(".github { color: red; }"))
        XCTAssertTrue(html.contains(".app { color: blue; }"))
    }

    func testIncludesPreviewPreferenceOverrides() {
        let factory = HTMLDocumentFactory(githubStyles: "", appStyles: "")

        let html = factory.makeDocument(
            bodyHTML: "<p>Hello</p>",
            title: "README",
            renderingPreferences: PreviewRenderingPreferences(
                marginPreset: .extraWide,
                fontPreset: .inter,
                allowWideContent: true
            )
        )

        XCTAssertTrue(html.contains("--viewer-markdown-max-width: none;"))
        XCTAssertTrue(html.contains("--viewer-markdown-padding-max: 120px;"))
        XCTAssertTrue(html.contains("MarkdownViewerInter"))
        XCTAssertTrue(html.contains("@font-face"))
    }
}
