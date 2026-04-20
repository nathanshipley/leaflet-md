import Foundation

struct RenderedDocument: Equatable, Sendable {
    let html: String
    let bodyHTML: String
    let baseURL: URL?
    let displayMode: MarkdownDisplayMode
    let note: String?

    static func placeholder(
        title: String = "Markdown Preview",
        displayMode: MarkdownDisplayMode = .preview,
        note: String? = nil,
        renderingPreferences: PreviewRenderingPreferences = .standard
    ) -> RenderedDocument {
        let factory = HTMLDocumentFactory()
        let body = """
        <section class="empty-state">
          <h1>\(title.htmlEscaped)</h1>
          <p>Open an .md file, or paste Markdown from your clipboard.</p>
        </section>
        """

        return RenderedDocument(
            html: factory.makeDocument(
            bodyHTML: body,
            title: title,
            containerClass: displayMode.containerClass,
            contentClass: displayMode.contentClass,
            contentTag: displayMode.contentTag,
            renderingPreferences: renderingPreferences
        ),
        bodyHTML: body,
        baseURL: nil,
        displayMode: displayMode,
        note: note
        )
    }
}
