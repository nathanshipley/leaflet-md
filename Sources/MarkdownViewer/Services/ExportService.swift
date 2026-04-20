import AppKit
import UniformTypeIdentifiers
import WebKit

@MainActor
enum ExportService {
    static func requestSaveURL(
        contentType: UTType,
        suggestedName: String,
        allowReplacing: Bool = true
    ) -> URL? {
        while true {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.allowedContentTypes = [contentType]
            panel.nameFieldStringValue = suggestedName

            guard panel.runModal() == .OK, let url = panel.url else {
                return nil
            }

            if allowReplacing || !FileManager.default.fileExists(atPath: url.path) {
                return url
            }

            presentOverwriteBlockedAlert(for: url)
        }
    }

    static func exportMarkdown(_ markdown: String, to destinationURL: URL) throws {
        try Data(markdown.utf8).write(to: destinationURL, options: .atomic)
    }

    static func exportHTML(_ renderedDocument: RenderedDocument, to destinationURL: URL) throws {
        try Data(renderedDocument.html.utf8).write(to: destinationURL, options: .atomic)
    }

    static func exportPDF(_ renderedDocument: RenderedDocument, to destinationURL: URL) async throws {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1200, height: 1600))
        let delegate = ExportNavigationDelegate()
        webView.navigationDelegate = delegate
        webView.loadHTMLString(renderedDocument.html, baseURL: renderedDocument.baseURL)
        try await delegate.waitForNavigation()
        let data = try await webView.pdfData()
        try data.write(to: destinationURL, options: .atomic)
    }
}

private extension ExportService {
    static func presentOverwriteBlockedAlert(for url: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Choose a New Markdown Filename"
        alert.informativeText = "\"\(url.lastPathComponent)\" already exists. Overwriting existing Markdown files is disabled in Leaflet right now."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private final class ExportNavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func waitForNavigation() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume(returning: ())
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private extension WKWebView {
    func pdfData() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            createPDF(configuration: WKPDFConfiguration()) { result in
                switch result {
                case let .success(data):
                    continuation.resume(returning: data)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
