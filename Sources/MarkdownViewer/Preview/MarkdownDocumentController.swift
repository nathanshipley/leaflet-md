import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class MarkdownDocumentController: ObservableObject {
    @Published private(set) var renderedDocument: RenderedDocument
    @Published private(set) var isRendering = false
    @Published private(set) var statusText = ""
    @Published private(set) var documentText: String
    @Published private(set) var fileURL: URL?
    @Published private(set) var isFindPresented = false
    @Published private(set) var findQuery = ""
    @Published private(set) var findMatchCount = 0
    @Published private(set) var findResultText = ""
    @Published private(set) var findFocusToken = 0
    @Published var displayMode: MarkdownDisplayMode = .preview {
        didSet {
            refresh(force: true)
        }
    }

    private let renderer: MarkdownRenderer
    let previewSelectionBridge = PreviewSelectionBridge()
    private var renderingPreferences = PreviewRenderingPreferences.standard
    private var documentOpenMode: DocumentOpenMode = .tab
    private var preferredSlackTableMode: SlackTableRenderingMode = .codeBlock
    private var renderTask: Task<Void, Never>?
    private var findTask: Task<Void, Never>?
    private var pendingPreviewSelectionCapture: Task<PreviewSlackSelectionSnapshot?, Never>?
    private var lastRenderSignature = ""
    weak var window: NSWindow?
    private var reloadFromDiskAction: (@MainActor () async -> Void)?

    init(
        document: MarkdownDocument,
        renderer: MarkdownRenderer = MarkdownRenderer()
    ) {
        self.renderer = renderer
        documentText = document.text
        fileURL = nil
        renderedDocument = .placeholder(title: "Markdown Preview", displayMode: .preview)
    }

    var suggestedBaseName: String {
        guard let fileURL else {
            return "Markdown Preview"
        }

        return fileURL.deletingPathExtension().lastPathComponent
    }

    var documentTitle: String {
        fileURL?.lastPathComponent ?? "Untitled Markdown"
    }

    var canSaveMarkdownCopy: Bool {
        !documentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canCopyForSlack: Bool {
        canSaveMarkdownCopy
    }

    var isReusableBlankDocument: Bool {
        fileURL == nil && documentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func sync(document: MarkdownDocument, fileURL: URL?, forceRender: Bool) {
        documentText = document.text
        self.fileURL = fileURL
        refresh(force: forceRender)
    }

    func updatePreferences(_ preferences: PreviewRenderingPreferences) {
        guard renderingPreferences != preferences else {
            return
        }

        renderingPreferences = preferences
        refresh(force: true)
    }

    func updateSlackTableMode(_ tableMode: SlackTableRenderingMode) {
        preferredSlackTableMode = tableMode
    }

    func updateDocumentOpenMode(_ mode: DocumentOpenMode) {
        guard documentOpenMode != mode else {
            applyWindowMode()
            return
        }

        documentOpenMode = mode
        applyWindowMode()
    }

    func attachWindow(_ window: NSWindow?) {
        self.window = window
        applyWindowMode()
    }

    func setReloadFromDiskAction(_ action: (@MainActor () async -> Void)?) {
        reloadFromDiskAction = action
    }

    func refresh(force: Bool = false) {
        let signature = [
            documentText,
            fileURL?.path ?? "",
            displayMode.rawValue,
            renderingPreferences.marginPreset.rawValue,
            renderingPreferences.fontPreset.rawValue,
            renderingPreferences.allowWideContent.description
        ].joined(separator: "::")

        guard force || signature != lastRenderSignature else {
            return
        }

        lastRenderSignature = signature
        renderTask?.cancel()
        isRendering = true
        statusText = "Rendering \(displayMode.title.lowercased())…"

        let markdown = documentText
        let fileURL = fileURL
        let displayMode = displayMode
        let renderingPreferences = renderingPreferences

        renderTask = Task { [weak self] in
            guard let self else { return }

            let repositoryContext = await GitHubRepositoryContextResolver.resolve(for: fileURL)
            if Task.isCancelled { return }

            let title = fileURL?.lastPathComponent ?? self.suggestedBaseName
            let context = RenderContext(
                baseURL: fileURL?.deletingLastPathComponent(),
                repoContext: repositoryContext,
                purpose: .preview,
                title: title
            )

            let rendered = await self.renderer.render(
                markdown: markdown,
                displayMode: displayMode,
                context: context,
                preferences: renderingPreferences
            )

            if Task.isCancelled { return }

            self.renderedDocument = rendered
            self.isRendering = false
            self.statusText = rendered.note ?? self.defaultStatusText(for: displayMode)
        }
    }

    func reloadDocument() async {
        if fileURL != nil, let reloadFromDiskAction {
            await reloadFromDiskAction()
            return
        }

        refresh(force: true)
    }

    func didReloadFromDisk(document: MarkdownDocument, fileURL: URL?) {
        sync(document: document, fileURL: fileURL, forceRender: true)
        statusText = "Reloaded from disk."
    }

    func newDocumentFromClipboard() {
        guard let markdown = MarkdownClipboard.currentString else {
            NSSound.beep()
            return
        }

        if let viewerDocumentController = NSDocumentController.shared as? ViewerDocumentController {
            viewerDocumentController.newDocumentFromClipboard(markdown, sender: nil)
        } else {
            ClipboardDocumentSeed.stage(markdown)
            NSDocumentController.shared.newDocument(nil)
        }
    }

    func copyForSlack(
        tableMode: SlackTableRenderingMode? = nil
    ) async {
        guard canCopyForSlack else {
            NSSound.beep()
            return
        }

        let effectiveTableMode = tableMode ?? preferredSlackTableMode

        switch displayMode {
        case .preview:
            await copyPreviewForSlack(tableMode: effectiveTableMode)
        case .code:
            await copyCodeForSlack(tableMode: effectiveTableMode)
        }
    }

    func copySystemSelection() async -> Bool {
        switch displayMode {
        case .preview:
            return previewSelectionBridge.copyNativeSelection()
        case .code:
            guard let selectedSource = await previewSelectionBridge.selectedSourceText() else {
                return false
            }

            MarkdownClipboard.write(selectedSource)
            statusText = "Copied Markdown from code view."
            return true
        }
    }

    var canFind: Bool {
        !documentText.isEmpty
    }

    func showFind() {
        guard canFind else {
            NSSound.beep()
            return
        }

        isFindPresented = true
        findFocusToken += 1
    }

    func hideFind() {
        guard isFindPresented else {
            return
        }

        isFindPresented = false
        findResultText = ""
        findTask?.cancel()
        findTask = Task { @MainActor in
            await previewSelectionBridge.clearFind()
        }
    }

    func setFindQuery(_ query: String) {
        findQuery = query
        runFind(resetAnchor: true, backwards: false)
    }

    func findNext() {
        if findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showFind()
            return
        }

        showFind()
        runFind(resetAnchor: false, backwards: false)
    }

    func findPrevious() {
        if findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showFind()
            return
        }

        showFind()
        runFind(resetAnchor: false, backwards: true)
    }

    func handleDocumentDidFinishLoading() {
        guard isFindPresented, !findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        runFind(resetAnchor: true, backwards: false)
    }

    func saveMarkdownCopy() {
        guard canSaveMarkdownCopy else {
            NSSound.beep()
            return
        }

        guard let destinationURL = ExportService.requestSaveURL(
            contentType: .markdownSource,
            suggestedName: suggestedMarkdownFileName,
            allowReplacing: false
        ) else {
            return
        }

        do {
            try ExportService.exportMarkdown(documentText, to: destinationURL)
            statusText = "Saved Markdown copy to \(destinationURL.lastPathComponent)."
        } catch {
            ErrorPresenter.present(error)
        }
    }

    func exportHTML() {
        guard let destinationURL = ExportService.requestSaveURL(
            contentType: .html,
            suggestedName: suggestedBaseName + ".html"
        ) else {
            return
        }

        do {
            try ExportService.exportHTML(renderedDocument, to: destinationURL)
            statusText = "Exported HTML to \(destinationURL.lastPathComponent)."
        } catch {
            ErrorPresenter.present(error)
        }
    }

    func exportPDF() {
        guard let destinationURL = ExportService.requestSaveURL(
            contentType: .pdf,
            suggestedName: suggestedBaseName + ".pdf"
        ) else {
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let renderedDocument = self.renderedDocument
            do {
                try await ExportService.exportPDF(renderedDocument, to: destinationURL)
                await MainActor.run {
                    self.statusText = "Exported PDF to \(destinationURL.lastPathComponent)."
                }
            } catch {
                await MainActor.run {
                    ErrorPresenter.present(error)
                }
            }
        }
    }

    func handleLinkActivation(_ url: URL) {
        if url.isFileURL {
            let cleanedURL = url.removingFragment()
            let lowercasedExtension = cleanedURL.pathExtension.lowercased()

            if ["md", "markdown", "mdown"].contains(lowercasedExtension) {
                NSDocumentController.shared.openDocument(
                    withContentsOf: cleanedURL,
                    display: true
                ) { _, _, error in
                    if let error { ErrorPresenter.present(error) }
                }
                return
            }

            NSWorkspace.shared.open(cleanedURL)
            return
        }

        NSWorkspace.shared.open(url)
    }

    func openDroppedFiles(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        for url in fileURLs {
            NSDocumentController.shared.openDocument(
                withContentsOf: url,
                display: true
            ) { _, _, error in
                if let error { ErrorPresenter.present(error) }
            }
        }
    }

    func beginPreviewSelectionCapture() {
        guard displayMode == .preview else {
            return
        }

        let tableMode = preferredSlackTableMode
        pendingPreviewSelectionCapture?.cancel()
        pendingPreviewSelectionCapture = Task { @MainActor [weak self] in
            guard let self else {
                return nil
            }

            return await previewSelectionBridge.slackSelectionSnapshot(tableMode: tableMode)
        }
    }

    private func defaultStatusText(for _: MarkdownDisplayMode) -> String {
        ""
    }

    private func copyPreviewForSlack(
        tableMode: SlackTableRenderingMode
    ) async {
        let pendingSelection = await consumePendingPreviewSelectionCapture()
        let liveSelection = await previewSelectionBridge.slackSelectionSnapshot(tableMode: tableMode)
        if let selection = pendingSelection ?? liveSelection {
            if let fragment = selection.htmlFragment {
                if let slackTexty = selection.slackTexty {
                    do {
                        try SlackClipboardWriter.writeSlackTexty(
                            slackTexty,
                            htmlFragment: fragment,
                            plainText: selection.plainText
                        )
                    } catch {
                        do {
                            try SlackClipboardWriter.writeRichHTMLFragment(
                                fragment,
                                plainText: selection.plainText
                            )
                        } catch {
                            SlackClipboardWriter.writeHTMLFragment(
                                fragment,
                                plainText: selection.plainText
                            )
                        }
                    }
                } else {
                    do {
                        try SlackClipboardWriter.writeRichHTMLFragment(
                            fragment,
                            plainText: selection.plainText
                        )
                    } catch {
                        SlackClipboardWriter.writeHTMLFragment(
                            fragment,
                            plainText: selection.plainText
                        )
                    }
                }
            } else {
                MarkdownClipboard.write(selection.plainText)
            }

            statusText = "Copied selected preview content \(tableMode.statusDescription)."
            return
        }

        let exporter = SlackExporter()
        let plainText = exporter.export(markdown: documentText, tableMode: tableMode)
        let slackTexty = exporter.exportSlackTexty(markdown: documentText, tableMode: tableMode)
        guard !plainText.isEmpty else {
            NSSound.beep()
            return
        }

        do {
            try SlackClipboardWriter.writeSlackTexty(
                slackTexty,
                attributed: exporter.exportAttributed(
                    markdown: documentText,
                    tableMode: tableMode
                ),
                plainText: plainText
            )
        } catch {
            SlackClipboardWriter.writeHTMLDocument(
                exporter.exportHTMLDocument(
                    markdown: documentText,
                    tableMode: tableMode
                ),
                plainText: plainText
            )
        }
        statusText = "Copied rendered preview \(tableMode.statusDescription)."
    }

    private func copyCodeForSlack(
        tableMode: SlackTableRenderingMode
    ) async {
        let exporter = SlackExporter()
        let markdown = await previewSelectionBridge.selectedSourceText() ?? documentText
        let plainText = exporter.export(markdown: markdown, tableMode: tableMode)
        let slackTexty = exporter.exportSlackTexty(markdown: markdown, tableMode: tableMode)
        guard !plainText.isEmpty else {
            NSSound.beep()
            return
        }

        do {
            try SlackClipboardWriter.writeSlackTexty(
                slackTexty,
                attributed: exporter.exportAttributed(
                    markdown: markdown,
                    tableMode: tableMode
                ),
                plainText: plainText
            )
        } catch {
            SlackClipboardWriter.writeHTMLDocument(
                exporter.exportHTMLDocument(
                    markdown: markdown,
                    tableMode: tableMode
                ),
                plainText: plainText
            )
        }
        statusText = "Copied Markdown selection \(tableMode.statusDescription)."
    }

    private var suggestedMarkdownFileName: String {
        let baseName: String
        if let fileURL {
            baseName = fileURL.deletingPathExtension().lastPathComponent + " copy"
        } else {
            baseName = "Untitled Markdown"
        }

        return baseName + ".md"
    }

    private func applyWindowMode() {
        window?.tabbingMode = documentOpenMode == .tab ? .preferred : .disallowed
    }

    private func runFind(
        resetAnchor: Bool,
        backwards: Bool
    ) {
        let query = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        findTask?.cancel()

        guard !query.isEmpty else {
            findMatchCount = 0
            findResultText = ""
            findTask = Task { @MainActor in
                await previewSelectionBridge.clearFind()
            }
            return
        }

        findTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let count = await previewSelectionBridge.countMatches(for: query)
            if Task.isCancelled { return }

            self.findMatchCount = count

            guard count > 0 else {
                self.findResultText = "No matches"
                await previewSelectionBridge.clearFind()
                return
            }

            let found = await previewSelectionBridge.findString(
                query,
                backwards: backwards,
                resetAnchor: resetAnchor
            )
            if Task.isCancelled { return }

            self.findResultText = found
                ? (count == 1 ? "1 match" : "\(count) matches")
                : "No matches"
        }
    }

    private func consumePendingPreviewSelectionCapture() async -> PreviewSlackSelectionSnapshot? {
        guard let task = pendingPreviewSelectionCapture else {
            return nil
        }

        pendingPreviewSelectionCapture = nil
        return await task.value
    }
}
