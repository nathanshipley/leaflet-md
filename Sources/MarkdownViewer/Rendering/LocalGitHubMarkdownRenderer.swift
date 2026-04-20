import Foundation
import cmark_gfm
import cmark_gfm_extensions

struct LocalGitHubMarkdownRenderer: LocalMarkdownRendering {
    func render(markdown: String) throws -> String {
        cmark_gfm_core_extensions_ensure_registered()

        let options = CInt(CMARK_OPT_FOOTNOTES | CMARK_OPT_STRIKETHROUGH_DOUBLE_TILDE | CMARK_OPT_GITHUB_PRE_LANG)
        guard let parser = cmark_parser_new(options) else {
            throw LocalGitHubMarkdownRendererError.parserCreationFailed
        }
        defer {
            cmark_parser_free(parser)
        }

        for extensionName in ["table", "strikethrough", "autolink", "tagfilter", "tasklist"] {
            let attached = extensionName.withCString { pointer in
                guard let syntaxExtension = cmark_find_syntax_extension(pointer) else {
                    return false
                }

                return cmark_parser_attach_syntax_extension(parser, syntaxExtension) == 1
            }

            if !attached {
                throw LocalGitHubMarkdownRendererError.extensionAttachmentFailed(extensionName)
            }
        }

        let utf8Bytes = Array(markdown.utf8)
        utf8Bytes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            cmark_parser_feed(parser, UnsafeRawPointer(baseAddress).assumingMemoryBound(to: CChar.self), buffer.count)
        }

        guard let document = cmark_parser_finish(parser) else {
            throw LocalGitHubMarkdownRendererError.renderFailed
        }
        defer {
            cmark_node_free(document)
        }

        let syntaxExtensions = cmark_parser_get_syntax_extensions(parser)
        guard let htmlPointer = cmark_render_html(document, options, syntaxExtensions) else {
            throw LocalGitHubMarkdownRendererError.renderFailed
        }
        defer {
            free(htmlPointer)
        }

        return String(cString: htmlPointer)
    }
}

enum LocalGitHubMarkdownRendererError: LocalizedError {
    case parserCreationFailed
    case extensionAttachmentFailed(String)
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .parserCreationFailed:
            return "Could not create the local cmark-gfm parser."
        case let .extensionAttachmentFailed(name):
            return "Could not attach the \(name) GitHub-flavored markdown extension."
        case .renderFailed:
            return "Could not render markdown with the local cmark-gfm renderer."
        }
    }
}
