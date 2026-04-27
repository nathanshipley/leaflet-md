import AppKit
import UniformTypeIdentifiers

@MainActor
final class ViewerDocumentController: NSDocumentController {
    override var defaultType: String? {
        UTType.markdownSource.identifier
    }

    override func beginOpenPanel(
        _ openPanel: NSOpenPanel,
        forTypes inTypes: [String]?,
        completionHandler: @escaping (Int) -> Void
    ) {
        openPanel.allowedContentTypes = []
        super.beginOpenPanel(openPanel, forTypes: nil, completionHandler: completionHandler)
    }

    func newDocumentFromClipboard(_ markdown: String, sender: Any?) {
        if let blankDocument = findReusableBlankDocument() {
            blankDocument.text = markdown
            blankDocument.fileURL = nil
            blankDocument.allowsNativeSave = true
            blankDocument.updateChangeCount(.changeDone)

            if let wc = blankDocument.windowControllers.first as? ViewerWindowController {
                wc.controller.sync(
                    document: MarkdownDocument(text: markdown),
                    fileURL: nil,
                    forceRender: true
                )
            }

            blankDocument.windowControllers.first?.window?.makeKeyAndOrderFront(sender)
            return
        }

        ClipboardDocumentSeed.stage(markdown)
        newDocument(sender)
    }

    override func newDocument(_ sender: Any?) {
        do {
            let doc = try openUntitledDocumentAndDisplay(false)
            if let viewerDocument = doc as? ViewerDocument,
               viewerDocument.canSaveNativeDocument {
                viewerDocument.updateChangeCount(.changeDone)
            }
            doc.makeWindowControllers()
            guard let wc = doc.windowControllers.first, let window = wc.window else {
                doc.showWindows()
                return
            }
            window.tabbingMode = .disallowed
            window.makeKeyAndOrderFront(nil)
        } catch {
            presentError(error)
        }
    }

    override func openDocument(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
    ) {
        // If the document is already open, bring its window to front
        // with a subtle bounce so the user notices.
        if let existingDoc = documents.first(where: { $0.fileURL == url }) {
            existingDoc.showWindows()
            if let window = existingDoc.windowControllers.first?.window {
                Self.bounceWindow(window)
            }
            completionHandler(existingDoc, true, nil)
            return
        }

        // If the currently-focused document is a blank untitled doc, load
        // the file into it so the empty window/tab the user is staring at
        // becomes the file's home. This runs regardless of the
        // tab-vs-window preference: reusing a focused blank never surprises
        // anyone because they can see the empty doc disappear. The
        // preference only controls what happens when there's NOT a focused
        // blank to reuse.
        if let blankDocument = findReusableBlankDocument() {
            do {
                let data = try Data(contentsOf: url)
                try blankDocument.read(from: data, ofType: UTType.markdownSource.identifier)
                blankDocument.fileURL = url
                noteNewRecentDocument(blankDocument)

                if let wc = blankDocument.windowControllers.first as? ViewerWindowController {
                    let docModel = MarkdownDocument(text: blankDocument.text)
                    wc.controller.sync(document: docModel, fileURL: url, forceRender: true)
                }

                if displayDocument, let window = blankDocument.windowControllers.first?.window {
                    window.makeKeyAndOrderFront(nil)
                }

                completionHandler(blankDocument, false, nil)
            } catch {
                // Fall back to standard open if reading fails
                super.openDocument(withContentsOf: url, display: displayDocument, completionHandler: completionHandler)
            }
            return
        }

        // When the preference is "tab" and there's an existing window,
        // open as a tab instead of a separate window.
        let existingWindow = NSApp.keyWindow ?? NSApp.mainWindow
        let shouldTab = ViewerAppDelegate.shared.preferences.documentOpenMode == .tab
            && existingWindow != nil

        if shouldTab {
            super.openDocument(withContentsOf: url, display: false) { [weak existingWindow] document, wasAlreadyOpen, error in
                guard error == nil,
                      !wasAlreadyOpen,
                      let document,
                      let existingWindow else {
                    completionHandler(document, wasAlreadyOpen, error)
                    return
                }

                if document.windowControllers.isEmpty {
                    document.makeWindowControllers()
                }

                guard let wc = document.windowControllers.first,
                      let newWindow = wc.window else {
                    document.showWindows()
                    completionHandler(document, wasAlreadyOpen, error)
                    return
                }

                existingWindow.addTabbedWindow(newWindow, ordered: .above)
                newWindow.makeKeyAndOrderFront(nil)
                completionHandler(document, wasAlreadyOpen, error)
            }
        } else {
            super.openDocument(withContentsOf: url, display: displayDocument, completionHandler: completionHandler)
        }
    }

    private func findReusableBlankDocument() -> ViewerDocument? {
        // Only the currently-focused document is "reusable." We deliberately
        // do NOT scan every open document for a blank one to fill: hijacking
        // a buried blank tab in some other window surprises the user, who
        // doesn't see where the file landed. Keep the rule simple — if the
        // doc you're looking at is empty and untitled, it's fair game;
        // otherwise leave existing windows alone.
        guard let current = currentDocument as? ViewerDocument,
              current.fileURL == nil,
              current.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return current
    }

    private static func bounceWindow(_ window: NSWindow) {
        let original = window.frame
        let inset: CGFloat = 12
        let shrunk = original.insetBy(dx: inset, dy: inset)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(shrunk, display: true)
        }) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(original, display: true)
            }
        }
    }
}
