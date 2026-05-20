//
//  HorizonTests.swift
//  AstroPup HorizonTests
//
//  Unit tests for the slim Horizon class — a 360-point list with
//  helpers + Codable. Metadata (name, dates, location) now lives
//  on HorizonBundle and is covered by HorizonBundleTests.
//

import XCTest
import Foundation
import simd
import AstroPupHorizonBundle

final class HorizonTests: XCTestCase {

    var horizon: Horizon!

    override func setUp() {
        super.setUp()
        horizon = Horizon()
    }

    override func tearDown() {
        horizon = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testBasicInitialization() {
        XCTAssertEqual(horizon.points.count, 360, "Should have exactly 360 points")

        // Verify all points are initialized correctly
        for i in 0..<360 {
            let point = horizon.getPoint(at: i)!
            XCTAssertEqual(point.azimuth, i)
            XCTAssertEqual(point.altitude, 0.0)
        }
    }

    func testLoadManyPoints() {
        // Create some test points
        let testPoints = [
            HorizonPoint(azimuth: 0, altitude: 5.0),
            HorizonPoint(azimuth: 90, altitude: 15.0),
            HorizonPoint(azimuth: 180, altitude: 10.0),
        ]

        // Load points individually using updatePoint
        var loadedCount = 0
        for point in testPoints {
            if horizon.updatePoint(at: point.azimuth, altitude: point.altitude) {
                loadedCount += 1
            }
        }

        XCTAssertEqual(loadedCount, 3)
        XCTAssertEqual(horizon.points.count, 360)

        // Check specific points
        XCTAssertEqual(horizon.getPoint(at: 0)?.altitude, 5.0)
        XCTAssertEqual(horizon.getPoint(at: 90)?.altitude, 15.0)
        XCTAssertEqual(horizon.getPoint(at: 180)?.altitude, 10.0)

        // Check unmeasured points
        XCTAssertEqual(horizon.getPoint(at: 45)?.altitude, 0.0)
    }

    func testLoadManyPointsValidation() {
        // Test with invalid azimuth values
        let invalidPoints = [
            HorizonPoint(azimuth: -1, altitude: 5.0), // Invalid: negative
            HorizonPoint(azimuth: 360, altitude: 10.0), // Invalid: too large
            HorizonPoint(azimuth: 100, altitude: 15.0), // Valid
            HorizonPoint(azimuth: 500, altitude: 20.0), // Invalid: too large
        ]

        // Load points individually using updatePoint
        var loadedCount = 0
        for point in invalidPoints {
            if horizon.updatePoint(at: point.azimuth, altitude: point.altitude) {
                loadedCount += 1
            }
        }

        // Should only load the valid point
        XCTAssertEqual(loadedCount, 1)
        XCTAssertEqual(horizon.getPoint(at: 100)?.altitude, 15.0)

        // Invalid points should not be loaded
        XCTAssertEqual(horizon.getPoint(at: 0)?.altitude, 0.0) // Default
        XCTAssertEqual(horizon.getPoint(at: 359)?.altitude, 0.0) // Default
    }

    func testLoadManyPointsEmptyArray() {
        // Test with empty array: updatePoint never gets called, so
        // nothing changes.
        let emptyPoints: [HorizonPoint] = []
        var loadedCount = 0
        for point in emptyPoints {
            if horizon.updatePoint(at: point.azimuth, altitude: point.altitude) {
                loadedCount += 1
            }
        }

        XCTAssertEqual(loadedCount, 0)
    }

    // MARK: - Point Access Tests

    func testGetPoint() {
        // Valid indices
        XCTAssertNotNil(horizon.getPoint(at: 0))
        XCTAssertNotNil(horizon.getPoint(at: 359))
        XCTAssertNotNil(horizon.getPoint(at: 180))

        // Invalid indices
        XCTAssertNil(horizon.getPoint(at: -1))
        XCTAssertNil(horizon.getPoint(at: 360))
        XCTAssertNil(horizon.getPoint(at: 1000))
    }

    func testUpdatePointByIndex() {
        // Update a point
        horizon.updatePoint(at: 45, altitude: 12.5)

        let point = horizon.getPoint(at: 45)!
        XCTAssertEqual(point.altitude, 12.5, accuracy: 0.001)
    }

    func testUpdatePointReturnsFalseOnNoOp() {
        // No-op rewrite (identical altitude) returns false.
        horizon.updatePoint(at: 100, altitude: 5.0)
        XCTAssertFalse(horizon.updatePoint(at: 100, altitude: 5.0))
        // But a fresh value still returns true.
        XCTAssertTrue(horizon.updatePoint(at: 100, altitude: 6.0))
    }

    func testUpdatePointByDoubleAzimuth() {
        // Test with various double azimuth values
        horizon.updatePoint(azimuth: 45.7, altitude: 10.0) // Should round to 46
        horizon.updatePoint(azimuth: 89.3, altitude: 15.0) // Should round to 89
        horizon.updatePoint(azimuth: 359.8, altitude: 20.0) // Should round to 0 (360 % 360)

        XCTAssertEqual(horizon.getPoint(at: 46)?.altitude, 10.0)
        XCTAssertEqual(horizon.getPoint(at: 89)?.altitude, 15.0)
        XCTAssertEqual(horizon.getPoint(at: 0)?.altitude, 20.0)
    }

    func testUpdatePointWithNegativeAzimuth() {
        // Test negative azimuth values (should normalize)
        horizon.updatePoint(azimuth: -10.0, altitude: 5.0) // Should become 350
        XCTAssertEqual(horizon.getPoint(at: 350)?.altitude, 5.0)
    }

    // Export tests (generateHRZ / generateCSV / Stellarium / SkySafari)
    // live in the consumer apps' test suites — the export extensions
    // are app-side code, not shared. The package only tests the slim
    // Horizon's points + Codable behavior here.

    // MARK: - Codable Tests
    //
    // The slim Horizon's Codable only encodes/decodes `points`. The
    // legacy keys (`name`, `captureLocation`, `createdAt`, etc.) are
    // ignored on decode so older horizon.json blobs still load cleanly
    // — they just lose their metadata, which lives on the bundle now.

    func testLoadFromJSON() {
        let jsonString = """
        {
            "points": [
                {"azimuth": 0, "altitude": 10.0},
                {"azimuth": 180, "altitude": 5.0}
            ]
        }
        """

        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to create Data from JSON string")
            return
        }

        do {
            let loadedHorizon = try JSONDecoder().decode(Horizon.self, from: jsonData)
            XCTAssertEqual(loadedHorizon.points.count, 360, "Should have exactly 360 points")

            // Verify specific points from JSON were loaded
            XCTAssertEqual(loadedHorizon.getPoint(at: 0)?.altitude, 10.0)
            XCTAssertEqual(loadedHorizon.getPoint(at: 180)?.altitude, 5.0)

            // Verify unspecified points default to 0.0
            XCTAssertEqual(loadedHorizon.getPoint(at: 90)?.altitude, 0.0)
            XCTAssertEqual(loadedHorizon.getPoint(at: 270)?.altitude, 0.0)
        } catch {
            XCTFail("Failed to decode Horizon from JSON: \(error)")
        }
    }

