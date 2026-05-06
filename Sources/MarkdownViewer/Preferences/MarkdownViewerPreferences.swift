import Foundation
import SwiftUI

@MainActor
public final class MarkdownViewerPreferences: ObservableObject {
    private enum Keys {
        static let documentOpenMode = "markdownViewer.document.openMode"
        static let marginPreset = "markdownViewer.preview.marginPreset"
        static let fontPreset = "markdownViewer.preview.fontPreset"
        static let allowWideContent = "markdownViewer.preview.allowWideContent"
        static let wrapCodeViewLines = "markdownViewer.codeView.wrapLines"
        static let slackTableMode = "markdownViewer.slack.tableMode"
        // Legacy key from beta.7 and earlier — read once on init to
        // migrate the Bool toggle into the new three-way preference.
        static let flattenSlackTablesLegacy = "markdownViewer.slack.flattenTables"
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

    @Published var wrapCodeViewLines: Bool {
        didSet {
            UserDefaults.standard.set(wrapCodeViewLines, forKey: Keys.wrapCodeViewLines)
        }
    }

    @Published var slackTableMode: SlackTableRenderingMode {
        didSet {
            UserDefaults.standard.set(slackTableMode.rawValue, forKey: Keys.slackTableMode)
        }
    }

    @Published var warnOnQuit: Bool {
        didSet {
            UserDefaults.standard.set(warnOnQuit, forKey: Keys.warnOnQuit)
        }
    }

    var renderingPreferences: PreviewRenderingPreferences {
        PreviewRenderingPreferences(
            marginPreset: marginPreset,
            fontPreset: fontPreset,
            allowWideContent: allowWideContent,
            wrapCodeViewLines: wrapCodeViewLines
        )
    }

    public init(defaults: UserDefaults = .standard) {
        documentOpenMode = DocumentOpenMode(rawValue: defaults.string(forKey: Keys.documentOpenMode) ?? "") ?? .tab
        marginPreset = PreviewMarginPreset(rawValue: defaults.string(forKey: Keys.marginPreset) ?? "") ?? .normal
        fontPreset = PreviewFontPreset(rawValue: defaults.string(forKey: Keys.fontPreset) ?? "") ?? .github
        allowWideContent = defaults.object(forKey: Keys.allowWideContent) as? Bool ?? false
        wrapCodeViewLines = defaults.object(forKey: Keys.wrapCodeViewLines) as? Bool ?? true
        slackTableMode = Self.resolveSlackTableMode(defaults: defaults)
        warnOnQuit = defaults.object(forKey: Keys.warnOnQuit) as? Bool ?? true
    }

    /// Resolve the user's Slack table preference, migrating the older
    /// Bool toggle (`flattenSlackTables`) into the new three-way enum the
    /// first time we see it. Existing testers who had the toggle on map
    /// to `.flattenAll`; everyone else gets the new `.wrap` default.
    private static func resolveSlackTableMode(defaults: UserDefaults) -> SlackTableRenderingMode {
        if let stored = defaults.string(forKey: Keys.slackTableMode),
           let mode = SlackTableRenderingMode(rawValue: stored) {
            return mode
        }
        if defaults.object(forKey: Keys.flattenSlackTablesLegacy) != nil {
            return defaults.bool(forKey: Keys.flattenSlackTablesLegacy) ? .flattenAll : .wrap
        }
        return .wrap
    }
}
