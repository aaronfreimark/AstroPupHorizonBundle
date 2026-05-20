//
//  HorizonBundle.swift
//  AstroPupHorizonBundle
//
//  Domain-shaped public API around a `.horizon` package on disk. The
//  on-disk `bundle.json` (a `BundleDocument` Codable) is an
//  implementation detail — callers see only domain-level reads and
//  mutations:
//
//      let name = try bundle.name                 ← throwing computed
//      try await bundle.setName("Brooklyn")       ← updates modifiedAt
//      let panos = try bundle.panos               ← always an array, never nil
//      if let img = bundle.image(for: panos[0]) { … }
//      try await bundle.addPano(image: …, kind: .photo, …)
//
//  Per HORIZON_BUNDLE_FORMAT.md:
//    - bundle.json holds the structured document (metadata + horizon
//      points + pano manifests + frame manifests).
//    - Pano images live as sibling files at the bundle root.
//    - Frame images live in `frames/<filename>`.
//    - `undo.json` stays separate so editor churn doesn't touch the
//      publicly-portable index.
//
//  Reference type (`class`) so a single in-memory bundle can stay
//  valid across renames (the directory move updates `url` in place)
//  and so the cached document doesn't have to be threaded through
//  every call. `@MainActor`-isolated; tests run on main too.
//

import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
public final class HorizonBundle: Identifiable, ObservableObject, Equatable {

    // MARK: - Public type aliases
    //
    // BundleDocument's nested Codable types ARE the value-carrier
    // types callers manipulate (PanoEntry, FrameEntry, Location,
    // HorizonPoint). Aliasing them under HorizonBundle's namespace
    // makes the public surface speak in HorizonBundle terms; the
    // BundleDocument type itself stays an implementation detail.

    public typealias Location = BundleDocument.Location
    public typealias HorizonData = BundleDocument.HorizonData
    public typealias HorizonPoint = BundleDocument.HorizonData.Point
    public typealias PanoEntry = BundleDocument.PanoEntry
    public typealias FrameEntry = BundleDocument.FrameEntry
    public typealias CameraData = BundleDocument.FrameEntry.CameraData

    // MARK: - Identity

    /// Absolute URL of the bundle directory. Updated in-place by
    /// renames that move the directory (see BundleStore.renameBundle).
    public private(set) var url: URL

