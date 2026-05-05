import AppKit
import SwiftUI
import cmark_gfm
import cmark_gfm_extensions

struct TextKitPreviewView: NSViewRepresentable {
    let markdown: String
    let preferences: PreviewRenderingPreferences

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = NSTextStorage()
        let layoutManager = TextKitPreviewLayoutManager()
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )

        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = TextKitPreviewTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .white
        textView.previewPreferences = preferences
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.allowsUndo = false
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.usesRuler = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.linkTextAttributes = [
            .foregroundColor: TextKitMarkdownTheme.link,
            .underlineStyle: 0
        ]

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .white
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        if let textKitTextView = textView as? TextKitPreviewTextView {
            textKitTextView.previewPreferences = preferences
        }

        guard context.coordinator.lastMarkdown != markdown ||
              context.coordinator.lastPreferences != preferences
        else {
            return
        }

        context.coordinator.lastMarkdown = markdown
        context.coordinator.lastPreferences = preferences
        let selectedRange = textView.selectedRange()
        textView.textStorage?.setAttributedString(context.coordinator.renderer.render(markdown: markdown))

        if selectedRange.location <= textView.string.utf16.count {
            textView.setSelectedRange(NSRange(location: selectedRange.location, length: 0))
        }
    }

    final class Coordinator {
        var lastMarkdown = ""
        var lastPreferences: PreviewRenderingPreferences?
        fileprivate let renderer = TextKitMarkdownRenderer()
    }
}

private final class TextKitPreviewTextView: NSTextView {
    var previewPreferences = PreviewRenderingPreferences.standard {
        didSet {
            updateDocumentInsets()
        }
    }

    override var isFlipped: Bool {
        true
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateDocumentInsets()
    }

    override func layout() {
        super.layout()
        updateDocumentInsets()
    }

    private func updateDocumentInsets() {
        let availableWidth = enclosingScrollView?.contentSize.width ?? bounds.width
        guard availableWidth > 0 else {
            return
        }

        let nextInset = TextKitMarkdownTheme.documentInset(
            availableWidth: availableWidth,
            preferences: previewPreferences
        )
        guard abs(textContainerInset.width - nextInset.width) > 0.5 ||
              abs(textContainerInset.height - nextInset.height) > 0.5
        else {
            return
        }

        textContainerInset = nextInset
    }
}

