# App Icon Pipeline

This project is a SwiftPM executable manually bundled by `scripts/package_app.sh`. There is no Xcode project or asset catalog build phase, so the icon pipeline is handled separately.

## Current pipeline (Liquid Glass + fallback)

The app ships two icon assets:
- **`Assets.car`** — compiled directly from the `.icon` file. Contains the full Liquid Glass icon with all appearance variants (light, dark, tinted). Used by macOS 26+ via `CFBundleIconName`.
- **`AppIcon.icns`** — compiled from a PNG export. Flat pre-Tahoe icon used as fallback on macOS 13–15 via `CFBundleIconFile`.

### Rebuilding the icon

When the icon design changes:

1. Save the design in **Icon Composer** (`icon/IconCompose_02.icon`)

2. **Build `Assets.car`** (Liquid Glass — all appearances):
   ```bash
   mkdir -p /tmp/IconBuild
   xcrun actool icon/IconCompose_02.icon \
     --compile /tmp/IconBuild \
     --output-format human-readable-text \
     --notices --warnings --errors \
     --output-partial-info-plist /tmp/icon-partial.plist \
     --app-icon AppIcon \
     --include-all-app-icons \
     --enable-on-demand-resources NO \
     --development-region en \
     --target-device mac \
     --minimum-deployment-target 26.0 \
     --platform macosx
   cp /tmp/IconBuild/Assets.car Support/Assets.car
   ```

3. **Build `AppIcon.icns`** (pre-Tahoe fallback):
   - Export a PNG from Icon Composer: File > Export Icon as PNG, Platform: **macOS pre-Tahoe**, Size: 1024pt 1x, Appearance: Default
   - Compile with `actool`:
     ```bash
     mkdir -p /tmp/IcnsBuild/AppIcon.xcassets/AppIcon.appiconset
     mkdir -p /tmp/IcnsBuild/output

     cp icon/IconCompose_02-macOS-Default-1024x1024@1x.png \
        /tmp/IcnsBuild/AppIcon.xcassets/AppIcon.appiconset/icon_512x512@2x.png

     cat > /tmp/IcnsBuild/AppIcon.xcassets/AppIcon.appiconset/Contents.json << 'EOF'
     {
       "images": [
         {
           "filename": "icon_512x512@2x.png",
           "idiom": "mac",
           "scale": "2x",
           "size": "512x512"
         }
       ],
       "info": { "author": "xcode", "version": 1 }
     }
     EOF

     cat > /tmp/IcnsBuild/AppIcon.xcassets/Contents.json << 'EOF'
     { "info": { "version": 1, "author": "xcode" } }
     EOF

     xcrun actool \
       --compile /tmp/IcnsBuild/output \
       --platform macosx \
       --minimum-deployment-target 13.0 \
       --app-icon AppIcon \
       --output-partial-info-plist /tmp/IcnsBuild/partial.plist \
       /tmp/IcnsBuild/AppIcon.xcassets

     cp /tmp/IcnsBuild/output/AppIcon.icns Support/AppIcon.icns
     ```

4. Run `./scripts/package_app.sh` — it copies both `Assets.car` and `AppIcon.icns` into the app bundle

### How Info.plist ties it together

```xml
<key>CFBundleIconName</key>
<string>AppIcon</string>     <!-- macOS 26+: looks in Assets.car for Liquid Glass icon -->

<key>CFBundleIconFile</key>
<string>AppIcon</string>     <!-- pre-Tahoe fallback: uses AppIcon.icns -->
```

## Key files

| File | Purpose |
|------|---------|
| `icon/IconCompose_02.icon` | Source icon (Icon Composer format) |
| `icon/IconCompose_02-macOS-Default-1024x1024@1x.png` | macOS PNG export (for `.icns` fallback) |
| `Support/Assets.car` | Compiled Liquid Glass icon (all appearances) |
| `Support/AppIcon.icns` | Compiled flat icon (pre-Tahoe fallback) |

## Notes

### Why `.icon` files couldn't compile before
Earlier attempts with `actool` silently produced empty output because the wrong flags were used. The critical flags for `.icon` compilation are `--target-device mac`, `--include-all-app-icons`, and `--minimum-deployment-target 26.0`. This requires Xcode 26+.

### iOS export vs macOS export (for `.icns` fallback PNG)
- **iOS-Default**: Full-bleed artwork filling the entire 1024x1024 canvas (iOS applies its own mask)
- **macOS pre-Tahoe**: Artwork with ~100px optical padding and drop shadow (current macOS style)

Always use the macOS export for the `.icns` fallback. The iOS export will appear oversized in the Dock.
