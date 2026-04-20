import Foundation

struct PreviewRenderingPreferences: Equatable, Sendable {
    var marginPreset: PreviewMarginPreset
    var fontPreset: PreviewFontPreset
    var allowWideContent: Bool

    static let standard = PreviewRenderingPreferences(
        marginPreset: .normal,
        fontPreset: .github,
        allowWideContent: false
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
        """
    }
}
