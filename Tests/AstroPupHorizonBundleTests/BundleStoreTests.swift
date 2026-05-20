//
//  BundleStoreTests.swift
//  AstroPupHorizonBundleTests
//
//  Tests against the BundleStore listing / lifecycle layer using
//  the domain-shaped HorizonBundle API. Per-test temp directory so
//  tests are isolated.
//

import XCTest
@testable import AstroPupHorizonBundle

@MainActor
final class BundleStoreTests: XCTestCase {

    private var tempDir: URL!
    private var baseDir: URL!
    private var store: BundleStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundleStoreTests-\(UUID().uuidString)", isDirectory: true)
        baseDir = tempDir.appendingPathComponent("Captures", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        store = BundleStore(baseURL: baseDir)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        baseDir = nil
        store = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func create(
        named name: String,
        capturedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) async throws -> HorizonBundle {
        try await store.createBundle(name: name, capturedAt: capturedAt)
    }

    private func makeImage(width: Int = 8, height: Int = 4) -> PlatformImage {
        TestImageMaker.makeImage(width: width, height: height)
    }

    // MARK: - Refresh

    func testRefresh_emptyBase_returnsEmpty() async {
        await store.refresh()
        XCTAssertTrue(store.bundles.isEmpty)
    }

    func testRefresh_findsValidBundles() async throws {
        _ = try await create(named: "A")
        _ = try await create(named: "B")
        await store.refresh()
        XCTAssertEqual(store.bundles.count, 2)
    }

    func testRefresh_ignoresJunkFiles() async throws {
        try Data("ignore me".utf8).write(to: baseDir.appendingPathComponent("README.txt"))
        try FileManager.default.createDirectory(
            at: baseDir.appendingPathComponent("not-a-bundle"),
            withIntermediateDirectories: true
        )
        _ = try await create(named: "Real")
        await store.refresh()
        XCTAssertEqual(store.bundles.count, 1)
        XCTAssertEqual(store.bundles.first?.directoryName, "Real.horizon")
    }

    func testRefresh_skipsBundleWithMissingBundleJSON() async throws {
        let fakeURL = baseDir.appendingPathComponent("Broken.horizon", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeURL, withIntermediateDirectories: true)
        _ = try await create(named: "Real")
        await store.refresh()
        XCTAssertEqual(store.bundles.count, 1)
    }

    func testRefresh_skipsBundleWithMalformedJSON() async throws {
        let badURL = baseDir.appendingPathComponent("Bad.horizon", isDirectory: true)
        try FileManager.default.createDirectory(at: badURL, withIntermediateDirectories: true)
        try Data("not json".utf8).write(
            to: badURL.appendingPathComponent(HorizonBundle.bundleJSONFilename)
        )
        _ = try await create(named: "Real")
        await store.refresh()
        XCTAssertEqual(store.bundles.count, 1)
    }

    func testRefresh_sortsByModifiedAtNewestFirst() async throws {
        // createBundle sets modifiedAt = capturedAt initially.
        // Captures with different capturedAt sort accordingly.
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newDate = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try await create(named: "Old", capturedAt: oldDate)
        _ = try await create(named: "New", capturedAt: newDate)
        await store.refresh()
        XCTAssertEqual(store.bundles.count, 2)
        XCTAssertEqual(try store.bundles[0].name, "New")
        XCTAssertEqual(try store.bundles[1].name, "Old")
    }

    // MARK: - Create

    func testCreate_writesBundle() async throws {
        let bundle = try await create(named: "First")
        XCTAssertEqual(bundle.directoryName, "First.horizon")
        XCTAssertTrue(bundle.directoryExists)
        XCTAssertEqual(try bundle.name, "First")
    }

    func testCreate_appendsCounter_onDuplicateName() async throws {
        let a = try await create(named: "Brooklyn")
        let b = try await create(named: "Brooklyn")
        let c = try await create(named: "Brooklyn")
        XCTAssertEqual(a.directoryName, "Brooklyn.horizon")
        XCTAssertEqual(b.directoryName, "Brooklyn 2.horizon")
        XCTAssertEqual(c.directoryName, "Brooklyn 3.horizon")
    }

    func testCreate_sanitizesPathUnsafeCharacters() async throws {
        let bundle = try await create(named: "Foo/Bar:Baz")
        XCTAssertEqual(bundle.directoryName, "Foo_Bar_Baz.horizon")
        // The user-typed name survives intact.
        XCTAssertEqual(try bundle.name, "Foo/Bar:Baz")
    }

    func testCreate_emptyNameBecomesUntitled() async throws {
        let bundle = try await create(named: "")
        XCTAssertEqual(bundle.directoryName, "Untitled.horizon")
    }

    func testCreate_refreshesBundleList() async throws {
        XCTAssertTrue(store.bundles.isEmpty)
        _ = try await create(named: "X")
        XCTAssertEqual(store.bundles.count, 1)
    }

    // MARK: - Import

    func testImport_copiesForeignBundleIntoBase() async throws {
        // Foreign bundle outside baseDir.
        let foreignDir = tempDir.appendingPathComponent("foreign", isDirectory: true)
        try FileManager.default.createDirectory(at: foreignDir, withIntermediateDirectories: true)
        let foreignURL = foreignDir.appendingPathComponent("Some Site.horizon", isDirectory: true)
        _ = try await HorizonBundle.create(at: foreignURL, name: "Some Site")

        let imported = try await store.importBundle(from: foreignURL)
        XCTAssertEqual(imported.url.deletingLastPathComponent().path, baseDir.path)
        XCTAssertEqual(imported.directoryName, "Some Site.horizon")
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreignURL.path),
                      "Source should be untouched (copy, not move)")
        XCTAssertEqual(store.bundles.count, 1)
    }

    func testImport_appendsCounter_onCollidingName() async throws {
        _ = try await create(named: "Brooklyn")

        let foreignDir = tempDir.appendingPathComponent("foreign", isDirectory: true)
        try FileManager.default.createDirectory(at: foreignDir, withIntermediateDirectories: true)
        let foreignURL = foreignDir.appendingPathComponent("Brooklyn.horizon", isDirectory: true)
        _ = try await HorizonBundle.create(at: foreignURL, name: "Brooklyn")

        let imported = try await store.importBundle(from: foreignURL)
        XCTAssertEqual(imported.directoryName, "Brooklyn 2.horizon")
    }

    func testImport_refusesMalformedSource() async throws {
        let badURL = tempDir.appendingPathComponent("Bad.horizon", isDirectory: true)
        try FileManager.default.createDirectory(at: badURL, withIntermediateDirectories: true)
        try Data("not json".utf8).write(
            to: badURL.appendingPathComponent(HorizonBundle.bundleJSONFilename)
        )
        do {
            _ = try await store.importBundle(from: badURL)
            XCTFail("Expected throw on malformed source")
        } catch HorizonBundleError.bundleJSONMalformed {
            // expected
        } catch {
            XCTFail("Expected bundleJSONMalformed, got \(error)")
        }
    }

    func testImport_alreadyInsideBase_returnsExistingWithoutCopy() async throws {
        let existing = try await create(named: "Inside")
        let result = try await store.importBundle(from: existing.url)
        XCTAssertEqual(result.url, existing.url)
        await store.refresh()
        XCTAssertEqual(store.bundles.count, 1)
    }

    // MARK: - Rename

    func testRename_movesDirectoryAndUpdatesName() async throws {
        let bundle = try await create(named: "Original")
        XCTAssertEqual(bundle.directoryName, "Original.horizon")

        let renamed = try await store.renameBundle(bundle, to: "Renamed")
        XCTAssertEqual(renamed.directoryName, "Renamed.horizon")
        XCTAssertTrue(renamed.directoryExists)
        XCTAssertEqual(try renamed.name, "Renamed")
        // Class semantic: rename returns the SAME object, just relocated.
        XCTAssertTrue(renamed === bundle)
    }

    func testRename_appendsCounterOnCollisionWithSiblingBundle() async throws {
        _ = try await create(named: "Brooklyn")
        let other = try await create(named: "Manhattan")

        let renamed = try await store.renameBundle(other, to: "Brooklyn")
        XCTAssertEqual(renamed.directoryName, "Brooklyn 2.horizon")
        XCTAssertEqual(try renamed.name, "Brooklyn")
    }

    func testRename_toSameName_noOp() async throws {
        let bundle = try await create(named: "Stable")
        let originalURL = bundle.url
        let renamed = try await store.renameBundle(bundle, to: "Stable")
        XCTAssertEqual(renamed.directoryName, "Stable.horizon")
        XCTAssertEqual(renamed.url, originalURL)
        XCTAssertTrue(renamed.directoryExists)
    }

    func testRename_sanitizesPathUnsafeCharacters() async throws {
        let bundle = try await create(named: "Plain")
        let renamed = try await store.renameBundle(bundle, to: "Foo/Bar:Baz")
        XCTAssertEqual(renamed.directoryName, "Foo_Bar_Baz.horizon")
        XCTAssertEqual(try renamed.name, "Foo/Bar:Baz")
    }

    func testRename_emptyName_throws() async throws {
        let bundle = try await create(named: "Original")
        do {
            _ = try await store.renameBundle(bundle, to: "   ")
            XCTFail("Expected invalidName for whitespace-only input")
        } catch HorizonBundleError.invalidName {
            // expected
        } catch {
            XCTFail("Expected invalidName, got \(error)")
        }
        XCTAssertEqual(bundle.directoryName, "Original.horizon",
                       "Bundle should be untouched on validation failure")
    }

    func testRename_bumpsModifiedAt() async throws {
        let initial = Date(timeIntervalSince1970: 1_700_000_000)
        let bundle = try await create(named: "T", capturedAt: initial)
        let originalModified = try bundle.modifiedAt!

        try await Task.sleep(nanoseconds: 10_000_000)
        _ = try await store.renameBundle(bundle, to: "U")
        XCTAssertGreaterThan(try bundle.modifiedAt!, originalModified)
    }

    func testRename_refreshesStoreList() async throws {
        let bundle = try await create(named: "Before")
        XCTAssertEqual(store.bundles.first?.directoryName, "Before.horizon")

        _ = try await store.renameBundle(bundle, to: "After")
        XCTAssertEqual(store.bundles.count, 1)
        XCTAssertEqual(store.bundles.first?.directoryName, "After.horizon")
    }

    /// Class instance carries through the rename — the same in-memory
    /// reference is fully functional at the new URL afterward. No
    /// "get the new bundle" handoff needed by callers.
    func testRename_referenceStaysValidAndFullyFunctional() async throws {
        let bundle = try await create(named: "Original")
        let originalURL = bundle.url

        _ = try await store.renameBundle(bundle, to: "Renamed")

        // url updated in place.
        XCTAssertNotEqual(bundle.url, originalURL)
        XCTAssertTrue(bundle.directoryExists)

        // Every public operation works on the same in-memory bundle.
        XCTAssertEqual(try bundle.name, "Renamed")
        try await bundle.setCompassOffsetDegrees(5.5)
        XCTAssertEqual(try bundle.compassOffsetDegrees, 5.5)

        let pano = try await bundle.addPano(
            image: makeImage(),
            kind: "photo", projection: "equirectangular",
            altitudeMin: 0, altitudeMax: 90
        )
        XCTAssertEqual(try bundle.panos.count, 1)
        XCTAssertNotNil(bundle.image(for: pano))

        let frame = try await bundle.addFrame(
            image: makeImage(),
            capturedAt: Date(), azimuth: 0, altitude: 0
        )
        XCTAssertNotNil(bundle.image(for: frame))

        try await bundle.delete()
        XCTAssertFalse(bundle.directoryExists)
    }

    // MARK: - Delete

    func testDelete_removesFromList() async throws {
        let bundle = try await create(named: "Doomed")
        XCTAssertEqual(store.bundles.count, 1)
        try await store.deleteBundle(bundle)
        XCTAssertEqual(store.bundles.count, 0)
        XCTAssertFalse(bundle.directoryExists)
    }
}
