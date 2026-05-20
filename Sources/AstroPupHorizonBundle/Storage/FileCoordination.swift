//
//  FileCoordination.swift
//  AstroPupHorizonBundle
//
//  Thin filesystem helpers for the storage layer.
//
//  HISTORY: an earlier revision wrapped these in `NSFileCoordinator`
//  on the theory that ubiquity-container writes needed coordination
//  with iCloud's File Provider. Empirically that backfires: with
//  `.forReplacing`, the coordinator stages writes through a
//  promote-asynchronously path, and another in-process read of the
//  canonical URL sees the pre-replacement content (or a "permission
//  denied" error from the File Provider) until iCloud upload
//  completes. Within a single process the OS-level atomic-write
//  semantics of `Data.write(to:options:.atomic)` are already enough,
//  and cross-device consistency is what iCloud's own conflict-
//  resolution is for.
//
//  All helpers are nonisolated and safe to call from a detached
//  Task.
//

import Foundation

enum FileCoordination {

    /// Write `data` atomically to `url`. `.atomic` does write-to-
    /// temp + rename, so a concurrent reader either sees the old
    /// content or the new content — never a partial / torn write.
    static func write(
        _ data: Data,
        to url: URL,
        options: Data.WritingOptions = .atomic
    ) throws {
        try data.write(to: url, options: options)
    }

    /// Delete the item at `url`. Missing items are silently treated
    /// as success (matches `try?` semantics).
    static func delete(at url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as NSError where error.code == NSFileNoSuchFileError {
            // Missing → success.
        }
    }

    /// Move `from` → `to`.
    static func move(from src: URL, to dst: URL) throws {
        try FileManager.default.moveItem(at: src, to: dst)
    }

    /// Copy `from` → `to`.
    static func copy(from src: URL, to dst: URL) throws {
        try FileManager.default.copyItem(at: src, to: dst)
    }
}
