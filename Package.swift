// swift-tools-version: 6.2
//
// AstroPupHorizonBundle — Swift implementation of the `.horizon`
// file-system bundle format for sharing 360° horizon profiles
// between astronomy / planetarium apps. See README.md and
// HORIZON_BUNDLE_FORMAT.md.
//

import PackageDescription

let package = Package(
    name: "AstroPupHorizonBundle",
    platforms: [
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
