import CoreGraphics
import CoreText
import Foundation

/// The adjustments to spacing that Japanese typesetting makes and Core Text doesn't.
///
/// Each follows a clause of the W3C's Requirements for Japanese Text Layout (JLREQ). They are on unless you turn
/// them off; `TategakiSpacing.none` leaves every character where Core Text puts it.
public struct TategakiSpacing: Hashable, Sendable {
    /// Closes up punctuation marks that follow one another (JLREQ 3.1.4).
    ///
    /// Brackets, commas and full stops are half a character wide and carry half a character of blank, which makes
    /// two in a row look a whole character apart. This removes the blank between them, so that 。「 or 」「 takes
    /// one and a half characters instead of two.
    public var closesUpPunctuation: Bool

    /// Sets an opening bracket at the top of a column flush with the top, without the blank that precedes it
    /// (JLREQ 3.1.5). It applies to every column, the first of a paragraph included, because the text isn't
    /// indented.
    public var setsColumnTopsFlush: Bool

    /// Adds a quarter of a character between Japanese characters and the Latin letters or digits next to them
    /// (JLREQ 3.2.6). A tate-chu-yoko run gets none, and nor does a boundary where you typed a space.
    ///
    /// None is added after a run of two or more characters that has ruby, because the space would have to be
    /// attached to the run's last character and that would break up its ruby.
    public var spacesWesternText: Bool

    public init(closesUpPunctuation: Bool = true, setsColumnTopsFlush: Bool = true, spacesWesternText: Bool = true) {
        self.closesUpPunctuation = closesUpPunctuation
        self.setsColumnTopsFlush = setsColumnTopsFlush
        self.spacesWesternText = spacesWesternText
    }

    /// All the adjustments.
    public static let standard = TategakiSpacing()
    /// No adjustments: the spacing Core Text gives.
    public static let none = TategakiSpacing(closesUpPunctuation: false, setsColumnTopsFlush: false, spacesWesternText: false)
}

/// The classes of punctuation that JLREQ's spacing rules are written in terms of (its appendix A).
enum PunctuationClass {
    case opening, closing, comma, fullStop, middleDot

    // The full-width members of each class. The ASCII characters JLREQ lists beside them are left out: in a
    // Japanese font they are narrow and belong to Western text.
    private static let members: [(PunctuationClass, String)] = [
        (.opening, "「『（〔［｛〈《【｟〘〖〝"),
        (.closing, "」』）〕］｝〉》】｠〙〗〟"),
        (.comma, "、，"),
        (.fullStop, "。．"),
        (.middleDot, "・：；"),
    ]
    private static let table: [Character: PunctuationClass] = {
        var table: [Character: PunctuationClass] = [:]
        for (kind, characters) in members {
            for character in characters { table[character] = kind }
        }
        return table
    }()

    init?(_ character: Character) {
        guard let kind = Self.table[character] else { return nil }
        self = kind
    }

    /// Whether the blank half of a mark of this class comes after its ink. The marks of the other classes have it
    /// before, or on both sides.
    var hasBlankAfter: Bool { self == .closing || self == .comma || self == .fullStop }
}

/// Decides where the spacing of a text is adjusted, and by how much.
struct SpacingRules {
    /// A character as Core Text sets it on its own in a vertical line: how far it advances, and where along that
    /// advance its ink starts and ends.
    private struct Box {
        var advance, inkStart, inkEnd, em: CGFloat

        var isFullWidth: Bool { abs(advance - em) <= 0.05 * em }
        /// The second half of the advance holds no ink, so it can be taken away.
        var hasBlankAfter: Bool { isFullWidth && inkEnd <= 0.55 * em }
        /// The first half of the advance holds no ink.
        var hasBlankBefore: Bool { isFullWidth && inkStart >= 0.45 * em }
    }

    private struct Unit {
        var range: NSRange
        var character: Character
        var font: CTFont
        var isInGroup: Bool
        var em: CGFloat { CTFontGetSize(font) }
    }

    private static let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
    private static let kernKey = NSAttributedString.Key(kCTKernAttributeName as String)
    private static let rubyKey = NSAttributedString.Key(kCTRubyAnnotationAttributeName as String)
    private static let verticalKey = NSAttributedString.Key(kCTVerticalFormsAttributeName as String)

    // The rules trust what a mark looks like, not what it is: a font may draw a full stop in the middle of its
    // square, as Chinese fonts do, and closing that up would run it into its neighbour. So each mark is shaped and
    // its ink looked at before any blank is taken away.
    private var boxes: [String: Box] = [:]

