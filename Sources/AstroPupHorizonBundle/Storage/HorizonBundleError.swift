//
//  HorizonBundleError.swift
//  AstroPupHorizonBundle
//
//  Typed errors thrown by `HorizonBundle` and `BundleStore` so
//  callers can branch on specific failure modes (e.g. surface a
//  name-conflict alert instead of a generic "save failed" toast).
//

import Foundation

public enum HorizonBundleError: Error, Equatable {
    /// The bundle's directory doesn't exist or isn't a directory.
    case directoryNotFound(URL)

    /// `bundle.json` is missing or unreadable from a directory that
    /// otherwise looks like a bundle.
    case bundleJSONMissing(URL)

    /// `bundle.json` exists but failed to parse against the schema.
    case bundleJSONMalformed(URL, reason: String)

    /// The bundle declares a `formatVersion` newer than this build
    /// understands.
    case formatVersionTooNew(URL, found: Int, supported: Int)

    /// A referenced sibling file (pano image, frame JPEG) is
    /// missing.
    case fileNotFound(filename: String)

    /// The requested name failed validation (empty, etc.).
    case invalidName(reason: String)

    /// A rename target would collide with an existing bundle.
    case nameConflict(suggestedDirectory: String)
}
