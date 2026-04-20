import XCTest
@testable import MarkdownViewerCore

final class SlackExporterTests: XCTestCase {
    func testConvertsHeadingsListsLinksAndQuotes() {
        let markdown = """
        # Title

        Some **bold** text with [a link](https://example.com).

        - First item
        - [ ] Open task
        1. First step
        > Quoted line
        """

        let exported = SlackExporter().export(markdown: markdown)

        XCTAssertTrue(exported.contains("Title"))
        XCTAssertTrue(exported.contains("Some *bold* text with a link: https://example.com."))
        XCTAssertTrue(exported.contains("• First item"))
        XCTAssertTrue(exported.contains("☐ Open task"))
        XCTAssertTrue(exported.contains("1. First step"))
        XCTAssertTrue(exported.contains("> Quoted line"))
        XCTAssertTrue(exported.contains("Title\n\nSome *bold* text"))
    }

    func testConvertsCodeFencesWithoutLanguageTag() {
        let markdown = """
        ```swift
        print("Hello")
        ```
        """

        let exported = SlackExporter().export(markdown: markdown)

        XCTAssertEqual(exported, """
        ```
        print("Hello")
        ```
        """)
    }

    func testFlattensTablesIntoSlackFriendlyBullets() {
        let markdown = """
        | Name | Role |
        | --- | --- |
        | Alex | Design |
        | Sam | Engineering |
        """

        let exported = SlackExporter().export(markdown: markdown)

        XCTAssertTrue(exported.contains("Name: Alex\nRole: Design"))
        XCTAssertTrue(exported.contains("Name: Sam\nRole: Engineering"))
        XCTAssertTrue(exported.contains("Design\n\nName: Sam"))
    }

    func testExportsBlockquotesAsHTMLBlockquotes() {
        let markdown = """
        Before

        > Quoted line

        After
        """

        let html = SlackExporter().exportHTMLDocument(markdown: markdown)

        XCTAssertTrue(html.contains("<blockquote><p>Quoted line</p></blockquote>"))
        XCTAssertTrue(html.contains("<p class=\"slack-spacer\"><br></p>"))
    }

    func testExportsTablesAsCodeBlocksWhenRequested() {
        let markdown = """
        | Language | Rank | Appeared |
        | --- | --- | --- |
        | JavaScript | 6 | 1995 |
        | C# | 5 | 2000 |
        | Scratch | 17 | 2002 |
        """

        let plainText = SlackExporter().export(markdown: markdown, tableMode: .codeBlock)
        let html = SlackExporter().exportHTMLDocument(markdown: markdown, tableMode: .codeBlock)

        XCTAssertTrue(plainText.contains("```"))
        XCTAssertTrue(plainText.contains("| Language"))
        XCTAssertTrue(plainText.contains("| JavaScript"))
        XCTAssertTrue(html.contains("<pre><code>"))
        XCTAssertTrue(html.contains("| Language"))
        XCTAssertTrue(html.contains("| JavaScript"))
    }

    func testPreservesSlackFormattingMarkersInPlainText() {
        let markdown = """
        This has **bold**, *italic*, and ~~strikethrough~~.
        """

        let exported = SlackExporter().export(markdown: markdown)

        XCTAssertEqual(
            exported,
            "This has *bold*, _italic_, and ~strikethrough~."
        )
    }

    func testRendersNestedListsWithIndentationAndOrderedRestart() {
        let markdown = """
        - Parent
          - Child
            - Grandchild
        - Another parent

        1. First step
          1. Sub-step A
          2. Sub-step B
        2. Second step
        """

        let exported = SlackExporter().export(markdown: markdown)

        XCTAssertTrue(exported.contains("• Parent"))
        XCTAssertTrue(exported.contains("    • Child"))
        XCTAssertTrue(exported.contains("        • Grandchild"))
        XCTAssertTrue(exported.contains("• Another parent"))
        XCTAssertTrue(exported.contains("1. First step"))
        XCTAssertTrue(exported.contains("    1. Sub-step A"))
        XCTAssertTrue(exported.contains("    2. Sub-step B"))
        XCTAssertTrue(exported.contains("2. Second step"))
    }

    func testExportsHorizontalRulesAndStrikethroughInHTML() {
        let markdown = """
        Before

        ---

        ~~After~~
        """

        let html = SlackExporter().exportHTMLDocument(markdown: markdown)

        XCTAssertTrue(html.contains("<p class=\"slack-rule\">"))
        XCTAssertTrue(html.contains("────────────────────"))
        XCTAssertTrue(html.contains("<s>After</s>"))
    }

    func testExportsSemanticNestedListsInHTML() {
        let markdown = """
        - Parent
          - Child
            - Grandchild

        1. First step
          1. Sub-step A
          2. Sub-step B
        2. Second step
        """

        let html = SlackExporter().exportHTMLDocument(markdown: markdown)

        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertTrue(html.contains("<li>Parent<ul>"))
        XCTAssertTrue(html.contains("<li>Child<ul>"))
        XCTAssertTrue(html.contains("<li>Grandchild</li>"))
        XCTAssertTrue(html.contains("<ol>"))
        XCTAssertTrue(html.contains("<li>First step<ol type=\"a\">"))
        XCTAssertTrue(html.contains("<li>Sub-step A</li>"))
        XCTAssertTrue(html.contains("<li>Sub-step B</li>"))
        XCTAssertTrue(html.contains("<li>Second step</li>"))
    }

