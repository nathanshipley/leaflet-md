import PDFKit
import SwiftUI
import WebKit

struct PDFPreviewView: NSViewRepresentable {
    let renderedDocument: RenderedDocument

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFPreviewContainerView {
        let view = PDFPreviewContainerView()
        view.layoutHandler = { [weak coordinator = context.coordinator] in
            coordinator?.schedulePDFRender()
        }
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: PDFPreviewContainerView, context: Context) {
        context.coordinator.attach(to: view)
        context.coordinator.update(renderedDocument)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private weak var containerView: PDFPreviewContainerView?
        private var renderedDocument: RenderedDocument?
        private var htmlSignature = ""
        private var pdfSignature = ""
        private var isLoading = false
        private var pendingRender: DispatchWorkItem?

        func attach(to view: PDFPreviewContainerView) {
            containerView = view
            view.webView.navigationDelegate = self
        }

        func update(_ renderedDocument: RenderedDocument) {
            self.renderedDocument = renderedDocument
            let nextSignature = [
                renderedDocument.html,
                renderedDocument.baseURL?.absoluteString ?? ""
            ].joined(separator: "::")

            guard nextSignature != htmlSignature else {
                schedulePDFRender()
                return
            }

            htmlSignature = nextSignature
            pdfSignature = ""
            isLoading = true
            containerView?.pdfView.document = nil
            containerView?.webView.loadHTMLString(
                renderedDocument.html,
                baseURL: renderedDocument.baseURL
            )
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            isLoading = false
            schedulePDFRender()
        }

        func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError _: Error) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) {
            isLoading = false
        }

        func schedulePDFRender() {
            guard !isLoading,
                  let containerView,
                  renderedDocument != nil
            else {
                return
            }

            let width = max(1, containerView.bounds.width.rounded(.toNearestOrAwayFromZero))
            guard width > 1 else {
                return
            }

            let nextPDFSignature = "\(htmlSignature)::width=\(Int(width))"
            guard nextPDFSignature != pdfSignature else {
                return
            }

            pendingRender?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.createPDF(signature: nextPDFSignature)
            }
            pendingRender = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
        }

        private func createPDF(signature: String) {
            guard let containerView else {
                return
            }

            let webView = containerView.webView
            let script = """
            Math.ceil(Math.max(
              document.documentElement.scrollHeight,
              document.body ? document.body.scrollHeight : 0,
              document.documentElement.offsetHeight,
              document.body ? document.body.offsetHeight : 0
            ));
            """

            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self,
                      signature != self.pdfSignature
                else {
                    return
                }

                let width = max(1, webView.bounds.width)
                let contentHeight = max(
                    webView.bounds.height,
                    CGFloat((result as? NSNumber)?.doubleValue ?? 0)
                )
                let configuration = WKPDFConfiguration()
                configuration.rect = CGRect(
                    x: 0,
                    y: 0,
                    width: width,
                    height: max(contentHeight, 1)
                )

                webView.createPDF(configuration: configuration) { [weak self] pdfResult in
                    DispatchQueue.main.async {
                        guard let self,
                              signature != self.pdfSignature,
                              let containerView = self.containerView
                        else {
                            return
                        }

                        switch pdfResult {
                        case let .success(data):
                            containerView.pdfView.document = PDFDocument(data: data)
                            containerView.pdfView.scaleFactor = 1
                            containerView.pdfView.goToFirstPage(nil)
                            self.pdfSignature = signature
                        case .failure:
                            break
                        }
                    }
                }
            }
        }
    }
}

final class PDFPreviewContainerView: NSView {
    let pdfView = PDFView()
    let webView: WKWebView
    var layoutHandler: (() -> Void)?

    override init(frame frameRect: NSRect) {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.suppressesIncrementalRendering = false
        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor

        webView.setValue(false, forKey: "drawsBackground")
        webView.alphaValue = 0

        pdfView.autoScales = false
        pdfView.scaleFactor = 1
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = false
        pdfView.backgroundColor = .white
        pdfView.autoresizingMask = [.width, .height]

        addSubview(webView)
        addSubview(pdfView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        pdfView.frame = bounds
        webView.frame = bounds
        layoutHandler?()
    }
}