private final class TextKitPreviewLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawBlockBackgrounds(
            for: glyphsToShow,
            at: origin,
            attribute: .leafletCodeBlock,
            color: TextKitMarkdownTheme.codeBlockBackground,
            cornerRadius: 6,
            verticalOutset: 8
        )
        drawTableRows(for: glyphsToShow, at: origin)
        drawBlockQuoteBorders(for: glyphsToShow, at: origin)
        drawRuleRows(for: glyphsToShow, at: origin)
        drawInlineCodeBackgrounds(for: glyphsToShow, at: origin)
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawInlineCodeBackgrounds(for glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textStorage else {
            return
        }

        let characterRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        textStorage.enumerateAttribute(.leafletInlineCode, in: characterRange) { value, range, _ in
            guard value != nil else {
                return
            }

            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            self.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, textContainer, lineGlyphRange, _ in
                let intersection = NSIntersectionRange(glyphRange, lineGlyphRange)
                guard intersection.length > 0 else {
                    return
                }

                var rect = self.boundingRect(forGlyphRange: intersection, in: textContainer)
                rect = rect.offsetBy(dx: origin.x, dy: origin.y)
                rect = rect.insetBy(dx: -4, dy: -2)
                TextKitMarkdownTheme.inlineCodeBackground.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            }
        }
    }

    private func drawBlockBackgrounds(
        for glyphsToShow: NSRange,
        at origin: NSPoint,
        attribute: NSAttributedString.Key,
        color: NSColor,
        cornerRadius: CGFloat,
        verticalOutset: CGFloat
    ) {
        guard let textStorage else {
            return
        }

        let characterRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        textStorage.enumerateAttribute(attribute, in: characterRange) { value, range, _ in
            guard value != nil,
                  let textContainer = self.textContainers.first
            else {
                return
            }

            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var unionRect: NSRect?

            self.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, lineGlyphRange, _ in
                let intersection = NSIntersectionRange(glyphRange, lineGlyphRange)
                guard intersection.length > 0 else {
                    return
                }

                let rect = NSRect(
                    x: origin.x,
                    y: origin.y + lineRect.minY - verticalOutset,
                    width: textContainer.containerSize.width,
                    height: lineRect.height + verticalOutset * 2
                )

                unionRect = unionRect.map { $0.union(rect) } ?? rect
            }

            guard let rect = unionRect else {
                return
            }

            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        }
    }

    private func drawBlockQuoteBorders(for glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textStorage else {
            return
        }

        let characterRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        textStorage.enumerateAttribute(.leafletBlockQuoteDepth, in: characterRange) { value, range, _ in
            guard let depth = value as? Int, depth > 0 else {
                return
            }

            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var unionRect: NSRect?

            self.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, lineGlyphRange, _ in
                let intersection = NSIntersectionRange(glyphRange, lineGlyphRange)
                guard intersection.length > 0 else {
                    return
                }

                let rect = NSRect(
                    x: origin.x + CGFloat(depth - 1) * TextKitMarkdownTheme.quoteIndent,
                    y: origin.y + lineRect.minY + 1,
                    width: 4,
                    height: lineRect.height
                )

                unionRect = unionRect.map { $0.union(rect) } ?? rect
            }

            guard let rect = unionRect?.insetBy(dx: 0, dy: -2) else {
                return
            }

            TextKitMarkdownTheme.border.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    private func drawTableRows(for glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textStorage else {
            return
        }

        let characterRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        textStorage.enumerateAttribute(.leafletTableRowLayout, in: characterRange) { value, range, _ in
            guard let layout = value as? TextKitTableRowLayout else {
                return
            }

            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            self.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, lineGlyphRange, _ in
                let intersection = NSIntersectionRange(glyphRange, lineGlyphRange)
                guard intersection.length > 0 else {
                    return
                }

                let rect = NSRect(
                    x: origin.x + layout.leftInset,
                    y: origin.y + lineRect.minY,
                    width: layout.totalWidth,
                    height: lineRect.height
                )

                if self.isRowSelected(range: range) {
                    TextKitMarkdownTheme.selectionFill.setFill()
                    NSBezierPath(rect: rect).fill()
                } else if let fillColor = layout.fillColor {
                    fillColor.setFill()
                    NSBezierPath(rect: rect).fill()
                }

                TextKitMarkdownTheme.border.setStroke()
                let border = NSBezierPath()
                border.lineWidth = 0.5
                if layout.isFirstRow {
                    border.move(to: NSPoint(x: rect.minX, y: rect.minY))
                    border.line(to: NSPoint(x: rect.maxX, y: rect.minY))
                }
                border.move(to: NSPoint(x: rect.minX, y: rect.minY))
                border.line(to: NSPoint(x: rect.minX, y: rect.maxY))
                border.move(to: NSPoint(x: rect.maxX, y: rect.minY))
                border.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
                border.move(to: NSPoint(x: rect.minX, y: rect.maxY))
                border.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
                border.stroke()

                var columnX = rect.minX
                layout.columnWidths.dropLast().forEach { width in
                    columnX += width
                    let divider = NSBezierPath()
                    divider.move(to: NSPoint(x: columnX, y: rect.minY))
                    divider.line(to: NSPoint(x: columnX, y: rect.maxY))
                    divider.lineWidth = 0.5
                    divider.stroke()
                }
            }
        }
    }

    private func isRowSelected(range: NSRange) -> Bool {
        guard let textView = firstTextView else {
            return false
        }

        return textView.selectedRanges.contains { selectedRange in
            NSIntersectionRange(selectedRange.rangeValue, range).length > 0
        }
    }

    private func drawRuleRows(for glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textStorage,
              let textContainer = textContainers.first
        else {
            return
        }

        let characterRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        textStorage.enumerateAttribute(.leafletRuleLayout, in: characterRange) { value, range, _ in
            guard let layout = value as? TextKitRuleLayout else {
                return
            }

            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            self.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, lineGlyphRange, _ in
                let intersection = NSIntersectionRange(glyphRange, lineGlyphRange)
                guard intersection.length > 0 else {
                    return
                }

                let quoteOffset = CGFloat(layout.quoteDepth) * TextKitMarkdownTheme.quoteIndent
                let y = origin.y + lineRect.midY - layout.thickness / 2
                let rect = NSRect(
                    x: origin.x + quoteOffset,
                    y: y,
                    width: max(0, textContainer.containerSize.width - quoteOffset),
                    height: layout.thickness
                )

                layout.color.setFill()
                NSBezierPath(rect: rect).fill()
            }
        }
    }
}

private struct TextKitMarkdownRenderer {
    func render(markdown: String) -> NSAttributedString {
        do {
            return try renderParsed(markdown: markdown)
        } catch {
            return NSAttributedString(
                string: markdown,
                attributes: TextKitMarkdownTheme.baseAttributes
            )
        }
    }

    private func renderParsed(markdown: String) throws -> NSAttributedString {
        cmark_gfm_core_extensions_ensure_registered()

        let options = CInt(CMARK_OPT_FOOTNOTES | CMARK_OPT_STRIKETHROUGH_DOUBLE_TILDE | CMARK_OPT_GITHUB_PRE_LANG)
        guard let parser = cmark_parser_new(options) else {
            throw TextKitMarkdownRendererError.parserCreationFailed
        }
        defer { cmark_parser_free(parser) }

        for extensionName in ["table", "strikethrough", "autolink", "tagfilter", "tasklist"] {
            let attached = extensionName.withCString { pointer in
                guard let syntaxExtension = cmark_find_syntax_extension(pointer) else {
                    return false
                }

                return cmark_parser_attach_syntax_extension(parser, syntaxExtension) == 1
            }

            if !attached {
                throw TextKitMarkdownRendererError.extensionAttachmentFailed(extensionName)
            }
        }

        let utf8Bytes = Array(markdown.utf8)
        utf8Bytes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            cmark_parser_feed(parser, UnsafeRawPointer(baseAddress).assumingMemoryBound(to: CChar.self), buffer.count)
        }

