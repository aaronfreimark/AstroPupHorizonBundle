//
//  TestImageMaker.swift
//  AstroPupHorizonBundleTests
//
//  Cross-platform helper for creating tiny placeholder PlatformImages
//  in tests. The package is multi-platform; using UIKit's
//  `UIGraphicsImageRenderer` directly would force the test target to
//  be iOS-only.
//

import Foundation
import CoreGraphics
import ImageIO
@preconcurrency import UniformTypeIdentifiers
@testable import AstroPupHorizonBundle

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum TestImageMaker {

    /// Build a solid-color PlatformImage at the given size. Returns
    /// `nil` only if CoreGraphics fails to allocate the context, which
    /// shouldn't happen for the tiny test sizes we use.
    static func makeImage(
        width: Int = 8,
        height: Int = 4,
        rgba: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255)
    ) -> PlatformImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            fatalError("Failed to allocate test CGContext")
        }
        ctx.setFillColor(
            red: CGFloat(rgba.0) / 255.0,
            green: CGFloat(rgba.1) / 255.0,
            blue: CGFloat(rgba.2) / 255.0,
            alpha: CGFloat(rgba.3) / 255.0
        )
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cg = ctx.makeImage() else {
            fatalError("Failed to create CGImage")
        }
        #if canImport(UIKit)
        return UIImage(cgImage: cg)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cg, size: CGSize(width: width, height: height))
        #endif
    }
}
