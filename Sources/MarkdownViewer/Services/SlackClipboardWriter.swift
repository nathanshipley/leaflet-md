import AppKit

@MainActor
enum SlackClipboardWriter {
    private static let textKit1ListMarkerOption = NSAttributedString.DocumentReadingOptionKey(
        rawValue: "NSTextKit1ListMarkerFormatDocumentOption"
    )

    static func writeHTMLDocument(
        _ htmlDocument: String,
        plainText: String
    ) {
        writePasteboard(
            htmlData: Data(htmlDocument.utf8),
            plainText: plainText
        )
    }

    static func writeHTMLFragment(
        _ htmlFragment: String,
        plainText: String
    ) {
        writeHTMLDocument(makeHTMLDocument(from: htmlFragment), plainText: plainText)
    }

    static func writeRichHTMLDocument(
        _ htmlDocument: String,
        plainText: String? = nil
    ) throws {
        let htmlData = Data(htmlDocument.utf8)
        let attributed = try attributedString(fromHTMLDocument: htmlDocument)
        let rtfData = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )

        writePasteboard(
            htmlData: htmlData,
            rtfData: rtfData,
            plainText: plainText ?? attributed.string
        )
    }

    static func writeRichHTMLFragment(
        _ htmlFragment: String,
        plainText: String? = nil
    ) throws {
        try writeRichHTMLDocument(
            makeHTMLDocument(from: htmlFragment),
            plainText: plainText
        )
    }

    static func writeAttributedString(
        _ attributed: NSAttributedString,
        plainText: String? = nil
    ) throws {
        let range = NSRange(location: 0, length: attributed.length)
        let htmlData = try attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
        )
        let rtfData = try attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )

        writePasteboard(
            htmlData: htmlData,
            rtfData: rtfData,
            plainText: plainText ?? attributed.string
        )
    }

    static func writeSlackTexty(
        _ slackTexty: String,
        attributed: NSAttributedString,
        plainText: String? = nil
    ) throws {
        let range = NSRange(location: 0, length: attributed.length)
        let htmlData = try attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
        )
        let rtfData = try attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let resolvedPlainText = plainText ?? attributed.string

        writePasteboard(
            htmlData: htmlData,
            rtfData: rtfData,
            plainText: resolvedPlainText,
            chromiumWebCustomData: ChromiumWebCustomDataEncoder.encode(
                entries: [
                    ChromiumWebCustomDataEntry(
                        type: "public.utf8-plain-text",
                        value: resolvedPlainText
                    ),
                    ChromiumWebCustomDataEntry(
                        type: "slack/texty",
                        value: slackTexty
                    )
                ]
            )
        )
    }

    static func writeSlackTexty(
        _ slackTexty: String,
        htmlFragment: String,
        plainText: String? = nil
    ) throws {
        let htmlDocument = makeHTMLDocument(from: htmlFragment)
        let attributed = try attributedString(fromHTMLDocument: htmlDocument)
        try writeSlackTexty(
            slackTexty,
            attributed: attributed,
            plainText: plainText ?? attributed.string
        )
    }

    private static func writePasteboard(
        htmlData: Data? = nil,
        rtfData: Data? = nil,
        plainText: String,
        chromiumWebCustomData: Data? = nil
    ) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes(
            declaredPasteboardTypes(
                hasHTML: htmlData != nil,
                hasRTF: rtfData != nil,
                hasChromiumWebCustomData: chromiumWebCustomData != nil
            ),
            owner: nil
        )

        if let htmlData {
            pasteboard.setData(htmlData, forType: .html)
        }
        if let rtfData {
            pasteboard.setData(rtfData, forType: .rtf)
        }
        if let chromiumWebCustomData {
            pasteboard.setData(
                chromiumWebCustomData,
                forType: ChromiumWebCustomDataEncoder.pasteboardType
            )
        }

        pasteboard.setString(plainText, forType: .string)
    }

    private static func declaredPasteboardTypes(
        hasHTML: Bool,
        hasRTF: Bool,
        hasChromiumWebCustomData: Bool
    ) -> [NSPasteboard.PasteboardType] {
        var types: [NSPasteboard.PasteboardType] = [.string]
        if hasHTML {
            types.append(.html)
        }
        if hasRTF {
            types.append(.rtf)
        }
        if hasChromiumWebCustomData {
            types.append(ChromiumWebCustomDataEncoder.pasteboardType)
        }
        return types
    }

    private static func attributedString(fromHTMLDocument htmlDocument: String) throws -> NSAttributedString {
        try NSAttributedString(
            data: Data(htmlDocument.utf8),
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
                textKit1ListMarkerOption: true
            ],
            documentAttributes: nil
        )
    }

    private static func makeHTMLDocument(from fragment: String) -> String {
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

            h1, h2, h3, h4, h5, h6 {
              font-size: 1em;
              font-weight: 700;
              margin: 0.75em 0 0.2em;
            }

            p, ul, ol, blockquote, pre {
              margin: 0.4em 0;
            }

            ul, ol {
              padding-left: 1.45em;
            }

            li {
              margin: 0.18em 0;
            }

            li > ul,
            li > ol {
              margin-top: 0.2em;
            }

            .slack-list-block {
              margin: 0;
            }

            .slack-list-item {
              margin: 0 0 0.35em;
            }

            .slack-list-prefix {
              white-space: pre-wrap;
            }

            .slack-rule {
              color: #57606a;
              letter-spacing: 0.04em;
            }

            blockquote {
              margin-left: 0;
              padding-left: 0.9em;
              border-left: 3px solid #d0d7de;
              color: #57606a;
            }

            table {
              border-collapse: collapse;
            }

            td, th {
              border: 1px solid #d0d7de;
              padding: 4px 8px;
            }

            .slack-spacer {
              margin: 0;
            }
          </style>
        </head>
        <body>
          \(fragment)
        </body>
        </html>
        """
    }
}

struct ChromiumWebCustomDataEntry: Equatable {
    let type: String
    let value: String
}

enum ChromiumWebCustomDataEncoder {
    static let pasteboardType = NSPasteboard.PasteboardType("org.chromium.web-custom-data")

    static func encode(entries: [ChromiumWebCustomDataEntry]) -> Data {
        var payload = Data()
        payload.appendUInt32LE(UInt32(entries.count))

        for entry in entries {
            payload.appendPickleString16(entry.type)
            payload.appendPickleString16(entry.value)
        }

        var output = Data()
        output.appendUInt32LE(UInt32(payload.count))
        output.append(payload)
        return output
    }
}

private extension Data {
    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size))
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt16>.size))
    }

    mutating func appendPickleString16(_ value: String) {
        let codeUnits = Array(value.utf16)
        appendUInt32LE(UInt32(codeUnits.count))
        for codeUnit in codeUnits {
            appendUInt16LE(codeUnit)
        }
        appendPicklePadding()
    }

    mutating func appendPicklePadding() {
        let padding = (4 - (count % 4)) % 4
        if padding > 0 {
            append(Data(repeating: 0, count: padding))
        }
    }
}
