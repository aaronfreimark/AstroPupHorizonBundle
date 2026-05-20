# AstroPupHorizonBundle

A Swift package defining the `.horizon` file-system bundle format — a
portable container for a 360° altitude profile of the local horizon,
plus optional source frames, panoramas, and observing-site metadata.

Used by the [AstroPup](https://astropup.app) family of iOS apps:

| App | Role |
|---|---|
| **AstroPup Horizon** | Captures a 360° sweep, analyzes it, and writes the resulting `.horizon` bundle. |
| **AstroPup Sky**     | Reads and writes `.horizon` bundles as observing sites; lets users plan around the saved horizon. |

The package is the contract between them. Anyone else who wants to
read or produce `.horizon` files — whether that's planetarium
software, an Android port, a sharing service, or another app
entirely — can adopt the package directly, or implement the format
from the spec in [`HORIZON_BUNDLE_FORMAT.md`](./HORIZON_BUNDLE_FORMAT.md).

## What's inside

- `HorizonBundle` — domain-shaped read/write API around a single
  `.horizon` directory. Throwing computed properties for reads,
  async mutators for writes, ObservableObject for SwiftUI.
- `BundleStore` — observe + create + import + rename + delete the
  bundles in a given directory.
- `BundleDocument` — Codable shape of `bundle.json`.
- `HorizonBundleError` — typed errors.
- `Horizon`, `HorizonPoint` — slim 360-point altitude profile type.
- `PlatformImage` — UIImage/NSImage typealias + ImageIO encoders so
  the package compiles on both iOS and macOS.

Anything app-specific (capture pipeline, stitcher, depth-estimation
ML model, export adapters for Stellarium / SkySafari / NINA, SwiftUI
views) lives in the consuming app, not here.

## Platforms

- iOS 26+
- macOS 15+

The macOS support is forward-looking — when AstroPup's iCloud-Drive
sync ships, `.horizon` bundles will appear automatically in Finder
on Mac, ready for a future native consumer.

## Adding it

Xcode → File → Add Package Dependencies… → paste:

```
https://github.com/aaronfreimark/AstroPupHorizonBundle
```

…and pin to `Up to Next Major Version` from `0.1.0`.

```swift
import AstroPupHorizonBundle

let store = BundleStore(baseURL: capturesURL)
await store.refresh()

let bundle = try await store.createBundle(name: "Backyard")
try await bundle.setCaptureLocation(.init(latitude: 41.42, longitude: -73.95))
try await bundle.setHorizon(points: [...])
```

See [`INTEGRATION.md`](./INTEGRATION.md) for a deeper walk-through.

## Versioning

Semantic versioning. The bundle format version is independent of the
package version — see the spec for the on-disk format-version field
and migration rules.

## Running tests

```bash
swift test
```

GitHub Actions also runs the tests on every push.

## License

MIT — see [LICENSE](./LICENSE).