    private mutating func box(_ unit: Unit) -> Box {
        let key = "\(unit.character)\u{0}\(CTFontCopyPostScriptName(unit.font))\u{0}\(unit.em)"
        if let box = boxes[key] { return box }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(unit.character), attributes: [
            Self.fontKey: unit.font, Self.verticalKey: true,
        ]))
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let box = ink.isNull || ink.isEmpty
            ? Box(advance: advance, inkStart: 0, inkEnd: advance, em: unit.em)
            : Box(advance: advance, inkStart: ink.minX, inkEnd: ink.maxX, em: unit.em)
        boxes[key] = box
        return box
    }

    /// Adds kerning to a text where its spacing is to change. `groups` are its tate-chu-yoko runs.
    ///
    /// Kerning can only follow a character. Where the blank to remove is the one before a mark, the kerning goes on
    /// the character ahead of it, and the mark's ink then starts before the place Core Text reports for the mark.
    /// The result gives, for each such mark, how far back its true start is, keyed by its UTF-16 offset.
    mutating func adjust(_ text: NSMutableAttributedString, groups: [Range<Int>], spacing: TategakiSpacing) -> [Int: CGFloat] {
        guard spacing.closesUpPunctuation || spacing.spacesWesternText else { return [:] }
        var shifts: [Int: CGFloat] = [:]
        var previous: Unit?
        for unit in Self.units(of: text, groups: groups) {
            defer { previous = unit }
            guard let first = previous, !first.isInGroup, !unit.isInGroup else { continue }
            if spacing.closesUpPunctuation, let a = PunctuationClass(first.character), let b = PunctuationClass(unit.character) {
                switch (a, b) {
                case (.comma, .closing), (.fullStop, .closing), (.closing, .comma), (.closing, .fullStop),
                     (.comma, .opening), (.fullStop, .opening), (.closing, .opening), (.closing, .closing):
                    // The blank after the first mark goes.
                    if box(first).hasBlankAfter {
                        Self.kern(text, after: first, by: -first.em / 2)
                    }
                case (.closing, .middleDot):
                    // The same, leaving the quarter of blank that the dot has before it.
                    if box(first).hasBlankAfter, box(unit).isFullWidth {
                        Self.kern(text, after: first, by: -first.em / 2)
                    }
                case (.opening, .opening), (.middleDot, .opening):
                    // The blank before the second mark goes.
                    if box(unit).hasBlankBefore, box(first).isFullWidth, Self.kern(text, after: first, by: -unit.em / 2) {
                        shifts[unit.range.location] = unit.em / 2
                    }
                default:
                    break
                }
            } else if spacing.spacesWesternText {
                if Self.isJapanese(first.character), Self.isWestern(unit.character) {
                    Self.kern(text, after: first, by: first.em / 4)
                } else if Self.isWestern(first.character), Self.isJapanese(unit.character) {
                    Self.kern(text, after: first, by: unit.em / 4)
                }
            }
        }
        return shifts
    }

    /// Changes the space after a character, if that can be done, and says whether it was.
    ///
    /// It can't be done to a character that shares its ruby with others. Core Text sets ruby over a stretch of text
    /// whose attributes are all the same; kerning one character of the stretch would split it in two, and each
    /// part would get the whole of the ruby.
    @discardableResult
    private static func kern(_ text: NSMutableAttributedString, after unit: Unit, by amount: CGFloat) -> Bool {
        var annotated = NSRange()
        let whole = NSRange(location: 0, length: text.length)
        if text.attribute(rubyKey, at: unit.range.location, longestEffectiveRange: &annotated, in: whole) != nil,
           annotated != unit.range {
            return false
        }
        text.addAttribute(kernKey, value: amount, range: unit.range)
        return true
    }

    /// How far to raise a column so that the opening bracket it starts with is flush with the top, or zero if it
    /// doesn't start with one.
    mutating func lift(forColumnAt index: Int, of text: NSAttributedString, groups: [Range<Int>]) -> CGFloat {
        guard index < text.length else { return 0 }
        let string = text.string as NSString
        let range = string.rangeOfComposedCharacterSequence(at: index)
        guard let character = string.substring(with: range).first, PunctuationClass(character) == .opening,
              !groups.contains(where: { $0.contains(index) }),
              let font = text.attribute(Self.fontKey, at: index, effectiveRange: nil) else { return 0 }
        let unit = Unit(range: range, character: character, font: font as! CTFont, isInGroup: false)
        return box(unit).hasBlankBefore ? unit.em / 2 : 0
    }

    /// The space added after the last character of a line, which Core Text counts in the line's length although
    /// nothing comes after it there. Space taken away is not given back: a mark that ends a column and has lost the
    /// blank after it is simply half a character long, as JLREQ 3.1.9 allows at the end of a line.
    static func trailingSpace(of text: NSAttributedString, in range: Range<Int>) -> CGFloat {
        let string = text.string as NSString
        var end = range.upperBound
        while end > range.lowerBound, let scalar = Unicode.Scalar(string.character(at: end - 1)), CharacterSet.newlines.contains(scalar) {
            end -= 1
        }
        guard end > range.lowerBound, let kern = text.attribute(kernKey, at: end - 1, effectiveRange: nil) as? NSNumber else { return 0 }
        return max(CGFloat(kern.doubleValue), 0)
    }

    private static func units(of text: NSAttributedString, groups: [Range<Int>]) -> [Unit] {
        let string = text.string as NSString
        var units: [Unit] = []
        var index = 0, group = 0
        while index < string.length {
            let range = string.rangeOfComposedCharacterSequence(at: index)
            while group < groups.count, groups[group].upperBound <= index { group += 1 }
            if let character = string.substring(with: range).first,
               let font = text.attribute(fontKey, at: index, effectiveRange: nil) {
                units.append(Unit(range: range, character: character, font: font as! CTFont,
                                  isInGroup: group < groups.count && groups[group].contains(index)))
            }
            index = NSMaxRange(range)
        }
        return units
    }

    /// Hiragana, katakana and ideographs: the characters that JLREQ sets a quarter em away from Western text.
    static func isJapanese(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first?.value else { return false }
        switch scalar {
        case 0x3041...0x309F, 0x30A1...0x30FA, 0x30FC...0x30FF, 0x31F0...0x31FF,   // kana
             0x3005...0x3007, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F:   // ideographs
            return true
        default:
            return false
        }
    }

    /// Latin letters and European digits. Their full-width forms are not among them: those are set as Japanese
    /// characters are.
    static func isWestern(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, scalar.value < 0x250 else { return false }
        return scalar.properties.isAlphabetic || scalar.properties.numericType == .decimal
    }
}
