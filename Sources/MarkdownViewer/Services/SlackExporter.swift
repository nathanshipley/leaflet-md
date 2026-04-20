import AppKit
import Foundation

struct SlackExporter {
    private let inlineRenderer = LocalGitHubMarkdownRenderer()

    func export(
        markdown: String,
        tableMode: SlackTableRenderingMode = .readableRows
    ) -> String {
        renderPlainText(blocks(from: markdown), tableMode: tableMode)
    }

    func exportHTMLDocument(
        markdown: String,
        tableMode: SlackTableRenderingMode = .readableRows
    ) -> String {
        makeHTMLDocument(renderHTML(blocks(from: markdown), tableMode: tableMode))
    }

    func exportAttributed(
        markdown: String,
        tableMode: SlackTableRenderingMode = .readableRows
    ) -> NSAttributedString {
        renderAttributedText(blocks(from: markdown), tableMode: tableMode)
    }

    func exportSlackTexty(
        markdown: String,
        tableMode: SlackTableRenderingMode = .readableRows
    ) -> String {
        let encoder = JSONEncoder()
        guard
            let data = try? encoder.encode(
                renderSlackTexty(blocks(from: markdown), tableMode: tableMode)
            )
        else {
            return #"{"ops":[]}"#
        }

        return String(decoding: data, as: UTF8.self)
    }

