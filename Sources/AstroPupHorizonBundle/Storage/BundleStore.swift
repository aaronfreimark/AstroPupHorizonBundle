//
//  BundleStore.swift
//  AstroPup Horizon
//
//  The listing / refresh / import layer over a directory of
//  `.horizon` packages. Wraps a base URL (typically
//  `Documents/Captures/` in the app sandbox; tests construct
//  per-test temp directories) and publishes the list of valid
//  bundles inside it.
//
//  Bundle directory naming is opaque to consumers — `BundleStore`
//  generates safe directory names at create / import time, but
//  renaming a bundle's display name does not move its directory.
//  See HORIZON_BUNDLE_FORMAT.md.
//

import Foundation
import Combine

@MainActor
public final class BundleStore: ObservableObject {

    /// Where bundles live on disk.
    public let baseURL: URL

    /// All bundles found at `baseURL`, sorted newest-first by
    /// `modifiedAt` (falling back to `capturedAt`, then directory
    /// mtime). Published so SwiftUI views update on refresh.
    @Published public private(set) var bundles: [HorizonBundle] = []

    /// True while a refresh is in flight. Views can show a spinner.
    @Published public private(set) var isLoading: Bool = false

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// App-wide store rooted at `Documents/Captures/`. Production
    /// callers use this; tests construct their own with a temp
    /// directory.
    ///
    /// `XCODE_RUNNING_FOR_PREVIEWS` short-circuit: under SwiftUI
    /// preview rendering the auto-`refresh()` on first access is
    /// skipped so #Preview blocks can assign synthetic bundles to
    /// `bundles` without the disk-scan immediately overwriting
    /// them.
    public static let shared: BundleStore = {
        let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let store = BundleStore(
            baseURL: docs.appendingPathComponent("Captures", isDirectory: true)
        )
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            Task { await store.refresh() }
        }
        return store
    }()

    // MARK: - Refresh

    /// Rescan `baseURL` and update `bundles`. Safe to call from any
    /// thread; the actor isolation handles the hop. Malformed or
    /// unreadable bundles are skipped silently — consumers that
    /// want to surface errors should validate before adding.
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let fm = FileManager.default
        try? fm.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(
                at: baseURL,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            bundles = []
            return
        }

        struct Entry {
            let bundle: HorizonBundle
            let sortKey: Date
        }

        var entries: [Entry] = []
        for url in urls {
            guard url.pathExtension == HorizonBundle.directoryExtension else { continue }
            let bundle = HorizonBundle(url: url)
            // Validate by loading. Skip bundles that fail any of the
            // gates (missing bundle.json, malformed, too-new version).
            guard let document = try? bundle.loadedDocument() else { continue }

            // Sort key precedence: modifiedAt → capturedAt → directory mtime.
            let dirMTime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date.distantPast
            let sortKey = document.modifiedAt ?? document.capturedAt ?? dirMTime
            entries.append(Entry(bundle: bundle, sortKey: sortKey))
        }

        entries.sort { $0.sortKey > $1.sortKey }
        bundles = entries.map(\.bundle)
    }

    // MARK: - Lookup

    /// Find a bundle by its directory name (the last path
    /// component). Reads from the cached `bundles` list; call
    /// `refresh()` first if you suspect the list is stale.
    public func bundle(directoryName: String) -> HorizonBundle? {
        bundles.first { $0.directoryName == directoryName }
    }

    // MARK: - Create

    /// Create a new bundle with the given initial metadata. Picks a
    /// unique sanitized directory name from `name`. The returned
    /// bundle is fresh on disk with the metadata seeded; callers
    /// add panos / frames / horizon through the bundle's domain
    /// mutators afterward.
    @discardableResult
    public func createBundle(
        name: String,
        capturedAt: Date? = nil,
        captureLocation: HorizonBundle.Location? = nil,
        compassOffsetDegrees: Double? = nil,
        appVersion: String? = nil
    ) async throws -> HorizonBundle {
        try FileManager.default.createDirectory(
            at: baseURL, withIntermediateDirectories: true
        )
        let targetDir = Self.uniqueDirectoryName(displayName: name, in: baseURL)
        let targetURL = baseURL.appendingPathComponent(targetDir, isDirectory: true)
        let bundle = try await HorizonBundle.create(
            at: targetURL,
            name: name,
            capturedAt: capturedAt,
            captureLocation: captureLocation,
            compassOffsetDegrees: compassOffsetDegrees,
            appVersion: appVersion
        )
        await refresh()
        return bundle
    }

    // MARK: - Import

    /// Copy a foreign `.horizon` directory into `baseURL`. Picks a
    /// unique directory name based on the source's name (not the
    /// source directory name, so externally-renamed directories
    /// don't leak in). Validates the source's bundle.json before
    /// copying.
    @discardableResult
    public func importBundle(from sourceURL: URL) async throws -> HorizonBundle {
        let fm = FileManager.default
        try fm.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let sourceBundle = HorizonBundle(url: sourceURL)
        let sourceName = try sourceBundle.name  // throws if invalid

        // If we'd be importing from inside our own base directory,
        // refuse — bundles inside baseURL are already managed.
        if sourceURL.standardizedFileURL.path.hasPrefix(baseURL.standardizedFileURL.path) {
            return sourceBundle
        }

        let targetDir = Self.uniqueDirectoryName(displayName: sourceName, in: baseURL)
        let targetURL = baseURL.appendingPathComponent(targetDir, isDirectory: true)

        try await Task.detached(priority: .userInitiated) {
            try fm.copyItem(at: sourceURL, to: targetURL)
        }.value

        let imported = HorizonBundle(url: targetURL)
        await refresh()
        return imported
    }

    // MARK: - Rename

    /// Update a bundle's display name and keep its directory name in
    /// sync. The Files app shows the on-disk directory name, so we
    /// move the directory to match what the user just typed rather
    /// than letting them diverge.
    ///
    /// Behavior:
    ///   - Empty / whitespace-only `newName` throws `.invalidName`.
    ///   - Sanitized target directory name is computed from
    ///     `newName`. If it collides with another bundle (NOT the
    ///     bundle being renamed), a " 2", " 3", … counter is
    ///     appended to the directory name only. The user-visible
    ///     `bundle.json::name` is set to `newName` verbatim.
    ///   - The directory move and bundle.json update happen as two
    ///     separate operations; if the move succeeds but the JSON
    ///     write fails, the bundle's name field is stale relative to
    ///     its directory. Acceptable risk: callers that care can
    ///     catch and surface, and the next refresh will reconcile
    ///     by showing whichever name `bundle.json` carries.
    ///   - Returns the bundle at its possibly-new URL. Callers MUST
    ///     replace any held reference to the old bundle.
    @discardableResult
    public func renameBundle(_ bundle: HorizonBundle, to newName: String) async throws -> HorizonBundle {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HorizonBundleError.invalidName(reason: "Name cannot be empty")
        }

        let targetDir = Self.uniqueDirectoryName(
            displayName: trimmed,
            in: baseURL,
            excluding: bundle.url
        )

        if targetDir != bundle.directoryName {
            let targetURL = baseURL.appendingPathComponent(targetDir, isDirectory: true)
            let oldURL = bundle.url
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.moveItem(at: oldURL, to: targetURL)
            }.value
            // Class instance carries through the rename — update its
            // url in place rather than minting a new HorizonBundle.
            bundle.relocate(to: targetURL)
        }

        // Domain-level mutator handles modifiedAt bump + atomic write.
        try await bundle.setName(trimmed)

        await refresh()
        return bundle
    }

    // MARK: - Delete

    /// Delete a bundle and refresh the list.
    public func deleteBundle(_ bundle: HorizonBundle) async throws {
        try await bundle.delete()
        await refresh()
    }

    // MARK: - Preview support

    /// Replace the published `bundles` list with the given handles
    /// without touching disk. Used by `PreviewHorizons.seedPreviewCaptures`
    /// to populate SwiftUI #Previews with synthetic bundles whose
    /// files live in a per-preview temp directory. Not intended for
    /// production callers — pair with the
    /// `XCODE_RUNNING_FOR_PREVIEWS` guard in `.shared`'s init so the
    /// auto-refresh on first access doesn't clobber the injection.
    public func injectBundles(_ bundles: [HorizonBundle]) {
        self.bundles = bundles
    }

    // MARK: - Directory naming

    /// Build a directory name that doesn't collide with anything
    /// already at `baseURL`. Appends ` 2`, ` 3`, … if needed.
    /// `excluding` is the URL of a bundle whose directory should be
    /// ignored during collision-checking — used by rename so a
    /// bundle's existing directory doesn't count as a collision
    /// against itself.
    static func uniqueDirectoryName(
        displayName: String,
        in baseURL: URL,
        excluding excludeURL: URL? = nil
    ) -> String {
        let base = sanitizedDirectoryStem(displayName)
        let ext = "." + HorizonBundle.directoryExtension
        let excludedPath = excludeURL?.standardizedFileURL.path
        var candidate = base + ext
        var counter = 2
        while true {
            let candidateURL = baseURL.appendingPathComponent(candidate)
            let exists = FileManager.default.fileExists(atPath: candidateURL.path)
            let isSelf = excludedPath != nil
                && candidateURL.standardizedFileURL.path == excludedPath
            if !exists || isSelf { return candidate }
            candidate = "\(base) \(counter)" + ext
            counter += 1
        }
    }

    /// Strip path-unsafe characters from a user-provided display
    /// name. Returns "Untitled" for empty input. The returned string
    /// does NOT include the `.horizon` extension — callers append
    /// it.
    static func sanitizedDirectoryStem(_ displayName: String) -> String {
        let cleaned = displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "\0", with: "_")
        return cleaned.isEmpty ? "Untitled" : cleaned
    }
}
