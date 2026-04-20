import Foundation
import SwiftUI

@MainActor
public final class MarkdownViewerPreferences: ObservableObject {
    private enum Keys {
        static let documentOpenMode = "markdownViewer.document.openMode"
        static let marginPreset = "markdownViewer.preview.marginPreset"
        static let fontPreset = "markdownViewer.preview.fontPreset"
        static let allowWideContent = "markdownViewer.preview.allowWideContent"
        static let flattenSlackTables = "markdownViewer.slack.flattenTables"
        static let warnOnQuit = "markdownViewer.app.warnOnQuit"
    }

    @Published var documentOpenMode: DocumentOpenMode {
        didSet {
            UserDefaults.standard.set(documentOpenMode.rawValue, forKey: Keys.documentOpenMode)
        }
    }

    @Published var marginPreset: PreviewMarginPreset {
        didSet {
            UserDefaults.standard.set(marginPreset.rawValue, forKey: Keys.marginPreset)
        }
    }

    @Published var fontPreset: PreviewFontPreset {
        didSet {
            UserDefaults.standard.set(fontPreset.rawValue, forKey: Keys.fontPreset)
        }
    }

    @Published var allowWideContent: Bool {
        didSet {
            UserDefaults.standard.set(allowWideContent, forKey: Keys.allowWideContent)
        }
    }

    @Published var flattenSlackTables: Bool {
        didSet {
            UserDefaults.standard.set(flattenSlackTables, forKey: Keys.flattenSlackTables)
        }
    }

    @Published var warnOnQuit: Bool {
        didSet {
            UserDefaults.standard.set(warnOnQuit, forKey: Keys.warnOnQuit)
        }
    }

    var slackTableMode: SlackTableRenderingMode {
        flattenSlackTables ? .readableRows : .codeBlock
    }

    var renderingPreferences: PreviewRenderingPreferences {
        PreviewRenderingPreferences(
            marginPreset: marginPreset,
            fontPreset: fontPreset,
            allowWideContent: allowWideContent
        )
    }

    public init(defaults: UserDefaults = .standard) {
        documentOpenMode = DocumentOpenMode(rawValue: defaults.string(forKey: Keys.documentOpenMode) ?? "") ?? .tab
        marginPreset = PreviewMarginPreset(rawValue: defaults.string(forKey: Keys.marginPreset) ?? "") ?? .normal
        fontPreset = PreviewFontPreset(rawValue: defaults.string(forKey: Keys.fontPreset) ?? "") ?? .github
        allowWideContent = defaults.object(forKey: Keys.allowWideContent) as? Bool ?? false
        flattenSlackTables = defaults.object(forKey: Keys.flattenSlackTables) as? Bool ?? false
        warnOnQuit = defaults.object(forKey: Keys.warnOnQuit) as? Bool ?? true
    }
}
