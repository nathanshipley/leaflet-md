enum MarkdownDisplayMode: String, CaseIterable, Identifiable {
    case preview
    case pdf
    case overlay
    case textKit
    case code

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preview:
            return "Preview"
        case .pdf:
            return "PDF"
        case .overlay:
            return "Overlay"
        case .textKit:
            return "TextKit"
        case .code:
            return "Code"
        }
    }

    var containerClass: String {
        switch self {
        case .preview, .pdf, .overlay:
            return "preview-shell"
        case .textKit:
            return "preview-shell"
        case .code:
            return "code-shell"
        }
    }

    var contentClass: String {
        switch self {
        case .preview, .pdf, .overlay:
            return "markdown-body"
        case .textKit:
            return "markdown-body"
        case .code:
            return "source-pane"
        }
    }

    var contentTag: String {
        switch self {
        case .preview, .pdf, .overlay:
            return "article"
        case .textKit:
            return "article"
        case .code:
            return "section"
        }
    }
}
