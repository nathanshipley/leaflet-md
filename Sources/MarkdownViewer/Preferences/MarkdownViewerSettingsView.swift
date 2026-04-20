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
                Toggle(
                    "Flatten copied tables instead of using code blocks",
                    isOn: $preferences.flattenSlackTables
                )

                Text(preferences.flattenSlackTables
                     ? "Slack copy uses readable label-and-value table rows."
                     : "Slack copy uses monospaced codeblock tables by default.")
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
}