        guard let document = cmark_parser_finish(parser) else {
            throw TextKitMarkdownRendererError.renderFailed
        }
        defer { cmark_node_free(document) }

        let output = NSMutableAttributedString()
        renderChildren(of: document, into: output, context: .root)
        trimTrailingWhitespace(in: output)
        return output
    }

    private func renderChildren(
        of node: UnsafeMutablePointer<cmark_node>,
        into output: NSMutableAttributedString,
        context: TextKitRenderContext
    ) {
        var child = cmark_node_first_child(node)
        while let current = child {
            renderBlock(current, into: output, context: context)
            child = cmark_node_next(current)
        }
    }

    private func renderBlock(
        _ node: UnsafeMutablePointer<cmark_node>,
        into output: NSMutableAttributedString,
        context: TextKitRenderContext
    ) {
        switch cmark_node_get_type(node) {
        case CMARK_NODE_HEADING:
            renderHeading(node, into: output, context: context)
        case CMARK_NODE_PARAGRAPH:
            renderParagraph(node, into: output, context: context)
        case CMARK_NODE_LIST:
            renderList(node, into: output, context: context)
        case CMARK_NODE_BLOCK_QUOTE:
            renderBlockQuote(node, into: output, context: context)
        case CMARK_NODE_CODE_BLOCK:
            renderCodeBlock(node, into: output, context: context)
        case CMARK_NODE_THEMATIC_BREAK:
            renderRule(into: output, context: context)
        case CMARK_NODE_HTML_BLOCK:
            renderHTMLBlock(node, into: output, context: context)
        default:
            switch typeString(for: node) {
            case "table":
                renderTable(node, into: output, context: context)
            default:
                renderChildren(of: node, into: output, context: context)
            }
        }
    }

    private func renderHeading(
        _ node: UnsafeMutablePointer<cmark_node>,
        into output: NSMutableAttributedString,
        context: TextKitRenderContext
    ) {
        appendBlockSpacingIfNeeded(to: output)
        let start = output.length
        let level = max(1, min(6, Int(cmark_node_get_heading_level(node))))
        var inlineContext = context
        inlineContext.baseFont = TextKitMarkdownTheme.headingFont(level: level)
        renderInlineChildren(of: node, into: output, context: inlineContext)
        output.append("\n", attributes: inlineContext.attributes)
        output.addAttribute(
            .paragraphStyle,
            value: TextKitMarkdownTheme.headingParagraphStyle(level: level, quoteDepth: context.quoteDepth),
            range: NSRange(location: start, length: output.length - start)
        )

        if level <= 2 {
            appendRule(into: output, context: context, kind: .heading)
        }
    }

    private func renderParagraph(
        _ node: UnsafeMutablePointer<cmark_node>,
        into output: NSMutableAttributedString,
        context: TextKitRenderContext
    ) {
        appendBlockSpacingIfNeeded(to: output)
        let start = output.length
        renderInlineChildren(of: node, into: output, context: context)
        output.append("\n", attributes: context.attributes)
        output.addAttributes(
            paragraphAttributes(
                style: TextKitMarkdownTheme.bodyParagraphStyle(quoteDepth: context.quoteDepth),
                context: context
            ),
            range: NSRange(location: start, length: output.length - start)
        )
    }

    private func renderList(
        _ node: UnsafeMutablePointer<cmark_node>,
        into output: NSMutableAttributedString,
        context: TextKitRenderContext
    ) {
        appendBlockSpacingIfNeeded(to: output)

        let listType = cmark_node_get_list_type(node)
        var index = max(1, Int(cmark_node_get_list_start(node)))
        var item = cmark_node_first_child(node)
        while let currentItem = item {
            let marker = listType == CMARK_ORDERED_LIST
                ? orderedMarker(index: index, level: context.listLevel)
                : bulletMarker(level: context.listLevel)
            renderListItem(
                currentItem,
                marker: marker,
                into: output,
                context: context
            )
            index += 1
            item = cmark_node_next(currentItem)
        }

        if context.listLevel == 0 {
            appendSpacer(into: output, height: 13, context: context)
        }
    }

    private func renderListItem(
        _ node: UnsafeMutablePointer<cmark_node>,
        marker: String,
        into output: NSMutableAttributedString,
        context: TextKitRenderContext
    ) {
        var child = cmark_node_first_child(node)
        let taskMarker = taskListMarker(in: node)
        var didRenderFirstParagraph = false

        while let current = child {
            defer { child = cmark_node_next(current) }

            if typeString(for: current) == "tasklist" {
                continue
            }

            if cmark_node_get_type(current) == CMARK_NODE_PARAGRAPH, !didRenderFirstParagraph {
                let start = output.length
                var itemContext = context
                itemContext.listLevel += 1
                let displayedMarker = taskMarker ?? marker
                output.append(displayedMarker + "\t", attributes: itemContext.attributes)
                renderInlineChildren(of: current, into: output, context: itemContext)
                output.append("\n", attributes: itemContext.attributes)
                output.addAttributes(
                    paragraphAttributes(
                        style: TextKitMarkdownTheme.listParagraphStyle(
                            level: context.listLevel,
                            quoteDepth: context.quoteDepth
                        ),
                        context: itemContext
                    ),
                    range: NSRange(location: start, length: output.length - start)
                )
                didRenderFirstParagraph = true
            } else if cmark_node_get_type(current) == CMARK_NODE_LIST {
                var nestedContext = context
                nestedContext.listLevel += 1
                renderList(current, into: output, context: nestedContext)
            } else {
                renderBlock(current, into: output, context: context)
            }
        }
    }

    private func renderBlockQuote(
        _ node: UnsafeMutablePointer<cmark_node>,
        into output: NSMutableAttributedString,
        context: TextKitRenderContext
    ) {
        appendBlockSpacingIfNeeded(to: output)
        var quoteContext = context
        quoteContext.quoteDepth += 1
        quoteContext.color = TextKitMarkdownTheme.muted
        renderChildren(of: node, into: output, context: quoteContext)
    }

    private func renderCodeBlock(
        _ node: UnsafeMutablePointer<cmark_node>,
        into output: NSMutableAttributedString,
        context: TextKitRenderContext
    ) {
        appendBlockSpacingIfNeeded(to: output)
        let start = output.length
        let literal = literalString(for: node).trimmingCharacters(in: CharacterSet.newlines)
        output.append(literal + "\n", attributes: TextKitMarkdownTheme.codeBlockAttributes)
        output.addAttribute(
            .paragraphStyle,
            value: TextKitMarkdownTheme.codeBlockParagraphStyle(quoteDepth: context.quoteDepth),
            range: NSRange(location: start, length: output.length - start)
        )
        output.addAttribute(
            .leafletCodeBlock,
            value: true,
            range: NSRange(location: start, length: output.length - start)
        )
        appendSpacer(into: output, height: 8, context: context)
    }

    private func renderRule(into output: NSMutableAttributedString, context: TextKitRenderContext) {
        appendBlockSpacingIfNeeded(to: output)
        appendRule(into: output, context: context, kind: .thematic)
    }

    private func appendRule(
        into output: NSMutableAttributedString,
        context: TextKitRenderContext,
        kind: TextKitRuleKind
    ) {
        let start = output.length
        output.append("\u{200B}\n", attributes: context.attributes)
        output.addAttributes(
            [
                .paragraphStyle: TextKitMarkdownTheme.ruleParagraphStyle(
                    kind: kind,
                    quoteDepth: context.quoteDepth
                ),
                .leafletRuleLayout: TextKitRuleLayout(kind: kind, quoteDepth: context.quoteDepth)
            ],
            range: NSRange(location: start, length: output.length - start)
        )
    }

    private func renderHTMLBlock(
        _ node: UnsafeMutablePointer<cmark_node>,
        into output: NSMutableAttributedString,
        context: TextKitRenderContext
    ) {
        appendBlockSpacingIfNeeded(to: output)
        let start = output.length
        output.append(literalString(for: node).trimmingCharacters(in: .newlines) + "\n", attributes: context.attributes)
        output.addAttribute(
            .paragraphStyle,
            value: TextKitMarkdownTheme.bodyParagraphStyle(quoteDepth: context.quoteDepth),
            range: NSRange(location: start, length: output.length - start)
        )
    }

    private func renderTable(
        _ node: UnsafeMutablePointer<cmark_node>,
        into output: NSMutableAttributedString,
        context: TextKitRenderContext
    ) {
        appendBlockSpacingIfNeeded(to: output)

        let rows = tableRows(in: node)
        guard !rows.isEmpty else {
            return
        }

        let columnCount = rows.map(\.count).max() ?? 0
        let widths = tableColumnWidths(rows: rows, columnCount: columnCount)
        let alignments = tableAlignments(in: node, columnCount: columnCount)

        for (rowIndex, row) in rows.enumerated() {
            let start = output.length
            let cells = (0..<columnCount).map { column in
                column < row.count ? row[column] : ""
            }
            let isHeader = rowIndex == 0
            let usesLeadingTab = isHeader || alignments.first != .left
            let line = usesLeadingTab ? "\t" + cells.joined(separator: "\t") : cells.joined(separator: "\t")
            let isLastRow = rowIndex == rows.count - 1

            var attributes = TextKitMarkdownTheme.tableAttributes
            if isHeader {
                attributes[.font] = TextKitMarkdownTheme.tableHeaderFont
            }

            output.append(line + "\n", attributes: attributes)
            output.addAttribute(
                .paragraphStyle,
                value: TextKitMarkdownTheme.tableParagraphStyle(
                    columnWidths: widths,
                    alignments: alignments,
                    quoteDepth: context.quoteDepth,
                    isHeader: isHeader,
                    usesLeadingTab: usesLeadingTab,
                    isLastRow: isLastRow
                ),
                range: NSRange(location: start, length: output.length - start)
            )
            output.addAttribute(
                .leafletTableRowLayout,
                value: TextKitTableRowLayout(
                    columnWidths: widths,
                    rowIndex: rowIndex,
                    rowCount: rows.count,
                    isHeader: isHeader,
                    quoteDepth: context.quoteDepth
                ),
                range: NSRange(location: start, length: output.length - start)
            )
        }
    }

    private func tableColumnWidths(rows: [[String]], columnCount: Int) -> [CGFloat] {
        return (0..<columnCount).map { column in
            let measured = rows.enumerated().map { rowIndex, row -> CGFloat in
                let cell = column < row.count ? row[column] : ""
                let font = rowIndex == 0 ? TextKitMarkdownTheme.tableHeaderFont : TextKitMarkdownTheme.bodyFont
                return (cell as NSString).size(withAttributes: [.font: font]).width
            }.max() ?? 0

            let minimumWidth: CGFloat = column == 2 ? 96 : 118
            let maximumWidth: CGFloat = column == columnCount - 1 ? 560 : 320
            return min(maximumWidth, max(minimumWidth, ceil(measured) + TextKitMarkdownTheme.tableCellHorizontalPadding * 2))
        }
    }

    private func tableAlignments(
        in table: UnsafeMutablePointer<cmark_node>,
        columnCount: Int
    ) -> [TextKitTableAlignment] {
        guard columnCount > 0,
              let pointer = cmark_gfm_extensions_get_table_alignments(table)
        else {
            return Array(repeating: .left, count: columnCount)
        }

        return (0..<columnCount).map { column in
            switch pointer[column] {
            case 99: // c
                return .center
            case 114: // r
                return .right
            default:
                return .left
            }
        }
    }

    private func renderInlineChildren(
        of node: UnsafeMutablePointer<cmark_node>,
        into output: NSMutableAttributedString,
        context: TextKitRenderContext
    ) {
        var child = cmark_node_first_child(node)
        while let current = child {
            renderInline(current, into: output, context: context)
            child = cmark_node_next(current)
        }
    }

    private func renderInline(
        _ node: UnsafeMutablePointer<cmark_node>,
        into output: NSMutableAttributedString,
        context: TextKitRenderContext
    ) {
        switch cmark_node_get_type(node) {
        case CMARK_NODE_TEXT:
            output.append(literalString(for: node), attributes: context.attributes)
        case CMARK_NODE_SOFTBREAK:
            output.append(" ", attributes: context.attributes)
        case CMARK_NODE_LINEBREAK:
            output.append("\n", attributes: context.attributes)
        case CMARK_NODE_CODE:
            var attributes = TextKitMarkdownTheme.inlineCodeAttributes
            if context.quoteDepth > 0 {
                attributes[.leafletBlockQuoteDepth] = context.quoteDepth
            }
            output.append(literalString(for: node), attributes: attributes)
        case CMARK_NODE_EMPH:
            var nextContext = context
            nextContext.isItalic = true
            renderInlineChildren(of: node, into: output, context: nextContext)
        case CMARK_NODE_STRONG:
            var nextContext = context
            nextContext.isBold = true
            renderInlineChildren(of: node, into: output, context: nextContext)
        case CMARK_NODE_LINK:
            var nextContext = context
            nextContext.linkURL = urlString(for: node)
            renderInlineChildren(of: node, into: output, context: nextContext)
        case CMARK_NODE_IMAGE:
            output.append("[Image]", attributes: context.attributes)
        case CMARK_NODE_HTML_INLINE:
            output.append(literalString(for: node), attributes: context.attributes)
        default:
            if typeString(for: node) == "strikethrough" {
                var nextContext = context
                nextContext.isStruckThrough = true
                renderInlineChildren(of: node, into: output, context: nextContext)
            } else {
                renderInlineChildren(of: node, into: output, context: context)
            }
        }
    }

    private func tableRows(in table: UnsafeMutablePointer<cmark_node>) -> [[String]] {
        var rows: [[String]] = []
        var row = cmark_node_first_child(table)
        while let currentRow = row {
            var cells: [String] = []
            var cell = cmark_node_first_child(currentRow)
            while let currentCell = cell {
                cells.append(plainText(in: currentCell).trimmingCharacters(in: .whitespacesAndNewlines))
                cell = cmark_node_next(currentCell)
            }

            rows.append(cells)
            row = cmark_node_next(currentRow)
        }
        return rows
    }

    private func plainText(in node: UnsafeMutablePointer<cmark_node>) -> String {
        switch cmark_node_get_type(node) {
        case CMARK_NODE_TEXT, CMARK_NODE_CODE:
            return literalString(for: node)
        case CMARK_NODE_SOFTBREAK, CMARK_NODE_LINEBREAK:
            return " "
        default:
            var result = ""
            var child = cmark_node_first_child(node)
            while let current = child {
                result += plainText(in: current)
                child = cmark_node_next(current)
            }
            return result
        }
    }

    private func taskListMarker(in item: UnsafeMutablePointer<cmark_node>) -> String? {
        var child = cmark_node_first_child(item)
        while let current = child {
            if typeString(for: current) == "tasklist" {
                return cmark_gfm_extensions_get_tasklist_item_checked(current) ? "[x]" : "[ ]"
            }
            child = cmark_node_next(current)
        }
        return nil
    }

    private func paragraphAttributes(
        style: NSParagraphStyle,
        context: TextKitRenderContext
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: style]
        if context.quoteDepth > 0 {
            attributes[.leafletBlockQuoteDepth] = context.quoteDepth
        }
        return attributes
    }

    private func appendBlockSpacingIfNeeded(to output: NSMutableAttributedString) {
        guard output.length > 0, !output.string.hasSuffix("\n") else {
            return
        }

        output.append("\n", attributes: TextKitMarkdownTheme.baseAttributes)
    }

    private func appendSpacer(
        into output: NSMutableAttributedString,
        height: CGFloat,
        context: TextKitRenderContext
    ) {
        let start = output.length
        output.append("\u{200B}\n", attributes: context.attributes)
        output.addAttribute(
            .paragraphStyle,
            value: TextKitMarkdownTheme.spacerParagraphStyle(height: height, quoteDepth: context.quoteDepth),
            range: NSRange(location: start, length: output.length - start)
        )
    }

    private func trimTrailingWhitespace(in output: NSMutableAttributedString) {
        while output.length > 0,
              let lastScalar = output.string.unicodeScalars.last,
              CharacterSet.whitespacesAndNewlines.contains(lastScalar) || lastScalar == "\u{200B}" {
            output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1))
        }
    }

    private func bulletMarker(level: Int) -> String {
        ["\u{2022}", "\u{25E6}", "\u{25AA}"][level % 3]
    }

    private func orderedMarker(index: Int, level: Int) -> String {
        switch level % 3 {
        case 1:
            return romanNumeral(index).lowercased() + "."
        case 2:
            return alphabeticMarker(index) + "."
        default:
            return "\(index)."
        }
    }

    private func alphabeticMarker(_ index: Int) -> String {
        let scalar = UnicodeScalar(97 + ((max(1, index) - 1) % 26)) ?? "a"
        return String(scalar)
    }

    private func romanNumeral(_ number: Int) -> String {
        let numerals: [(Int, String)] = [
            (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")
        ]
        var value = max(1, min(39, number))
        var result = ""
        for (amount, numeral) in numerals {
            while value >= amount {
                result += numeral
                value -= amount
            }
        }
        return result
    }

    private func literalString(for node: UnsafeMutablePointer<cmark_node>) -> String {
        guard let pointer = cmark_node_get_literal(node) else {
            return ""
        }
        return String(cString: pointer)
    }

    private func urlString(for node: UnsafeMutablePointer<cmark_node>) -> String? {
        guard let pointer = cmark_node_get_url(node) else {
            return nil
        }
        let url = String(cString: pointer)
        return url.isEmpty ? nil : url
    }

    private func typeString(for node: UnsafeMutablePointer<cmark_node>) -> String {
        guard let pointer = cmark_node_get_type_string(node) else {
            return ""
        }
        return String(cString: pointer)
    }
}

