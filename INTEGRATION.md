# Integrating AstroPupHorizonBundle

How to adopt this package in a Swift app that wants to read or
write `.horizon` bundles. The format itself is documented in
[`HORIZON_BUNDLE_FORMAT.md`](./HORIZON_BUNDLE_FORMAT.md); this doc
covers wiring.

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

If you're iterating on the package itself and want edits to take
effect without push/tag/update, clone the package locally and drag
that checkout into the Xcode workspace window's Project Navigator.
Xcode automatically prefers a workspace-embedded package over the
remote dependency. Drag it back out when you're done — the remote
pin still works.

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
- `bundle.image(for: pano)` / `bundle.image(for: frame)` — load image data as `PlatformImage` (UIImage on iOS, NSImage on macOS).
- `bundle.panos` / `bundle.frames` / `bundle.horizon` — read accessors (throwing).

## 4. Shared storage across apps + devices

For multiple apps from the same developer team to see the same
bundles — and for bundles to sync across devices — point
`BundleStore`'s `baseURL` at an **iCloud Drive ubiquity container**
shared between the apps:

```swift
let containerURL = FileManager.default
    .url(forUbiquityContainerIdentifier: "iCloud.your.app.identifier")!
    .appendingPathComponent("Documents/Captures", isDirectory: true)
let store = BundleStore(baseURL: containerURL)
```

Requirements in each app's target:
- iCloud capability with the same `iCloud.your.app.identifier`
  container ID.
- `NSUbiquitousContainerIsDocumentScopePublic = YES` in Info.plist
  if you want the bundles to also appear in iCloud Drive in
  Files.app / Finder.

This work happens in each consuming app, not in the package —
`BundleStore` is location-agnostic on purpose.

## 5. Custom sidecars

Bundles are package directories. Each app can add sidecar files
alongside `bundle.json` for app-specific data (e.g. an editor's
undo state, a planner's favorite-objects list). The package
exposes `bundle.undoData` / `bundle.setUndoData` as a model;
follow the same pattern for your own sidecar.

Sidecars don't go into the shared `BundleDocument` schema — apps
that don't know about them simply ignore them.
