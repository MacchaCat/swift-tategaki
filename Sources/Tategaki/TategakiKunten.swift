import CoreGraphics
import CoreText
import Foundation
import SwiftUI

/// Kunten: the small marks that let classical Chinese be read as Japanese. Okurigana go to the lower right of a
/// character and kaeriten to its lower left.
///
/// Core Text has nothing for these, so they are set as small lines of their own and hung on the character they
/// belong to. The placement follows the `kanbun` package for LaTeX (Yuanhao Chen): marks are half the size of the
/// character, okurigana start beside the lower half of the character, below any reading it has, and kaeriten sit
/// directly below its left side. Characters are set solid, with a gap after a character only where its marks need
/// one.
enum Kunten {
    /// The size of a mark as a fraction of its character's.
    static let scale: CGFloat = 0.5

    /// A mark before it is known where its character is: which character, and where the mark goes from the top of
    /// that character and the centre line of its column.
    struct Mark {
        var line: CTLine
        var characterIndex: Int
        /// The mark's centre line, right of the column's.
        var dx: CGFloat
        /// The mark's top, below the top of the character.
        var dy: CGFloat
        var length: CGFloat
        var halfWidth: CGFloat
    }

    /// What one run asks for, worked out: its marks, and the gap to leave after its last character for them.
    struct Plan {
        var marks: [Mark] = []
        var gap: CGFloat = 0
        /// The last character of the run, which the marks hang on and the gap follows.
        var character = NSRange()
    }

    private static let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
    private static let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
    private static let verticalKey = NSAttributedString.Key(kCTVerticalFormsAttributeName as String)
    private static let kernKey = NSAttributedString.Key(kCTKernAttributeName as String)

    static func plan(for run: TategakiLayoutKey.Run, at range: Range<Int>, in string: NSString) -> Plan? {
        let okurigana = run.okurigana ?? "", kaeriten = run.kaeriten ?? ""
        guard !range.isEmpty, !okurigana.isEmpty || !kaeriten.isEmpty else { return nil }
        let font = run.font.ctFont
        let em = CTFontGetSize(font), small = em * scale
        let smallFont = CTFontCreateCopyWithAttributes(font, small, nil, nil)
        let color = run.color.cgColor

        // The marks hang on the last character of the run that is a character: not on a line break or a space that
        // ends it.
        var last = range.upperBound
        while last > range.lowerBound, let scalar = Unicode.Scalar(string.character(at: last - 1)),
              CharacterSet.whitespacesAndNewlines.contains(scalar) {
            last -= 1
        }
        guard last > range.lowerBound else { return nil }
        var plan = Plan()
        plan.character = string.rangeOfComposedCharacterSequence(at: last - 1)
        let advance = length(of: string.substring(with: plan.character), font: font)

        // Where the run's reading ends, measured from the top of its last character. On a run with kunten the
        // reading starts at the top of the run.
        var readingEnd = -CGFloat.infinity
        if let ruby = run.ruby, !ruby.isEmpty {
            let whole = length(of: string.substring(with: NSRange(location: range.lowerBound, length: last - range.lowerBound)), font: font)
            let reading = length(of: ruby, font: CTFontCreateCopyWithAttributes(font, em * TategakiLayout.rubyScale, nil, nil))
            readingEnd = reading - (whole - advance)
        }

        if !okurigana.isEmpty {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: okurigana, attributes: [
                fontKey: smallFont, colorKey: color, verticalKey: true,
            ]))
            let length = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            // Tucked in beside the lower half of the character, unless a reading is in the way.
            let top = max(advance - small, readingEnd)
            plan.marks.append(Mark(line: line, characterIndex: plan.character.location, dx: em / 2 + small / 2, dy: top,
                                   length: length, halfWidth: small / 2))
            plan.gap = max(plan.gap, top + length - advance)
        }
        if !kaeriten.isEmpty {
            let (line, lead) = kaeritenLine(kaeriten, font: smallFont, color: color, small: small)
            let length = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            plan.marks.append(Mark(line: line, characterIndex: plan.character.location, dx: -em / 2 + small / 2, dy: advance + lead,
                                   length: length, halfWidth: small / 2))
            plan.gap = max(plan.gap, lead + length)
        }
        return plan
    }

    /// A kaeriten as a small vertical line. Marks that are written together, as 一 and レ are in 一レ, overlap as
    /// they do in print. The second value is how far above its natural place the line starts.
    private static func kaeritenLine(_ marks: String, font: CTFont, color: CGColor, small: CGFloat) -> (CTLine, CGFloat) {
        let text = NSMutableAttributedString(string: marks, attributes: [fontKey: font, colorKey: color, verticalKey: true])
        let characters = Array(marks)
        var lead: CGFloat = 0
        var offset = 0
        for (index, character) in characters.enumerated() {
            let length = String(character).utf16.count
            if index + 1 < characters.count {
                // 一 is a single stroke in the middle of its square, so レ tucks further under it than under the
                // other marks, and the pair starts a little higher.
                let tight = character == "一" && characters[index + 1] == "レ"
                text.addAttribute(kernKey, value: tight ? -0.75 * small : -0.25 * small, range: NSRange(location: offset, length: length))
                if tight, index == 0 { lead = -0.25 * small }
            }
            offset += length
        }
        return (CTLineCreateWithAttributedString(text), lead)
    }

    private static func length(of text: String, font: CTFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [fontKey: font, verticalKey: true]))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