private struct TextKitRenderContext {
    var baseFont = TextKitMarkdownTheme.bodyFont
    var color = TextKitMarkdownTheme.text
    var isBold = false
    var isItalic = false
    var isStruckThrough = false
    var linkURL: String?
    var listLevel = 0
    var quoteDepth = 0

    static let root = TextKitRenderContext()

    var attributes: [NSAttributedString.Key: Any] {
        var result: [NSAttributedString.Key: Any] = [
            .font: TextKitMarkdownTheme.font(baseFont, bold: isBold, italic: isItalic),
            .foregroundColor: linkURL == nil ? color : TextKitMarkdownTheme.link
        ]

        if isStruckThrough {
            result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }

        if let linkURL {
            result[.link] = linkURL
            result[.underlineStyle] = 0
        }

        if quoteDepth > 0 {
            result[.leafletBlockQuoteDepth] = quoteDepth
        }

        return result
    }
}

private final class TextKitTableRowLayout: NSObject {
    let columnWidths: [CGFloat]
    let rowIndex: Int
    let rowCount: Int
    let isHeader: Bool
    let quoteDepth: Int

    init(columnWidths: [CGFloat], rowIndex: Int, rowCount: Int, isHeader: Bool, quoteDepth: Int) {
        self.columnWidths = columnWidths
        self.rowIndex = rowIndex
        self.rowCount = rowCount
        self.isHeader = isHeader
        self.quoteDepth = quoteDepth
    }

