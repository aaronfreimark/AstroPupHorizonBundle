//
//  PlatformImage.swift
//  AstroPupHorizonBundle
//
//  Cross-platform shim so the bundle API can speak in `UIImage`
//  on iOS and `NSImage` on macOS without forcing consumers (or this
//  package) to fork their call sites. Use `PlatformImage` anywhere
//  a pano or frame image crosses the API boundary.
//
//  Encoding helpers go through `CGImage` + ImageIO, which is the
//  same backend on both platforms. That keeps the on-disk bytes
//  identical regardless of which OS produced them.
//

import Foundation
import CoreGraphics
import ImageIO
@preconcurrency import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif

// MARK: - CGImage extraction

extension PlatformImage {
    /// The image's `CGImage` backing, if any. UIKit exposes this
    /// directly; AppKit needs an explicit best-rep query.
    var platformCGImage: CGImage? {
        #if canImport(UIKit)
        return cgImage
        #elseif canImport(AppKit)
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #endif
    }
}

// MARK: - Encoding helpers

enum PlatformImageEncoding {

    /// Encode `image` as PNG bytes. Returns `nil` if the image has
    /// no CGImage backing or the encoder fails.
    static func pngData(from image: PlatformImage) -> Data? {
        guard let cg = image.platformCGImage else { return nil }
        return pngData(from: cg)
    }

    /// Encode a CGImage directly as PNG bytes.
    static func pngData(from cg: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Encode `image` as JPEG bytes at the given quality (0…1).
    static func jpegData(from image: PlatformImage, quality: CGFloat) -> Data? {
        guard let cg = image.platformCGImage else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(dest, cg, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

// MARK: - Decoding helper

extension PlatformImage {
    /// Decode raw image data into a platform image. Returns `nil` if
    /// the data isn't a supported format.
    static func decode(_ data: Data) -> PlatformImage? {
        #if canImport(UIKit)
        return UIImage(data: data)
        #elseif canImport(AppKit)
        return NSImage(data: data)
        #endif
    }
}