    func exportAttributed(plainText: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: normalized(plainText),
            attributes: baseAttributes(font: .systemFont(ofSize: 15), color: .labelColor)
        )
        applyDataDetectedLinks(to: attributed)
        return attributed
    }

    private func blocks(from markdown: String) -> [SlackBlock] {
        let lines = normalized(markdown).components(separatedBy: "\n")
        var blocks: [SlackBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }

            if let fence = codeFenceDelimiter(for: line) {
                let result = consumeCodeBlock(lines: lines, startIndex: index, fence: fence)
                blocks.append(.code(result.lines))
                index = result.nextIndex
                continue
            }

            if let table = consumeTable(lines: lines, startIndex: index) {
                blocks.append(.table(table.rows))
                index = table.nextIndex
                continue
            }

            if let heading = match(line, pattern: #"^\s{0,3}#{1,6}\s+(.+?)\s*$"#, group: 1) {
                blocks.append(.heading(heading))
                index += 1
                continue
            }

            if isHorizontalRule(line) {
                blocks.append(.horizontalRule)
                index += 1
                continue
            }

            if let quote = consumeQuote(lines: lines, startIndex: index) {
                blocks.append(.quote(quote))
                index += quote.count
                continue
            }

            if let list = consumeList(lines: lines, startIndex: index) {
                blocks.append(.list(list.items))
                index = list.nextIndex
                continue
            }

            let paragraph = consumeParagraph(lines: lines, startIndex: index)
            blocks.append(.paragraph(paragraph.text))
            index = paragraph.nextIndex
        }

        return blocks
    }

    private func renderPlainText(
        _ blocks: [SlackBlock],
        tableMode: SlackTableRenderingMode
    ) -> String {
        blocks
            .map { block in
                switch block {
                case let .heading(raw):
                    return renderInlinePlainText(raw)
                case let .paragraph(raw):
                    return renderInlinePlainText(raw)
                case let .quote(lines):
                    return lines
                        .map { "> " + renderInlinePlainText($0) }
                        .joined(separator: "\n")
                case let .list(items):
                    let markers = renderedListMarkers(for: items)
                    return items
                        .enumerated()
                        .map { index, item in
                            renderPlainTextListItem(item, marker: markers[index])
                        }
                        .joined(separator: "\n")
                case let .code(lines):
                    return ["```", lines.joined(separator: "\n"), "```"].joined(separator: "\n")
                case .horizontalRule:
                    return horizontalRuleText()
                case let .table(rows):
                    switch tableMode {
                    case .readableRows:
                        return rows
                            .map { row in
                                row
                                    .map { pair in
                                        "\(renderInlinePlainText(pair.label)): \(renderInlinePlainText(pair.value))"
                                    }
                                    .joined(separator: "\n")
                            }
                            .joined(separator: "\n\n")
                    case .codeBlock:
                        return renderTableAsCodeBlockPlainText(rows)
                    }
                }
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func renderHTML(
        _ blocks: [SlackBlock],
        tableMode: SlackTableRenderingMode
    ) -> String {
        blocks
            .map { block in
                switch block {
                case let .heading(raw):
                    return "<p><strong>\(renderInlineHTML(raw))</strong></p>"
                case let .paragraph(raw):
                    return "<p>\(renderInlineHTML(raw))</p>"
                case let .quote(lines):
                    let paragraphs = lines
                        .map { "<p>\(renderInlineHTML($0))</p>" }
                        .joined()
                    return "<blockquote>\(paragraphs)</blockquote>"
                case let .list(items):
                    return renderHTMLList(items)
                case let .code(lines):
                    return "<pre><code>\(lines.joined(separator: "\n").htmlEscaped)</code></pre>"
                case .horizontalRule:
                    return "<p class=\"slack-rule\">\(horizontalRuleText().htmlEscaped)</p>"
                case let .table(rows):
                    switch tableMode {
                    case .readableRows:
                        return rows
                            .map(renderHTMLTableRow(_:))
                            .joined(separator: htmlSpacer())
                    case .codeBlock:
                        return renderHTMLTableCodeBlock(rows)
                    }
                }
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: htmlSpacer())
    }

    private func renderAttributedText(
        _ blocks: [SlackBlock],
        tableMode: SlackTableRenderingMode
    ) -> NSAttributedString {
        let output = NSMutableAttributedString()

        for (index, block) in blocks.enumerated() {
            if index > 0 {
                output.append(makePlainAttributed("\n\n"))
            }

            switch block {
            case let .heading(raw):
                let attributed = renderInlineAttributedText(raw)
                if attributed.length > 0 {
                    attributed.addAttributes(
                        [.font: NSFont.systemFont(ofSize: 15, weight: .semibold)],
                        range: NSRange(location: 0, length: attributed.length)
                    )
                }
                output.append(attributed)
            case let .paragraph(raw):
                output.append(renderInlineAttributedText(raw))
            case let .quote(lines):
                let quoteBlock = NSMutableAttributedString()

                for (quoteIndex, line) in lines.enumerated() {
                    if quoteIndex > 0 {
                        quoteBlock.append(makePlainAttributed("\n", color: .secondaryLabelColor))
                    }

                    quoteBlock.append(makePlainAttributed("> ", color: .secondaryLabelColor))
                    let lineText = renderInlineAttributedText(line)
                    lineText.addAttributes(
                        [.foregroundColor: NSColor.secondaryLabelColor],
                        range: NSRange(location: 0, length: lineText.length)
                    )
                    quoteBlock.append(lineText)
                }

                output.append(quoteBlock)
            case let .list(items):
                output.append(renderSemanticAttributedList(items))
            case let .code(lines):
                let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                let codeBlock = makePlainAttributed(
                    ["```", lines.joined(separator: "\n"), "```"].joined(separator: "\n"),
                    font: codeFont
                )
                output.append(codeBlock)
            case let .table(rows):
                let tableBlock: NSMutableAttributedString
                switch tableMode {
                case .readableRows:
                    tableBlock = NSMutableAttributedString()

                    for (rowIndex, row) in rows.enumerated() {
                        if rowIndex > 0 {
                            tableBlock.append(makePlainAttributed("\n\n"))
                        }

                        let rowBlock = NSMutableAttributedString()
                        for (pairIndex, pair) in row.enumerated() {
                            if pairIndex > 0 {
                                rowBlock.append(makePlainAttributed("\n"))
                            }

                            rowBlock.append(
                                makePlainAttributed(
                                    renderInlinePlainText(pair.label) + ": ",
                                    font: .systemFont(ofSize: 15, weight: .semibold)
                                )
                            )
                            rowBlock.append(renderInlineAttributedText(pair.value))
                        }

                        tableBlock.append(rowBlock)
                    }
                case .codeBlock:
                    tableBlock = NSMutableAttributedString(
                        attributedString: makePlainAttributed(
                            renderTableAsCodeBlockPlainText(rows),
                            font: .monospacedSystemFont(ofSize: 13, weight: .regular)
                        )
                    )
                }
                output.append(tableBlock)
            case .horizontalRule:
                output.append(
                    makePlainAttributed(
                        horizontalRuleText(),
                        color: .secondaryLabelColor
                    )
                )
            }
        }

        applyDataDetectedLinks(to: output)
        return output
    }

    private func renderSlackTexty(
        _ blocks: [SlackBlock],
        tableMode: SlackTableRenderingMode
    ) -> SlackTextyDocument {
        var builder = SlackTextyBuilder()

        for (index, block) in blocks.enumerated() {
            if index > 0 {
                builder.append(blockSeparator(after: blocks[index - 1]))
            }

            switch block {
            case let .heading(raw):
                appendInlineTexty(
                    raw,
                    defaultAttributes: SlackTextyAttributes(bold: true),
                    to: &builder
                )
            case let .paragraph(raw):
                appendInlineTexty(raw, to: &builder)
            case let .quote(lines):
                appendTextyBlockquote(lines, to: &builder)
            case let .list(items):
                appendTextyList(items, to: &builder)
            case let .code(lines):
                appendTextyCodeBlock(lines, to: &builder)
            case .horizontalRule:
                builder.append(horizontalRuleText())
            case let .table(rows):
                switch tableMode {
                case .readableRows:
                    builder.append(renderPlainText([.table(rows)], tableMode: tableMode))
                case .codeBlock:
                    appendTextyCodeBlock(
                        renderCodeBlockTable(rows).components(separatedBy: "\n"),
                        to: &builder
                    )
                }
            }
        }

        return SlackTextyDocument(ops: builder.ops)
    }

    private func renderPlainTextListItem(_ item: SlackListItem, marker: String) -> String {
        let indent = String(repeating: "    ", count: item.indentLevel)
        return indent + marker + " " + renderInlinePlainText(item.content)
    }

    private func renderAttributedListItem(_ item: SlackListItem, marker: String) -> NSAttributedString {
        let indent = String(repeating: "    ", count: item.indentLevel)
        let output = NSMutableAttributedString()
        output.append(makePlainAttributed(indent + marker + " "))
        output.append(renderInlineAttributedText(item.content))
        return output
    }

    private func renderSemanticAttributedList(_ items: [SlackListItem]) -> NSAttributedString {
        let output = NSMutableAttributedString()
        var activeLists: [NSTextList] = []
        var activeKinds: [SlackHTMLListKind] = []

        for (index, item) in items.enumerated() {
            if index > 0 {
                output.append(makePlainAttributed("\n"))
            }

            if item.indentLevel < activeLists.count {
                activeLists.removeLast(activeLists.count - item.indentLevel)
                activeKinds.removeLast(activeKinds.count - item.indentLevel)
            }

            let targetDepth = item.indentLevel + 1
            let itemKind = semanticListKind(for: item.marker)

            while activeLists.count < targetDepth {
                let depth = activeLists.count
                let kind = depth == item.indentLevel ? itemKind : .unordered
                activeLists.append(makeTextList(for: kind, depth: depth))
                activeKinds.append(kind)
            }

            if activeKinds[item.indentLevel] != itemKind {
                activeLists[item.indentLevel] = makeTextList(for: itemKind, depth: item.indentLevel)
                activeKinds[item.indentLevel] = itemKind
            }

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.textLists = Array(activeLists.prefix(targetDepth))
            paragraphStyle.firstLineHeadIndent = CGFloat(targetDepth) * 18
            paragraphStyle.headIndent = paragraphStyle.firstLineHeadIndent
            paragraphStyle.paragraphSpacing = 2
            paragraphStyle.tabStops = []
            paragraphStyle.defaultTabInterval = 18

            let itemText = NSMutableAttributedString()
            let prefix = semanticListTextPrefix(for: item.marker)
            if !prefix.isEmpty {
                itemText.append(makePlainAttributed(prefix))
            }
            itemText.append(renderInlineAttributedText(item.content))
            itemText.addAttribute(
                .paragraphStyle,
                value: paragraphStyle,
                range: NSRange(location: 0, length: itemText.length)
            )
            output.append(itemText)
        }

        return output
    }

    private func appendTextyList(
        _ items: [SlackListItem],
        to builder: inout SlackTextyBuilder
    ) {
        for item in items {
            let prefix = semanticListTextPrefix(for: item.marker)
            if !prefix.isEmpty {
                builder.append(prefix)
            }

            appendInlineTexty(item.content, to: &builder)
            builder.append(
                "\n",
                attributes: SlackTextyAttributes(
                    list: textyListKind(for: item.marker).rawValue,
                    indent: item.indentLevel > 0 ? item.indentLevel : nil
                )
            )
        }
    }

    private func appendTextyBlockquote(
        _ lines: [String],
        to builder: inout SlackTextyBuilder
    ) {
        for line in lines {
            if !line.isEmpty {
                appendInlineTexty(line, to: &builder)
            }

            builder.append(
                "\n",
                attributes: SlackTextyAttributes(blockquote: true)
            )
        }
    }

    private func appendTextyCodeBlock(
        _ lines: [String],
        to builder: inout SlackTextyBuilder
    ) {
        if lines.isEmpty {
            builder.append(
                "\n",
                attributes: SlackTextyAttributes(codeBlock: true)
            )
            return
        }

        for line in lines {
            if !line.isEmpty {
                builder.append(line)
            }

            builder.append(
                "\n",
                attributes: SlackTextyAttributes(codeBlock: true)
            )
        }
    }

    private func renderHTMLList(_ items: [SlackListItem]) -> String {
        guard !items.isEmpty else {
            return ""
        }

        let (nodes, _) = buildHTMLListNodes(
            from: items,
            startIndex: 0,
            indentLevel: items[0].indentLevel
        )
        return renderHTMLListGroups(nodes, depth: 0)
    }

    private func renderHTMLTableRow(_ row: [(label: String, value: String)]) -> String {
        let content = row
            .map { pair in
                "<strong>\(renderInlinePlainText(pair.label).htmlEscaped):</strong> \(renderInlineHTML(pair.value))"
            }
            .joined(separator: "<br>")

        return "<p class=\"slack-table-row\">\(content)</p>"
    }

    private func renderHTMLTableCodeBlock(_ rows: [[(label: String, value: String)]]) -> String {
        "<pre><code>\(renderCodeBlockTable(rows).htmlEscaped)</code></pre>"
    }

    private func renderTableAsCodeBlockPlainText(_ rows: [[(label: String, value: String)]]) -> String {
        ["```", renderCodeBlockTable(rows), "```"].joined(separator: "\n")
    }

    private func renderCodeBlockTable(_ rows: [[(label: String, value: String)]]) -> String {
        guard
            let firstRow = rows.first,
            !firstRow.isEmpty
        else {
            return ""
        }

        let headers = firstRow.map { renderInlinePlainText($0.label) }
        let values = rows.map { row in
            row.map { renderInlinePlainText($0.value) }
        }

        let widths = headers.indices.map { column in
            max(
                headers[column].count,
                values.map { row in row.indices.contains(column) ? row[column].count : 0 }.max() ?? 0
            )
        }

        let headerLine = markdownTableLine(cells: headers, widths: widths)
        let separatorLine = markdownTableSeparator(widths: widths)
        let bodyLines = values.map { markdownTableLine(cells: $0, widths: widths) }

        return ([headerLine, separatorLine] + bodyLines).joined(separator: "\n")
    }

    private func markdownTableLine(cells: [String], widths: [Int]) -> String {
        let paddedCells = widths.indices.map { index in
            let value = cells.indices.contains(index) ? cells[index] : ""
            return value.padding(toLength: widths[index], withPad: " ", startingAt: 0)
        }

        return "| " + paddedCells.joined(separator: " | ") + " |"
    }

    private func markdownTableSeparator(widths: [Int]) -> String {
        let cells = widths.map { String(repeating: "-", count: max($0, 3)) }
        return "| " + cells.joined(separator: " | ") + " |"
    }

    private func renderInlinePlainText(_ text: String) -> String {
        let protected = protectInlineCode(in: text)
        var transformed = protected.text
        var placeholders = protected.placeholders
        var nextIndex = 0

        transformed = replacing(
            in: transformed,
            pattern: #"!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#
        ) { groups in
            let alt = groups[1]
            let url = groups[2]
            return alt.isEmpty ? url : "\(alt): \(url)"
        }

        transformed = replacing(
            in: transformed,
            pattern: #"\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#
        ) { groups in
            "\(groups[1]): \(groups[2])"
        }

        transformed = protectingMatches(
            in: transformed,
            pattern: #"~~(.+?)~~"#,
            placeholders: &placeholders,
            nextIndex: &nextIndex
        ) { "~\($0[1])~" }

        transformed = protectingMatches(
            in: transformed,
            pattern: #"\*\*(.+?)\*\*"#,
            placeholders: &placeholders,
            nextIndex: &nextIndex
        ) { "*\($0[1])*" }

        transformed = protectingMatches(
            in: transformed,
            pattern: #"__(.+?)__"#,
            placeholders: &placeholders,
            nextIndex: &nextIndex
        ) { "*\($0[1])*" }

        transformed = protectingMatches(
            in: transformed,
            pattern: #"(?<!\*)\*(?![\s\*])(.+?)(?<![\s\*])\*(?!\*)"#,
            placeholders: &placeholders,
            nextIndex: &nextIndex
        ) { "_\($0[1])_" }

        transformed = protectingMatches(
            in: transformed,
            pattern: #"(?<!_)_(?![\s_])(.+?)(?<![\s_])_(?!_)"#,
            placeholders: &placeholders,
            nextIndex: &nextIndex
        ) { "_\($0[1])_" }

        return restoreInlineCode(in: transformed, placeholders: placeholders)
    }

    private func renderInlineHTML(_ text: String) -> String {
        let rendered: String
        if let html = try? inlineRenderer.render(markdown: text) {
            rendered = html.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            rendered = text.htmlEscaped
        }

        if rendered.hasPrefix("<p>"), rendered.hasSuffix("</p>") {
            return convertSlackHTMLInline(String(rendered.dropFirst(3).dropLast(4)))
        }

        return convertSlackHTMLInline(rendered)
    }

    private func renderInlineAttributedText(_ text: String) -> NSMutableAttributedString {
        let htmlBody: String
        if let rendered = try? inlineRenderer.render(markdown: text) {
            htmlBody = rendered
        } else {
            htmlBody = "<p>\(text.htmlEscaped)</p>"
        }

        let htmlDocument = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <style>
            body {
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
              font-size: 15px;
              line-height: 1.5;
              color: #1f2328;
            }

            p, ul, ol {
              margin: 0;
            }

            a {
              color: #0969da;
              text-decoration: underline;
            }

            code {
              font-family: SFMono-Regular, ui-monospace, Menlo, monospace;
              font-size: 13px;
            }
          </style>
        </head>
        <body>
          \(htmlBody)
        </body>
        </html>
        """

        guard
            let attributed = try? NSAttributedString(
                data: Data(htmlDocument.utf8),
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            )
        else {
            return NSMutableAttributedString(string: renderInlinePlainText(text), attributes: baseAttributes())
        }

        let mutable = NSMutableAttributedString(attributedString: attributed)
        trimTrailingNewlines(from: mutable)
        return mutable
    }

    private func appendInlineTexty(
        _ text: String,
        defaultAttributes: SlackTextyAttributes = SlackTextyAttributes(),
        to builder: inout SlackTextyBuilder
    ) {
        let attributed = renderInlineAttributedText(text)
        guard attributed.length > 0 else {
            return
        }

        attributed.enumerateAttributes(
            in: NSRange(location: 0, length: attributed.length)
        ) { attributes, range, _ in
            let fragment = attributed.attributedSubstring(from: range).string
            guard !fragment.isEmpty else {
                return
            }

            let mergedAttributes = defaultAttributes.merged(
                with: textyInlineAttributes(from: attributes)
            )
            builder.append(fragment, attributes: mergedAttributes.nonEmpty)
        }
    }

    private func consumeParagraph(
        lines: [String],
        startIndex: Int
    ) -> (text: String, nextIndex: Int) {
        var collected: [String] = []
        var index = startIndex

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty || startsNewBlock(lines: lines, index: index) {
                break
            }

            collected.append(line.trimmingCharacters(in: .whitespaces))
            index += 1
        }

        return (collected.joined(separator: " "), index)
    }

    private func consumeQuote(lines: [String], startIndex: Int) -> [String]? {
        guard transformedBlockquoteContent(lines[startIndex]) != nil else {
            return nil
        }

        var collected: [String] = []
        var index = startIndex

        while index < lines.count, let content = transformedBlockquoteContent(lines[index]) {
            collected.append(content)
            index += 1
        }

        return collected
    }

    private func transformedBlockquoteContent(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else {
            return nil
        }

        var working = trimmed[...]
        while working.first == ">" {
            working = working.dropFirst()
            while working.first == " " {
                working = working.dropFirst()
            }
        }

        return String(working)
    }

    private func consumeList(
        lines: [String],
        startIndex: Int
    ) -> (items: [SlackListItem], nextIndex: Int)? {
        guard let first = parseListItem(lines[startIndex]) else {
            return nil
        }

        var items = [first]
        var index = startIndex + 1

        while index < lines.count, let item = parseListItem(lines[index]) {
            items.append(item)
            index += 1
        }

        return (items, index)
    }

    private func parseListItem(_ line: String) -> SlackListItem? {
        if let match = firstMatch(line, pattern: #"^(\s*)(\d+)[\.\)]\s+(.+?)\s*$"#) {
            return SlackListItem(
                indentLevel: indentationLevel(for: match[1]),
                marker: .ordered(match[2]),
                content: match[3]
            )
        }

        if let match = firstMatch(line, pattern: #"^(\s*)[-\+\*]\s+(\[[ xX]\]\s+)?(.+?)\s*$"#) {
            let checkbox = match[2].trimmingCharacters(in: .whitespaces)
            let marker: SlackListMarker
            switch checkbox.lowercased() {
            case "[ ]":
                marker = .unordered(true)
            case "[x]":
                marker = .unorderedCompleted
            default:
                marker = .unordered(false)
            }

            return SlackListItem(
                indentLevel: indentationLevel(for: match[1]),
                marker: marker,
                content: match[3]
            )
        }

        return nil
    }

    private func consumeCodeBlock(
        lines: [String],
        startIndex: Int,
        fence: String
    ) -> (lines: [String], nextIndex: Int) {
        var codeLines: [String] = []
        var index = startIndex + 1

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(fence) {
                return (codeLines, index + 1)
            }

            codeLines.append(lines[index])
            index += 1
        }

        return (codeLines, index)
    }

    private func consumeTable(
        lines: [String],
        startIndex: Int
    ) -> (rows: [[(label: String, value: String)]], nextIndex: Int)? {
        guard startIndex + 1 < lines.count else {
            return nil
        }

        let headerCells = parseTableRow(lines[startIndex])
        guard !headerCells.isEmpty, isTableSeparator(lines[startIndex + 1]) else {
            return nil
        }

        var rows: [[(label: String, value: String)]] = []
        var index = startIndex + 2

        while index < lines.count {
            let rowCells = parseTableRow(lines[index])
            if rowCells.isEmpty {
                break
            }

            let pairs = zip(headerCells, rowCells).map { header, value in
                (label: header, value: value)
            }
            if !pairs.isEmpty {
                rows.append(pairs)
            }

            index += 1
        }

        guard !rows.isEmpty else {
            return nil
        }

        return (rows, index)
    }

    private func parseTableRow(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|"), !trimmed.hasPrefix("```") else {
            return []
        }

        return trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|"), trimmed.contains("-") else {
            return false
        }

        let reduced = trimmed.replacingOccurrences(
            of: #"[|\-:\s]"#,
            with: "",
            options: .regularExpression
        )
        return reduced.isEmpty
    }

    private func startsNewBlock(lines: [String], index: Int) -> Bool {
        let line = lines[index]
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            return true
        }

        if index + 1 < lines.count {
            let headerCells = parseTableRow(line)
            if !headerCells.isEmpty, isTableSeparator(lines[index + 1]) {
                return true
            }
        }

        return codeFenceDelimiter(for: line) != nil
            || isHorizontalRule(line)
            || match(line, pattern: #"^\s{0,3}#{1,6}\s+(.+?)\s*$"#, group: 1) != nil
            || transformedBlockquoteContent(line) != nil
            || parseListItem(line) != nil
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        line.range(
            of: #"^\s*([-*_])(?:\s*\1){2,}\s*$"#,
            options: .regularExpression
        ) != nil
    }

    private func codeFenceDelimiter(for line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") {
            return "```"
        }

        if trimmed.hasPrefix("~~~") {
            return "~~~"
        }

        return nil
    }

    private func indentationLevel(for leadingWhitespace: String) -> Int {
        let spaces = leadingWhitespace.replacingOccurrences(of: "\t", with: "    ").count
        return spaces / 2
    }

    private func protectInlineCode(in text: String) -> (text: String, placeholders: [String: String]) {
        let pattern = #"`[^`]+`"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (text, [:])
        }

        let matches = regex.matches(
            in: text,
            range: NSRange(location: 0, length: text.utf16.count)
        )

        guard !matches.isEmpty else {
            return (text, [:])
        }

        var result = text
        var placeholders: [String: String] = [:]

        for (index, match) in matches.reversed().enumerated() {
            guard let range = Range(match.range, in: result) else { continue }
            let token = "@@SLACKCODETOKEN\(index)@@"
            placeholders[token] = String(result[range])
            result.replaceSubrange(range, with: token)
        }

        return (result, placeholders)
    }

    private func restoreInlineCode(in text: String, placeholders: [String: String]) -> String {
        placeholders.reduce(text) { partial, entry in
            partial.replacingOccurrences(of: entry.key, with: entry.value)
        }
    }

    private func protectingMatches(
        in text: String,
        pattern: String,
        placeholders: inout [String: String],
        nextIndex: inout Int,
        transform: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
        guard !matches.isEmpty else {
            return text
        }

        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let groups = (0..<match.numberOfRanges).map { index -> String in
                let matchRange = match.range(at: index)
                guard matchRange.location != NSNotFound,
                      let swiftRange = Range(matchRange, in: result)
                else {
                    return ""
                }
                return String(result[swiftRange])
            }

            let token = "@@SLACKFORMATTOKEN\(nextIndex)@@"
            nextIndex += 1
            placeholders[token] = transform(groups)
            result.replaceSubrange(range, with: token)
        }

        return result
    }

    private func replacing(
        in text: String,
        pattern: String,
        transform: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
        guard !matches.isEmpty else {
            return text
        }

        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let groups = (0..<match.numberOfRanges).map { index -> String in
                let matchRange = match.range(at: index)
                guard matchRange.location != NSNotFound,
                      let swiftRange = Range(matchRange, in: result)
                else {
                    return ""
                }
                return String(result[swiftRange])
            }
            result.replaceSubrange(range, with: transform(groups))
        }

        return result
    }

    private func firstMatch(_ text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)) else {
            return nil
        }

        return (0..<match.numberOfRanges).map { index -> String in
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else {
                return ""
            }
            return String(text[swiftRange])
        }
    }

    private func match(_ text: String, pattern: String, group: Int) -> String? {
        firstMatch(text, pattern: pattern).flatMap { matches in
            guard matches.indices.contains(group) else {
                return nil
            }
            return matches[group]
        }
    }

    private func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
    }

    private func convertSlackHTMLInline(_ html: String) -> String {
        html
            .replacingOccurrences(of: "<del>", with: "<s>")
            .replacingOccurrences(of: "</del>", with: "</s>")
    }

    private func renderedListMarkers(for items: [SlackListItem]) -> [String] {
        var orderedCounters: [Int: Int] = [:]

        return items.map { item in
            for depth in orderedCounters.keys where depth > item.indentLevel {
                orderedCounters.removeValue(forKey: depth)
            }

            switch item.marker {
            case .unordered(false):
                return "•"
            case .unordered(true):
                return "☐"
            case .unorderedCompleted:
                return "☑"
            case .ordered:
                let next = (orderedCounters[item.indentLevel] ?? 0) + 1
                orderedCounters[item.indentLevel] = next
                return "\(next)."
            }
        }
    }

    private func horizontalRuleText() -> String {
        "────────────────────"
    }

    private func blockSeparator(after block: SlackBlock) -> String {
        switch block {
        case .list:
            return "\n"
        default:
            return "\n\n"
        }
    }

    private func textyListKind(for marker: SlackListMarker) -> SlackTextyListKind {
        switch marker {
        case .ordered:
            return .ordered
        case .unordered, .unorderedCompleted:
            return .bullet
        }
    }

    private func semanticListKind(for marker: SlackListMarker) -> SlackHTMLListKind {
        switch marker {
        case .ordered:
            return .ordered
        case .unordered, .unorderedCompleted:
            return .unordered
        }
    }

    private func semanticListTextPrefix(for marker: SlackListMarker) -> String {
        switch marker {
        case .unorderedCompleted:
            return "☑ "
        case .unordered(let open):
            return open ? "☐ " : ""
        case .ordered:
            return ""
        }
    }

    private func makeTextList(
        for kind: SlackHTMLListKind,
        depth: Int
    ) -> NSTextList {
        switch kind {
        case .unordered:
            let marker: NSTextList.MarkerFormat
            switch depth % 3 {
            case 1:
                marker = .circle
            case 2:
                marker = .square
            default:
                marker = .disc
            }
            return NSTextList(markerFormat: marker, options: [], startingItemNumber: 1)
        case .ordered:
            let marker: NSTextList.MarkerFormat
            switch depth % 3 {
            case 1:
                marker = .lowercaseAlpha
            case 2:
                marker = .lowercaseRoman
            default:
                marker = .decimal
            }
            return NSTextList(markerFormat: marker, options: [], startingItemNumber: 1)
        }
    }

    private func buildHTMLListNodes(
        from items: [SlackListItem],
        startIndex: Int,
        indentLevel: Int
    ) -> ([SlackHTMLListNode], Int) {
        var nodes: [SlackHTMLListNode] = []
        var index = startIndex

        while index < items.count {
            let item = items[index]

            if item.indentLevel < indentLevel {
                break
            }

            if item.indentLevel > indentLevel {
                let nestedIndentLevel = item.indentLevel
                let (children, nextIndex) = buildHTMLListNodes(
                    from: items,
                    startIndex: index,
                    indentLevel: nestedIndentLevel
                )

                if var previous = nodes.popLast() {
                    previous.children.append(contentsOf: children)
                    nodes.append(previous)
                } else {
                    nodes.append(contentsOf: children)
                }

                index = nextIndex
                continue
            }

            var node = SlackHTMLListNode(item: item)
            index += 1

            if index < items.count, items[index].indentLevel > indentLevel {
                let (children, nextIndex) = buildHTMLListNodes(
                    from: items,
                    startIndex: index,
                    indentLevel: items[index].indentLevel
                )
                node.children = children
                index = nextIndex
            }

            nodes.append(node)
        }

        return (nodes, index)
    }

    private func renderHTMLListGroups(
        _ nodes: [SlackHTMLListNode],
        depth: Int
    ) -> String {
        var index = 0
        var fragments: [String] = []

        while index < nodes.count {
            let kind = htmlListKind(for: nodes[index].item.marker)
            var group: [SlackHTMLListNode] = []

            while index < nodes.count, htmlListKind(for: nodes[index].item.marker) == kind {
                group.append(nodes[index])
                index += 1
            }

            let body = group
                .map { renderHTMLListNode($0, depth: depth) }
                .joined()
            fragments.append(
                "<\(listTag(for: kind))\(listAttributes(for: kind, depth: depth))>\(body)</\(listTag(for: kind))>"
            )
        }

        return fragments.joined()
    }

    private func renderHTMLListNode(
        _ node: SlackHTMLListNode,
        depth: Int
    ) -> String {
        let prefix = htmlListItemPrefix(for: node.item.marker)
        let content = prefix + renderInlineHTML(node.item.content)
        let children = node.children.isEmpty
            ? ""
            : renderHTMLListGroups(node.children, depth: depth + 1)
        return "<li>\(content)\(children)</li>"
    }

    private func htmlListItemPrefix(for marker: SlackListMarker) -> String {
        switch marker {
        case .unorderedCompleted:
            return "☑ "
        case .unordered(let open):
            return open ? "☐ " : ""
        case .ordered:
            return ""
        }
    }

    private func htmlListKind(for marker: SlackListMarker) -> SlackHTMLListKind {
        switch marker {
        case .ordered:
            return .ordered
        case .unordered, .unorderedCompleted:
            return .unordered
        }
    }

    private func listTag(for kind: SlackHTMLListKind) -> String {
        switch kind {
        case .unordered:
            return "ul"
        case .ordered:
            return "ol"
        }
    }

    private func listAttributes(
        for kind: SlackHTMLListKind,
        depth: Int
    ) -> String {
        guard kind == .ordered else {
            return ""
        }

        switch depth % 3 {
        case 1:
            return " type=\"a\""
        case 2:
            return " type=\"i\""
        default:
            return ""
        }
    }

    private func makeHTMLDocument(_ body: String) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <style>
            body {
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
              font-size: 15px;
              line-height: 1.5;
              color: #1f2328;
            }

            p, pre, blockquote {
              margin: 0 0 1em;
            }

            ul, ol {
              margin: 0 0 0.8em;
              padding-left: 1.45em;
            }

            li {
              margin: 0.18em 0;
            }

            li > ul,
            li > ol {
              margin-top: 0.2em;
              margin-bottom: 0;
            }

            blockquote {
              margin-left: 0;
              padding-left: 0.9em;
              border-left: 3px solid #d0d7de;
              color: #57606a;
            }

            blockquote p:last-child,
            p:last-child {
              margin-bottom: 0;
            }

            .slack-list-item {
              margin-top: 0;
              margin-bottom: 0.35em;
            }

            .slack-list-block {
              margin: 0;
            }

            .slack-list-prefix {
              white-space: pre-wrap;
            }

            .slack-table-row {
              margin-bottom: 1em;
            }

            .slack-spacer {
              margin: 0;
            }

            .slack-rule {
              color: #57606a;
              letter-spacing: 0.04em;
            }

            a {
              color: #0969da;
              text-decoration: underline;
            }

            code {
              font-family: SFMono-Regular, ui-monospace, Menlo, monospace;
              font-size: 13px;
            }
          </style>
        </head>
        <body>
          \(body)
        </body>
        </html>
        """
    }

    private func htmlSpacer() -> String {
        "<p class=\"slack-spacer\"><br></p>"
    }

    private func makePlainAttributed(
        _ text: String,
        font: NSFont = .systemFont(ofSize: 15),
        color: NSColor = .labelColor
    ) -> NSAttributedString {
        NSAttributedString(string: text, attributes: baseAttributes(font: font, color: color))
    }

    private func baseAttributes(
        font: NSFont = .systemFont(ofSize: 15),
        color: NSColor = .labelColor
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: color
        ]
    }

    private func trimTrailingNewlines(from attributed: NSMutableAttributedString) {
        while attributed.string.hasSuffix("\n") {
            attributed.deleteCharacters(in: NSRange(location: attributed.length - 1, length: 1))
        }
    }

    private func applyDataDetectedLinks(to attributed: NSMutableAttributedString) {
        guard
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else {
            return
        }

        let range = NSRange(location: 0, length: attributed.length)
        detector.enumerateMatches(in: attributed.string, options: [], range: range) { match, _, _ in
            guard let match, let url = match.url else { return }
            attributed.addAttributes(
                [
                    .link: url,
                    .foregroundColor: NSColor.systemBlue,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                range: match.range
            )
        }
    }

    private func textyInlineAttributes(
        from attributes: [NSAttributedString.Key: Any]
    ) -> SlackTextyAttributes {
        var output = SlackTextyAttributes()

        if let font = attributes[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.bold) {
                output.bold = true
            }
            if traits.contains(.italic) {
                output.italic = true
            }
            if traits.contains(.monoSpace) || isMonospaced(font: font) {
                output.code = true
            }
        }

        if let strikethrough = (attributes[.strikethroughStyle] as? NSNumber)?.intValue,
           strikethrough != 0 {
            output.strike = true
        }

        if let link = attributes[.link] as? URL {
            output.link = link.absoluteString
        } else if let link = attributes[.link] as? String, !link.isEmpty {
            output.link = link
        }

        return output
    }

    private func isMonospaced(font: NSFont) -> Bool {
        [font.fontName, font.familyName ?? ""].contains { descriptor in
            let lowercase = descriptor.lowercased()
            return lowercase.contains("mono")
                || lowercase.contains("menlo")
                || lowercase.contains("monaco")
                || lowercase.contains("courier")
                || lowercase.contains("code")
        }
    }
}

