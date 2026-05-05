import SwiftUI
import WebKit

struct PreviewWebView: NSViewRepresentable {
    let renderedDocument: RenderedDocument
    let selectionBridge: PreviewSelectionBridge
    let selectionOverlayEnabled: Bool
    let linkHandler: (URL) -> Void
    let selectionChangeHandler: () -> Void
    let documentDidFinishLoading: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            linkHandler: linkHandler,
            selectionBridge: selectionBridge,
            documentDidFinishLoading: documentDidFinishLoading
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.suppressesIncrementalRendering = false

        let webView = SelectionAwareWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true
        webView.selectionChangeHandler = selectionChangeHandler
        selectionBridge.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.selectionOverlayEnabled = selectionOverlayEnabled
        selectionBridge.webView = webView
        (webView as? SelectionAwareWebView)?.selectionChangeHandler = selectionChangeHandler
        let signature = [
            renderedDocument.displayMode.rawValue,
            renderedDocument.html,
            renderedDocument.baseURL?.path ?? ""
        ].joined(separator: "::")

        guard signature != context.coordinator.lastSignature else { return }
        context.coordinator.lastSignature = signature
        webView.loadHTMLString(renderedDocument.html, baseURL: renderedDocument.baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastSignature = ""
        var selectionOverlayEnabled = false
        private let linkHandler: (URL) -> Void
        private let selectionBridge: PreviewSelectionBridge
        private let documentDidFinishLoading: () -> Void

        init(
            linkHandler: @escaping (URL) -> Void,
            selectionBridge: PreviewSelectionBridge,
            documentDidFinishLoading: @escaping () -> Void
        ) {
            self.linkHandler = linkHandler
            self.selectionBridge = selectionBridge
            self.documentDidFinishLoading = documentDidFinishLoading
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard
                navigationAction.navigationType == .linkActivated,
                let requestURL = navigationAction.request.url
            else {
                decisionHandler(.allow)
                return
            }

            if requestURL.isSameDocumentAnchor(for: navigationAction.request.mainDocumentURL) {
                decisionHandler(.allow)
                return
            }

            linkHandler(requestURL)
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            selectionBridge.webView = webView
            Task { @MainActor in
                await selectionBridge.installSelectionEnhancements(
                    selectionOverlayEnabled: selectionOverlayEnabled
                )
                documentDidFinishLoading()
            }
        }
    }

    final class SelectionAwareWebView: WKWebView {
        var selectionChangeHandler: (() -> Void)?

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            selectionChangeHandler?()
        }

        override func keyUp(with event: NSEvent) {
            super.keyUp(with: event)
            selectionChangeHandler?()
        }
    }
}
