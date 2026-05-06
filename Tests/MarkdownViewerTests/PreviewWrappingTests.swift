import XCTest
@testable import MarkdownViewerCore

final class PreviewWrappingTests: XCTestCase {
    @MainActor
    func testFreshDefaultWrapsCodeViewLines() {
        XCTAssertTrue(PreviewRenderingPreferences.standard.wrapCodeViewLines)

        let suiteName = "PreviewWrappingTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated defaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = MarkdownViewerPreferences(defaults: defaults)
        XCTAssertTrue(preferences.wrapCodeViewLines)
    }

    func testPreviewCodeBlocksWrapLongLines() {
        let css = ResourceLoader.text(named: "app", extension: "css")

        XCTAssertTrue(css.contains(".markdown-body pre code"))
        XCTAssertTrue(css.contains("white-space: pre-wrap;"))
        XCTAssertTrue(css.contains("overflow-wrap: anywhere;"))
    }
}
