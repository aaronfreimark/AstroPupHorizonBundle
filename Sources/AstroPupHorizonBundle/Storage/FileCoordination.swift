//
//  FileCoordination.swift
//  AstroPupHorizonBundle
//
//  Thin wrappers around NSFileCoordinator for the few file-system
//  operations the bundle storage layer performs. NSFileCoordinator
//  prevents data corruption when two writers (different apps on the
//  same device, or sibling devices via iCloud sync) try to touch the
//  same file at the same time — it acquires a lock that's
//  system-wide for ubiquity items.
//
//  All helpers are nonisolated and safe to call from a detached
//  Task. They block until the lock is acquired; for production
//  callers that means the @MainActor caller should always hop to a
//  detached task before invoking them (which the package already
//  does for every write).
//

import Foundation

enum FileCoordination {

    /// Write `data` atomically to `url`, coordinating with any other
    /// file presenter on the same item (locally or via iCloud).
    /// Equivalent to `data.write(to: url, options: .atomic)` outside
    /// of coordination — adds the lock plus the iCloud-aware
    /// "another writer was just here, update your view" notification.
    static func write(
        _ data: Data,
        to url: URL,
        options: Data.WritingOptions = .atomic
    ) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        var writeError: Error?
        coordinator.coordinate(
            writingItemAt: url,
            options: [.forReplacing],
            error: &coordError
        ) { writeURL in
            do {
                try data.write(to: writeURL, options: options)
            } catch {
                writeError = error
            }
        }
        if let err = writeError { throw err }
        if let err = coordError { throw err }
    }

    /// Delete the item at `url` under coordination. Missing items are
    /// silently treated as success (matches `try?` semantics).
    static func delete(at url: URL) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        var opError: Error?
        coordinator.coordinate(
            writingItemAt: url,
            options: [.forDeleting],
            error: &coordError
        ) { deleteURL in
            do {
                try FileManager.default.removeItem(at: deleteURL)
            } catch let error as NSError where error.code == NSFileNoSuchFileError {
                // Missing → success.
            } catch {
                opError = error
            }
        }
        if let err = opError { throw err }
        if let err = coordError { throw err }
    }

    /// Move `from` → `to` under coordinated access of both URLs.
    static func move(from src: URL, to dst: URL) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        var opError: Error?
        coordinator.coordinate(
            writingItemAt: src,
            options: [.forMoving],
            writingItemAt: dst,
            options: [.forReplacing],
            error: &coordError
        ) { srcURL, dstURL in
            do {
                try FileManager.default.moveItem(at: srcURL, to: dstURL)
            } catch {
                opError = error
            }
        }
        if let err = opError { throw err }
        if let err = coordError { throw err }
    }

    /// Copy `from` → `to` under coordinated access of both URLs.
    static func copy(from src: URL, to dst: URL) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        var opError: Error?
        coordinator.coordinate(
            readingItemAt: src,
            options: [.withoutChanges],
            writingItemAt: dst,
            options: [.forReplacing],
            error: &coordError
        ) { srcURL, dstURL in
            do {
                try FileManager.default.copyItem(at: srcURL, to: dstURL)
            } catch {
                opError = error
            }
        }
        if let err = opError { throw err }
        if let err = coordError { throw err }
    }
}