    /// Legacy horizon.json blobs (from before the bundle migration)
    /// carry name + location + dates + version alongside `points`.
    /// The slim decoder must ignore those keys without throwing.
    func testLoadFromLegacyJSON_IgnoresMetadata() {
        let jsonString = """
        {
            "version": 1,
            "name": "Old Horizon",
            "captureLocation": [37.7749, -122.4194],
            "createdAt": 781037028.429956,
            "lastModified": 781037028.431077,
            "points": [
                {"azimuth": 0, "altitude": 10.0}
            ]
        }
        """

        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to create Data from JSON string")
            return
        }

        let loaded = try? JSONDecoder().decode(Horizon.self, from: jsonData)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.getPoint(at: 0)?.altitude, 10.0)
        XCTAssertEqual(loaded?.points.count, 360)
    }

    func testCodableRoundTripPreservesPoints() throws {
        for i in stride(from: 0, to: 360, by: 17) {
            horizon.updatePoint(at: i, altitude: Double(i) / 10.0)
        }

        let data = try JSONEncoder().encode(horizon)
        let decoded = try JSONDecoder().decode(Horizon.self, from: data)

        for i in 0..<360 {
            XCTAssertEqual(
                decoded.getPoint(at: i)?.altitude,
                horizon.getPoint(at: i)?.altitude,
                "Altitude at \(i) should round-trip"
            )
        }
    }
}

// MARK: - Performance Tests

extension HorizonTests {

    func testUpdatePerformance() {
        measure {
            // Measure time to update all 360 points
            for i in 0..<360 {
                _ = horizon.updatePoint(at: i, altitude: Double(i) / 10.0)
            }
        }
    }

}
