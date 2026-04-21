# Leaflet v0.1.0-beta.1

First friend-testing beta for Apple Silicon Macs running macOS 13 or newer.

Download `Leaflet-v0.1.0-beta.1-macOS-arm64.zip`, unzip it, move `Leaflet.app` to Applications, and open it.

If macOS blocks the app because it is from an unidentified developer, Control-click `Leaflet.app`, choose **Open**, then choose **Open** again. This is expected for the early unsigned beta.

## Tahoe note

On macOS Tahoe, this unsigned beta may say **"Leaflet is damaged and can't be opened"** instead of showing the usual Open Anyway flow. If that happens, run:

```bash
xattr -dr com.apple.quarantine /Applications/Leaflet.app
```

Then open Leaflet again.

This removes the browser download quarantine flag from the app. A future notarized build should not require this.

Please send feedback with your macOS version, whether you used Slack desktop or browser Slack, and a screenshot or sample Markdown if something breaks.
