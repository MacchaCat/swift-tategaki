import CoreGraphics
import CoreText
import Foundation
import os
import SwiftUI

/// What a layout is made from. Two equal keys give the same layout, so a layout can be cached by its key.
struct TategakiLayoutKey: Hashable, Sendable {
    struct Run: Hashable, Sendable {
        var text: String
        var font: TategakiFont
        var color: Color.Resolved
        var ruby: String? = nil
        var emphasis: TategakiEmphasis? = nil
        var isTateChuYoko = false
    }

    var runs: [Run]
    var maxHeight: CGFloat
    var columnGap: CGFloat
    var spacing = TategakiSpacing.standard
}

/// Text laid out in columns that run top to bottom and stack right to left.
///
/// Core Text breaks the text into lines and shapes each one, with ruby and tate-chu-yoko. The layout places the
/// lines itself, as columns, in the coordinates of the view that draws them: the origin is the top left corner of
/// the layout's bounds and y points down.
final class TategakiLayout: @unchecked Sendable {
    // Everything here is immutable after init, and Core Text's line objects are safe to read from any thread, so
    // the layout can be drawn from a Canvas that renders off the main thread.

    struct Column {
        var line: CTLine
        /// The UTF-16 range of the text in this column, including a line break that ends it.
        var range: Range<Int>
        /// The x coordinate of the centre line the characters sit on.
        var x: CGFloat
        /// The y coordinate at which the column's text starts.
        var top: CGFloat
        /// How long the text is, from `top` downwards.
        var length: CGFloat
        /// How far the characters reach left and right of `x`. Ruby and emphasis marks lie further right.
        var halfLeft: CGFloat
        var halfRight: CGFloat
    }

    /// The size of ruby text and of sesame emphasis marks, as a fraction of the font size.
    static let rubyScale: CGFloat = 0.5
    /// The most characters Core Text sets upright as one tate-chu-yoko group.
    static let longestTateChuYoko = 4

    /// The text without its ruby, as UTF-16, which is what Core Text's indices count.
    let string: NSString
    /// The columns, the first one rightmost.
    let columns: [Column]
    /// The size of the columns together, with their ruby and emphasis marks.
    let size: CGSize
    /// Where a selection may start or end: between characters, never inside one, nor inside a tate-chu-yoko group.
    let boundaries: [Int]
    /// The runs with ruby that didn't fit in one column, as UTF-16 ranges. Core Text sets such a run a character to
    /// a column, which is never what was wanted, so each is reported with a warning in the log.
    let brokenRubyRuns: [Range<Int>]
    /// Marks whose ink starts before the place Core Text reports for them, because the blank ahead of them was
    /// closed up: how far before, by UTF-16 offset. See `SpacingRules.adjust`.
    private let boundaryShifts: [Int: CGFloat]

    private static let logger = Logger(subsystem: "Tategaki", category: "layout")

    var columnCount: Int { columns.count }
    var columnOrigins: [CGFloat] { columns.map(\.x) }

