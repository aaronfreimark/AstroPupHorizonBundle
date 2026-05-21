//
//  HorizonBundleTests.swift
//  AstroPupHorizonBundleTests
//
//  Tests against the domain-shaped HorizonBundle API. The on-disk
//  Codable (BundleDocument) is an implementation detail, exercised
//  indirectly through HorizonBundle's metadata accessors and
//  mutators.
//
//  Per-test temp directory ensures isolation and no leftover files
//  on the filesystem.
//

import XCTest
@testable import AstroPupHorizonBundle

@MainActor
final class HorizonBundleTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HorizonBundleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func bundleURL(_ name: String = "Test.horizon") -> URL {
        tempDir.appendingPathComponent(name, isDirectory: true)
    }

    private func makeBundle(
        name: String = "Test Bundle",
        capturedAt: Date? = Date(timeIntervalSince1970: 1_700_000_000),
        location: HorizonBundle.Location? = .init(latitude: 40.7, longitude: -74.0)
    ) async throws -> HorizonBundle {
        try await HorizonBundle.create(
            at: bundleURL(),
            name: name,
            capturedAt: capturedAt,
            captureLocation: location,
            compassOffsetDegrees: 3.5,
            appVersion: "AstroPup Horizon 1.0 (test)"
        )
    }

    /// Tiny opaque PNG image. Cross-platform via TestImageMaker so
    /// the package's tests run on both iOS and macOS.
    private func makeImage(width: Int = 8, height: Int = 4) -> PlatformImage {
        TestImageMaker.makeImage(width: width, height: height)
    }

    // MARK: - Create / metadata reads

    func testCreate_seedsMetadata() async throws {
        let bundle = try await makeBundle()
        XCTAssertEqual(try bundle.name, "Test Bundle")
        XCTAssertEqual(try bundle.capturedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(try bundle.captureLocation?.latitude, 40.7)
        XCTAssertEqual(try bundle.compassOffsetDegrees, 3.5)
        XCTAssertEqual(try bundle.formatVersion, BundleDocument.currentFormatVersion)
        XCTAssertTrue(bundle.directoryExists)
    }

    func testCreate_emptyContentReturnsEmptyArrays() async throws {
        let bundle = try await makeBundle()
        XCTAssertNil(try bundle.horizon)
        XCTAssertEqual(try bundle.panos, [])
        XCTAssertEqual(try bundle.frames, [])
    }

    func testCreate_failsIfDirectoryExists() async throws {
        _ = try await makeBundle()
        do {
            _ = try await makeBundle(name: "Other")
            XCTFail("Expected nameConflict")
        } catch HorizonBundleError.nameConflict {
            // expected
        } catch {
            XCTFail("Expected nameConflict, got \(error)")
        }
    }

    func testCreate_minimalMetadata() async throws {
        let bundle = try await HorizonBundle.create(
            at: bundleURL(),
            name: "Bare"
        )
        XCTAssertEqual(try bundle.name, "Bare")
        XCTAssertNil(try bundle.capturedAt)
        XCTAssertNotNil(try bundle.modifiedAt)
        XCTAssertNil(try bundle.captureLocation)
        XCTAssertNil(try bundle.compassOffsetDegrees)
    }

    // MARK: - Stable identifier

    /// New bundles get a UUID at create time.
    func testCreate_assignsStableID() async throws {
        let bundle = try await makeBundle()
        XCTAssertNotNil(try bundle.bundleID)
    }

    /// The id assigned at create time survives a fresh disk read.
    func testBundleID_persistsAcrossInstances() async throws {
        let writer = try await makeBundle()
        let firstID = try XCTUnwrap(try writer.bundleID)

        // Fresh instance forces a disk reload — value should match.
        let reader = HorizonBundle(url: writer.url)
        XCTAssertEqual(try reader.bundleID, firstID)
    }

    /// The id survives a rename: directoryName changes but the
    /// stable identifier doesn't.
    func testBundleID_survivesRename() async throws {
        let bundle = try await makeBundle()
        let originalID = try XCTUnwrap(try bundle.bundleID)
        let originalDirName = bundle.directoryName

        try await bundle.setName("Renamed In Place")

        // bundle.setName doesn't move the directory (that's
        // BundleStore.renameBundle's job), but the id MUST be
        // preserved either way.
        XCTAssertEqual(try bundle.bundleID, originalID)
        XCTAssertEqual(bundle.directoryName, originalDirName)
    }

    /// Legacy bundle missing the `id` field decodes cleanly with
    /// nil, then auto-fills on first persist.
    func testBundleID_legacyBundleAutoFillsOnFirstPersist() async throws {
        // Write a bundle.json by hand with no `id` field — simulates
        // a bundle authored before this field existed.
        let url = bundleURL()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let legacyJSON = #"""
        {
          "formatVersion": 1,
          "name": "Legacy Bundle",
          "modifiedAt": "2025-01-01T00:00:00Z"
        }
        """#
        try Data(legacyJSON.utf8).write(
            to: url.appendingPathComponent(HorizonBundle.bundleJSONFilename)
        )

        let bundle = HorizonBundle(url: url)
        XCTAssertNil(try bundle.bundleID, "Legacy bundle starts with nil id")

        // Any mutation triggers persist, which auto-fills the id.
        try await bundle.setName("Now Mutated")
        let assigned = try XCTUnwrap(try bundle.bundleID)

        // A fresh instance reading from disk sees the same assigned id.
        let reader = HorizonBundle(url: url)
        XCTAssertEqual(try reader.bundleID, assigned)
    }

    // MARK: - Error cases on reads

    func testReads_missingDirectory_throws() {
        let bundle = HorizonBundle(url: bundleURL("does-not-exist.horizon"))
        XCTAssertThrowsError(try bundle.name) { error in
            guard case HorizonBundleError.directoryNotFound = error else {
                return XCTFail("Expected directoryNotFound, got \(error)")
            }
        }
    }

    func testReads_missingBundleJSON_throws() throws {
        let url = bundleURL()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let bundle = HorizonBundle(url: url)
        XCTAssertThrowsError(try bundle.name) { error in
            guard case HorizonBundleError.bundleJSONMissing = error else {
                return XCTFail("Expected bundleJSONMissing, got \(error)")
            }
        }
    }

    func testReads_malformedJSON_throws() throws {
        let url = bundleURL()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("{ not really json ".utf8).write(
            to: url.appendingPathComponent(HorizonBundle.bundleJSONFilename)
        )
        let bundle = HorizonBundle(url: url)
        XCTAssertThrowsError(try bundle.name) { error in
            guard case HorizonBundleError.bundleJSONMalformed = error else {
                return XCTFail("Expected bundleJSONMalformed, got \(error)")
            }
        }
    }

    func testReads_formatVersionTooNew_throws() async throws {
        let url = bundleURL()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let future = BundleDocument(
            formatVersion: BundleDocument.currentFormatVersion + 1,
            name: "Future"
        )
        let data = try BundleJSON.encoder.encode(future)
        try data.write(to: url.appendingPathComponent(HorizonBundle.bundleJSONFilename))
        let bundle = HorizonBundle(url: url)
        XCTAssertThrowsError(try bundle.name) { error in
            guard case HorizonBundleError.formatVersionTooNew(_, let found, let supported) = error else {
                return XCTFail("Expected formatVersionTooNew, got \(error)")
            }
            XCTAssertEqual(found, BundleDocument.currentFormatVersion + 1)
            XCTAssertEqual(supported, BundleDocument.currentFormatVersion)
        }
    }

    // MARK: - Metadata mutations

    func testSetName_updatesNameAndBumpsModified() async throws {
        let bundle = try await makeBundle()
        let initialModified = try bundle.modifiedAt!

        try await Task.sleep(nanoseconds: 10_000_000) // 10 ms — ensure clock advances
        try await bundle.setName("Renamed")

        XCTAssertEqual(try bundle.name, "Renamed")
        XCTAssertGreaterThan(try bundle.modifiedAt!, initialModified)
    }

    func testSetCaptureLocation_updates() async throws {
        let bundle = try await makeBundle(location: nil)
        XCTAssertNil(try bundle.captureLocation)
        try await bundle.setCaptureLocation(.init(latitude: 1.0, longitude: 2.0))
        XCTAssertEqual(try bundle.captureLocation?.latitude, 1.0)
    }

    /// Elevation is optional. Constructing a Location without one
    /// (or with explicit nil) round-trips through the bundle with
    /// the field absent from the encoded JSON.
    func testCaptureLocation_elevationOptional_roundTrips() async throws {
        let bundle = try await makeBundle(location: nil)
        try await bundle.setCaptureLocation(.init(latitude: 1.0, longitude: 2.0))
        XCTAssertNil(try bundle.captureLocation?.elevation)
    }

    /// Elevation, when supplied, round-trips through the bundle.
    func testCaptureLocation_elevationProvided_roundTrips() async throws {
        let bundle = try await makeBundle(location: nil)
        try await bundle.setCaptureLocation(
            .init(latitude: 40.7, longitude: -74.0, elevation: 12.5)
        )
        XCTAssertEqual(try bundle.captureLocation?.elevation, 12.5)
    }

    /// Bundles written before the `elevation` field existed are
    /// missing the key from `captureLocation`. The decoder must
    /// treat that as nil rather than throwing.
    func testCaptureLocation_decodesLegacyJSONWithoutElevation() throws {
        let json = #"""
        {
          "formatVersion": 1,
          "name": "Legacy",
          "captureLocation": { "latitude": 40.7, "longitude": -74.0 }
        }
        """#
        let doc = try BundleJSON.decoder.decode(
            BundleDocument.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(doc.captureLocation?.latitude, 40.7)
        XCTAssertEqual(doc.captureLocation?.longitude, -74.0)
        XCTAssertNil(doc.captureLocation?.elevation)
    }

    func testSetCompassOffsetDegrees_updates() async throws {
        let bundle = try await makeBundle()
        try await bundle.setCompassOffsetDegrees(nil)
        XCTAssertNil(try bundle.compassOffsetDegrees)
        try await bundle.setCompassOffsetDegrees(12.5)
        XCTAssertEqual(try bundle.compassOffsetDegrees, 12.5)
    }

    // MARK: - Horizon mutations

    func testSetHorizon_andClear() async throws {
        let bundle = try await makeBundle()
        let points: [HorizonBundle.HorizonPoint] = [
            .init(azimuth: 0, altitude: 10),
            .init(azimuth: 90, altitude: 20),
            .init(azimuth: 180, altitude: 5),
        ]
        try await bundle.setHorizon(points: points)
        XCTAssertEqual(try bundle.horizon?.points.count, 3)
        XCTAssertEqual(try bundle.horizon?.points[1].altitude, 20)

        try await bundle.clearHorizon()
        XCTAssertNil(try bundle.horizon)
    }

    // MARK: - Pano mutations

    func testAddPano_writesImageAndAppendsEntry() async throws {
        let bundle = try await makeBundle()
        let entry = try await bundle.addPano(
            image: makeImage(),
            kind: HorizonBundle.PanoEntry.Kind.photo,
            projection: HorizonBundle.PanoEntry.Projection.equirectangular,
            altitudeMin: -5, altitudeMax: 90
        )
        XCTAssertEqual(entry.filename, "pano-photo.png")
        XCTAssertEqual(try bundle.panos.count, 1)
        XCTAssertNotNil(bundle.image(for: entry))
    }

    func testAddPano_secondPhotoGetsCounterSuffix() async throws {
        let bundle = try await makeBundle()
        let first = try await bundle.addPano(
            image: makeImage(), kind: "photo", projection: "equirectangular",
            altitudeMin: 0, altitudeMax: 90
        )
        let second = try await bundle.addPano(
            image: makeImage(), kind: "photo", projection: "equirectangular",
            altitudeMin: 0, altitudeMax: 90
        )
        XCTAssertEqual(first.filename, "pano-photo.png")
        XCTAssertEqual(second.filename, "pano-photo-2.png")
        XCTAssertEqual(try bundle.panos.count, 2)
    }

    func testRemovePano_dropsEntryAndDeletesImage() async throws {
        let bundle = try await makeBundle()
        let entry = try await bundle.addPano(
            image: makeImage(), kind: "photo", projection: "equirectangular",
            altitudeMin: 0, altitudeMax: 90
        )
        let imgURL = bundle.url.appendingPathComponent(entry.filename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imgURL.path))

        try await bundle.remove(pano: entry)
        XCTAssertEqual(try bundle.panos, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: imgURL.path))
    }

    func testClearPanos_emptiesAll() async throws {
        let bundle = try await makeBundle()
        _ = try await bundle.addPano(image: makeImage(), kind: "photo", projection: "equirectangular", altitudeMin: 0, altitudeMax: 90)
        _ = try await bundle.addPano(image: makeImage(), kind: "synthetic", projection: "equirectangular", altitudeMin: 0, altitudeMax: 90)
        XCTAssertEqual(try bundle.panos.count, 2)
        try await bundle.clearPanos()
        XCTAssertEqual(try bundle.panos, [])
    }

    // MARK: - Frame mutations

    func testAddFrame_writesImageAndAppendsEntry() async throws {
        let bundle = try await makeBundle()
        let frame = try await bundle.addFrame(
            image: makeImage(),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_001),
            azimuth: 12.5,
            altitude: 7.0
        )
        XCTAssertEqual(frame.filename, "0001.jpg")
        XCTAssertEqual(try bundle.frames.count, 1)
        XCTAssertNotNil(bundle.image(for: frame))
    }

    func testAddFrame_withCameraData_preservesCalibration() async throws {
        let bundle = try await makeBundle()
        let cam = HorizonBundle.CameraData(
            intrinsics: [1, 2, 3, 4, 5, 6, 7, 8, 9],
            imageWidth: 100, imageHeight: 200,
            cameraBufferWidth: 1920, cameraBufferHeight: 1440,
            viewportWidth: 400, viewportHeight: 800
        )
        let frame = try await bundle.addFrame(
            image: makeImage(), capturedAt: Date(), azimuth: 0, altitude: 0, camera: cam
        )
        XCTAssertEqual(frame.camera?.intrinsics, cam.intrinsics)
        XCTAssertEqual(try bundle.frames.first?.camera?.viewportWidth, 400)
    }

    func testAddFrame_sequentialNumbering() async throws {
        let bundle = try await makeBundle()
        let a = try await bundle.addFrame(image: makeImage(), capturedAt: Date(), azimuth: 0, altitude: 0)
        let b = try await bundle.addFrame(image: makeImage(), capturedAt: Date(), azimuth: 0, altitude: 0)
        let c = try await bundle.addFrame(image: makeImage(), capturedAt: Date(), azimuth: 0, altitude: 0)
        XCTAssertEqual(a.filename, "0001.jpg")
        XCTAssertEqual(b.filename, "0002.jpg")
        XCTAssertEqual(c.filename, "0003.jpg")
    }

    func testClearFrames_dropsAllAndRemovesDirectory() async throws {
        let bundle = try await makeBundle()
        _ = try await bundle.addFrame(image: makeImage(), capturedAt: Date(), azimuth: 0, altitude: 0)
        _ = try await bundle.addFrame(image: makeImage(), capturedAt: Date(), azimuth: 0, altitude: 0)
        XCTAssertEqual(try bundle.frames.count, 2)

        try await bundle.clearFrames()
        XCTAssertEqual(try bundle.frames, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundle.framesURL.path))
    }

    // MARK: - Undo

    func testUndoData_setAndRead() async throws {
        let bundle = try await makeBundle()
        XCTAssertNil(bundle.undoData)
        try await bundle.setUndoData(Data("opaque".utf8))
        XCTAssertEqual(bundle.undoData, Data("opaque".utf8))
    }

    func testUndoData_setNilRemovesFile() async throws {
        let bundle = try await makeBundle()
        try await bundle.setUndoData(Data("x".utf8))
        try await bundle.setUndoData(nil)
        XCTAssertNil(bundle.undoData)
    }

    // MARK: - Bundle lifecycle

    func testDelete_removesDirectory() async throws {
        let bundle = try await makeBundle()
        _ = try await bundle.addPano(image: makeImage(), kind: "photo", projection: "equirectangular", altitudeMin: 0, altitudeMax: 90)
        _ = try await bundle.addFrame(image: makeImage(), capturedAt: Date(), azimuth: 0, altitude: 0)
        XCTAssertTrue(bundle.directoryExists)

        try await bundle.delete()
        XCTAssertFalse(bundle.directoryExists)
    }

    // MARK: - Document round-trip (smoke check on the underlying Codable)

    func testBundleDocument_codableRoundTrip() throws {
        // Direct Codable round-trip — ensures the on-disk format
        // survives encode→decode unchanged. Property-based reads on
        // HorizonBundle cover the indirect path.
        let doc = BundleDocument(
            name: "Test",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_100),
            captureLocation: .init(latitude: 40.7, longitude: -74.0),
            compassOffsetDegrees: 3.5,
            appVersion: "AstroPup Horizon 1.0 (test)",
            horizon: .init(points: [.init(azimuth: 0, altitude: 12.3)]),
            panos: [.init(
                filename: "pano-photo.png",
                kind: "photo",
                projection: "equirectangular",
                altitudeMin: -5, altitudeMax: 90
            )],
            frames: [.init(
                filename: "0001.jpg",
                capturedAt: Date(timeIntervalSince1970: 1_700_000_001),
                azimuth: 0.5, altitude: 12.0,
                camera: .init(
                    intrinsics: [1, 2, 3, 4, 5, 6, 7, 8, 9],
                    imageWidth: 100, imageHeight: 200,
                    cameraBufferWidth: 1920, cameraBufferHeight: 1440,
                    viewportWidth: 400, viewportHeight: 800
                )
            )]
        )
        let data = try BundleJSON.encoder.encode(doc)
        let decoded = try BundleJSON.decoder.decode(BundleDocument.self, from: data)
        XCTAssertEqual(decoded, doc)
    }

    func testBundleJSON_datesAreISO8601() throws {
        let doc = BundleDocument(
            name: "Test",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try BundleJSON.encoder.encode(doc)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("T") && json.contains("Z"),
                      "Expected ISO-8601 timestamps; got: \(json)")
        XCTAssertFalse(json.contains("1700000000"),
                       "Expected ISO-8601 encoding, not bare TimeInterval")
    }

    func testBundleDocument_optionalDatesAbsent_roundTrip() throws {
        // HRZ-style import: bundle has no capture event. Both date
        // fields are absent. Round-trip must preserve the nils
        // rather than fill them with epoch defaults.
        let doc = BundleDocument(
            name: "Imported HRZ",
            capturedAt: nil,
            modifiedAt: nil,
            horizon: .init(points: [.init(azimuth: 0, altitude: 10)])
        )
        let data = try BundleJSON.encoder.encode(doc)
        let decoded = try BundleJSON.decoder.decode(BundleDocument.self, from: data)
        XCTAssertEqual(decoded, doc)
        XCTAssertNil(decoded.capturedAt)
        XCTAssertNil(decoded.modifiedAt)
    }

    func testBundleJSON_sortedKeys() throws {
        // Pretty-printed sorted-keys output makes git diffs stable
        // when fixtures are committed and the encoder is involved.
        let doc = BundleDocument(
            name: "Test",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            appVersion: "AstroPup Horizon 1.0 (test)"
        )
        let data = try BundleJSON.encoder.encode(doc)
        let json = String(data: data, encoding: .utf8) ?? ""
        let appVersionIdx = json.range(of: "\"appVersion\"")?.lowerBound
        let nameIdx = json.range(of: "\"name\"")?.lowerBound
        XCTAssertNotNil(appVersionIdx)
        XCTAssertNotNil(nameIdx)
        XCTAssertLessThan(appVersionIdx!, nameIdx!,
                          "Expected alphabetically sorted top-level keys")
    }

    func testBundleDocument_frameEntry_withoutCameraData_roundTrip() throws {
        // Frame WITHOUT the camera extension — the shape an
        // imported / authored bundle would produce. Spec says
        // `camera` is optional; round-trip must preserve nil.
        let frame = BundleDocument.FrameEntry(
            filename: "0001.jpg",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_001),
            azimuth: 12.5,
            altitude: 7.0,
            camera: nil
        )
        let doc = BundleDocument(
            name: "Authored",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            frames: [frame]
        )
        let data = try BundleJSON.encoder.encode(doc)
        let decoded = try BundleJSON.decoder.decode(BundleDocument.self, from: data)
        XCTAssertEqual(decoded, doc)
        XCTAssertNil(decoded.frames?.first?.camera)
    }
}
