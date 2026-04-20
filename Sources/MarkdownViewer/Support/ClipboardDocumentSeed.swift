import Foundation

enum ClipboardDocumentSeed {
    private static var pendingText: String?

    static func stage(_ text: String) {
        pendingText = text
    }

    static func consumeSeed() -> String? {
        defer { pendingText = nil }
        return pendingText
    }

    static func consume() -> String {
        consumeSeed() ?? ""
    }
}
