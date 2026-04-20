# Beta Testing Checklist

Use this checklist for the `v0.1.0-beta.1` friends-and-family GitHub release.

## Supported Beta Target

- Apple Silicon Macs only for this first artifact.
- macOS 13 or newer.
- Unsigned/ad-hoc build distributed by GitHub zip.
- Not notarized, not App Store sandboxed, and not intended for broad public release yet.

## Install Test

1. Download `Leaflet-v0.1.0-beta.1-macOS-arm64.zip`.
2. Unzip it.
3. Move `Leaflet.app` to Applications.
4. Open the app.
5. If Gatekeeper blocks it, Control-click the app, choose **Open**, then confirm **Open**.

## Functional Smoke Test

- Open `Samples/slack-export-kitchen-sink.md`.
- Switch between Preview and Code.
- Use `Command-F`, `Command-G`, and `Shift-Command-G`.
- Edit the file externally, then press Reload.
- Create a blank tab/window and use New From Clipboard.
- Save a clipboard-created document.
- Confirm opened documents remain read-only.

## Slack Copy Test

Test both Slack desktop and Slack in Chrome if available.

- Copy a whole document with Copy for Slack.
- Select a subsection in Preview and Copy for Slack.
- Select raw Markdown in Code view and Copy for Slack.
- Confirm Slack preserves:
  - nested bullet lists
  - nested ordered lists
  - bold, italic, strikethrough, and inline code
  - fenced code blocks
  - blockquotes
  - tables

## Feedback To Collect

- macOS version.
- Mac model and chip.
- Slack desktop version, if tested.
- Browser and version, if Slack web was tested.
- Whether first launch required Gatekeeper workarounds.
- Screenshots or sample Markdown for any failure.
