import AppKit
import Combine
import SwiftUI

@MainActor
public final class ViewerAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    public static var shared: ViewerAppDelegate!

    private let appName = "Leaflet"
    public let preferences = MarkdownViewerPreferences()
    private var settingsWindowController: NSWindowController?
    private var preferencesObservers: Set<AnyCancellable> = []

    public override init() {
        super.init()
        ViewerAppDelegate.shared = self
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        // Register our custom document controller before any document operations.
        // The first NSDocumentController subclass instantiated becomes .shared.
        _ = ViewerDocumentController()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        buildMainMenu()
        observePreferencesForMenu()
    }

    public func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let hasSubstantiveDocuments = NSDocumentController.shared.documents.contains { doc in
            guard let viewerDoc = doc as? ViewerDocument else { return false }
            return viewerDoc.fileURL != nil
                || !viewerDoc.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard preferences.warnOnQuit, hasSubstantiveDocuments else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Are you sure you want to quit?"
        alert.informativeText = "All open documents will be closed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")

        let checkbox = NSButton(checkboxWithTitle: "Always warn before quitting", target: nil, action: nil)
        checkbox.state = .on
        alert.accessoryView = checkbox

        let response = alert.runModal()

        if checkbox.state == .off {
            preferences.warnOnQuit = false
        }

        return response == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    public func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Settings Window

    @objc func showSettingsWindow(_ sender: Any?) {
        if let wc = settingsWindowController {
            wc.showWindow(sender)
            wc.window?.makeKeyAndOrderFront(sender)
            return
        }

        let settingsView = MarkdownViewerSettingsView()
            .environmentObject(preferences)
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(hostingController.view.fittingSize)
        window.center()

        let wc = NSWindowController(window: window)
        settingsWindowController = wc
        wc.showWindow(sender)
    }

    // MARK: - Menu Actions

    @objc func createNewTab(_ sender: Any?) {
        guard let keyWindow = NSApp.keyWindow ?? NSApp.mainWindow else {
            NSDocumentController.shared.newDocument(sender)
            return
        }

        do {
            let doc = try NSDocumentController.shared.openUntitledDocumentAndDisplay(false)
            doc.makeWindowControllers()
            guard let wc = doc.windowControllers.first, let newWindow = wc.window else {
                doc.showWindows()
                return
            }

            keyWindow.tabbingMode = .preferred
            newWindow.tabbingMode = .preferred
            keyWindow.addTabbedWindow(newWindow, ordered: .above)
            newWindow.makeKeyAndOrderFront(nil)
        } catch {
            ErrorPresenter.present(error)
        }
    }

    @objc func createNewDocument(_ sender: Any?) {
        NSDocumentController.shared.newDocument(sender)
    }

    @objc func openDocument(_ sender: Any?) {
        NSDocumentController.shared.openDocument(sender)
    }

    @objc func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(
            withContentsOf: url,
            display: true
        ) { _, _, error in
            if let error { ErrorPresenter.present(error) }
        }
    }

    @objc func newFromClipboard(_ sender: Any?) {
        guard let markdown = MarkdownClipboard.currentString else {
            NSSound.beep()
            return
        }

        if let viewerDocumentController = NSDocumentController.shared as? ViewerDocumentController {
            viewerDocumentController.newDocumentFromClipboard(markdown, sender: sender)
        } else {
            ClipboardDocumentSeed.stage(markdown)
            NSDocumentController.shared.newDocument(sender)
        }
    }

    @objc func copyForSlack(_ sender: Any?) {
        guard let wc = NSApp.mainWindow?.windowController as? ViewerWindowController else {
            NSSound.beep()
            return
        }

        Task { @MainActor in
            await wc.controller.copyForSlack()
        }
    }

    @objc func copy(_ sender: Any?) {
        if let keyWindow = NSApp.keyWindow {
            guard let wc = keyWindow.windowController as? ViewerWindowController else {
                if !sendStandardEditAction(#selector(NSText.copy(_:)), sender: sender) {
                    NSSound.beep()
                }
                return
            }

            Task { @MainActor in
                if await wc.controller.copySystemSelection() {
                    return
                }

                if !sendStandardEditAction(#selector(NSText.copy(_:)), sender: sender) {
                    NSSound.beep()
                }
            }
            return
        }

        guard let wc = NSApp.mainWindow?.windowController as? ViewerWindowController else {
            if !sendStandardEditAction(#selector(NSText.copy(_:)), sender: sender) {
                NSSound.beep()
            }
            return
        }

        Task { @MainActor in
            if await wc.controller.copySystemSelection() {
                return
            }

            if !sendStandardEditAction(#selector(NSText.copy(_:)), sender: sender) {
                NSSound.beep()
            }
        }
    }

    @objc func showFind(_ sender: Any?) {
        guard let wc = activeViewerWindowController else {
            NSSound.beep()
            return
        }

        wc.controller.showFind()
    }

    @objc func findNext(_ sender: Any?) {
        guard let wc = activeViewerWindowController else {
            NSSound.beep()
            return
        }

        wc.controller.findNext()
    }

    @objc func findPrevious(_ sender: Any?) {
        guard let wc = activeViewerWindowController else {
            NSSound.beep()
            return
        }

        wc.controller.findPrevious()
    }

    @objc func reloadPreview(_ sender: Any?) {
        guard let wc = NSApp.mainWindow?.windowController as? ViewerWindowController else {
            NSSound.beep()
            return
        }

        Task { @MainActor in
            await wc.controller.reloadDocument()
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let document = activeViewerDocument,
              document.canSaveNativeDocument else {
            NSSound.beep()
            return
        }

        document.save(sender)
    }

    @objc func saveMarkdownCopy(_ sender: Any?) {
        guard let wc = NSApp.mainWindow?.windowController as? ViewerWindowController else {
            NSSound.beep()
            return
        }

        wc.controller.saveMarkdownCopy()
    }

    @objc func exportHTML(_ sender: Any?) {
        guard let wc = NSApp.mainWindow?.windowController as? ViewerWindowController else {
            NSSound.beep()
            return
        }

        wc.controller.exportHTML()
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let wc = NSApp.mainWindow?.windowController as? ViewerWindowController else {
            NSSound.beep()
            return
        }

        wc.controller.exportPDF()
    }

    @objc func closeAllWindows(_ sender: Any?) {
        let candidateWindows = NSApp.orderedWindows.filter {
            $0.isVisible && !$0.isExcludedFromWindowsMenu
        }

        guard !candidateWindows.isEmpty else {
            NSSound.beep()
            return
        }

        for window in candidateWindows {
            window.performClose(sender)
        }
    }

    @objc func closeCurrentWindow(_ sender: Any?) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            NSSound.beep()
            return
        }

        window.performClose(sender)
    }

    // MARK: - View Menu Actions

    @objc func setFontPreset(_ sender: NSMenuItem) {
        guard let preset = PreviewFontPreset.allCases.first(where: { $0.title == sender.title }) else {
            return
        }
        preferences.fontPreset = preset
    }

    @objc func setMarginPreset(_ sender: NSMenuItem) {
        guard let preset = PreviewMarginPreset.allCases.first(where: { $0.title == sender.title }) else {
            return
        }
        preferences.marginPreset = preset
    }

    @objc func toggleWideContent(_ sender: NSMenuItem) {
        preferences.allowWideContent.toggle()
    }

    @objc func toggleWrapCodeViewLines(_ sender: NSMenuItem) {
        preferences.wrapCodeViewLines.toggle()
    }

    // MARK: - Menu Validation

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let wc = activeViewerWindowController

        switch menuItem.action {
        case #selector(copyForSlack(_:)):
            return wc?.controller.canCopyForSlack == true
        case #selector(saveDocument(_:)):
            return activeViewerDocument?.canSaveNativeDocument == true
        case #selector(saveMarkdownCopy(_:)):
            return wc?.controller.canSaveMarkdownCopy == true
        case #selector(exportHTML(_:)), #selector(exportPDF(_:)):
            return wc != nil
        case #selector(reloadPreview(_:)):
            return wc != nil
        case #selector(showFind(_:)):
            return wc?.controller.canFind == true
        case #selector(findNext(_:)), #selector(findPrevious(_:)):
            guard let wc else { return false }
            return !wc.controller.findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case #selector(closeAllWindows(_:)):
            return NSApp.orderedWindows.contains { $0.isVisible && !$0.isExcludedFromWindowsMenu }
        case #selector(toggleWideContent(_:)):
            // Reflect the current preference as a checkmark on every
            // menu open. Observer-driven updates were unreliable in
            // practice — this guarantees the state is always fresh.
            menuItem.state = preferences.allowWideContent ? .on : .off
            return true
        case #selector(toggleWrapCodeViewLines(_:)):
            menuItem.state = preferences.wrapCodeViewLines ? .on : .off
            return true
        default:
            return true
        }
    }

    // MARK: - NSMenuDelegate (Open Recent)

    public func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "Open Recent" else { return }

        menu.removeAllItems()

        let recentURLs = NSDocumentController.shared.recentDocumentURLs
        for url in recentURLs {
            let item = NSMenuItem(
                title: url.lastPathComponent,
                action: #selector(openRecentDocument(_:)),
                keyEquivalent: ""
            )
            item.representedObject = url
            item.target = self
            menu.addItem(item)
        }

        if !recentURLs.isEmpty {
            menu.addItem(.separator())
        }

        menu.addItem(
            withTitle: "Clear Menu",
            action: #selector(NSDocumentController.clearRecentDocuments(_:)),
            keyEquivalent: ""
        )
    }

    // MARK: - Menu Construction

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        mainMenu.addItem(buildAppMenu())
        mainMenu.addItem(buildFileMenu())
        mainMenu.addItem(buildEditMenu())
        mainMenu.addItem(buildMarkdownMenu())
        mainMenu.addItem(buildViewMenu())
        mainMenu.addItem(buildWindowMenu())
        mainMenu.addItem(buildHelpMenu())

        NSApp.mainMenu = mainMenu
    }

    private func buildAppMenu() -> NSMenuItem {
        let appMenu = NSMenu()

        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettingsWindow(_:)), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")

        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)

        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let item = NSMenuItem()
        item.submenu = appMenu
        return item
    }

    private func buildFileMenu() -> NSMenuItem {
        let fileMenu = NSMenu(title: "File")

        let newItem = NSMenuItem(title: "New", action: #selector(createNewDocument(_:)), keyEquivalent: "n")
        newItem.target = self
        fileMenu.addItem(newItem)

        let newTabItem = NSMenuItem(title: "New Tab", action: #selector(createNewTab(_:)), keyEquivalent: "t")
        newTabItem.target = self
        fileMenu.addItem(newTabItem)

        let openItem = NSMenuItem(title: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)

        let recentMenu = NSMenu(title: "Open Recent")
        recentMenu.delegate = self
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recentMenu
        fileMenu.addItem(recentItem)

        fileMenu.addItem(.separator())
        let closeItem = NSMenuItem(title: "Close", action: #selector(closeCurrentWindow(_:)), keyEquivalent: "w")
        closeItem.target = self
        fileMenu.addItem(closeItem)

        let closeAllItem = NSMenuItem(title: "Close All", action: #selector(closeAllWindows(_:)), keyEquivalent: "w")
        closeAllItem.keyEquivalentModifierMask = [.command, .option]
        closeAllItem.target = self
        fileMenu.addItem(closeAllItem)

        fileMenu.addItem(.separator())

        let saveItem = NSMenuItem(title: "Save", action: #selector(saveDocument(_:)), keyEquivalent: "s")
        saveItem.target = self
        fileMenu.addItem(saveItem)

        let saveCopyItem = NSMenuItem(title: "Save Markdown Copy…", action: #selector(saveMarkdownCopy(_:)), keyEquivalent: "")
        saveCopyItem.target = self
        fileMenu.addItem(saveCopyItem)

        fileMenu.addItem(.separator())

        let exportHTMLItem = NSMenuItem(title: "Export as HTML…", action: #selector(exportHTML(_:)), keyEquivalent: "")
        exportHTMLItem.target = self
        fileMenu.addItem(exportHTMLItem)

        let exportPDFItem = NSMenuItem(title: "Export as PDF…", action: #selector(exportPDF(_:)), keyEquivalent: "")
        exportPDFItem.target = self
        fileMenu.addItem(exportPDFItem)

        let item = NSMenuItem()
        item.submenu = fileMenu
        return item
    }

    private func buildEditMenu() -> NSMenuItem {
        let editMenu = NSMenu(title: "Edit")

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        let copyItem = NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: "c")
        copyItem.target = self
        editMenu.addItem(copyItem)
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())

        let findItem = NSMenuItem(title: "Find…", action: #selector(showFind(_:)), keyEquivalent: "f")
        findItem.target = self
        editMenu.addItem(findItem)

        let findNextItem = NSMenuItem(title: "Find Next", action: #selector(findNext(_:)), keyEquivalent: "g")
        findNextItem.target = self
        editMenu.addItem(findNextItem)

        let findPreviousItem = NSMenuItem(title: "Find Previous", action: #selector(findPrevious(_:)), keyEquivalent: "G")
        findPreviousItem.keyEquivalentModifierMask = [.command, .shift]
        findPreviousItem.target = self
        editMenu.addItem(findPreviousItem)

        let item = NSMenuItem()
        item.submenu = editMenu
        return item
    }

    private func sendStandardEditAction(
        _ action: Selector,
        sender: Any?
    ) -> Bool {
        if let firstResponder = NSApp.keyWindow?.firstResponder,
           NSApp.sendAction(action, to: firstResponder, from: sender) {
            return true
        }

        if let firstResponder = NSApp.mainWindow?.firstResponder,
           NSApp.sendAction(action, to: firstResponder, from: sender) {
            return true
        }

        return false
    }

    private var activeViewerWindowController: ViewerWindowController? {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.windowController as? ViewerWindowController
    }

    private var activeViewerDocument: ViewerDocument? {
        activeViewerWindowController?.document as? ViewerDocument
    }

    private func buildMarkdownMenu() -> NSMenuItem {
        let markdownMenu = NSMenu(title: "Markdown")

        let clipboardItem = NSMenuItem(title: "New from Clipboard", action: #selector(newFromClipboard(_:)), keyEquivalent: "V")
        clipboardItem.keyEquivalentModifierMask = [.command, .shift]
        clipboardItem.target = self
        markdownMenu.addItem(clipboardItem)

        markdownMenu.addItem(.separator())

        let slackItem = NSMenuItem(title: "Copy for Slack", action: #selector(copyForSlack(_:)), keyEquivalent: "")
        slackItem.target = self
        markdownMenu.addItem(slackItem)

        markdownMenu.addItem(.separator())

        let reloadItem = NSMenuItem(title: "Reload Preview", action: #selector(reloadPreview(_:)), keyEquivalent: "r")
        reloadItem.target = self
        markdownMenu.addItem(reloadItem)

        let item = NSMenuItem()
        item.submenu = markdownMenu
        return item
    }

    private func buildViewMenu() -> NSMenuItem {
        let viewMenu = NSMenu(title: "View")

        let fontSubmenu = NSMenu(title: "Preview Font")
        for preset in PreviewFontPreset.allCases {
            let fontItem = NSMenuItem(title: preset.title, action: #selector(setFontPreset(_:)), keyEquivalent: "")
            fontItem.target = self
            fontSubmenu.addItem(fontItem)
        }
        let fontMenuItem = NSMenuItem(title: "Preview Font", action: nil, keyEquivalent: "")
        fontMenuItem.submenu = fontSubmenu
        viewMenu.addItem(fontMenuItem)

        let marginSubmenu = NSMenu(title: "Margin Size")
        for preset in PreviewMarginPreset.allCases {
            let marginItem = NSMenuItem(title: preset.title, action: #selector(setMarginPreset(_:)), keyEquivalent: "")
            marginItem.target = self
            marginSubmenu.addItem(marginItem)
        }
        let marginMenuItem = NSMenuItem(title: "Margin Size", action: nil, keyEquivalent: "")
        marginMenuItem.submenu = marginSubmenu
        viewMenu.addItem(marginMenuItem)

        viewMenu.addItem(.separator())

        let wideItem = NSMenuItem(title: "Allow text to use the full window width", action: #selector(toggleWideContent(_:)), keyEquivalent: "")
        wideItem.target = self
        viewMenu.addItem(wideItem)

        let wrapItem = NSMenuItem(title: "Wrap Long Lines in Code View", action: #selector(toggleWrapCodeViewLines(_:)), keyEquivalent: "")
        wrapItem.target = self
        wrapItem.state = preferences.wrapCodeViewLines ? .on : .off
        viewMenu.addItem(wrapItem)

        let item = NSMenuItem()
        item.submenu = viewMenu
        return item
    }

    private func buildWindowMenu() -> NSMenuItem {
        let windowMenu = NSMenu(title: "Window")

        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")

        NSApp.windowsMenu = windowMenu

        let item = NSMenuItem()
        item.submenu = windowMenu
        return item
    }

    private func buildHelpMenu() -> NSMenuItem {
        let helpMenu = NSMenu(title: "Help")
        NSApp.helpMenu = helpMenu

        let item = NSMenuItem()
        item.submenu = helpMenu
        return item
    }

    // MARK: - Preference-Synced Menu State

    private func observePreferencesForMenu() {
        preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateViewMenuState()
            }
            .store(in: &preferencesObservers)

        updateViewMenuState()
    }

    private func updateViewMenuState() {
        guard let viewMenu = NSApp.mainMenu?.item(withTitle: "View")?.submenu else { return }

        if let fontMenu = viewMenu.item(withTitle: "Preview Font")?.submenu {
            for item in fontMenu.items {
                item.state = item.title == preferences.fontPreset.title ? .on : .off
            }
        }

        if let marginMenu = viewMenu.item(withTitle: "Margin Size")?.submenu {
            for item in marginMenu.items {
                item.state = item.title == preferences.marginPreset.title ? .on : .off
            }
        }

        if let wideItem = viewMenu.item(withTitle: "Allow text to use the full window width") {
            wideItem.state = preferences.allowWideContent ? .on : .off
        }

        if let wrapItem = viewMenu.item(withTitle: "Wrap Long Lines in Code View") {
            wrapItem.state = preferences.wrapCodeViewLines ? .on : .off
        }
    }
}
