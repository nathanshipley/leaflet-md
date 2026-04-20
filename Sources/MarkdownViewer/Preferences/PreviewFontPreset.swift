import Foundation

enum PreviewFontPreset: String, CaseIterable, Identifiable {
    case github
    case inter
    case sourceSerif4
    case newsreader

    var id: String { rawValue }

    var title: String {
        switch self {
        case .github:
            return "GitHub Default"
        case .inter:
            return "Inter"
        case .sourceSerif4:
            return "Source Serif 4"
        case .newsreader:
            return "Newsreader"
        }
    }

    var cssFontStack: String {
        switch self {
        case .github:
            return #"-apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji""#
        case .inter:
            return #""MarkdownViewerInter", -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji""#
        case .sourceSerif4:
            return #""MarkdownViewerSourceSerif4", Georgia, "Times New Roman", serif"#
        case .newsreader:
            return #""MarkdownViewerNewsreader", Georgia, "Times New Roman", serif"#
        }
    }

    var fontFaceCSS: String {
        switch self {
        case .github:
            return ""
        case .inter:
            return Self.variableFontFaceCSS(
                familyName: "MarkdownViewerInter",
                normalDataURL: Self.interNormalDataURL,
                italicDataURL: Self.interItalicDataURL
            )
        case .sourceSerif4:
            return Self.variableFontFaceCSS(
                familyName: "MarkdownViewerSourceSerif4",
                normalDataURL: Self.sourceSerif4NormalDataURL,
                italicDataURL: Self.sourceSerif4ItalicDataURL
            )
        case .newsreader:
            return Self.variableFontFaceCSS(
                familyName: "MarkdownViewerNewsreader",
                normalDataURL: Self.newsreaderNormalDataURL,
                italicDataURL: Self.newsreaderItalicDataURL
            )
        }
    }

    private static let interNormalDataURL = ResourceLoader.dataURL(
        named: "InterVariable",
        extension: "ttf",
        mimeType: "font/ttf"
    )

    private static let interItalicDataURL = ResourceLoader.dataURL(
        named: "InterVariable-Italic",
        extension: "ttf",
        mimeType: "font/ttf"
    )

    private static let sourceSerif4NormalDataURL = ResourceLoader.dataURL(
        named: "SourceSerif4Variable",
        extension: "ttf",
        mimeType: "font/ttf"
    )

    private static let sourceSerif4ItalicDataURL = ResourceLoader.dataURL(
        named: "SourceSerif4Variable-Italic",
        extension: "ttf",
        mimeType: "font/ttf"
    )

    private static let newsreaderNormalDataURL = ResourceLoader.dataURL(
        named: "NewsreaderVariable",
        extension: "ttf",
        mimeType: "font/ttf"
    )

    private static let newsreaderItalicDataURL = ResourceLoader.dataURL(
        named: "NewsreaderVariable-Italic",
        extension: "ttf",
        mimeType: "font/ttf"
    )

    private static func variableFontFaceCSS(
        familyName: String,
        normalDataURL: String?,
        italicDataURL: String?
    ) -> String {
        let normalRule = normalDataURL.map {
            """
            @font-face {
              font-family: '\(familyName)';
              src: url('\($0)') format('truetype');
              font-style: normal;
              font-weight: 100 900;
              font-display: swap;
            }
            """
        } ?? ""

        let italicRule = italicDataURL.map {
            """
            @font-face {
              font-family: '\(familyName)';
              src: url('\($0)') format('truetype');
              font-style: italic;
              font-weight: 100 900;
              font-display: swap;
            }
            """
        } ?? ""

        return normalRule + italicRule
    }
}
