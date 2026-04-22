<p align="center">
  <img src="icon/Logo_Horizontal_v3.png" alt="Leaflet" width="490">
</p>

**A simple Markdown reader with pretty Slack pasting.**

Leaflet is a native macOS Markdown reader built around one daily annoyance: getting Markdown into Slack without losing structure.

It is intentionally **not** a Markdown editor. Think TextEdit or Preview for Markdown, with first-class Slack paste.

## Download the beta

<table>
  <tr>
    <td width="64">
      <a href="https://github.com/nathanshipley/leaflet-md/releases/download/v0.1.0-beta.2/Leaflet-v0.1.0-beta.2-macOS-arm64.zip">
        <img src="icon/IconCompose_02-macOS-Default-1024x1024@1x.png" alt="Leaflet app icon" width="52">
      </a>
    </td>
    <td>
      <a href="https://github.com/nathanshipley/leaflet-md/releases/download/v0.1.0-beta.2/Leaflet-v0.1.0-beta.2-macOS-arm64.zip">
        <strong>Download Leaflet v0.1.0-beta.2 for macOS</strong>
      </a>
      <br>
      Apple Silicon Macs, macOS 13+, unsigned friend-testing beta.
    </td>
  </tr>
</table>

To open the beta:

1. Download and unzip the release.
2. Move `Leaflet.app` to Applications.
3. Open the app.
4. If macOS blocks it, Control-click `Leaflet.app`, choose **Open**, then choose **Open** again.

That warning is expected for this early build. Developer ID signing, notarization, and App Store packaging are intentionally deferred.

## What Leaflet does

- Opens Markdown and plain text files in native Mac document windows
- Shows a clean rendered Preview and a raw Code view
- Supports Find, tabs, drag/drop, Open Recent, and Reload
- Creates temporary documents from clipboard Markdown
- Copies rich Markdown into Slack with nested lists, code blocks, tables, and inline formatting intact

The signature feature is **Copy for Slack**. It writes Slack's rich clipboard format so pastes can preserve structure in both Slack desktop and Slack in Chrome.

## What To Test (if you have a sec!)

- Open a Markdown file and switch between Preview and Code
- Try Find with `Command-F` and `Command-G`
- Try New from Clipboard
- Try Copy for Slack into Slack desktop or Slack in Chrome
- If anything looks weird, send a screenshot or the Markdown that broke

## Known limitations

- Apple Silicon only for this beta
- macOS 13+
- Not notarized yet, so macOS may show a first-launch warning
- Opened files are read-only by design
- Slack paste depends on Slack's current clipboard behavior

## Development

Open `Leaflet.xcodeproj` in Xcode and press Run to build and launch the app. Requires Xcode 26 or newer on macOS 15+.

Unit tests run from the command line:

```bash
swift test
```

The public product name is Leaflet. Some internal Swift package, module, and folder names still use `MarkdownViewer` for now.

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

If you fork or distribute a modified version, please preserve the license and notice files and make it clear that your version has been modified from the original Leaflet project.
