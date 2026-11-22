import CoreGraphics
import Foundation
import Testing
@testable import Tategaki

// MARK: Ruby

@Test func rubyDoesNotChangeTheDistanceBetweenColumns() {
    let plain = layout("春夏秋冬\n春夏秋冬\n春夏秋冬")
    let withRuby = layout([run("春夏秋冬\n"), run("春夏", ruby: "はるなつ"), run("秋冬\n春夏秋冬")])
    #expect(withRuby.columnCount == 3)
    for index in 0..<2 {
        let pitch = withRuby.columnOrigins[index] - withRuby.columnOrigins[index + 1]
        let plainPitch = plain.columnOrigins[index] - plain.columnOrigins[index + 1]
        #expect(abs(pitch - plainPitch) <= 0.5)
    }
}

@Test func rubyIsDrawnToTheRightOfItsColumnAndInsideTheBounds() throws {
    let withRuby = layout([run("山", ruby: "やま"), run("路")])
    let column = try #require(withRuby.columns.first)
    let ink = Ink(withRuby)
    // Right of the characters, beside the first one only.
    let beside = CGRect(x: column.x + column.halfRight + 1, y: column.top, width: 12, height: 20)
    #expect(ink.isInked(beside))
    #expect(!ink.isInked(beside.offsetBy(dx: 0, dy: 20)))
    #expect(inkIsInsideBounds(withRuby))
    // The bounds grew to the right to hold it.
    #expect(withRuby.size.width - layout("山路").size.width >= 8)
}

@Test func rubyLongerThanItsBaseStaysInsideTheBounds() {
    // Five kana over one kanji: the ruby reaches past both ends of its base, at the very top of a column.
    #expect(inkIsInsideBounds(layout([run("承", ruby: "うけたまわ"), run("る")])))
    #expect(inkIsInsideBounds(layout([run("春夏秋\n"), run("承", ruby: "うけたまわ")])))
}

@Test func rubyIsNotPartOfTheText() {
    let withRuby = layout([run("山路", ruby: "やまみち"), run("を登る")])
    #expect(withRuby.string as String == "山路を登る")
    #expect(withRuby.text(in: 0..<5) == "山路を登る")
}

// MARK: Tate-chu-yoko

@Test func tateChuYokoSetsAGroupInTheSpaceOfOneCharacter() {
    let upright = layout([run("年"), run("123", tateChuYoko: true), run("年")])
    let sideways = layout("年123年")
    #expect(abs(upright.columns[0].length - 60) <= 1)
    #expect(sideways.columns[0].length > 66)
    #expect(inkIsInsideBounds(upright))
}

@Test func tateChuYokoGroupsOfOneToFourCharactersFitTheColumn() {
    for digits in ["1", "12", "123", "1234"] {
        let upright = layout([run("年"), run(digits, tateChuYoko: true), run("年")])
        #expect(abs(upright.columns[0].length - 60) <= 1, "\(digits) is not one character tall")
        #expect(inkIsInsideBounds(upright))
        // The digits stay within the column's own width.
        let column = upright.columns[0]
        let ink = Ink(upright)
        #expect(!ink.isInked(CGRect(x: column.x + column.halfRight + 1, y: 20, width: 20, height: 20)), "\(digits) spills right")
        #expect(!ink.isInked(CGRect(x: column.x - column.halfLeft - 21, y: 20, width: 20, height: 20)), "\(digits) spills left")
    }
}

@Test func aRunTooLongForTateChuYokoIsSetAsUsual() {
    let asked = layout([run("年"), run("12345", tateChuYoko: true), run("年")])
    let plain = layout("年12345年")
    #expect(abs(asked.columns[0].length - plain.columns[0].length) <= 0.5)
    // And it is not one unit for selection.
    #expect(asked.boundaries == [0, 1, 2, 3, 4, 5, 6, 7])
}

@Test func aTateChuYokoGroupIsOneUnit() {
    let upright = layout([run("年"), run("12", tateChuYoko: true), run("月")])
    #expect(upright.boundaries == [0, 1, 3, 4])
    #expect(upright.snapped(2) == 1 || upright.snapped(2) == 3)
}

// MARK: Emphasis marks

@Test func emphasisMarksSitBesideEachCharacterButNotPunctuation() throws {
    let marked = layout([run("春、夏", emphasis: .sesame)])
    let column = try #require(marked.columns.first)
    let ink = Ink(marked)
    func beside(_ row: Int) -> CGRect {
        CGRect(x: column.x + column.halfRight + 1, y: column.top + CGFloat(row) * 20 + 2, width: 12, height: 16)
    }
    #expect(ink.isInked(beside(0)))
    #expect(!ink.isInked(beside(1)))
    #expect(ink.isInked(beside(2)))
    #expect(inkIsInsideBounds(marked))
}

@Test func everyEmphasisStyleDrawsAMark() throws {
    // A large font, so that the thin outline of the open marks is dark enough to count as ink.
    let large = TategakiFont.mincho(size: 60)
    for style in [TategakiEmphasis.sesame, .openSesame, .dot, .circle, .custom("▲", scale: 0.3)] {
        let marked = layout([run("春", font: large, emphasis: style)])
        let column = try #require(marked.columns.first)
        let isMarked = Ink(marked).isInked(CGRect(x: column.x + column.halfRight + 1, y: column.top, width: 36, height: 60))
        #expect(isMarked, "no mark for \(style.mark)")
        #expect(inkIsInsideBounds(marked), "\(style.mark) is drawn outside the bounds")
    }
}

