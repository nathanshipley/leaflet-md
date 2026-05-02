import SwiftUI

public struct MarkdownViewerSettingsView: View {
    @EnvironmentObject private var preferences: MarkdownViewerPreferences

    public init() {}

    public var body: some View {
        Form {
            Section {
                Picker("Open Documents In", selection: $preferences.documentOpenMode) {
                    ForEach(DocumentOpenMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(preferences.documentOpenMode.settingsDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Documents")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Margin Size")
                        .font(.subheadline.weight(.semibold))

                    Picker("Margin Size", selection: $preferences.marginPreset) {
                        ForEach(PreviewMarginPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)

                Picker("Preview Font", selection: $preferences.fontPreset) {
                    ForEach(PreviewFontPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }

                Toggle("Allow text to use the full window width", isOn: $preferences.allowWideContent)

                Text(preferences.allowWideContent
                     ? "Lines and paragraphs can expand with very wide windows."
                     : "Lines keep a more page-like reading width even in very wide windows.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Preview")
            }

            Section {
                Toggle("Warn before quitting", isOn: $preferences.warnOnQuit)

                Text("Show a confirmation dialog when you press ⌘Q.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("General")
            }

            Section {
                Picker("Slack tables", selection: $preferences.slackTableMode) {
                    ForEach(SlackTableRenderingMode.allCases, id: \.self) { mode in
                        Text(mode.settingsLabel).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(slackTableModeDescription(preferences.slackTableMode))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Slack")
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .padding(20)
    }

    private func slackTableModeDescription(_ mode: SlackTableRenderingMode) -> String {
        switch mode {
        case .wrap:
            return "Slack copy always uses code-block tables. Wide tables get their cell content wrapped to multiple lines so the table fits without scrolling."
        case .flattenWide:
            return "Narrow tables stay as code-block tables. Wide tables get flattened into readable label-and-value rows."
        case .flattenAll:
            return "Slack copy always uses readable label-and-value rows, regardless of table width."
        }
    }
}