    var leftInset: CGFloat {
        CGFloat(quoteDepth) * 20
    }

    var totalWidth: CGFloat {
        columnWidths.reduce(0, +)
    }

    var fillColor: NSColor? {
        if isHeader {
            return TextKitMarkdownTheme.tableHeaderBackground
        }

        return rowIndex.isMultiple(of: 2) ? TextKitMarkdownTheme.tableAlternateBackground : nil
    }

    var isFirstRow: Bool {
        rowIndex == 0
    }
}

private final class TextKitRuleLayout: NSObject {
    let kind: TextKitRuleKind
    let quoteDepth: Int

    init(kind: TextKitRuleKind, quoteDepth: Int) {
        self.kind = kind
        self.quoteDepth = quoteDepth
    }

    var thickness: CGFloat {
        switch kind {
        case .heading:
            return 0.5
        case .thematic:
            return 4
        }
    }

    var color: NSColor {
        TextKitMarkdownTheme.border
    }
}

private enum TextKitRuleKind {
    case heading
    case thematic
}

private enum TextKitTableAlignment {
    case left
    case center
    case right
}

private enum TextKitMarkdownRendererError: Error {
    case parserCreationFailed
    case extensionAttachmentFailed(String)
    case renderFailed
}

private enum TextKitMarkdownTheme {
    static let maximumDocumentWidth: CGFloat = 980
    static let quoteIndent: CGFloat = 20
    static let text = NSColor(calibratedRed: 31 / 255, green: 35 / 255, blue: 40 / 255, alpha: 1)
    static let muted = NSColor(calibratedRed: 101 / 255, green: 109 / 255, blue: 118 / 255, alpha: 1)
    static let link = NSColor(calibratedRed: 9 / 255, green: 105 / 255, blue: 218 / 255, alpha: 1)
    static let border = NSColor(calibratedRed: 208 / 255, green: 215 / 255, blue: 222 / 255, alpha: 1)
    static let inlineCodeBackground = NSColor(calibratedRed: 239 / 255, green: 241 / 255, blue: 243 / 255, alpha: 1)
    static let codeBlockBackground = NSColor(calibratedRed: 246 / 255, green: 248 / 255, blue: 250 / 255, alpha: 1)
    static let tableHeaderBackground = NSColor(calibratedRed: 246 / 255, green: 248 / 255, blue: 250 / 255, alpha: 1)
    static let tableAlternateBackground = NSColor(calibratedRed: 246 / 255, green: 248 / 255, blue: 250 / 255, alpha: 0.78)
    static let selectionFill = NSColor.selectedTextBackgroundColor

