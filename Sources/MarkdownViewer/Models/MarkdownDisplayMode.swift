enum MarkdownDisplayMode: String, CaseIterable, Identifiable {
    case preview
    case code

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preview:
            return "Preview"
        case .code:
            return "Code"
        }
    }

    var containerClass: String {
        switch self {
        case .preview:
            return "preview-shell"
        case .code:
            return "code-shell"
        }
    }

    var contentClass: String {
        switch self {
        case .preview:
            return "markdown-body"
        case .code:
            return "source-pane"
        }
    }

    var contentTag: String {
        switch self {
        case .preview:
            return "article"
        case .code:
            return "section"
        }
    }
}
