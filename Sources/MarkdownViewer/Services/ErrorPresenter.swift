import AppKit

@MainActor
enum ErrorPresenter {
    static func present(_ error: Error) {
        NSAlert(error: error).runModal()
    }
}