    func testExportsSlackTextyWithNestedListsAndIndentLevels() throws {
        let markdown = """
        - Parent item
          - Child item
            - Grandchild item
        - Another parent

        1. First step
          1. Sub-step A
          2. Sub-step B
        2. Second step
        """

        let json = SlackExporter().exportSlackTexty(markdown: markdown)
        let document = try textyDocument(from: json)
        let ops = try XCTUnwrap(document["ops"] as? [[String: Any]])
        let listNewlines = ops.filter { ($0["attributes"] as? [String: Any])?["list"] != nil }

        XCTAssertEqual(listNewlines.count, 8)
        XCTAssertEqual((listNewlines[0]["attributes"] as? [String: Any])?["list"] as? String, "bullet")
        XCTAssertNil((listNewlines[0]["attributes"] as? [String: Any])?["indent"])
        XCTAssertEqual((listNewlines[1]["attributes"] as? [String: Any])?["indent"] as? Int, 1)
        XCTAssertEqual((listNewlines[2]["attributes"] as? [String: Any])?["indent"] as? Int, 2)
        XCTAssertEqual((listNewlines[4]["attributes"] as? [String: Any])?["list"] as? String, "ordered")
        XCTAssertEqual((listNewlines[5]["attributes"] as? [String: Any])?["indent"] as? Int, 1)
    }

    func testExportsSlackTextyInlineFormattingAttributes() throws {
        let markdown = """
        This has **bold**, *italic*, ~~strikethrough~~, `code`, and [a link](https://example.com).
        """

        let json = SlackExporter().exportSlackTexty(markdown: markdown)
        let document = try textyDocument(from: json)
        let ops = try XCTUnwrap(document["ops"] as? [[String: Any]])

        XCTAssertTrue(
            ops.contains {
                ($0["insert"] as? String)?.contains("bold") == true
                    && (($0["attributes"] as? [String: Any])?["bold"] as? Bool) == true
            }
        )
        XCTAssertTrue(
            ops.contains {
                ($0["insert"] as? String)?.contains("italic") == true
                    && (($0["attributes"] as? [String: Any])?["italic"] as? Bool) == true
            }
        )
        XCTAssertTrue(
            ops.contains {
                ($0["insert"] as? String)?.contains("strikethrough") == true
                    && (($0["attributes"] as? [String: Any])?["strike"] as? Bool) == true
            }
        )
        XCTAssertTrue(
            ops.contains {
                ($0["insert"] as? String)?.contains("code") == true
                    && (($0["attributes"] as? [String: Any])?["code"] as? Bool) == true
            }
        )
        XCTAssertTrue(
            ops.contains {
                ($0["insert"] as? String)?.contains("a link") == true
                    && (($0["attributes"] as? [String: Any])?["link"] as? String)?.hasPrefix("https://example.com") == true
            }
        )
    }

    func testExportsSlackTextyBlockquotesAndCodeBlocksAsLineAttributes() throws {
        let markdown = """
        > Quoted line

        ```swift
        print("Hello")
        ```
        """

        let json = SlackExporter().exportSlackTexty(markdown: markdown)
        let document = try textyDocument(from: json)
        let ops = try XCTUnwrap(document["ops"] as? [[String: Any]])

        XCTAssertTrue(
            ops.contains {
                ($0["insert"] as? String) == "\n"
                    && (($0["attributes"] as? [String: Any])?["blockquote"] as? Bool) == true
            }
        )
        XCTAssertTrue(
            ops.contains {
                ($0["insert"] as? String) == "\n"
                    && (($0["attributes"] as? [String: Any])?["code-block"] as? Bool) == true
            }
        )
        XCTAssertFalse(json.contains("```"))
        XCTAssertFalse(json.contains("> Quoted line"))
    }

    func testExportsSlackTextyCodeBlockTablesWithoutLiteralFences() throws {
        let markdown = """
        | Name | Role |
        | --- | --- |
        | Alex | Design |
        | Sam | Engineering |
        """

        let json = SlackExporter().exportSlackTexty(markdown: markdown, tableMode: .codeBlock)
        let document = try textyDocument(from: json)
        let ops = try XCTUnwrap(document["ops"] as? [[String: Any]])

        XCTAssertTrue(
            ops.contains {
                ($0["insert"] as? String) == "\n"
                    && (($0["attributes"] as? [String: Any])?["code-block"] as? Bool) == true
            }
        )
        XCTAssertFalse(json.contains("```"))
        XCTAssertTrue(json.contains("| Name"))
        XCTAssertTrue(json.contains("| Alex"))
    }

    private func textyDocument(from json: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try XCTUnwrap(object as? [String: Any])
    }
}
