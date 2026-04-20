import Foundation

struct MarkdownDocument {
    var text: String

    init(text: String? = nil) {
        self.text = text ?? ClipboardDocumentSeed.consume()
    }
}