    static let bodyFont = NSFont.systemFont(ofSize: 16, weight: .regular)
    static let codeFont = NSFont.monospacedSystemFont(ofSize: 13.6, weight: .regular)
    static let tableHeaderFont = NSFont.systemFont(ofSize: 16, weight: .semibold)
    static let tableCellHorizontalPadding: CGFloat = 13

    static func documentInset(
        availableWidth: CGFloat,
        preferences: PreviewRenderingPreferences
    ) -> NSSize {
        let padding = preferences.marginPreset.textKitPadding(for: availableWidth)
        let horizontalInset: CGFloat
        if preferences.allowWideContent {
            horizontalInset = padding
        } else {
            let bodyWidth = min(availableWidth, maximumDocumentWidth)
            horizontalInset = max(0, (availableWidth - bodyWidth) / 2) + padding
        }

        return NSSize(width: horizontalInset, height: padding)
    }

    static let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: bodyFont,
        .foregroundColor: text,
        .paragraphStyle: bodyParagraphStyle(quoteDepth: 0)
    ]

    static let inlineCodeAttributes: [NSAttributedString.Key: Any] = [
        .font: codeFont,
        .foregroundColor: text,
        .leafletInlineCode: true
    ]

    static let codeBlockAttributes: [NSAttributedString.Key: Any] = [
        .font: codeFont,
        .foregroundColor: text
    ]

    static let tableAttributes: [NSAttributedString.Key: Any] = [
        .font: bodyFont,
        .foregroundColor: text
    ]

    static func font(_ baseFont: NSFont, bold: Bool, italic: Bool) -> NSFont {
        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold {
            traits.insert(.bold)
        }
        if italic {
            traits.insert(.italic)
        }

        guard !traits.isEmpty else {
            return baseFont
        }

        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont
    }

    static func headingFont(level: Int) -> NSFont {
        let size: CGFloat
        switch level {
        case 1:
            size = 32
        case 2:
            size = 24
        case 3:
            size = 20
        case 4:
            size = 16
        case 5:
            size = 14
        default:
            size = 13.6
        }
        return NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    static func bodyParagraphStyle(quoteDepth: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 24
        style.maximumLineHeight = 24
        style.paragraphSpacing = 16
        let quoteOffset = CGFloat(quoteDepth) * quoteIndent
        style.headIndent = quoteOffset
        style.firstLineHeadIndent = quoteOffset
        return style
    }

    static func headingParagraphStyle(level: Int, quoteDepth: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let lineHeight: CGFloat
        switch level {
        case 1:
            lineHeight = 40
        case 2:
            lineHeight = 30
        case 3:
            lineHeight = 25
        default:
            lineHeight = 22
        }
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.paragraphSpacingBefore = level == 1 ? 0 : 8
        style.paragraphSpacing = level <= 2 ? 4 : 16
        style.headIndent = CGFloat(quoteDepth) * quoteIndent
        style.firstLineHeadIndent = CGFloat(quoteDepth) * quoteIndent
        return style
    }

    static func listParagraphStyle(level: Int, quoteDepth: Int) -> NSParagraphStyle {
        let quoteOffset = CGFloat(quoteDepth) * quoteIndent
        let markerOffset = quoteOffset + CGFloat(level) * 28
        let contentOffset = markerOffset + 30
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 24
        style.maximumLineHeight = 24
        style.paragraphSpacing = 3
        style.firstLineHeadIndent = markerOffset
        style.headIndent = contentOffset
        style.tabStops = [NSTextTab(textAlignment: .left, location: contentOffset)]
        return style
    }

    static func codeBlockParagraphStyle(quoteDepth: Int) -> NSParagraphStyle {
        let quoteOffset = CGFloat(quoteDepth) * quoteIndent
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 18
        style.maximumLineHeight = 18
        style.paragraphSpacingBefore = 8
        style.paragraphSpacing = 0
        style.firstLineHeadIndent = quoteOffset + 16
        style.headIndent = quoteOffset + 16
        style.tailIndent = -16
        return style
    }

    static func tableParagraphStyle(
        columnWidths: [CGFloat],
        alignments: [TextKitTableAlignment],
        quoteDepth: Int,
        isHeader: Bool,
        usesLeadingTab: Bool,
        isLastRow: Bool
    ) -> NSParagraphStyle {
        let quoteOffset = CGFloat(quoteDepth) * quoteIndent
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 34
        style.maximumLineHeight = 34
        style.paragraphSpacing = isLastRow ? 14 : 0
        if usesLeadingTab {
            style.firstLineHeadIndent = quoteOffset
            style.headIndent = quoteOffset
            var columnStart = quoteOffset
            style.tabStops = columnWidths.enumerated().map { index, width in
                let tab = tableTab(
                    for: isHeader ? .center : alignments[safe: index] ?? .left,
                    columnStart: columnStart,
                    width: width
                )
                columnStart += width
                return tab
            }
        } else {
            style.firstLineHeadIndent = quoteOffset + tableCellHorizontalPadding
            style.headIndent = quoteOffset + tableCellHorizontalPadding
            var columnStart = quoteOffset
            style.tabStops = columnWidths.dropLast().enumerated().map { index, width in
                columnStart += width
                return tableTab(
                    for: alignments[safe: index + 1] ?? .left,
                    columnStart: columnStart,
                    width: columnWidths[safe: index + 1] ?? width
                )
            }
        }
        return style
    }

    static func tableTab(
        for alignment: TextKitTableAlignment,
        columnStart: CGFloat,
        width: CGFloat
    ) -> NSTextTab {
        switch alignment {
        case .left:
            return NSTextTab(textAlignment: .left, location: columnStart + tableCellHorizontalPadding)
        case .center:
            return NSTextTab(textAlignment: .center, location: columnStart + width / 2)
        case .right:
            return NSTextTab(textAlignment: .right, location: columnStart + width - tableCellHorizontalPadding)
        }
    }

    static func ruleParagraphStyle(kind: TextKitRuleKind, quoteDepth: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let lineHeight: CGFloat = kind == .heading ? 8 : 24
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.paragraphSpacing = kind == .heading ? 10 : 16
        style.headIndent = CGFloat(quoteDepth) * quoteIndent
        style.firstLineHeadIndent = CGFloat(quoteDepth) * quoteIndent
        return style
    }

    static func spacerParagraphStyle(height: CGFloat, quoteDepth: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = height
        style.maximumLineHeight = height
        style.paragraphSpacing = 0
        style.headIndent = CGFloat(quoteDepth) * quoteIndent
        style.firstLineHeadIndent = CGFloat(quoteDepth) * quoteIndent
        return style
    }
}

