//
//  BundleDocument.swift
//  AstroPup Horizon
//
//  The Codable representation of a `.horizon` package's `bundle.json`.
//  Holds the entire structured content of the bundle: top-level
//  metadata, the (optional) horizon points, the (optional) panorama
//  manifests, and the (optional) source-frame manifests. Binary
//  assets (pano PNGs, frame JPEGs) live as sibling files in the
//  bundle directory; this document indexes them by filename.
//
//  Schema is documented in `HORIZON_BUNDLE_FORMAT.md` at the repo
//  root — that doc is the source of truth, this type is one
//  implementation of it.
//

import Foundation

/// The on-disk `bundle.json` document. Top-level fields are bundle
/// metadata (single source of truth — no duplicates allowed in
/// sibling files); nested `horizon` / `panos` / `frames` hold the
/// optional structured content.
public struct BundleDocument: Codable, Equatable, Sendable {

    // MARK: - Top-level metadata

    /// Schema version this bundle was written against. Readers MUST
    /// refuse to open bundles with `formatVersion` newer than they
    /// understand.
    public var formatVersion: Int

    /// User-visible name. Single source of truth — readers MUST NOT
    /// look elsewhere.
    public var name: String

    /// When the source frames were shot. Immutable after capture —
    /// never updated by edit / re-analyze / rename. Optional so
    /// bundles authored without a capture event (e.g. HRZ imports)
    /// can omit it.
    public var capturedAt: Date?

    /// Last modification (any change). Writers SHOULD bump this on
    /// every save when known; readers MUST tolerate absence.
    public var modifiedAt: Date?

    /// Capture coordinates (WGS84). Absent when location wasn't
    /// available at capture.
    public var captureLocation: Location?

    /// Degrees to add to AR-session-local azimuths to recover
    /// true-north azimuths. Captured once at session start; never
    /// updated. Absent on bundles authored without an AR session.
    public var compassOffsetDegrees: Double?

    /// Free-form identifier of the writing program. Diagnostic only.
    public var appVersion: String?

    // MARK: - Optional content

    /// Horizon altitude points. Absent or nil when not yet analyzed.
    public var horizon: HorizonData?

    /// Panorama image manifests. Absent or empty when no panos.
    /// Display convention: the first entry is the preferred default.
    public var panos: [PanoEntry]?

    /// Source frame manifests. Absent or empty when source frames
    /// weren't retained.
    public var frames: [FrameEntry]?

    // MARK: - Init

    public init(
        formatVersion: Int = Self.currentFormatVersion,
        name: String,
        capturedAt: Date? = nil,
        modifiedAt: Date? = nil,
        captureLocation: Location? = nil,
        compassOffsetDegrees: Double? = nil,
        appVersion: String? = nil,
        horizon: HorizonData? = nil,
        panos: [PanoEntry]? = nil,
        frames: [FrameEntry]? = nil
    ) {
        self.formatVersion = formatVersion
        self.name = name
        self.capturedAt = capturedAt
        self.modifiedAt = modifiedAt
        self.captureLocation = captureLocation
        self.compassOffsetDegrees = compassOffsetDegrees
        self.appVersion = appVersion
        self.horizon = horizon
        self.panos = panos
        self.frames = frames
    }

    /// The latest format version this build understands.
    public static let currentFormatVersion: Int = 1

    // MARK: - Nested types

    public struct Location: Codable, Equatable, Sendable {
        public var latitude: Double
        public var longitude: Double

        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    /// The horizon-altitude data. Points may be sparse — covering
    /// only a subset of azimuths is valid and useful.
    public struct HorizonData: Codable, Equatable, Sendable {
        public var points: [Point]

        public init(points: [Point]) {
            self.points = points
        }

        public struct Point: Codable, Equatable, Sendable {
            /// Compass azimuth, 0–359°, where 0 = true north.
            public var azimuth: Int
            /// Degrees above the true horizontal (perpendicular to
            /// local gravity). Positive = above level; negative = below.
            public var altitude: Double

            public init(azimuth: Int, altitude: Double) {
                self.azimuth = azimuth
                self.altitude = altitude
            }
        }
    }

    /// One panorama image's manifest entry. The image file itself
    /// (PNG or JPEG) lives at `bundle/<filename>`.
    public struct PanoEntry: Codable, Equatable, Sendable {
        /// Bare filename at the bundle root. Writer's choice;
        /// readers MUST trust this field rather than enumerate the
        /// directory.
        public var filename: String

