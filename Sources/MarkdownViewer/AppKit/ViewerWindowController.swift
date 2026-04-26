import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ViewerWindowController: NSWindowController {
    let controller: MarkdownDocumentController
    private var preferencesObservers: Set<AnyCancellable> = []

    private var windowCloseObserver: Any?

    init(document: ViewerDocument) {
        let docModel = MarkdownDocument(text: document.text)
        controller = MarkdownDocumentController(document: docModel)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )

        window.minSize = NSSize(width: 260, height: 560)
        window.setFrameAutosaveName("ViewerWindow")
        window.center()

        super.init(window: window)

        let preferences = ViewerAppDelegate.shared.preferences

        let hostingView = NSHostingView(
            rootView: MarkdownDocumentView(controller: controller)
        )
        window.contentView = hostingView

        controller.attachWindow(window)
        controller.setReloadFromDiskAction { [weak self] in
            await self?.reloadDocumentFromDisk()
        }
        controller.updatePreferences(preferences.renderingPreferences)
        controller.updateDocumentOpenMode(preferences.documentOpenMode)
        controller.updateSlackTableMode(preferences.slackTableMode)
        controller.sync(
            document: docModel,
            fileURL: document.fileURL,
            forceRender: true
        )

        window.tabbingMode = .automatic

        observePreferences(preferences)

        // When a sibling tab closes, hide the tab bar if we're the only one left.
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let closingWindow = notification.object as? NSWindow,
                  let myWindow = self.window,
                  closingWindow !== myWindow,
                  myWindow.tabbedWindows?.contains(closingWindow) == true else { return }

            DispatchQueue.main.async {
                if (myWindow.tabbedWindows?.count ?? 0) <= 1,
                   myWindow.tabGroup?.isTabBarVisible == true {
                    myWindow.toggleTabBar(nil)
                }
            }
        }
    }

    deinit {
        if let observer = windowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // Hide the tab bar when there's only one tab. Only toggle if it's
        // currently visible to avoid accidentally showing a hidden bar.
        if let window, (window.tabbedWindows?.count ?? 0) <= 1,
           window.tabGroup?.isTabBarVisible == true {
            window.toggleTabBar(nil)
        }
    }

    override var document: AnyObject? {
        didSet {
            guard let viewerDocument = document as? ViewerDocument else { return }
            let docModel = MarkdownDocument(text: viewerDocument.text)
            controller.sync(
                document: docModel,
                fileURL: viewerDocument.fileURL,
                forceRender: true
            )
        }
    }

    override func newWindowForTab(_ sender: Any?) {
        guard let window else { return }

        window.tabbingMode = .preferred

        do {
            let openedDocument = try NSDocumentController.shared
                .openUntitledDocumentAndDisplay(false)
            guard let newDocument = openedDocument as? ViewerDocument else { return }
            newDocument.makeWindowControllers()
            guard let newWC = newDocument.windowControllers.first as? ViewerWindowController,
                  let newWindow = newWC.window else { return }

            newWindow.tabbingMode = .preferred
            window.addTabbedWindow(newWindow, ordered: .above)
            newWindow.makeKeyAndOrderFront(nil)
        } catch {
            ErrorPresenter.present(error)
        }
    }

    private func observePreferences(_ preferences: MarkdownViewerPreferences) {
        preferences.$documentOpenMode
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                self?.controller.updateDocumentOpenMode(mode)
            }
            .store(in: &preferencesObservers)

        preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let prefs = ViewerAppDelegate.shared.preferences
                self.controller.updatePreferences(prefs.renderingPreferences)
                self.controller.updateSlackTableMode(prefs.slackTableMode)
            }
            .store(in: &preferencesObservers)
    }

    private func reloadDocumentFromDisk() async {
        guard let viewerDocument = document as? ViewerDocument else {
            controller.refresh(force: true)
            return
        }

        guard let fileURL = viewerDocument.fileURL else {
            controller.refresh(force: true)
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            try viewerDocument.read(from: data, ofType: UTType.markdownSource.identifier)
            controller.didReloadFromDisk(
                document: MarkdownDocument(text: viewerDocument.text),
                fileURL: fileURL
            )
        } catch {
            ErrorPresenter.present(error)
        }
    }
}
