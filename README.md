# AstroPupHorizonBundle

A Swift package implementing the `.horizon` file-system bundle format
— a portable container for a 360° altitude profile of the local
horizon, optionally bundled with the panoramic image used to derive
it, the source frames captured by a phone, and observing-site
metadata (location, capture date, compass calibration offset).

The format is intentionally simple, human-inspectable (everything is
either JSON or a standard image format), and version-tagged. It's
designed for sharing observing horizons between astronomy /
planetarium apps that today each use their own ad-hoc HRZ variants.

See [`HORIZON_BUNDLE_FORMAT.md`](./HORIZON_BUNDLE_FORMAT.md) for the
on-disk spec; this package is the reference Swift implementation.

## What's inside

- `HorizonBundle` — domain-shaped read/write API around a single
  `.horizon` directory. Throwing computed properties for reads,
  async mutators for writes, ObservableObject for SwiftUI.
- `BundleStore` — observe + create + import + rename + delete the
  bundles in a given directory.
- `BundleDocument` — Codable shape of `bundle.json`.
- `HorizonBundleError` — typed errors.
- `Horizon`, `HorizonPoint` — 360-point altitude profile type.
- `PlatformImage` — UIImage/NSImage typealias + ImageIO encoders so
  the package compiles on both iOS and macOS.

The package is platform-agnostic about *where* the bundles live.
`BundleStore` takes a base URL and works the same against any
writable directory the host app chooses to point it at.

## Platforms

- iOS 26+
- macOS 15+

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

Semantic versioning on the package. The bundle format version is
independent of the package version — see the spec for the on-disk
format-version field and migration rules.

## Running tests

```bash
swift test
```

GitHub Actions also runs the tests on every push.

## License

MIT — see [LICENSE](./LICENSE).
