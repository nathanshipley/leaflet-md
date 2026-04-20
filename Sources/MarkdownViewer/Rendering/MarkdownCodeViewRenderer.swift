import Foundation

struct MarkdownCodeViewRenderer {
    private let tokenRegex = try! NSRegularExpression(
        pattern: #"\[[^\]]+\]\(([^)]+)\)|https?://[^\s<>()]+"#,
        options: []
    )
    private let markdownLinkRegex = try! NSRegularExpression(
        pattern: #"^\[([^\]]+)\]\(([^)]+)\)$"#,
        options: []
    )
    private let orderedListRegex = try! NSRegularExpression(
        pattern: #"^(\s*)(\d+[.)])(\s+)(.*)$"#,
        options: []
    )
    private let unorderedListRegex = try! NSRegularExpression(
        pattern: #"^(\s*)([-+*])(\s+)(.*)$"#,
        options: []
    )

    func render(markdown: String) -> String {
        let normalizedMarkdown = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalizedMarkdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var isInsideFrontMatter = false
        let rows = lines.enumerated().map { index, rawLine in
            renderRow(
                lineNumber: index + 1,
                rawLine: rawLine.replacingOccurrences(of: "\r", with: ""),
                isInsideFrontMatter: &isInsideFrontMatter
            )
        }.joined(separator: "\n")

        return """
        <section class="source-view">
          <table class="source-table" aria-label="Markdown source">
            <tbody>
              \(rows)
            </tbody>
          </table>
        </section>
        """
    }

    private func renderRow(lineNumber: Int, rawLine: String, isInsideFrontMatter: inout Bool) -> String {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        let isFence = trimmed == "---" || trimmed == "+++"
        let startsFrontMatter = lineNumber == 1 && isFence
        let highlightAsFrontMatter = isInsideFrontMatter || startsFrontMatter

        let contentHTML: String
        if rawLine.isEmpty {
            contentHTML = "&nbsp;"
        } else if highlightAsFrontMatter {
            contentHTML = wrapped("token-frontmatter", rawLine.htmlEscaped)
        } else if trimmed.hasPrefix("#") {
            contentHTML = wrapped("token-heading", rawLine.htmlEscaped)
        } else if let listMatch = firstMatch(for: unorderedListRegex, in: rawLine) ?? firstMatch(for: orderedListRegex, in: rawLine) {
            contentHTML = renderListLine(rawLine, match: listMatch)
        } else {
            contentHTML = renderInlineTokens(in: rawLine)
        }

        if startsFrontMatter {
            isInsideFrontMatter = true
        } else if isInsideFrontMatter && isFence {
            isInsideFrontMatter = false
        }

        return """
        <tr id="L\(lineNumber)">
          <td class="line-number" data-line-number="\(lineNumber)" aria-hidden="true"></td>
          <td class="line-content"><span class="line-inner">\(contentHTML)</span></td>
        </tr>
        """
    }

    private func renderListLine(_ rawLine: String, match: NSTextCheckingResult) -> String {
        let line = rawLine as NSString
        let indent = line.substring(with: match.range(at: 1)).htmlEscaped
        let bullet = line.substring(with: match.range(at: 2)).htmlEscaped
        let gap = line.substring(with: match.range(at: 3)).htmlEscaped
        let rest = line.substring(with: match.range(at: 4))

        return indent + wrapped("token-bullet", bullet) + gap + renderInlineTokens(in: rest)
    }

    private func renderInlineTokens(in rawLine: String) -> String {
        let nsLine = rawLine as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        let matches = tokenRegex.matches(in: rawLine, options: [], range: fullRange)

        guard !matches.isEmpty else {
            return rawLine.htmlEscaped
        }

        var result = ""
        var currentLocation = 0

        for match in matches {
            if match.range.location > currentLocation {
                let prefix = nsLine.substring(with: NSRange(location: currentLocation, length: match.range.location - currentLocation))
                result += prefix.htmlEscaped
            }

            let token = nsLine.substring(with: match.range)
            result += renderLinkToken(token)
            currentLocation = match.range.location + match.range.length
        }

        if currentLocation < nsLine.length {
            let suffix = nsLine.substring(from: currentLocation)
            result += suffix.htmlEscaped
        }

        return result
    }

    private func renderLinkToken(_ token: String) -> String {
        let fullRange = NSRange(location: 0, length: (token as NSString).length)

        if let match = markdownLinkRegex.firstMatch(in: token, options: [], range: fullRange) {
            let nsToken = token as NSString
            let destination = nsToken.substring(with: match.range(at: 2))
            let href = destination.htmlEscaped
            let literal = token.htmlEscaped
            return "<a class=\"token-link\" href=\"\(href)\">\(literal)</a>"
        }

        let href = token.htmlEscaped
        return "<a class=\"token-link\" href=\"\(href)\">\(href)</a>"
    }

    private func wrapped(_ className: String, _ content: String) -> String {
        "<span class=\"\(className)\">\(content)</span>"
    }

    private func firstMatch(for regex: NSRegularExpression, in string: String) -> NSTextCheckingResult? {
        let range = NSRange(location: 0, length: (string as NSString).length)
        return regex.firstMatch(in: string, options: [], range: range)
    }
}
