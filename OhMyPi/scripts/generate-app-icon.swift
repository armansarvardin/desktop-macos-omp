#!/usr/bin/env swift
//
//  generate-app-icon.swift
//  Renders the Oh My Pi app icon (a π glyph on a rounded gradient tile) into
//  an AppIcon.appiconset at every size macOS needs. Uses CoreGraphics and
//  CoreText only, so it runs from a plain `swift` script without an app context.
//
//  Usage: swift scripts/generate-app-icon.swift [output-appiconset-dir]
//

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = URL(
    fileURLWithPath: CommandLine.arguments.dropFirst().first
        ?? "OhMyPi/Assets.xcassets/AppIcon.appiconset",
    isDirectory: true
)

struct IconSlot {
    let points: Int
    let scale: Int

    var pixels: Int { points * scale }
    var filename: String { "icon_\(points)x\(points)@\(scale)x.png" }
}

let slots: [IconSlot] = [
    IconSlot(points: 16, scale: 1), IconSlot(points: 16, scale: 2),
    IconSlot(points: 32, scale: 1), IconSlot(points: 32, scale: 2),
    IconSlot(points: 128, scale: 1), IconSlot(points: 128, scale: 2),
    IconSlot(points: 256, scale: 1), IconSlot(points: 256, scale: 2),
    IconSlot(points: 512, scale: 1), IconSlot(points: 512, scale: 2)
]

enum IconError: Error {
    case context, image, encoder
}

func render(pixels: Int) throws -> Data {
    let size = CGFloat(pixels)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw IconError.context
    }

    context.clear(CGRect(x: 0, y: 0, width: size, height: size))

    // macOS icon grid: the tile fills ~80% of the canvas with ~22% corner radius.
    let inset = size * 0.1
    let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.22, cornerHeight: tile.height * 0.22, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.03, color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(tilePath)
    context.setFillColor(CGColor(red: 0.16, green: 0.12, blue: 0.24, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let colors = [
        CGColor(red: 0.42, green: 0.27, blue: 0.86, alpha: 1),
        CGColor(red: 0.13, green: 0.09, blue: 0.22, alpha: 1)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: tile.minX, y: tile.maxY),
            end: CGPoint(x: tile.maxX, y: tile.minY),
            options: []
        )
    }
    context.restoreGState()

    let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, size * 0.6, nil)
    let attributes: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 1)
    ]
    let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, "π" as CFString, attributes as CFDictionary))
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

    context.saveGState()
    context.textPosition = CGPoint(
        x: tile.midX - bounds.midX,
        y: tile.midY - bounds.midY
    )
    CTLineDraw(line, context)
    context.restoreGState()

    guard let image = context.makeImage() else { throw IconError.image }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
        throw IconError.encoder
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw IconError.encoder }
    return data as Data
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

var images: [[String: String]] = []
for slot in slots {
    let data = try render(pixels: slot.pixels)
    try data.write(to: outputDirectory.appendingPathComponent(slot.filename))
    images.append([
        "filename": slot.filename,
        "idiom": "mac",
        "scale": "\(slot.scale)x",
        "size": "\(slot.points)x\(slot.points)"
    ])
    print("wrote \(slot.filename) (\(slot.pixels)px, \(data.count) bytes)")
}

let contents: [String: Any] = [
    "images": images,
    "info": ["author": "xcode", "version": 1]
]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputDirectory.appendingPathComponent("Contents.json"))
print("wrote Contents.json")
