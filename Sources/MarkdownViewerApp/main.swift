import AppKit
import MarkdownViewerCore

MainActor.assumeIsolated {
    let delegate = ViewerAppDelegate()
    NSApplication.shared.delegate = delegate
    NSApp.run()
}
