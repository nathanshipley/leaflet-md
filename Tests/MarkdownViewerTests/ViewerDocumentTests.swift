import UniformTypeIdentifiers
import XCTest
@testable import MarkdownViewerCore

final class ViewerDocumentTests: XCTestCase {
    override func tearDown() {
        _ = ClipboardDocumentSeed.consumeSeed()
        super.tearDown()
    }

    func testClipboardDocumentsCanBeSavedNatively() throws {
        ClipboardDocumentSeed.stage("# Pasted\n\nMarkdown")

        let document = ViewerDocument()

        XCTAssertEqual(document.text, "# Pasted\n\nMarkdown")
        XCTAssertTrue(document.canSaveNativeDocument)
        XCTAssertEqual(
            try document.data(ofType: UTType.markdownSource.identifier),
            Data("# Pasted\n\nMarkdown".utf8)
        )
        XCTAssertEqual(
            document.fileNameExtension(
                forType: UTType.markdownSource.identifier,
                saveOperation: .saveAsOperation
            ),
            "md"
        )

        let saveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")
        defer { try? FileManager.default.removeItem(at: saveURL) }

        try document.write(to: saveURL, ofType: UTType.markdownSource.identifier)
        XCTAssertEqual(
            try String(contentsOf: saveURL, encoding: .utf8),
            "# Pasted\n\nMarkdown"
        )
    }

    func testOpenedDocumentsRemainViewerOnly() throws {
        let document = ViewerDocument()

        try document.read(
            from: Data("# Opened\n\nMarkdown".utf8),
            ofType: UTType.markdownSource.identifier
        )

        XCTAssertEqual(document.text, "# Opened\n\nMarkdown")
        XCTAssertFalse(document.canSaveNativeDocument)
    }

    func testExtensionlessDataDocumentsCanOpenWhenTheyAreText() throws {
        let document = ViewerDocument()

        try document.read(
            from: Data("plain extensionless text".utf8),
            ofType: UTType.data.identifier
        )

        XCTAssertEqual(document.text, "plain extensionless text")
    }

    func testBinaryDataDocumentsAreRejected() {
        let document = ViewerDocument()
        let binary = Data([0x00, 0x01, 0x02, 0x03, 0xFF])

        XCTAssertThrowsError(
            try document.read(from: binary, ofType: UTType.data.identifier)
        )
    }
}
