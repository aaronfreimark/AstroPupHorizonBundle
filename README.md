# AstroPupHorizonBundle

Shared storage model for the AstroPup family of iOS apps.

Defines the on-disk `.horizon` bundle format (a file-system package
containing `bundle.json` + optional pano images + optional frames)
and the Swift API both apps use to read, write, and observe those
bundles.

## Who uses it

| App | Role |
|---|---|
| **AstroPup Horizon** | Authors bundles: captures frames, analyzes them, stitches panoramas. |
| **AstroPup Sky**     | Reads + writes bundles as observing sites; may add a horizon, may attach app-specific sidecars (e.g. favorite DSOs). |

Both apps target the same iCloud Drive container, so a bundle
created in one shows up in the other (and on every device signed
into the same iCloud account).

## Public API

```swift
import AstroPupHorizonBundle

// Observe the set of bundles in a directory.
let store = BundleStore(baseDirectory: capturesDirectory)
store.bundles  // [HorizonBundle]

// Create / mutate / read.
let bundle = try await store.createBundle(name: "Backyard")
try await bundle.setCaptureLocation(.init(latitude: 41.42, longitude: -73.95))
try await bundle.setHorizon(points: [...])

// Bundles are @MainActor ObservableObjects — SwiftUI views observing
// `store.bundles` or an individual bundle redraw on mutation.
```

See [`HORIZON_BUNDLE_FORMAT.md`](./HORIZON_BUNDLE_FORMAT.md) for the
on-disk schema, and [`INTEGRATION.md`](./INTEGRATION.md) for
instructions on adopting the package in a new app.

## Versioning

Semantic versioning. Pinned via tag in each consuming app's
`Package.resolved`. During package development, use Xcode's
"Use Local Package" override to iterate without round-tripping
through GitHub.

## Running tests

```bash
swift test
```

The package also runs as part of each consuming app's Xcode test
suite via its SPM dependency.
