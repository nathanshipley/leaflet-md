import AppKit
import SwiftUI

struct MarkdownDocumentView: View {
    @ObservedObject var controller: MarkdownDocumentController
    @State private var isDropTargeted = false
    @FocusState private var isFindFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if controller.isFindPresented {
                findBar
            }
            Divider()

            if controller.documentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmptyPreviewView {
                    controller.newDocumentFromClipboard()
                }
            } else if controller.displayMode == .pdf {
                PDFPreviewView(renderedDocument: controller.renderedDocument)
            } else if controller.displayMode == .textKit {
                TextKitPreviewView(
                    markdown: controller.documentText,
                    preferences: controller.textKitRenderingPreferences
                )
            } else {
                PreviewWebView(
                    renderedDocument: controller.renderedDocument,
                    selectionBridge: controller.previewSelectionBridge,
                    selectionOverlayEnabled: controller.displayMode == .overlay,
                    linkHandler: controller.handleLinkActivation,
                    selectionChangeHandler: controller.beginPreviewSelectionCapture,
                    documentDidFinishLoading: controller.handleDocumentDidFinishLoading
                )
            }
        }
        .frame(minWidth: 260, minHeight: 560)
        .onChange(of: controller.findFocusToken) { _ in
            guard controller.isFindPresented else { return }
            DispatchQueue.main.async {
                isFindFieldFocused = true
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            controller.openDroppedFiles(urls)
            return !urls.isEmpty
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
        .overlay(alignment: .top) {
            if isDropTargeted {
                Text("Drop Markdown files to open them")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 14)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            modePicker
            Spacer(minLength: 12)

            if controller.isRendering {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 2)
            }

            ActionToolbarButton(
                title: "Copy for Slack",
                helpText: "Copy for Slack",
                isDisabled: !controller.canCopyForSlack
            ) {
                Task { @MainActor in
                    await controller.copyForSlack()
                }
            } label: {
                HStack(spacing: 6) {
                    SlackToolbarIcon()
                    Text("Copy for Slack")
                }
            }

            ToolbarSeparator()

            ActionToolbarButton(
                title: "Reload",
                helpText: "Reload Preview"
            ) {
                Task { @MainActor in
                    await controller.reloadDocument()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                    Text("Reload")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var findBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor.opacity(0.72))

                TextField(
                    "Find in document",
                    text: Binding(
                        get: { controller.findQuery },
                        set: { controller.setFindQuery($0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($isFindFieldFocused)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.12), lineWidth: 1)
            }

            Spacer(minLength: 8)

            if !controller.findResultText.isEmpty {
                Text(controller.findResultText)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.78))
                    .frame(minWidth: 76, alignment: .trailing)
            }

            FindBarButton(
                title: "Previous Match",
                helpText: "Find Previous",
                isDisabled: controller.findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                controller.findPrevious()
            } label: {
                Image(systemName: "chevron.up")
            }

            FindBarButton(
                title: "Next Match",
                helpText: "Find Next",
                isDisabled: controller.findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                controller.findNext()
            } label: {
                Image(systemName: "chevron.down")
            }

            FindBarButton(
                title: "Close Find",
                helpText: "Close Find"
            ) {
                controller.hideFind()
            } label: {
                Image(systemName: "xmark")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.08))
        .onExitCommand {
            controller.hideFind()
        }
    }

    private var modePicker: some View {
        DisplayModeToggle(selection: $controller.displayMode)
        .frame(width: 330)
    }
}

private struct DisplayModeToggle: View {
    @Binding var selection: MarkdownDisplayMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MarkdownDisplayMode.allCases) { mode in
                modeButton(for: mode)
            }
        }
        .padding(2)
        .frame(height: 24)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Display mode")
        .accessibilityValue(selection.title)
    }

    private func modeButton(for mode: MarkdownDisplayMode) -> some View {
        let isSelected = selection == mode

        return Button {
            selection = mode
        } label: {
            Text(mode.title)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: Color.black.opacity(0.08), radius: 1, y: 0.5)
            }
        }
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct FindBarButton<Label: View>: View {
    let title: String
    let helpText: String
    var isDisabled = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isDisabled ? Color.secondary.opacity(0.65) : Color.accentColor.opacity(0.82))
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(isDisabled ? 0.55 : (isHovered ? 1.0 : 0.92)))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(isHovered ? 0.18 : 0.11), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .help(helpText)
        .accessibilityLabel(helpText)
    }
}

private struct ActionToolbarButton<Label: View>: View {
    let title: String
    let helpText: String
    var isDisabled = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(foregroundStyle)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    private var backgroundStyle: Color {
        if isDisabled {
            return Color.primary.opacity(0.018)
        }

        return isHovered ? Color.primary.opacity(0.07) : Color.primary.opacity(0.025)
    }

    private var borderColor: Color {
        Color.primary.opacity(isHovered ? 0.12 : 0.045)
    }

    private var foregroundStyle: Color {
        isDisabled ? Color.secondary.opacity(0.65) : Color.primary
    }
}

private struct SlackToolbarIcon: View {
    private static let image = ResourceLoader
        .url(named: "slack_transparentBG", extension: "png")
        .flatMap(NSImage.init(contentsOf:))

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .colorMultiply(Color.primary.opacity(0.8))
            } else {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 10.5, weight: .regular))
            }
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}

private struct ToolbarSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(width: 1, height: 17)
            .padding(.horizontal, 1)
            .accessibilityHidden(true)
    }
}

private struct EmptyPreviewView: View {
    let newDocumentAction: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    LeafletLogo()

                    Text("A simple Markdown reader\nwith pretty Slack pasting.")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Text("Open an .md file, or paste Markdown from your clipboard.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .padding(.top, 14)

                Button("New from Clipboard", action: newDocumentAction)
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
            .padding(40)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .offset(y: -proxy.size.height * 0.05)
        }
    }
}

private struct LeafletLogo: View {
    private static let image = ResourceLoader
        .url(named: "LeafletLogo", extension: "png")
        .flatMap(NSImage.init(contentsOf:))

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Text("Leaflet")
                    .font(.system(size: 28, weight: .semibold))
            }
        }
        .frame(width: 203, height: 65)
        .accessibilityLabel("Leaflet")
    }
}
