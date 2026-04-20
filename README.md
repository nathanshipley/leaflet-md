![Leaflet](icon/Leaflet_ReadmeLogo_320.png)

**A simple Markdown reader with pretty Slack pasting.**

Leaflet is a native macOS Markdown reader built around one very specific daily annoyance: getting Markdown into Slack without losing structure.

If you work in Markdown but live in Slack, Leaflet helps you:

- open a `.md` or text file
- preview it cleanly
- search, select, and copy just what you need
- paste into Slack with nested lists, code blocks, tables, and inline formatting intact

Think **TextEdit for Markdown**, with **first-class Slack paste**. Leaflet is intentionally **not** a Markdown editor. It is for viewing, selecting, searching, and copying Markdown with native Mac document behavior.

> Friend-testing beta: Apple Silicon Macs, macOS 13+, unsigned GitHub builds.

## Downloading the beta

The first friend-testing release is distributed as a GitHub pre-release zip:

[![Leaflet app icon](icon/Leaflet_AppIcon_44.png) **Leaflet-v0.1.0-beta.1-macOS-arm64.zip**](https://github.com/nathanshipley/leaflet-md/releases/download/v0.1.0-beta.1/Leaflet-v0.1.0-beta.1-macOS-arm64.zip)

This beta is:

- for Apple Silicon Macs only
- for macOS 13 or newer
- unsigned/ad-hoc signed
- not notarized
- not an App Store build

To open the beta:

1. Download and unzip the release.
2. Move `Leaflet.app` to Applications.
3. Open the app.
4. If macOS says it is from an unidentified developer, Control-click `Leaflet.app`, choose **Open**, then choose **Open** again.

That warning is expected for this early testing build. Official Apple signing, notarization, and App Store packaging are intentionally deferred.

## Why this exists

Most Markdown tools lean hard in one of two directions:

- full editors with lots of writing UI
- browser-based previewers that do not feel native on macOS

Leaflet is something smaller and more opinionated:

> a lightweight, native Mac document app for Markdown reading and Slack sharing

The app is meant to feel closer to **Preview**, **TextEdit**, or **Marked** than to a code editor, but with a much stronger "share this to Slack cleanly" identity.

## The big promise

The signature feature is **Copy for Slack**.

Instead of flattening your Markdown into a messy paste, Leaflet writes Slack's rich clipboard format so your paste can preserve:

- bold, italic, strikethrough, and inline code
- nested bullet and ordered lists
- blockquotes
- fenced code blocks
- tables

It works with both:

- Slack in the browser
- the Slack desktop app

## Current feature set

### Copy for Slack

Use `Copy for Slack` when you want Slack-specific clipboard output instead of a generic paste.

It supports:

- whole-document copy
- partial selection copy from Preview
- raw Markdown selection copy from Code view
- browser Slack and desktop Slack

### Native document behavior

- open Markdown and text files in normal macOS document windows
- support tabs and separate windows
- `Open Recent`
- drag and drop files onto the app or an existing window
- bring already-open documents to the front instead of duplicating them
- optional warning before quitting

### Two ways to look at a document

- **Preview** for rendered Markdown
- **Code** for the raw source

Preview is rendered with a local GitHub-flavored Markdown pipeline, so it feels familiar and readable.

### Read-only find

- `Cmd-F` opens a slim in-window find bar
- `Cmd-G` / `Shift-Cmd-G` navigate matches
- works in both Preview and Code

### Export and sharing

- save a Markdown copy
- export HTML
- export PDF

### Display preferences

- preview font presets
- margin size presets
- wider reading mode for large windows
- Slack table copy mode

## What to test in the beta

If you are helping test, please try:

- opening Markdown files
- Preview and Code view
- `Command-F`, `Command-G`, and `Shift-Command-G`
- `Reload` after editing a file outside the app
- `New from Clipboard`
- saving a clipboard-created document
- `Copy for Slack` into Slack desktop
- `Copy for Slack` into Slack in Chrome

The most important Slack cases:

- nested bullet lists
- nested ordered lists
- bold, italic, strikethrough, and inline code
- fenced code blocks
- blockquotes
- tables

Please send:

- macOS version
- Mac model and chip
- Slack desktop or browser version
- whether macOS blocked first launch
- screenshot or sample Markdown for anything that fails

More details are in [docs/RELEASE_TESTING.md](docs/RELEASE_TESTING.md).

## What the app is not

- not a Markdown editor
- not a notes database
- not a publishing tool
- not an Electron shell

The project goal is a **small, native, focused Mac app** built around reading, selecting, and sharing Markdown well.

## Samples

The repo includes sample files you can use to kick the tires:

- [Samples/slack-export-kitchen-sink.md](Samples/slack-export-kitchen-sink.md)
- [Samples/slack-export-table-demo.md](Samples/slack-export-table-demo.md)
- [Samples/slack-export-test.md](Samples/slack-export-test.md)
- [Samples/second-window-demo.md](Samples/second-window-demo.md)

The Slack samples are especially useful for testing:

- `Copy for Slack`
- Preview vs Code behavior
- nested list rendering
- table handling

## Tech notes

- Swift Package Manager app
- macOS 13+
- AppKit document shell
- SwiftUI for the main document UI
- `WKWebView` for rendered preview
- `swift-cmark` / GFM rendering pipeline

## Running locally

### Build and package the app

```bash
./scripts/package_app.sh
```

This is the preferred path because it:

- builds the app
- refreshes the app bundle
- updates bundled resources
- touches the app bundle so macOS sees the new build

### Open the packaged app

```bash
open Leaflet.app
```

Or use:

```bash
./Try\ Leaflet.command
```

### Run tests

```bash
swift test
```

### Build a beta release zip

```bash
./scripts/build_release_zip.sh
```

This creates:

```text
release/Leaflet-v0.1.0-beta.1-macOS-arm64.zip
release/Leaflet-v0.1.0-beta.1-macOS-arm64.zip.sha256
```

### Create a clean public repo snapshot

```bash
./scripts/create_public_snapshot.sh
```

This creates a curated local repo at:

```text
release/Leaflet-public
```

It excludes scratch samples, old handoff docs, build products, and experimental icon files.

## Repo layout

```text
Sources/
  MarkdownViewer/         Core app code
  MarkdownViewerApp/      Entry point
Tests/
  MarkdownViewerTests/    Test suite
Samples/                  Demo Markdown files
docs/                     Project notes and handoff history
scripts/                  Build and utility scripts
tools/                    Small debugging / support tools
```

The internal Swift package, module, and folder names still use `MarkdownViewer` for now. The public product name is Leaflet.

## State of the project

The app now has:

- a stable native document architecture
- strong Slack copy support
- clean code-view copying
- a working read-only find feature

The most likely next phase is:

- branding
- screenshots
- release notes
- first-round friend testing
- signing/notarization research after the beta proves useful

## Known beta limitations

- The first GitHub release artifact is Apple Silicon only.
- The app is unsigned/ad-hoc signed and not notarized.
- The app is not sandboxed for Mac App Store distribution yet.
- Slack copy relies on Slack's current Chromium/Quill clipboard behavior.
- This is a viewer, not an editor; opened files are intentionally read-only.

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

If you fork or distribute a modified version, please preserve the license and notice files and make it clear that your version has been modified from the original Leaflet project.

Third-party dependency and font notes are tracked in [docs/THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md).
