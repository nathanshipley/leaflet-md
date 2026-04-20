import Foundation

enum DocumentOpenMode: String, CaseIterable, Identifiable {
    case tab
    case window

    var id: Self { self }

    var title: String {
        switch self {
        case .tab:
            return "Tab"
        case .window:
            return "Window"
        }
    }

    var settingsDescription: String {
        switch self {
        case .tab:
            return "Open files, recent documents, and dropped Markdown in tabs when possible."
        case .window:
            return "Open files, recent documents, and dropped Markdown in separate windows."
        }
    }
}