private enum SlackBlock {
    case heading(String)
    case paragraph(String)
    case quote([String])
    case list([SlackListItem])
    case code([String])
    case horizontalRule
    case table([[(label: String, value: String)]])
}

private struct SlackHTMLListNode {
    let item: SlackListItem
    var children: [SlackHTMLListNode] = []
}

private struct SlackListItem {
    let indentLevel: Int
    let marker: SlackListMarker
    let content: String
}

private enum SlackListMarker {
    case unordered(Bool)
    case unorderedCompleted
    case ordered(String)
}

private enum SlackHTMLListKind: Equatable {
    case unordered
    case ordered
}

private enum SlackTextyListKind: String {
    case bullet
    case ordered
}

private struct SlackTextyDocument: Codable, Equatable {
    let ops: [SlackTextyOperation]
}

private struct SlackTextyOperation: Codable, Equatable {
    var insert: String
    var attributes: SlackTextyAttributes?
}

private struct SlackTextyAttributes: Codable, Equatable {
    var bold: Bool?
    var italic: Bool?
    var strike: Bool?
    var code: Bool?
    var blockquote: Bool?
    var codeBlock: Bool?
    var link: String?
    var list: String?
    var indent: Int?

    enum CodingKeys: String, CodingKey {
        case bold
        case italic
        case strike
        case code
        case blockquote
        case codeBlock = "code-block"
        case link
        case list
        case indent
    }