        /// Open-string kind. See `Kind` for recognised values.
        /// Unknown values: readers should treat as "unknown" rather
        /// than reject the bundle.
        public var kind: String

        /// Open-string projection. See `Projection` for recognised
        /// values. Unknown values: readers may skip displaying this
        /// pano but MUST NOT reject the bundle.
        public var projection: String

        /// Altitude (degrees) at the bottom edge of the image.
        public var altitudeMin: Double

        /// Altitude (degrees) at the top edge of the image.
        public var altitudeMax: Double

        public init(
            filename: String,
            kind: String,
            projection: String,
            altitudeMin: Double,
            altitudeMax: Double
        ) {
            self.filename = filename
            self.kind = kind
            self.projection = projection
            self.altitudeMin = altitudeMin
            self.altitudeMax = altitudeMax
        }

        /// Standard pano-kind values. The on-disk field is open
        /// string; these are the names recognised by AstroPup
        /// Horizon. Readers should tolerate other values.
        public enum Kind {
            /// Stitched from captured source frames.
            public static let photo = "photo"
            /// Rendered from `BundleDocument.horizon.points`.
            public static let synthetic = "synthetic"
        }

        /// Standard projection values. The on-disk field is open
        /// string; v1 only defines `equirectangular`.
        public enum Projection {
            /// Linear in azimuth across the full 360°, linear in
            /// altitude across `[altitudeMin, altitudeMax]`.
            public static let equirectangular = "equirectangular"
        }
    }

    /// One source frame's manifest entry. The image file (JPEG by
    /// convention) lives at `bundle/frames/<filename>`.
    public struct FrameEntry: Codable, Equatable, Sendable {
        /// Bare filename, relative to `frames/`. No `frames/` prefix.
        public var filename: String

        /// Wall-clock time this frame was shot.
        public var capturedAt: Date

        /// AR-session-local azimuth of the camera at capture time,
        /// degrees. Add `BundleDocument.compassOffsetDegrees` to
        /// recover true-north azimuth.
        public var azimuth: Double

        /// Camera pitch at capture time, degrees.
        public var altitude: Double

        /// Optional camera-calibration data. Required by the
        /// AstroPup Horizon analyzer for re-stitching / re-running
        /// the pipeline against a saved bundle; readers that don't
        /// perform back-projection (e.g. third-party planetarium
        /// imports) can ignore it. Writers that don't have a
        /// calibrated camera at capture time (e.g. an editor
        /// authoring a bundle from a HRZ import) omit it.
        public var camera: CameraData?

        public init(
            filename: String,
            capturedAt: Date,
            azimuth: Double,
            altitude: Double,
            camera: CameraData? = nil
        ) {
            self.filename = filename
            self.capturedAt = capturedAt
            self.azimuth = azimuth
            self.altitude = altitude
            self.camera = camera
        }

        /// Per-frame camera + image dimensions needed to back-project
        /// image pixels to camera rays. Optional in the spec but
        /// required for the AstroPup Horizon analyzer.
        public struct CameraData: Codable, Equatable, Sendable {
            /// 3×3 row-major pinhole-camera intrinsics matrix in
            /// camera-buffer pixel coordinates. Order:
            /// `[fx, 0, cx, 0, fy, cy, 0, 0, 1]`.
            public var intrinsics: [Float]

            /// Width of the JPEG referenced by `FrameEntry.filename`,
            /// in pixels. (May be a downsampled view of
            /// `cameraBufferWidth`.)
            public var imageWidth: Double
            public var imageHeight: Double

            /// Pixel dimensions of the original camera sensor buffer
            /// the intrinsics were calibrated against.
            public var cameraBufferWidth: Double
            public var cameraBufferHeight: Double

            /// Pixel dimensions of the on-screen viewport the user
            /// saw at capture time. Used to map between camera-buffer
            /// coordinates and what the user pointed at. iOS-
            /// specific; not meaningful for non-iOS bundles.
            public var viewportWidth: Double
            public var viewportHeight: Double

            public init(
                intrinsics: [Float],
                imageWidth: Double, imageHeight: Double,
                cameraBufferWidth: Double, cameraBufferHeight: Double,
                viewportWidth: Double, viewportHeight: Double
            ) {
                self.intrinsics = intrinsics
                self.imageWidth = imageWidth
                self.imageHeight = imageHeight
                self.cameraBufferWidth = cameraBufferWidth
                self.cameraBufferHeight = cameraBufferHeight
                self.viewportWidth = viewportWidth
                self.viewportHeight = viewportHeight
            }
        }
    }
}
