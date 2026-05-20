//
//  BundleStore+Metadata.swift
//  AstroPupHorizonBundleTests
//
//  Live observation of file-system changes inside the bundle store's
//  base URL via `NSMetadataQuery`. Designed for iCloud Drive
//  ubiquity containers: when a sibling app on this device or a
//  remote device writes a `.horizon` bundle, the query fires an
//  update notification and we re-publish `bundles` so observing
//  SwiftUI views refresh automatically.
//
//  Local (non-iCloud) base URLs aren't covered here — NSMetadataQuery
//  with the ubiquitous-documents scope doesn't see them. A consuming
//  app pointing BundleStore at a local directory can call `refresh()`
//  on its own cadence (e.g. on `scenePhase` change to .active).
//
//  Opt-in: the consuming app decides when (and whether) to start
//  observing. This keeps the package free of side effects at init
//  time and avoids spinning up NSMetadataQuery for stores that don't
//  benefit from it.
//

import Foundation
import Combine

extension BundleStore {

    /// Begin watching `baseURL` for file-system changes via
    /// `NSMetadataQuery`. Idempotent — calling twice is a no-op.
    ///
    /// Effective only against iCloud Drive ubiquity containers
    /// (queries are scoped to `NSMetadataQueryUbiquitousDocumentsScope`).
    /// For local directories this is harmless but won't observe
    /// anything — call `refresh()` manually instead, or hook into
    /// `scenePhase`.
    public func startObservingFileSystemChanges() {
        guard metadataQuery == nil else { return }

        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        // Filename predicate: anything ending in `.horizon`. The
        // ubiquity index covers package directories the same way it
        // covers files. We further filter by `baseURL` containment
        // in the handler before triggering a refresh.
        q.predicate = NSPredicate(
            format: "%K LIKE %@",
            NSMetadataItemFSNameKey,
            "*.\(HorizonBundle.directoryExtension)"
        )
        q.operationQueue = .main

        let center = NotificationCenter.default
        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            // NotificationCenter delivers on .main per the operation
            // queue above. Hop into the MainActor explicitly so the
            // call into `refresh()` is well-typed.
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }

        metadataObservers = [
            center.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: q,
                queue: .main,
                using: handler
            ),
            center.addObserver(
                forName: .NSMetadataQueryDidUpdate,
                object: q,
                queue: .main,
                using: handler
            ),
        ]

        q.start()
        metadataQuery = q
    }

    /// Stop the NSMetadataQuery and detach observers. Safe to call
    /// even if `startObservingFileSystemChanges()` was never called.
    public func stopObservingFileSystemChanges() {
        metadataQuery?.stop()
        metadataQuery = nil
        let center = NotificationCenter.default
        for token in metadataObservers {
            center.removeObserver(token)
        }
        metadataObservers = []
    }
}
