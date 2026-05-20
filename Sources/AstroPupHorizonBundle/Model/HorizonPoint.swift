//
//  HorizonPoint.swift
//  AstroPup Horizon
//
//  Created for discrete horizon sampling

import Foundation

/// Represents a single point on the 360-degree horizon at a specific azimuth (compass direction).
///
/// Every saved horizon has a value at every integer azimuth — there's no
/// "unmeasured" sentinel. A fresh `Horizon()` initializes all 360 points
/// with `altitude = 0` (a flat horizon at the mathematical horizon line),
/// which is also what callers see for any azimuth that never received a
/// real measurement.
///
/// `nonisolated` because the target's default actor isolation is
/// `MainActor`, but this is a pure value type with no UI ties — used by
/// the (nonisolated) `Horizon` class on background threads during
/// capture/analysis.
nonisolated public struct HorizonPoint: Codable {
    /// The azimuth direction this point represents (0-359 degrees, where 0 = North)
    public let azimuth: Int

    /// The altitude angle in degrees where the horizon meets the sky at this azimuth
    /// - Positive values: horizon is above the mathematical horizon (hills, mountains)
    /// - Zero: horizon is at mathematical horizon level (flat terrain, distant ocean)
    /// - Negative values: horizon is below mathematical horizon (valleys, depressions)
    public var altitude: Double

    // MARK: - Initialization

    /// Initialize with default values for given azimuth
    public init(azimuth: Int, altitude: Double = 0.0) {
        self.azimuth = azimuth
        self.altitude = altitude
    }

    // MARK: - Mutation Methods

    /// Update this point's altitude.
    public mutating func updateMeasurement(altitude: Double) {
        self.altitude = altitude
    }

    /// Reset this point to its default altitude (0°).
    public mutating func reset() {
        self.altitude = 0.0
    }

    // MARK: - Equatable Implementation

    public static func == (lhs: HorizonPoint, rhs: HorizonPoint) -> Bool {
        return lhs.azimuth == rhs.azimuth
    }

    // MARK: - Codable Implementation

    /// Codable on `azimuth` + `altitude` only. Legacy horizon.json files
    /// may still carry an `isMeasured` field; Swift's default decoder
    /// silently ignores unknown keys, so old bundles keep loading.
    enum CodingKeys: String, CodingKey {
        case azimuth, altitude
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        azimuth = try c.decode(Int.self, forKey: .azimuth)
        altitude = try c.decode(Double.self, forKey: .altitude)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(azimuth, forKey: .azimuth)
        try c.encode(altitude, forKey: .altitude)
    }
}
