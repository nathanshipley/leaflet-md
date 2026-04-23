import AppKit
import UniformTypeIdentifiers

@objc(ViewerDocument)
class ViewerDocument: NSDocument {
    var text: String = ""
    var allowsNativeSave = false

    var canSaveNativeDocument: Bool {
        allowsNativeSave
            && fileURL == nil
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    override init() {
        super.init()
        if let clipboardText = ClipboardDocumentSeed.consumeSeed() {
            text = clipboardText
            allowsNativeSave = true
        }
    }

    override class var readableTypes: [String] {
        [
            UTType.markdownSource.identifier,
            UTType.text.identifier,
            UTType.data.identifier
        ]
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let decodedText = TextDocumentDecoder.decode(data) else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileReadCorruptFileError,
                userInfo: [
                    NSLocalizedDescriptionKey: "This file does not appear to be a readable text document."
                ]
            )
        }

        text = decodedText
        allowsNativeSave = false
        scheduleWindowControllerSync(forceRender: true)
    }

    override class var writableTypes: [String] {
        [
            UTType.markdownSource.identifier
        ]
    }

    // Leaflet presents opened files as read-only and only supports an explicit
    // Save for clipboard-seeded documents. Autosave-in-place would write back
    // to opened files on its own schedule, which is not what we want.
    override class var autosavesInPlace: Bool {
        false
    }

    override func data(ofType typeName: String) throws -> Data {
        Data(text.utf8)
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        savePanel.allowedContentTypes = [.markdownSource]
        savePanel.allowsOtherFileTypes = true
        savePanel.isExtensionHidden = false
        return true
    }

    override func fileNameExtension(
        forType typeName: String,
        saveOperation: NSDocument.SaveOperationType
    ) -> String? {
        "md"
    }

    override func makeWindowControllers() {
        let windowController = ViewerWindowController(document: self)
        addWindowController(windowController)
    }

    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool {
        true
    }

    override var isEntireFileLoaded: Bool {
        true
    }

    private func scheduleWindowControllerSync(forceRender: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let document = MarkdownDocument(text: text)

            for case let windowController as ViewerWindowController in windowControllers {
                windowController.controller.sync(
                    document: document,
                    fileURL: fileURL,
                    forceRender: forceRender
                )
            }
        }
    }
}

private enum TextDocumentDecoder {
    static func decode(_ data: Data) -> String? {
        if hasPrefix([0xFF, 0xFE], in: data) {
            return decode(data, as: .utf16LittleEndian)
        }

        if hasPrefix([0xFE, 0xFF], in: data) {
            return decode(data, as: .utf16BigEndian)
        }

        guard !data.contains(0) else { return nil }
        return decode(data, as: .utf8)
    }

    private static func decode(_ data: Data, as encoding: String.Encoding) -> String? {
        guard let text = String(data: data, encoding: encoding),
              isPlainText(text) else {
            return nil
        }

        return text
    }

    private static func hasPrefix(_ prefix: [UInt8], in data: Data) -> Bool {
        data.count >= prefix.count && data.prefix(prefix.count).elementsEqual(prefix)
    }

    private static func isPlainText(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            scalar.value == 9
                || scalar.value == 10
                || scalar.value == 13
                || scalar.value >= 32
        }
    }
}
