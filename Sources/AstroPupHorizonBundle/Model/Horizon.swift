//
//  Horizon.swift
//  AstroPupHorizonBundle
//
//  In-memory representation of a 360°-sampled horizon: exactly 360
//  `HorizonPoint`s, one per integer azimuth. After the storage-layer
//  rewrite the class is a pure list-of-points; all surrounding
//  metadata (name, capture date, location, modification times) lives
//  on the `HorizonBundle` that owns the points. Adapters at the
//  boundaries (`Horizon.from(bundle:)` + `HorizonExportMetadata.from(bundle:)`)
//  marshal data across the seam.
//
//  Not `@Observable` — individual `HorizonPoint`s are observed
//  individually, and cascading the whole horizon at every point edit
//  would force every chart row to redraw.
//

import Foundation
import SwiftUI
import simd
import Combine

nonisolated public class Horizon: Codable {

    // MARK: - HorizonBundle bridge

    /// Build an in-memory Horizon class instance from a HorizonBundle.
    /// Used by the chart / exports / editor; metadata stays on the
    /// bundle and is read separately via `HorizonExportMetadata.from`
    /// or `bundle.name` / `bundle.capturedAt` directly.
    @MainActor
    public static func from(bundle: HorizonBundle) -> Horizon {
        let h = Horizon()
        if let points = (try? bundle.horizon)?.points {
            for p in points {
                h.setAltitude(at: p.azimuth, altitude: p.altitude)
            }
        }
        return h
    }

    // MARK: - Constants

    /// Total number of azimuth points (0-359 degrees)
    public static let totalPoints = 360

    // MARK: - Data Properties

    /// Array of 360 horizon points, indexed by azimuth (0-359°)
    public private(set) var points: [HorizonPoint] = []

    // MARK: - Initialization

    /// Initialize with all 360 points at 0° altitude (default flat horizon)
    public init() {
        // Initialize all 360 points with default values
        self.points = (0..<Self.totalPoints).map { azimuth in
            HorizonPoint(azimuth: azimuth, altitude: 0.0)
        }
    }


    // MARK: - Point Management

    /// Get point at specific azimuth (0-359°)
    public func getPoint(at azimuth: Int) -> HorizonPoint? {
        guard azimuth >= 0 && azimuth < Self.totalPoints else { return nil }
        return points[azimuth]
    }

    /// Write `altitude` at `azimuth`. Returns `true` iff the azimuth
    /// was in range AND the altitude actually changed — a no-op write
    /// (identical altitude) is rejected. Cross-frame deduplication
    /// that used to happen here with uppermost-wins semantics is now
    /// handled upstream in the analyzer's per-fine-az max pass, so
    /// this method is symmetric: a smaller incoming altitude
    /// overwrites a larger existing one. The manual editor relies on
    /// that symmetry so the user can drag a point in either direction.
    @discardableResult
    public func updatePoint(at azimuth: Int, altitude: Double) -> Bool {
        guard azimuth >= 0 && azimuth < Self.totalPoints else { return false }
        if points[azimuth].altitude == altitude { return false }
        points[azimuth].altitude = altitude
        return true
    }

    /// Update point using azimuth as Double (will be rounded to nearest integer)
    /// Returns true if the point was actually changed, false if values were identical
    @discardableResult
    public func updatePoint(azimuth: Double, altitude: Double) -> Bool {
        let roundedAzimuth = Int(azimuth.rounded()) % Self.totalPoints
        let normalizedAzimuth = roundedAzimuth < 0 ? roundedAzimuth + Self.totalPoints : roundedAzimuth
        return updatePoint(at: normalizedAzimuth, altitude: altitude)
    }

    /// Void variant of `updatePoint(at:altitude:)`. Kept as a separate
    /// name purely for caller-site readability — the editor reads
    /// better as `setAltitude(...)` than `_ = updatePoint(...)`.
    public func setAltitude(at azimuth: Int, altitude: Double) {
        _ = updatePoint(at: azimuth, altitude: altitude)
    }

    /// Reset every point's altitude to 0° (flat horizon).
    public func resetAllPoints() {
        for i in 0..<Self.totalPoints {
            points[i].altitude = 0.0
        }
    }

    // MARK: - Statistics & Analysis

    /// Get minimum altitude from all points
    public var minAltitude: Double? {
        return points.map { $0.altitude }.min()
    }

    /// Get maximum altitude from all points
    public var maxAltitude: Double? {
        return points.map { $0.altitude }.max()
    }

    // MARK: - Codable
    //
    // The slim Horizon only encodes/decodes `points`. The old
    // metadata fields (name, dates, location) live on
    // HorizonBundle now and the bundle's JSON owns them.

    private enum CodingKeys: String, CodingKey {
        case points
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Initialize points array with defaults so any missing
        // azimuths fall through as 0°.
        self.points = (0..<Self.totalPoints).map { azimuth in
            HorizonPoint(azimuth: azimuth, altitude: 0.0)
        }

        // Decode points array and overwrite matching indices.
        let decodedPoints = try container.decodeIfPresent([HorizonPoint].self, forKey: .points) ?? []
        for point in decodedPoints where point.azimuth >= 0 && point.azimuth < Self.totalPoints {
            self.points[point.azimuth] = point
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Encode every point — the data structure no longer carries
        // an "unmeasured" sentinel, so 0° is just a legitimate
        // altitude that should round-trip rather than be elided.
        try container.encode(points, forKey: .points)
    }
}