@Test func emphasisedTextStillBreaksBetweenCharacters() {
    let plain = layout("春夏秋冬春夏秋冬春夏秋冬", maxHeight: 85)
    let marked = layout([run("春夏秋冬春夏秋冬春夏秋冬", emphasis: .sesame)], maxHeight: 85)
    #expect(marked.columnCount == plain.columnCount)
    #expect(marked.columns.map(\.range) == plain.columns.map(\.range))
    let pitch = marked.columnOrigins[0] - marked.columnOrigins[1]
    #expect(abs(pitch - (plain.columnOrigins[0] - plain.columnOrigins[1])) <= 0.5)
}

@Test func emphasisMarksAreNotPartOfTheText() {
    #expect(layout([run("重要", emphasis: .dot), run("な点")]).string as String == "重要な点")
}

@Test func rubyTakesTheMarksPlaceWhenARunHasBoth() {
    let both = layout([run("山路", ruby: "やまみち", emphasis: .sesame)])
    let rubyOnly = layout([run("山路", ruby: "やまみち")])
    let drawnAlike = Ink(both).pixels == Ink(rubyOnly).pixels
    #expect(drawnAlike)
}

@Test func aTateChuYokoGroupTakesOneEmphasisMark() throws {
    let marked = layout([run("12", emphasis: .dot, tateChuYoko: true), run("月")])
    #expect(marked.boundaries == [0, 2, 3])
    let column = try #require(marked.columns.first)
    #expect(Ink(marked).isInked(CGRect(x: column.x + column.halfRight + 1, y: column.top, width: 12, height: 20)))
}

// MARK: Geometry

@Test func eachCharactersRectangleCoversItsInk() throws {
    // Twelve characters, four to a column, three columns from right to left.
    let wrapped = layout("田田田田田田田田田田田田", maxHeight: 85, columnGap: 0)
    try #require(wrapped.columnCount == 3)
    let ink = Ink(wrapped)
    var previous: CGRect?
    for index in 0..<12 {
        let rects = wrapped.rects(for: index..<index + 1)
        try #require(rects.count == 1)
        let rect = rects[0]
        #expect(abs(rect.height - 20) <= 0.5)
        #expect(abs(rect.width - 20) <= 0.5)
        #expect(ink.isInked(rect.insetBy(dx: 2, dy: 2)))
        if let previous {
            if index % 4 == 0 {
                #expect(rect.midX < previous.midX, "column \(index / 4) is not left of the one before")
                #expect(abs(rect.minY) <= 0.5)
            } else {
                #expect(abs(rect.minY - previous.maxY) <= 0.5)
                #expect(abs(rect.midX - previous.midX) <= 0.5)
            }
        }
        previous = rect
    }
}

@Test func aRangeAcrossColumnsGivesARectangleForEach() {
    let wrapped = layout("田田田田田田田田田田田田", maxHeight: 85, columnGap: 0)
    let rects = wrapped.rects(for: 2..<9)
    #expect(rects.count == 3)
    #expect(rects.map { Int(($0.height / 20).rounded()) } == [2, 4, 1])
    #expect(wrapped.rects(for: 3..<3).isEmpty)
}

@Test func aPointFindsTheNearestBoundaryBetweenCharacters() throws {
    let wrapped = layout("田田田田田田田田田田田田", maxHeight: 85, columnGap: 0)
    for index in 0..<12 {
        let rect = try #require(wrapped.rects(for: index..<index + 1).first)
        #expect(wrapped.index(at: CGPoint(x: rect.midX, y: rect.minY + 3)) == index)
        #expect(wrapped.index(at: CGPoint(x: rect.midX, y: rect.maxY - 3)) == index + 1)
    }
    // Above a column is its start, below it its end, and far to either side the nearest column.
    #expect(wrapped.index(at: CGPoint(x: wrapped.columns[1].x, y: -50)) == 4)
    #expect(wrapped.index(at: CGPoint(x: wrapped.columns[1].x, y: 500)) == 8)
    #expect(wrapped.index(at: CGPoint(x: 9999, y: 30)) == 1 || wrapped.index(at: CGPoint(x: 9999, y: 30)) == 2)
    #expect(wrapped.index(at: CGPoint(x: -9999, y: 500)) == 12)
}

@Test func theEndOfAColumnIsBeforeItsLineBreak() {
    let broken = layout("春夏\n秋冬")
    #expect(broken.index(at: CGPoint(x: broken.columns[0].x, y: 500)) == 2)
    #expect(broken.text(in: 0..<broken.index(at: CGPoint(x: broken.columns[0].x, y: 500))) == "春夏")
}

@Test func boundariesNeverSplitACharacter() {
    // 𠮷 and the emoji are two UTF-16 units each; the family emoji is eleven.
    let text = layout("𠮷野家🍣と👨‍👩‍👧‍👦")
    #expect(text.boundaries == [0, 2, 3, 4, 6, 7, 18])
    #expect(text.text(in: 0..<2) == "𠮷")
    #expect(text.text(in: 4..<6) == "🍣")
    #expect([0, 2].contains(text.snapped(1)))
    #expect([7, 18].contains(text.snapped(12)))
    #expect(text.snapped(-5) == 0)
    #expect(text.snapped(99) == 18)
}

@Test func textAcrossRunsIsCopiedWithoutItsAnnotations() {
    let mixed = layout([run("山路", ruby: "やまみち"), run("12", tateChuYoko: true), run("月の"), run("重要", emphasis: .sesame), run("な点")])
    #expect(mixed.text(in: 0..<mixed.string.length) == "山路12月の重要な点")
    #expect(mixed.text(in: 2..<5) == "12月")
}