    init(_ key: TategakiLayoutKey) {
        let text = NSMutableAttributedString()
        var groups: [Range<Int>] = []
        var rubyRuns: [Range<Int>] = []
        for run in key.runs {
            let start = text.length
            Self.append(run, to: text, groups: &groups)
            if let ruby = run.ruby, !ruby.isEmpty, text.length > start { rubyRuns.append(start..<text.length) }
        }
        string = text.string as NSString
        boundaries = Self.boundaries(of: string, groups: groups)
        var rules = SpacingRules()
        boundaryShifts = rules.adjust(text, groups: groups, spacing: key.spacing)

        // Break the text into lines no longer than the columns may be.
        let typesetter = CTTypesetterCreateWithAttributedString(text)
        let limit = key.maxHeight.isFinite ? Double(max(key.maxHeight, 0)) : 10_000_000
        var lines: [(line: CTLine, range: Range<Int>)] = []
        var start = 0
        while start < text.length {
            let count = max(CTTypesetterSuggestLineBreak(typesetter, start, limit), 1)
            lines.append((CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)), start..<start + count))
            start += count
        }

        // A run with ruby belongs in one column. One that was broken is longer than a column can be.
        brokenRubyRuns = rubyRuns.filter { run in lines.count(where: { $0.range.overlaps(run) }) > 1 }
        for run in brokenRubyRuns {
            let excerpt = string.substring(with: NSRange(location: run.lowerBound, length: min(run.count, 16)))
            Self.logger.warning("""
                TategakiText: the run with ruby that starts “\(excerpt)” is longer than a column \
                (maxHeight \(key.maxHeight, format: .fixed(precision: 0))) and was broken a character to a column. \
                Give each word its own run, or allow a longer column.
                """)
        }

        // Place the columns from right to left. A line's ascent points right in a column and its descent left, and
        // its leading is the room the font wants before the next column. Ruby adds to a line's ascent, but it is
        // left out of the spacing so that columns are the same distance apart with or without it; it lies in the
        // room between columns. To know a line's ascent without its ruby, the same characters are shaped again
        // from a copy of the text that has none.
        let bare = NSMutableAttributedString(attributedString: text)
        bare.removeAttribute(.init(kCTRubyAnnotationAttributeName as String), range: NSRange(location: 0, length: bare.length))
        let bareTypesetter = CTTypesetterCreateWithAttributedString(bare)
        struct Metrics { var length, ascent, descent, leading, halfRight, lift: CGFloat; var ink: CGRect }
        let metrics = lines.map { entry -> Metrics in
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let length = CGFloat(CTLineGetTypographicBounds(entry.line, &ascent, &descent, &leading))
                - SpacingRules.trailingSpace(of: text, in: entry.range)
            let lift = key.spacing.setsColumnTopsFlush ? rules.lift(forColumnAt: entry.range.lowerBound, of: text, groups: groups) : 0
            let bareLine = CTTypesetterCreateLine(bareTypesetter, CFRange(location: entry.range.lowerBound, length: entry.range.count))
            var halfRight: CGFloat = 0
            _ = CTLineGetTypographicBounds(bareLine, &halfRight, nil, nil)
            let ink = CTLineGetBoundsWithOptions(entry.line, .useGlyphPathBounds)
            return Metrics(length: length, ascent: ascent, descent: descent, leading: leading, halfRight: min(halfRight, ascent),
                           lift: lift, ink: ink.isNull ? .zero : ink)
        }
        var xs: [CGFloat] = []
        for (index, metric) in metrics.enumerated() {
            if index == 0 {
                xs.append(0)
            } else {
                let previous = metrics[index - 1]
                xs.append(xs[index - 1] - previous.descent - previous.leading - key.columnGap - metric.halfRight)
            }
        }

        // The bounds: every column with its ruby, and any ink that reaches past the ends of a line, as ruby longer
        // than its base does. A column that starts with an opening bracket starts above the top by the blank that
        // precedes the bracket, so that the bracket itself is at the top.
        var left = CGFloat.infinity, right = -CGFloat.infinity, top: CGFloat = 0, bottom: CGFloat = 0
        for (x, metric) in zip(xs, metrics) {
            left = min(left, x - metric.descent, x + metric.ink.minY)
            right = max(right, x + metric.ascent, x + metric.ink.maxY)
            top = min(top, metric.ink.minX - metric.lift)
            bottom = max(bottom, metric.length - metric.lift, metric.ink.maxX - metric.lift)
        }
        if lines.isEmpty { left = 0; right = 0 }
        left = floor(left)
        top = floor(top)
        size = CGSize(width: ceil(right) - left, height: ceil(bottom) - top)
        columns = zip(lines, zip(xs, metrics)).map { entry, placed in
            Column(line: entry.line, range: entry.range, x: placed.0 - left, top: -top - placed.1.lift, length: placed.1.length,
                   halfLeft: placed.1.descent, halfRight: placed.1.halfRight)
        }
    }

    // MARK: Building the attributed string

    private static func append(_ run: TategakiLayoutKey.Run, to text: NSMutableAttributedString, groups: inout [Range<Int>]) {
        var attributes: [NSAttributedString.Key: Any] = [
            .init(kCTFontAttributeName as String): run.font.ctFont,
            .init(kCTForegroundColorAttributeName as String): run.color.cgColor,
            .init(kCTVerticalFormsAttributeName as String): true,
        ]
        let rubyKey = NSAttributedString.Key(kCTRubyAnnotationAttributeName as String)
        let start = text.length

        // Tate-chu-yoko: a few characters set upright, side by side, in the space of one.
        let isGroup = run.isTateChuYoko && (1...longestTateChuYoko).contains(run.text.count)
            && !run.text.contains(where: \.isNewline)
        if isGroup {
            attributes[.init(kCTHorizontalInVerticalFormsAttributeName as String)] = run.text.count
        }

        if let ruby = run.ruby, !ruby.isEmpty {
            attributes[rubyKey] = annotation(ruby, scale: rubyScale)
            text.append(NSAttributedString(string: run.text, attributes: attributes))
        } else if let emphasis = run.emphasis, isGroup {
            // One mark for the whole group, which reads as one character.
            attributes[rubyKey] = annotation(emphasis.mark, scale: emphasis.scale)
            text.append(NSAttributedString(string: run.text, attributes: attributes))
        } else if let emphasis = run.emphasis {
            // A mark beside each character. Each gets an annotation of its own, so the text can still break
            // between them. Spaces and punctuation take no mark.
            for character in run.text {
                var each = attributes
                if !character.isWhitespace, !character.isNewline, !character.isPunctuation {
                    each[rubyKey] = annotation(emphasis.mark, scale: emphasis.scale)
                }
                text.append(NSAttributedString(string: String(character), attributes: each))
            }
        } else {
            text.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        if isGroup { groups.append(start..<text.length) }
    }

    private static func annotation(_ text: String, scale: CGFloat) -> CTRubyAnnotation {
        CTRubyAnnotationCreateWithAttributes(.auto, .auto, .before, text as CFString,
                                             [kCTRubyAnnotationSizeFactorAttributeName: scale] as CFDictionary)
    }

    private static func boundaries(of string: NSString, groups: [Range<Int>]) -> [Int] {
        var result = [0]
        var index = 0, group = 0
        while index < string.length {
            var end = NSMaxRange(string.rangeOfComposedCharacterSequence(at: index))
            while group < groups.count, groups[group].upperBound <= index { group += 1 }
            if group < groups.count, groups[group].contains(index) { end = max(end, groups[group].upperBound) }
            result.append(end)
            index = end
        }
        return result
    }

    // MARK: Drawing

    /// Draws the columns into a context whose origin is at the top left with y pointing down, as a SwiftUI Canvas's
    /// is, so that they fill a rectangle of `size` at the origin.
    func draw(in context: CGContext) {
        for column in columns {
            context.saveGState()
            // Core Text draws a line along x with its ascent towards +y. Turn that so the line runs down the
            // column and its ascent points right. With y pointing down, that is a swap of the two axes.
            context.concatenate(CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: column.x, ty: column.top))
            context.textMatrix = .identity
            context.textPosition = .zero
            CTLineDraw(column.line, context)
            context.restoreGState()
        }
    }

    // MARK: Geometry

    /// The rectangles that cover the characters in a UTF-16 range, one for each column the range touches. They
    /// cover the characters themselves, not their ruby.
    func rects(for range: Range<Int>) -> [CGRect] {
        columns.compactMap { column in
            let covered = range.clamped(to: column.range)
            guard !covered.isEmpty else { return nil }
            let from = offset(of: covered.lowerBound, in: column)
            let to = offset(of: covered.upperBound, in: column)
            guard to > from else { return nil }
            return CGRect(x: column.x - column.halfLeft, y: column.top + from,
                          width: column.halfLeft + column.halfRight, height: to - from)
        }
    }

    /// The boundary between characters that is nearest to a point.
    func index(at point: CGPoint) -> Int {
        guard !columns.isEmpty else { return 0 }
        // Columns are ordered right to left; take the one whose centre line is nearest.
        let column = columns.min { abs($0.x - point.x) < abs($1.x - point.x) }!
        let end = textEnd(of: column)
        // Walk down the column's characters. The point is before the first one whose middle lies below it. A
        // character's extent is the part of it inside the view: the bracket at the top of a flush column has its
        // blank half above the view, and a click on the bracket must be able to land before it.
        var low = 0, high = boundaries.count - 1
        while low < high {
            let middle = (low + high) / 2
            if boundaries[middle] < column.range.lowerBound { low = middle + 1 } else { high = middle }
        }
        var start = column.range.lowerBound
        var top = max(column.top + offset(of: start, in: column), 0)
        var next = low + (boundaries[low] == start ? 1 : 0)
        while next < boundaries.count, boundaries[next] <= end {
            let bottom = min(column.top + offset(of: boundaries[next], in: column), size.height)
            if point.y < (top + bottom) / 2 { return start }
            start = boundaries[next]
            top = bottom
            next += 1
        }
        return end
    }

    /// The boundary nearest to an index that isn't one.
    func snapped(_ index: Int) -> Int {
        var low = 0, high = boundaries.count - 1
        while low < high {
            let middle = (low + high) / 2
            if boundaries[middle] < index { low = middle + 1 } else { high = middle }
        }
        if low > 0, index - boundaries[low - 1] < boundaries[low] - index { return boundaries[low - 1] }
        return boundaries[low]
    }

    /// The text in a UTF-16 range, without ruby or emphasis marks.
    func text(in range: Range<Int>) -> String {
        let covered = range.clamped(to: 0..<string.length)
        return string.substring(with: NSRange(location: covered.lowerBound, length: covered.count))
    }

    private func offset(of index: Int, in column: Column) -> CGFloat {
        if index >= textEnd(of: column) { return max(column.length, CGFloat(CTLineGetOffsetForStringIndex(column.line, index, nil))) }
        // A mark whose leading blank was closed up starts, to the eye, where its ink does.
        let shift = index > column.range.lowerBound ? boundaryShifts[index] ?? 0 : 0
        return CGFloat(CTLineGetOffsetForStringIndex(column.line, index, nil)) + shift
    }

    /// The end of a column's text, before the line break that ends the column if it has one.
    private func textEnd(of column: Column) -> Int {
        var end = column.range.upperBound
        while end > column.range.lowerBound, let scalar = Unicode.Scalar(string.character(at: end - 1)),
              CharacterSet.newlines.contains(scalar) {
            end -= 1
        }
        return end
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
