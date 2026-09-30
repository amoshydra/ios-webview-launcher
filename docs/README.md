# Screenshots

Captured from the simulator and a physical Android device; the numbers quoted in
the README are the readout of
[`amoshydra/demo-viewport`](https://amoshydra.github.io/demo-viewport/?fit=cover),
not the launcher's own.

| File | What it shows |
|---|---|
| `settings.webp` | `SettingsView`, edge to edge on, `150/40/180/40` entered |
| `override-off.webp` | Loaded page, no override — reports the real `62/0/34/0` |
| `override-on.webp` | Same page with the override applied — reports `150 40 180 40` |
| `duo-outer-portrait.webp` | iPhone Duo folded, outer display, portrait |
| `duo-outer-landscape.webp` | iPhone Duo folded, outer display, landscape |
| `duo-inner-unfolded.webp` | iPhone Duo unfolded to the inner display |

## Environment

- iPhone 16 Pro, iOS 18.6 simulator, Xcode 27.0, dpr 3 — `settings`,
  `override-off`, `override-on`
- iPhone Duo, iOS 27.1 simulator — the three `duo-*` images

## Regenerating

The iPhone 16 Pro shots come straight from the simulator:

```bash
UDID=<iPhone 16 Pro udid>
xcodebuild -project WebViewLauncher.xcodeproj -scheme WebViewLauncher \
  -sdk iphonesimulator -configuration Debug -destination "id=$UDID" \
  build CODE_SIGNING_ALLOWED=NO

APP=$(find ~/Library/Developer/Xcode/DerivedData/WebViewLauncher-*/Build/Products/Debug-iphonesimulator -name 'WebViewLauncher.app' -maxdepth 1)
xcrun simctl uninstall $UDID com.amoshydra.iosapp 2>/dev/null
xcrun simctl install $UDID "$APP"

xcrun simctl spawn $UDID defaults write com.amoshydra.iosapp url -string 'https://amoshydra.github.io/demo-viewport/?fit=cover'
xcrun simctl spawn $UDID defaults write com.amoshydra.iosapp edgeToEdge -bool true
# blank the four inset fields for override-off, or set them for override-on
xcrun simctl spawn $UDID defaults write com.amoshydra.iosapp insetTop -string '150'
xcrun simctl spawn $UDID defaults write com.amoshydra.iosapp insetRight -string '40'
xcrun simctl spawn $UDID defaults write com.amoshydra.iosapp insetBottom -string '180'
xcrun simctl spawn $UDID defaults write com.amoshydra.iosapp insetLeft -string '40'

# omit ENV_PROBE to land on the settings screen
SIMCTL_CHILD_ENV_PROBE=1 xcrun simctl launch $UDID com.amoshydra.iosapp
xcrun simctl io $UDID screenshot docs/override-on.png
```

Uninstall before re-seeding: relaunching an already-running app reuses the
existing `WKWebView` and the cached `@AppStorage` values, so the old settings
stick and the screenshot is of the previous run.

**The three Duo images come from a screen recording, not `simctl`.** Rotation and
folding cannot be driven headlessly — relaunching, the demo page's own rotate
button and `SBOrientationLockOverride` all leave the device in portrait — and the
native capture renders the bare screen with no device chassis. Crop the frames to
the device by bounding-boxing dark pixels against the white background, scanning
only the top 85% of the frame so the recorder's toolbar stays out. Worked-out
crops: `565x777+458+222` portrait, `773x561+356+334` landscape,
`1015x779+234+222` unfolded.

Scale with `sips -Z 1200` (fits within the box, preserves aspect ratio) and encode
with `cwebp -q 84`. Do not use `sips -c`, which forces exact dimensions and
stretches a screenshot taken on a device with a different resolution.
