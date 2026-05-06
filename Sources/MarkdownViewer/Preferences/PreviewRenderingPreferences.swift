import Foundation

struct PreviewRenderingPreferences: Equatable, Sendable {
    var marginPreset: PreviewMarginPreset
    var fontPreset: PreviewFontPreset
    var allowWideContent: Bool
    var wrapCodeViewLines: Bool

    static let standard = PreviewRenderingPreferences(
        marginPreset: .normal,
        fontPreset: .github,
        allowWideContent: false,
        wrapCodeViewLines: true
    )

    var cssOverrides: String {
        """
        \(fontPreset.fontFaceCSS)

        :root {
          --viewer-markdown-max-width: \(allowWideContent ? "none" : "980px");
          --viewer-markdown-padding-min: \(marginPreset.minimumPadding);
          --viewer-markdown-padding-fluid: \(marginPreset.fluidPadding);
          --viewer-markdown-padding-max: \(marginPreset.maximumPadding);
        }

        .markdown-body {
          --fontStack-sansSerif: \(fontPreset.cssFontStack);
        }

        \(codeViewWrapCSS)
        """
    }

    private var codeViewWrapCSS: String {
        guard wrapCodeViewLines else { return "" }
        // When the user opts in, force long lines in Code view to wrap so
        // they stay visible without horizontal scroll. We override the
        // .line-inner rule from app.css and break inside long unbroken
        // tokens (URLs, code identifiers, etc.) so nothing escapes the
        // viewport.
        return """
        .line-inner {
          white-space: pre-wrap;
          word-break: break-word;
          overflow-wrap: anywhere;
        }
        """
    }
}
