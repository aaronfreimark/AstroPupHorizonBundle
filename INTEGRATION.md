# Integrating AstroPupHorizonBundle

Aimed at the Sky session / future consumers. Horizon is already wired
up; this doc captures the steps you'd run for a fresh app.

## 1. Add the package

In Xcode, with your app's project open:

1. **File** → **Add Package Dependencies…**
2. Paste the GitHub URL:
   ```
   https://github.com/aaronfreimark/AstroPupHorizonBundle
   ```
3. Dependency Rule: **Up to Next Major Version** from `0.1.0`.
4. Add to the relevant app target.
5. Verify `AstroPupHorizonBundle` shows up under Package Dependencies
   in the Project Navigator.

## 2. Local override during package development

If you're iterating on the package and want edits to take effect
without push/tag/update, drag the local checkout
(`/Users/aaron/src/AstroPupHorizonBundle/`) into the Xcode workspace
window's Project Navigator. Xcode automatically prefers a workspace-
embedded package over the remote dependency. Drag it back out when
you're done — the remote pin still works.

## 3. Use the API

```swift
import AstroPupHorizonBundle

@MainActor
final class SiteListViewModel: ObservableObject {
    let store: BundleStore
    @Published var bundles: [HorizonBundle] = []

    init(baseURL: URL) {
        self.store = BundleStore(baseURL: baseURL)
        Task { await store.refresh() }
    }
}
```

Common entry points:
- `BundleStore(baseURL:)` — observe + create + import + rename + delete.
- `HorizonBundle.create(at:name:capturedAt:captureLocation:...)` — author a new bundle.
- `bundle.setName(_:)` / `bundle.setCaptureLocation(_:)` / `bundle.setHorizon(points:)` — domain mutations.
- `bundle.image(for: pano)` / `bundle.image(for: frame)` — load image data.
- `bundle.panos` / `bundle.frames` / `bundle.horizon` — read accessors (throwing).

See `HORIZON_BUNDLE_FORMAT.md` for the on-disk format. Both apps
must speak the same format to interop cleanly — that's what this
package guarantees.

## 4. Shared storage location

For two apps from the same team to see the same bundles, they need
to point `BundleStore`'s `baseURL` at a shared container. The
recommended pattern (planned for AstroPup Horizon + AstroPup Sky):

```swift
let containerURL = FileManager.default
    .url(forUbiquityContainerIdentifier: "iCloud.app.astropup.horizons")!
    .appendingPathComponent("Documents/Captures", isDirectory: true)
let store = BundleStore(baseURL: containerURL)
```

This requires:
- Both apps share the same `iCloud.app.astropup.horizons` entitlement.
- `NSUbiquitousContainerIsDocumentScopePublic = YES` in each app's
  Info.plist so the container shows up in iCloud Drive in Files.app
  and Finder.

That work happens in each consuming app, not in this package — the
package is location-agnostic on purpose.