private extension PreviewMarginPreset {
    func textKitPadding(for availableWidth: CGFloat) -> CGFloat {
        let fluid = availableWidth * fluidMultiplier
        return min(maximumPaddingPoints, max(minimumPaddingPoints, fluid))
    }

    var minimumPaddingPoints: CGFloat {
        switch self {
        case .tight:
            return 10
        case .normal:
            return 16
        case .wide:
            return 26
        case .extraWide:
            return 36
        }
    }

    var fluidMultiplier: CGFloat {
        switch self {
        case .tight:
            return 0.02
        case .normal:
            return 0.04
        case .wide:
            return 0.06
        case .extraWide:
            return 0.08
        }
    }

    var maximumPaddingPoints: CGFloat {
        switch self {
        case .tight:
            return 24
        case .normal:
            return 45
        case .wide:
            return 80
        case .extraWide:
            return 120
        }
    }
}

private extension NSMutableAttributedString {
    func append(_ string: String, attributes: [NSAttributedString.Key: Any]) {
        append(NSAttributedString(string: string, attributes: attributes))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension NSAttributedString.Key {
    static let leafletInlineCode = NSAttributedString.Key("LeafletTextKitInlineCode")
    static let leafletCodeBlock = NSAttributedString.Key("LeafletTextKitCodeBlock")
    static let leafletBlockQuoteDepth = NSAttributedString.Key("LeafletTextKitBlockQuoteDepth")
    static let leafletRuleLayout = NSAttributedString.Key("LeafletTextKitRuleLayout")
    static let leafletTableRowLayout = NSAttributedString.Key("LeafletTextKitTableRowLayout")
}