    var nonEmpty: SlackTextyAttributes? {
        isEmpty ? nil : self
    }

    func merged(with other: SlackTextyAttributes) -> SlackTextyAttributes {
        SlackTextyAttributes(
            bold: other.bold ?? bold,
            italic: other.italic ?? italic,
            strike: other.strike ?? strike,
            code: other.code ?? code,
            blockquote: other.blockquote ?? blockquote,
            codeBlock: other.codeBlock ?? codeBlock,
            link: other.link ?? link,
            list: other.list ?? list,
            indent: other.indent ?? indent
        )
    }

    private var isEmpty: Bool {
        bold == nil
            && italic == nil
            && strike == nil
            && code == nil
            && blockquote == nil
            && codeBlock == nil
            && link == nil
            && list == nil
            && indent == nil
    }
}

private struct SlackTextyBuilder {
    private(set) var ops: [SlackTextyOperation] = []

    mutating func append(
        _ text: String,
        attributes: SlackTextyAttributes? = nil
    ) {
        guard !text.isEmpty else {
            return
        }

        if let last = ops.last, last.attributes == attributes {
            ops[ops.count - 1].insert += text
            return
        }

        ops.append(SlackTextyOperation(insert: text, attributes: attributes))
    }
}

enum SlackTableRenderingMode: Equatable, Sendable {
    case readableRows
    case codeBlock

    var statusDescription: String {
        switch self {
        case .readableRows:
            return "for Slack with flattened tables"
        case .codeBlock:
            return "for Slack"
        }
    }
}
