#!/usr/bin/env swift

// Draws the app icon from the same SF Symbol the menu bar uses, so the two can
// never drift apart. Run it after changing anything here:
//
//     ./make-icon.swift
//
// It writes AppIcon.icns next to this file; build.sh copies that into the
// bundle. The .icns is committed, so a normal build needs no toolchain beyond
// Swift itself.

import AppKit
import Foundation

let symbolName = "cup.and.saucer.fill"

/// macOS icons are not full-bleed: the artwork sits on a rounded square that
/// leaves a margin on all sides. These are Apple's proportions for a 1024pt
/// canvas — an 824pt square with a 185.4pt corner radius — expressed as
/// fractions so any canvas size lands in the same place.
let squareFraction: CGFloat = 824.0 / 1024.0
let radiusFraction: CGFloat = 185.4 / 824.0
/// How much of that square the cup fills. Leaves the glyph room to breathe.
let glyphFraction: CGFloat = 0.56

let topColor = NSColor(srgbRed: 0.91, green: 0.53, blue: 0.38, alpha: 1)
let bottomColor = NSColor(srgbRed: 0.76, green: 0.31, blue: 0.21, alpha: 1)

func makeIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high

    let side = size * squareFraction
    let origin = (size - side) / 2
    let square = NSRect(x: origin, y: origin, width: side, height: side)
    let radius = side * radiusFraction

    let background = NSBezierPath(roundedRect: square, xRadius: radius, yRadius: radius)
    NSGradient(starting: topColor, ending: bottomColor)?.draw(in: background, angle: -90)

    // The symbol is asked for at the size it will be drawn, so its strokes are
    // hinted for that size rather than scaled up from a smaller master.
    let glyphSide = side * glyphFraction
    let configuration = NSImage.SymbolConfiguration(pointSize: glyphSide, weight: .regular)
    guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
    else {
        FileHandle.standardError.write(Data("Symbol \(symbolName) is unavailable.\n".utf8))
        exit(1)
    }

    // Centred on the square, not the canvas: the two differ once the margin is
    // taken into account.
    let drawn = symbol.size
    let glyphRect = NSRect(
        x: square.midX - drawn.width / 2,
        y: square.midY - drawn.height / 2,
        width: drawn.width,
        height: drawn.height
    )

    // Symbols carry their own black artwork, so recolouring means flooding
    // through .sourceAtop — which paints wherever the destination is already
    // opaque. That has to happen on its own transparent canvas: done straight
    // onto the icon it would flood the whole rect, background included.
    let white = NSImage(size: drawn, flipped: false) { rect in
        symbol.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    white.draw(in: glyphRect)

    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else { throw NSError(domain: "make-icon", code: 1) }
    try png.write(to: url)
}

let here = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()
let iconset = here.appendingPathComponent("AppIcon.iconset")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// iconutil expects exactly these names.
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = CGFloat(base * scale)
        let suffix = scale == 1 ? "" : "@2x"
        let name = "icon_\(base)x\(base)\(suffix).png"
        try writePNG(makeIcon(size: pixels), to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "--convert", "icns",
    "--output", here.appendingPathComponent("AppIcon.icns").path,
    iconset.path,
]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }

// The .iconset is scaffolding for iconutil; only the .icns is kept.
try? FileManager.default.removeItem(at: iconset)
print("Wrote AppIcon.icns")
