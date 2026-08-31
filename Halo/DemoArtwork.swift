//
//  DemoArtwork.swift
//  Halo
//
//  Pictures for the simulated cast, drawn rather than shipped.
//

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Demo content only. Drawn in code so the repo carries no image assets and
/// nobody's artwork is being copied — the point is to see a *picture* in a
/// halo, not any particular picture.
enum DemoArtwork {

    static let overNineThousand: Data? = render(lines: ["IT'S OVER", "9000!!!"],
                                                from: (1.0, 0.45, 0.05),
                                                to: (1.0, 0.85, 0.25))

    private static func render(lines: [String],
                               from startColour: (CGFloat, CGFloat, CGFloat),
                               to endColour: (CGFloat, CGFloat, CGFloat),
                               size: CGSize = CGSize(width: 400, height: 300)) -> Data? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil,
                                      width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // An energy-blast sort of background.
        let colours = [CGColor(colorSpace: space, components: [startColour.0, startColour.1, startColour.2, 1])!,
                       CGColor(colorSpace: space, components: [endColour.0, endColour.1, endColour.2, 1])!]
        if let gradient = CGGradient(colorsSpace: space, colors: colours as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: 0, y: size.height),
                                       end: CGPoint(x: size.width, y: 0),
                                       options: [])
        }

        // White fill with a heavy black outline — the look everyone recognises.
        let font = CTFontCreateWithName("Impact" as CFString, 58, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .init(kCTFontAttributeName as String): font,
            .init(kCTForegroundColorAttributeName as String): CGColor(colorSpace: space, components: [1, 1, 1, 1])!,
            .init(kCTStrokeColorAttributeName as String): CGColor(colorSpace: space, components: [0, 0, 0, 1])!,
            .init(kCTStrokeWidthAttributeName as String): -7.0,
        ]

        let lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + 10
        var y = (size.height + lineHeight * CGFloat(lines.count - 1)) / 2 - lineHeight / 2

        for line in lines {
            let attributed = NSAttributedString(string: line, attributes: attributes)
            let typeset = CTLineCreateWithAttributedString(attributed)
            let bounds = CTLineGetBoundsWithOptions(typeset, [])

            context.textPosition = CGPoint(x: (size.width - bounds.width) / 2, y: y)
            CTLineDraw(typeset, context)
            y -= lineHeight
        }

        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
