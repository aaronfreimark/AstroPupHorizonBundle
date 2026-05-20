// swift-tools-version: 6.2
//
// AstroPupHorizonBundle — shared storage model for AstroPup apps.
//
// Two iOS apps consume this package:
//   • AstroPup Horizon — captures + analyzes horizon profiles.
//   • AstroPup Sky     — observing-site planner.
//
// The package owns the on-disk `.horizon` bundle format (see
// HORIZON_BUNDLE_FORMAT.md in this repo's root), the storage layer
// (`HorizonBundle` / `BundleStore`), and the shared data model
// (`Horizon` + `HorizonPoint`). App-specific UI / capture / chart
// code stays in each app's project.
//

import PackageDescription

let package = Package(
    name: "AstroPupHorizonBundle",
    platforms: [
        // Multi-platform from day one: future-compatible with a Mac
        // consumer of `.horizon` bundles via iCloud Drive sync.
        .iOS(.v26),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "AstroPupHorizonBundle",
            targets: ["AstroPupHorizonBundle"]
        ),
    ],
    targets: [
        .target(
            name: "AstroPupHorizonBundle",
            path: "Sources/AstroPupHorizonBundle"
        ),
        .testTarget(
            name: "AstroPupHorizonBundleTests",
            dependencies: ["AstroPupHorizonBundle"],
            path: "Tests/AstroPupHorizonBundleTests"
        ),
    ]
)
