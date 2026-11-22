import CoreGraphics
import CoreText
import Foundation
import SwiftUI
@testable import Tategaki

// Hiragino Mincho ships with macOS. Its kanji are one em tall in vertical text, which makes the sizes below easy to
// predict.
let mincho = TategakiFont.mincho(size: 20)
let black = Color.Resolved(red: 0, green: 0, blue: 0, opacity: 1)

func run(_ text: String, font: TategakiFont = mincho, ruby: String? = nil, emphasis: TategakiEmphasis? = nil,
         tateChuYoko: Bool = false) -> TategakiLayoutKey.Run {
    .init(text: text, font: font, color: black, ruby: ruby, emphasis: emphasis, isTateChuYoko: tateChuYoko)
}

func layout(_ runs: [TategakiLayoutKey.Run], maxHeight: CGFloat = .infinity, columnGap: CGFloat = 5,
            spacing: TategakiSpacing = .standard) -> TategakiLayout {
    TategakiLayout(TategakiLayoutKey(runs: runs, maxHeight: maxHeight, columnGap: columnGap, spacing: spacing))
}

func layout(_ text: String, font: TategakiFont = mincho, maxHeight: CGFloat = .infinity, columnGap: CGFloat = 5,
            spacing: TategakiSpacing = .standard) -> TategakiLayout {
    layout([run(text, font: font)], maxHeight: maxHeight, columnGap: columnGap, spacing: spacing)
}

/// A layout drawn the way the view's Canvas draws it, top left origin with y pointing down, into a bitmap with a
/// margin around the layout's bounds, so that ink outside the bounds can be seen.
struct Ink {
    static let margin = 24
    let width: Int, height: Int, bytesPerRow: Int
    let pixels: [UInt8]

    init(_ layout: TategakiLayout) {
        width = Int(layout.size.width) + 2 * Self.margin
        height = Int(layout.size.height) + 2 * Self.margin
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: CGFloat(Self.margin), y: CGFloat(Self.margin))
        layout.draw(in: context)
        bytesPerRow = context.bytesPerRow
        pixels = Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: bytesPerRow * height))
    }

    /// Whether there is ink in a rectangle given in the layout's coordinates.
    func isInked(_ rect: CGRect) -> Bool {
        let xs = max(Int(rect.minX.rounded(.down)) + Self.margin, 0)..<min(Int(rect.maxX.rounded(.up)) + Self.margin, width)
        let ys = max(Int(rect.minY.rounded(.down)) + Self.margin, 0)..<min(Int(rect.maxY.rounded(.up)) + Self.margin, height)
        for y in ys {
            for x in xs where pixels[y * bytesPerRow + x] < 128 { return true }
        }
        return false
    }

    /// The smallest rectangle, in the layout's coordinates, that holds all the ink.
    var bounds: CGRect {
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * bytesPerRow + x] < 128 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return .null }
        return CGRect(x: minX - Self.margin, y: minY - Self.margin, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Which cells of a grid over the layout's bounds have ink. A cell is `pitch` wide and `character` tall.
    func cells(pitch: CGFloat, character: CGFloat = 20, in size: CGSize) -> Set<[Int]> {
        var cells = Set<[Int]>()
        for y in 0..<Int(size.height) {
            for x in 0..<Int(size.width) where pixels[(y + Self.margin) * bytesPerRow + x + Self.margin] < 128 {
                cells.insert([Int(CGFloat(x) / pitch), Int(CGFloat(y) / character)])
            }
        }
        return cells
    }
}

func inkedCells(of layout: TategakiLayout, pitch: CGFloat) -> Set<[Int]> {
    Ink(layout).cells(pitch: pitch, in: layout.size)
}

/// Whether all of a layout's ink lies inside its bounds, to within a pixel of rounding.
func inkIsInsideBounds(_ layout: TategakiLayout) -> Bool {
    let ink = Ink(layout).bounds
    guard !ink.isNull else { return true }
    return CGRect(origin: .zero, size: layout.size).insetBy(dx: -1, dy: -1).contains(ink)
}
