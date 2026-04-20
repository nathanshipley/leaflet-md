# Leaflet v0.1.0-beta.1

Leaflet is a simple native macOS Markdown reader with pretty Slack pasting.

This first beta is for friends/testers on Apple Silicon Macs running macOS 13 or newer. It is intentionally small: open Markdown, read it nicely, find/select what you need, and copy it into Slack without wrecking the formatting.

## What Leaflet Does

- Opens Markdown and plain text files in a native Mac document window
- Shows a clean rendered Preview and a raw Code view
- Supports Find, tabs, drag/drop, Open Recent, and Reload
- Creates temporary documents from clipboard Markdown
- Copies rich Markdown into Slack with formatting preserved

The marquee feature is **Copy for Slack**. It is designed to preserve nested lists, inline styles, code blocks, blockquotes, and tables in both Slack desktop and Slack in Chrome.

Leaflet is **not** a Markdown editor. Opened files are read-only by design. Think "Preview/TextEdit for Markdown, with much better Slack paste."

## Download

Download:

```text
Leaflet-v0.1.0-beta.1-macOS-arm64.zip
```

Unzip it, move `Leaflet.app` to Applications, and open it.

If macOS says the app is from an unidentified developer, Control-click `Leaflet.app`, choose **Open**, then choose **Open** again. This warning is expected for this early beta because it is not notarized yet.

## What To Test (if you have a sec!)

- Open a Markdown file and switch between Preview and Code
- Try Find with `Command-F` and `Command-G`
- Try New from Clipboard
- Try Copy for Slack into Slack desktop or Slack in Chrome
- If you hit anything weird, send me a screenshot or the Markdown that broke

## Known Limitations

- Apple Silicon only for this beta
- macOS 13+
- Not notarized yet, so macOS may show a first-launch warning
- Opened files are read-only
- Slack paste depends on Slack's current clipboard behavior

## Feedback

If something breaks, please send your macOS version, whether you used Slack desktop or browser Slack, and a screenshot or sample Markdown if you have one.

Thank you for testing. This is still early, but the core workflow is feeling surprisingly sturdy.
