import AppKit

enum MarkdownClipboard {
    static var currentString: String? {
        NSPasteboard.general.string(forType: .string)
    }

    static func write(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
