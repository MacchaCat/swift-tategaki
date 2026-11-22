import CoreGraphics
import CoreText
import Foundation
import SwiftUI

/// What a layout is made from. Two equal keys give the same layout, so a layout can be cached by its key.
struct TategakiLayoutKey: Hashable, Sendable {
    struct Run: Hashable, Sendable {
        var text: String
        var font: TategakiFont
        var color: Color.Resolved
    }

    var runs: [Run]
    var maxHeight: CGFloat
    var columnGap: CGFloat
}

/// Text laid out in columns that run top to bottom and stack right to left.
///
/// Core Text lays the text out in a frame much larger than the text needs. The layout then measures the columns, so
/// the view can be exactly as large as they are.
final class TategakiLayout: @unchecked Sendable {
    // Everything here is immutable after init, and Core Text's frame and line objects are safe to read from any
    // thread, so the layout can be drawn from a Canvas that renders off the main thread.

    /// The extent of the frame along an axis the caller left unbounded.
    static let unbounded: CGFloat = 100_000

    let frame: CTFrame
    /// The height of the frame the text was laid out in. The text sits against its top right corner.
    let frameHeight: CGFloat
    /// The x coordinate, in the frame, of the left edge of the leftmost column.
    let left: CGFloat
    /// The size of the columns together.
    let size: CGSize
    /// The x coordinate of each column's centre line, in the frame. The first column is the rightmost.
    let columnOrigins: [CGFloat]

    var columnCount: Int { columnOrigins.count }

    init(_ key: TategakiLayoutKey) {
        let text = NSMutableAttributedString()
        for run in key.runs {
            text.append(NSAttributedString(string: run.text, attributes: [
                .init(kCTFontAttributeName as String): run.font.ctFont,
                .init(kCTForegroundColorAttributeName as String): run.color.cgColor,
                .init(kCTVerticalFormsAttributeName as String): true,
            ]))
        }
        var gap = key.columnGap
        let style: CTParagraphStyle = withUnsafePointer(to: &gap) { pointer in
            var settings = [CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size, value: pointer)]
            return CTParagraphStyleCreate(&settings, settings.count)
        }
        text.addAttribute(.init(kCTParagraphStyleAttributeName as String), value: style, range: NSRange(location: 0, length: text.length))

        let setter = CTFramesetterCreateWithAttributedString(text)
        let wide = Self.unbounded
        let tall = key.maxHeight.isFinite ? min(max(key.maxHeight, 0), Self.unbounded) : Self.unbounded
        let attributes = [kCTFrameProgressionAttributeName: NSNumber(value: CTFrameProgression.rightToLeft.rawValue)] as CFDictionary
        frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0),
                                         CGPath(rect: CGRect(x: 0, y: 0, width: wide, height: tall), transform: nil), attributes)
        frameHeight = tall

        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        // In a vertical frame a line's ascent and descent lie along x, and its length along y.
        var low = wide, high: CGFloat = 0, long: CGFloat = 0
        for (line, origin) in zip(lines, origins) {
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let length = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            low = min(low, origin.x - descent)
            high = max(high, origin.x + ascent)
            long = max(long, length)
        }
        if lines.isEmpty { low = 0; high = 0 }
        left = floor(low)
        size = CGSize(width: ceil(high) - left, height: ceil(long))
        columnOrigins = origins.map(\.x)
    }

    /// Draws the columns into a context whose origin is at the top left with y pointing down, as a SwiftUI Canvas's
    /// is, so that they fill a rectangle of `size` at the origin.
    func draw(in context: CGContext) {
        context.saveGState()
        // Core Text draws with y pointing up: flip, then move the text's top left corner to the origin.
        context.translateBy(x: -left, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: size.height - frameHeight)
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}

/// Layouts already made, so that a view drawn again with the same text doesn't lay it out again.
@MainActor
final class TategakiLayoutCache {
    static let shared = TategakiLayoutCache()

    private var layouts: [TategakiLayoutKey: TategakiLayout] = [:]
    private let limit = 512

    func layout(for key: TategakiLayoutKey) -> TategakiLayout {
        if let layout = layouts[key] { return layout }
        if layouts.count >= limit { layouts.removeAll(keepingCapacity: true) }
        let layout = TategakiLayout(key)
        layouts[key] = layout
        return layout
    }
}
