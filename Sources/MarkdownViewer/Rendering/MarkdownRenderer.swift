import Foundation

protocol LocalMarkdownRendering {
    func render(markdown: String) throws -> String
}

struct MarkdownRenderer {
    private let localRenderer: LocalMarkdownRendering
    private let codeViewRenderer: MarkdownCodeViewRenderer
    private let htmlFactory: HTMLDocumentFactory

    init(
        localRenderer: LocalMarkdownRendering = LocalGitHubMarkdownRenderer(),
        codeViewRenderer: MarkdownCodeViewRenderer = MarkdownCodeViewRenderer(),
        htmlFactory: HTMLDocumentFactory = HTMLDocumentFactory()
    ) {
        self.localRenderer = localRenderer
        self.codeViewRenderer = codeViewRenderer
        self.htmlFactory = htmlFactory
    }

    func render(
        markdown: String,
        displayMode: MarkdownDisplayMode,
        context: RenderContext,
        preferences: PreviewRenderingPreferences
    ) async -> RenderedDocument {
        if markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .placeholder(
                title: context.title,
                displayMode: displayMode,
                renderingPreferences: preferences
            )
        }

        switch displayMode {
        case .preview:
            return renderPreview(
                markdown: markdown,
                displayMode: .preview,
                context: context,
                preferences: preferences
            )
        case .code:
            return renderCode(markdown: markdown, context: context, preferences: preferences)
        }
    }

    private func renderPreview(
        markdown: String,
        displayMode: MarkdownDisplayMode,
        context: RenderContext,
        preferences: PreviewRenderingPreferences,
        note: String? = nil
    ) -> RenderedDocument {
        do {
            let body = try localRenderer.render(markdown: markdown)
            return makeRenderedDocument(
                bodyHTML: body,
                displayMode: displayMode,
                context: context,
                preferences: preferences,
                note: note
            )
        } catch {
            let fallbackBody = """
            <pre><code>\(markdown.htmlEscaped)</code></pre>
            """

            return makeRenderedDocument(
                bodyHTML: fallbackBody,
                displayMode: displayMode,
                context: context,
                preferences: preferences,
                note: "Markdown parsing failed, so the preview is showing escaped source text: \(error.localizedDescription)"
            )
        }
    }

    private func renderCode(
        markdown: String,
        context: RenderContext,
        preferences: PreviewRenderingPreferences
    ) -> RenderedDocument {
        let body = codeViewRenderer.render(markdown: markdown)
        return makeRenderedDocument(
            bodyHTML: body,
            displayMode: .code,
            context: context,
            preferences: preferences,
            note: nil
        )
    }

    private func makeRenderedDocument(
        bodyHTML: String,
        displayMode: MarkdownDisplayMode,
        context: RenderContext,
        preferences: PreviewRenderingPreferences,
        note: String?
    ) -> RenderedDocument {
        RenderedDocument(
            html: htmlFactory.makeDocument(
                bodyHTML: bodyHTML,
                title: context.title,
                containerClass: displayMode.containerClass,
                contentClass: displayMode.contentClass,
                contentTag: displayMode.contentTag,
                renderingPreferences: preferences
            ),
            bodyHTML: bodyHTML,
            baseURL: context.baseURL,
            displayMode: displayMode,
            note: note
        )
    }
}
