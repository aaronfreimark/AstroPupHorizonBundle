//
//  BundleJSON.swift
//  AstroPupHorizonBundle
//
//  Shared JSONEncoder/Decoder used by every bundle file (bundle.json,
//  horizon.json, pano.json, frames/manifest.json). Configured once so
//  the on-disk format stays consistent with HORIZON_BUNDLE_FORMAT.md.
//
//  - Dates are ISO-8601 strings (human-readable, portable to other
//    languages without timezone hassles).
//  - Output is pretty-printed with sorted keys, so diffs are stable
//    and a human inspecting a bundle in the Files app or by
//    extracting one can read it.
//

import Foundation

enum BundleJSON {
    static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()

    static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()
}