    public nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }

    /// Opaque directory name. Always `url.lastPathComponent`.
    public var directoryName: String { url.lastPathComponent }

    public init(url: URL) {
        self.url = url
    }

    /// Equatable by object identity — `HorizonBundle` is a class and
    /// each in-memory instance carries its own cached document.
    /// Two different instances pointing at the same URL are NOT
    /// equal; that's intentional (they have independent caches).
    public nonisolated static func == (lhs: HorizonBundle, rhs: HorizonBundle) -> Bool {
        lhs === rhs
    }

    // MARK: - Filename constants
    //
    // `nonisolated` so detached Tasks (which do the actual JSON write
    // off the main actor) can read them without an actor hop.

    public nonisolated static let bundleJSONFilename = "bundle.json"
    public nonisolated static let undoJSONFilename = "undo.json"
    public nonisolated static let framesDirectoryName = "frames"
    public nonisolated static let directoryExtension = "horizon"

    /// Sentinel "no bundle here" handle. Used by SwiftUI views that
    /// need an @ObservedObject reference in code paths where no real
    /// bundle exists (e.g. DetailView's `.analyzing` mode, or
    /// `#Preview`s that inject pano + canvas directly instead of
    /// using a real on-disk bundle). The url points at `/dev/null`
    /// so any accidental read predictably throws
    /// `.directoryNotFound` rather than crashing.
    public static let placeholder = HorizonBundle(
        url: URL(fileURLWithPath: "/dev/null")
    )

    // MARK: - URL helpers (internal — public callers don't construct paths)

    var bundleJSONURL: URL { url.appendingPathComponent(Self.bundleJSONFilename) }
    var undoJSONURL: URL { url.appendingPathComponent(Self.undoJSONFilename) }
    var framesURL: URL {
        url.appendingPathComponent(Self.framesDirectoryName, isDirectory: true)
    }

    // MARK: - Cache

    /// Cached on first metadata access. Cleared by `reload()` and
    /// by external instances of HorizonBundle pointing at the same
    /// URL (we don't try to coordinate across instances).
    private var cachedDocument: BundleDocument?

    /// Drop the cached document so the next metadata access re-reads
    /// from disk. Rarely needed in normal use; useful in tests or
    /// after external file mutations.
    public func reload() {
        cachedDocument = nil
    }

    // MARK: - Existence

    public var directoryExists: Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    // MARK: - Metadata reads (throwing computed)

    public var formatVersion: Int {
        get throws { try ensureDocument().formatVersion }
    }

    public var name: String {
        get throws { try ensureDocument().name }
    }

    public var capturedAt: Date? {
        get throws { try ensureDocument().capturedAt }
    }

    public var modifiedAt: Date? {
        get throws { try ensureDocument().modifiedAt }
    }

    public var captureLocation: Location? {
        get throws { try ensureDocument().captureLocation }
    }

    public var compassOffsetDegrees: Double? {
        get throws { try ensureDocument().compassOffsetDegrees }
    }

    public var appVersion: String? {
        get throws { try ensureDocument().appVersion }
    }

    // MARK: - Content reads

    /// Horizon altitude data, or `nil` when the bundle hasn't been
    /// analyzed yet.
    public var horizon: HorizonData? {
        get throws { try ensureDocument().horizon }
    }

    /// Pano manifests. Always returns an array (empty when no panos),
    /// not optional, to spare callers a `?? []` dance.
    public var panos: [PanoEntry] {
        get throws { try ensureDocument().panos ?? [] }
    }

    /// Frame manifests. Always returns an array.
    public var frames: [FrameEntry] {
        get throws { try ensureDocument().frames ?? [] }
    }

    // MARK: - Image fetches

    /// Load a pano image by manifest entry. Returns `nil` if the
    /// file is missing or undecodable. Synchronous — fine for small
    /// thumbnail loads on the main actor; callers handling many large
    /// panos should hop to a detached task themselves.
    public func image(for pano: PanoEntry) -> PlatformImage? {
        let imgURL = url.appendingPathComponent(pano.filename)
        guard let data = try? Data(contentsOf: imgURL) else { return nil }
        return PlatformImage.decode(data)
    }

    /// Load a source-frame image by manifest entry. Returns `nil`
    /// on missing / undecodable.
    public func image(for frame: FrameEntry) -> PlatformImage? {
        let imgURL = framesURL.appendingPathComponent(frame.filename)
        guard let data = try? Data(contentsOf: imgURL) else { return nil }
        return PlatformImage.decode(data)
    }

    // MARK: - Metadata mutations

    public func setName(_ newName: String) async throws {
        var doc = try ensureDocument()
        doc.name = newName
        try await persist(&doc, bumpModified: true)
    }

    public func setCaptureLocation(_ location: Location?) async throws {
        var doc = try ensureDocument()
        doc.captureLocation = location
        try await persist(&doc, bumpModified: true)
    }

    public func setCompassOffsetDegrees(_ degrees: Double?) async throws {
        var doc = try ensureDocument()
        doc.compassOffsetDegrees = degrees
        try await persist(&doc, bumpModified: true)
    }

    // MARK: - Horizon mutations

    public func setHorizon(points: [HorizonPoint]) async throws {
        var doc = try ensureDocument()
        doc.horizon = HorizonData(points: points)
        try await persist(&doc, bumpModified: true)
    }

    public func clearHorizon() async throws {
        var doc = try ensureDocument()
        doc.horizon = nil
        try await persist(&doc, bumpModified: true)
    }

    // MARK: - Pano mutations

    /// Add a pano. Writes the image to a unique filename inside the
    /// bundle and appends a matching entry to `panos[]`. Returns the
    /// new entry so callers can hold onto it (e.g. to look up the
    /// pano later via `image(for:)`).
    @discardableResult
    public func addPano(
        image: PlatformImage,
        kind: String,
        projection: String,
        altitudeMin: Double,
        altitudeMax: Double
    ) async throws -> PanoEntry {
        var doc = try ensureDocument()
        let existing = doc.panos ?? []
        let filename = Self.uniquePanoFilename(kind: kind, existing: existing)
        try await writePano(image: image, filename: filename)
        let entry = PanoEntry(
            filename: filename,
            kind: kind,
            projection: projection,
            altitudeMin: altitudeMin,
            altitudeMax: altitudeMax
        )
        doc.panos = existing + [entry]
        try await persist(&doc, bumpModified: true)
        return entry
    }

    /// Remove a pano entry and its image file.
    public func remove(pano: PanoEntry) async throws {
        var doc = try ensureDocument()
        doc.panos = (doc.panos ?? []).filter { $0.filename != pano.filename }
        try await deletePanoFile(filename: pano.filename)
        try await persist(&doc, bumpModified: true)
    }

    /// Drop all pano entries + image files.
    public func clearPanos() async throws {
        var doc = try ensureDocument()
        let toDelete = doc.panos ?? []
        doc.panos = nil
        for entry in toDelete {
            try? await deletePanoFile(filename: entry.filename)
        }
        try await persist(&doc, bumpModified: true)
    }

    // MARK: - Frame mutations

    /// Add a source frame. Writes the JPEG to a unique filename
    /// inside `frames/` and appends a matching entry to `frames[]`.
    @discardableResult
    public func addFrame(
        image: PlatformImage,
        capturedAt: Date,
        azimuth: Double,
        altitude: Double,
        camera: CameraData? = nil
    ) async throws -> FrameEntry {
        var doc = try ensureDocument()
        let existing = doc.frames ?? []
        let filename = Self.uniqueFrameFilename(existing: existing)
        try await writeFrame(image: image, filename: filename)
        let entry = FrameEntry(
            filename: filename,
            capturedAt: capturedAt,
            azimuth: azimuth,
            altitude: altitude,
            camera: camera
        )
        doc.frames = existing + [entry]
        try await persist(&doc, bumpModified: true)
        return entry
    }

    /// Drop all frame entries + remove the `frames/` directory.
    public func clearFrames() async throws {
        var doc = try ensureDocument()
        doc.frames = nil
        try await deleteFramesDirectory()
        try await persist(&doc, bumpModified: true)
    }

    // MARK: - Undo blob

    /// Editor's opaque undo/redo bytes. Read synchronously; returns
    /// nil if absent.
    public var undoData: Data? {
        guard FileManager.default.fileExists(atPath: undoJSONURL.path) else {
            return nil
        }
        return try? Data(contentsOf: undoJSONURL)
    }

    /// Set / clear the editor's undo blob. Passing nil deletes the
    /// undo file. Does NOT bump `modifiedAt` — undo state churn
    /// shouldn't surface as bundle-level modifications.
    public func setUndoData(_ data: Data?) async throws {
        let undoURL = undoJSONURL
        let dirURL = url
        try await Task.detached(priority: .userInitiated) {
            if let data {
                try FileManager.default.createDirectory(
                    at: dirURL, withIntermediateDirectories: true
                )
                try FileCoordination.write(data, to: undoURL)
            } else {
                try? FileCoordination.delete(at: undoURL)
            }
        }.value
    }

    // MARK: - Lifecycle

    /// Create a fresh bundle on disk with the given starting
    /// metadata. The directory must not already exist. Initial
    /// `modifiedAt` is set to `capturedAt ?? now`.
    @discardableResult
    public static func create(
        at url: URL,
        name: String,
        capturedAt: Date? = nil,
        captureLocation: Location? = nil,
        compassOffsetDegrees: Double? = nil,
        appVersion: String? = nil
    ) async throws -> HorizonBundle {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            throw HorizonBundleError.nameConflict(
                suggestedDirectory: url.lastPathComponent
            )
        }
        let now = Date()
        let document = BundleDocument(
            formatVersion: BundleDocument.currentFormatVersion,
            name: name,
            capturedAt: capturedAt,
            modifiedAt: capturedAt ?? now,
            captureLocation: captureLocation,
            compassOffsetDegrees: compassOffsetDegrees,
            appVersion: appVersion,
            horizon: nil,
            panos: nil,
            frames: nil
        )
        try await Task.detached(priority: .userInitiated) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            let data = try BundleJSON.encoder.encode(document)
            try FileCoordination.write(
                data,
                to: url.appendingPathComponent(bundleJSONFilename)
            )
        }.value
        let bundle = HorizonBundle(url: url)
        bundle.cachedDocument = document
        return bundle
    }

    /// Remove the bundle directory and all its contents.
    public func delete() async throws {
        let dirURL = url
        try await Task.detached(priority: .userInitiated) {
            try FileCoordination.delete(at: dirURL)
        }.value
        cachedDocument = nil
    }

    /// Internal: BundleStore uses this when a rename moves the
    /// directory on disk. Callers shouldn't invoke directly — go
    /// through `BundleStore.renameBundle(_:to:)` so the store's
    /// published list stays in sync.
    func relocate(to newURL: URL) {
        objectWillChange.send()
        url = newURL
        // Cache stays valid — bundle.json didn't change shape, only
        // the directory it lives in. Image fetches will use the new
        // URL automatically.
    }

    /// Internal: BundleStore reads the cached document during refresh
    /// without re-hitting disk. Callers go through the public
    /// throwing properties.
    func loadedDocument() throws -> BundleDocument {
        try ensureDocument()
    }

    // MARK: - Private helpers

    /// Load `bundle.json` from disk if not already cached. Throws on
    /// missing file / malformed JSON / too-new format version.
    private func ensureDocument() throws -> BundleDocument {
        if let cached = cachedDocument { return cached }
        guard directoryExists else {
            throw HorizonBundleError.directoryNotFound(url)
        }
        guard FileManager.default.fileExists(atPath: bundleJSONURL.path) else {
            throw HorizonBundleError.bundleJSONMissing(url)
        }
        let data: Data
        do {
            data = try Data(contentsOf: bundleJSONURL)
        } catch {
            throw HorizonBundleError.bundleJSONMissing(url)
        }
        let doc: BundleDocument
        do {
            doc = try BundleJSON.decoder.decode(BundleDocument.self, from: data)
        } catch {
            throw HorizonBundleError.bundleJSONMalformed(
                url, reason: error.localizedDescription
            )
        }
        if doc.formatVersion > BundleDocument.currentFormatVersion {
            throw HorizonBundleError.formatVersionTooNew(
                url,
                found: doc.formatVersion,
                supported: BundleDocument.currentFormatVersion
            )
        }
        cachedDocument = doc
        return doc
    }

    /// Encode + atomic-write the document. Bumps `modifiedAt` to
    /// `now` if `bumpModified` is true. Updates the cache + fires
    /// objectWillChange on success so SwiftUI views observing the
    /// bundle as @ObservedObject pick up the new state.
    private func persist(_ document: inout BundleDocument, bumpModified: Bool) async throws {
        if bumpModified {
            document.modifiedAt = Date()
        }
        let dirURL = url
        let bundleURL = bundleJSONURL
        let snapshot = document
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(
                at: dirURL, withIntermediateDirectories: true
            )
            let data = try BundleJSON.encoder.encode(snapshot)
            try FileCoordination.write(data, to: bundleURL)
        }.value
        objectWillChange.send()
        cachedDocument = snapshot
    }

    /// Pick a pano filename derived from `kind` that doesn't collide
    /// with any existing entry. Convention: `pano-<kind>.png` for
    /// the first of a given kind, `pano-<kind>-2.png`, … for repeats.
    private static func uniquePanoFilename(
        kind: String, existing: [PanoEntry]
    ) -> String {
        let safeKind = kind.isEmpty ? "image" : kind
        let usedNames = Set(existing.map(\.filename))
        var candidate = "pano-\(safeKind).png"
        var counter = 2
        while usedNames.contains(candidate) {
            candidate = "pano-\(safeKind)-\(counter).png"
            counter += 1
        }
        return candidate
    }

    /// Pick a 4-digit zero-padded frame filename that doesn't
    /// collide with any existing entry. Convention: `0001.jpg`,
    /// `0002.jpg`, …
    private static func uniqueFrameFilename(existing: [FrameEntry]) -> String {
        let usedNames = Set(existing.map(\.filename))
        var counter = existing.count + 1
        while true {
            let candidate = String(format: "%04d.jpg", counter)
            if !usedNames.contains(candidate) { return candidate }
            counter += 1
        }
    }

    private func writePano(image: PlatformImage, filename: String) async throws {
        let dirURL = url
        let imgURL = url.appendingPathComponent(filename)
        guard let data = PlatformImageEncoding.pngData(from: image) else {
            throw HorizonBundleError.bundleJSONMalformed(
                imgURL, reason: "Image produced no PNG data"
            )
        }
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(
                at: dirURL, withIntermediateDirectories: true
            )
            try FileCoordination.write(data, to: imgURL)
        }.value
    }

    private func writeFrame(image: PlatformImage, filename: String) async throws {
        let framesDir = framesURL
        let imgURL = framesDir.appendingPathComponent(filename)
        guard let data = PlatformImageEncoding.jpegData(from: image, quality: 0.9) else {
            throw HorizonBundleError.bundleJSONMalformed(
                imgURL, reason: "Image produced no JPEG data"
            )
        }
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(
                at: framesDir, withIntermediateDirectories: true
            )
            try FileCoordination.write(data, to: imgURL)
        }.value
    }

    private func deletePanoFile(filename: String) async throws {
        let imgURL = url.appendingPathComponent(filename)
        try await Task.detached(priority: .userInitiated) {
            try? FileCoordination.delete(at: imgURL)
        }.value
    }

    private func deleteFramesDirectory() async throws {
        let framesDir = framesURL
        try await Task.detached(priority: .userInitiated) {
            try? FileCoordination.delete(at: framesDir)
        }.value
    }
}
