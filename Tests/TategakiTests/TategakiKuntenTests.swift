import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import Tategaki

// A large font, so that marks half its size are dark enough to count as ink: a character is 40 tall, a mark 20.
private let large = TategakiFont.mincho(size: 40)

private func kan(_ text: String, okurigana: String? = nil, kaeriten: String? = nil, ruby: String? = nil) -> TategakiLayoutKey.Run {
    run(text, font: large, ruby: ruby, okurigana: okurigana, kaeriten: kaeriten)
}

private func inkCount(_ layout: TategakiLayout) -> Int {
    Ink(layout).pixels.count(where: { $0 < 128 })
}

/// The rectangle of a mark, from where the layout placed it.
private func rect(_ mark: TategakiLayout.PlacedMark) -> CGRect {
    CGRect(x: mark.x - mark.halfWidth, y: mark.y, width: mark.halfWidth * 2, height: mark.length)
}

// MARK: Placement

@Test func okuriganaSitBesideTheLowerRightOfTheirCharacter() throws {
    let marked = layout([kan("人", okurigana: "ニ"), kan("有")])
    let column = marked.columns[0]
    let mark = try #require(marked.marks.first)
    // Right of the character, and beside its lower half.
    #expect(mark.x > column.x + column.halfRight)
    #expect(abs(mark.y - (column.top + 20)) <= 0.5)
    #expect(Ink(marked).isInked(rect(mark).insetBy(dx: 1, dy: 1)))
    // One kana fits beside the character, so nothing moves.
    #expect(abs(marked.columns[0].length - 80) <= 0.5)
    #expect(inkIsInsideBounds(marked))
}

@Test func kaeritenSitBelowTheLeftOfTheirCharacter() throws {
    let marked = layout([kan("讀", kaeriten: "レ"), kan("書")])
    let column = marked.columns[0]
    let mark = try #require(marked.marks.first)
    #expect(mark.x < column.x)
    #expect(abs(mark.y - (column.top + 40)) <= 0.5)
    #expect(Ink(marked).isInked(rect(mark).insetBy(dx: 1, dy: 1)))
    // The next character starts below the mark.
    let next = try #require(marked.rects(for: 1..<2).first)
    #expect(abs(next.minY - rect(mark).maxY) <= 0.5)
    #expect(abs(marked.columns[0].length - 100) <= 0.5)
    #expect(inkIsInsideBounds(marked))
}

@Test func aGapOpensOnlyAsLongAsTheMarksNeed() {
    func length(_ runs: [TategakiLayoutKey.Run]) -> CGFloat { layout(runs).columns[0].length }
    #expect(abs(length([kan("人"), kan("有")]) - 80) <= 0.5)
    #expect(abs(length([kan("人", okurigana: "ニ"), kan("有")]) - 80) <= 0.5)
    // Three kana: the first beside the character, two below it.
    #expect(abs(length([kan("說", okurigana: "バシカ"), kan("乎")]) - 120) <= 0.5)
    // The longer of the two decides.
    #expect(abs(length([kan("習", okurigana: "フ", kaeriten: "レ"), kan("之")]) - 100) <= 0.5)
    #expect(abs(length([kan("說", okurigana: "バシカ", kaeriten: "一"), kan("乎")]) - 120) <= 0.5)
}

@Test func marksAddInkWithoutDisturbingTheCharacters() {
    // The characters, okurigana and kaeriten don't overlap, so the ink of all three is the sum of each.
    let plain = inkCount(layout([kan("習"), kan("之")]))
    let okurigana = inkCount(layout([kan("習", okurigana: "フ"), kan("之")]))
    let kaeriten = inkCount(layout([kan("習", kaeriten: "レ"), kan("之")]))
    let both = inkCount(layout([kan("習", okurigana: "フ", kaeriten: "レ"), kan("之")]))
    #expect(okurigana > plain)
    #expect(kaeriten > plain)
    #expect(both == okurigana + kaeriten - plain)
}

@Test func okuriganaStartBelowAReading() throws {
    // A reading of one, two and three kana, then okurigana. If the two ran together there would be less ink.
    for reading in ["ひ", "ひさ", "ひさぐ"] {
        let plain = inkCount(layout([kan("鬻"), kan("盾")]))
        let read = inkCount(layout([kan("鬻", ruby: reading), kan("盾")]))
        let sent = inkCount(layout([kan("鬻", okurigana: "グ"), kan("盾")]))
        let both = layout([kan("鬻", okurigana: "グ", ruby: reading), kan("盾")])
        #expect(inkCount(both) == read + sent - plain, "the reading \(reading) and the okurigana overlap")
        #expect(inkIsInsideBounds(both))
    }
    // A one-kana reading leaves the okurigana where they would be; a three-kana one pushes them below.
    let short = try #require(layout([kan("鬻", okurigana: "グ", ruby: "ひ"), kan("盾")]).marks.first)
    let long = try #require(layout([kan("鬻", okurigana: "グ", ruby: "ひさぐ"), kan("盾")]).marks.first)
    #expect(abs(long.y - short.y - 40) <= 0.5)
}

@Test func compoundKaeritenAreSetAsOneMark() throws {
    for marks in ["一レ", "上レ", "二", "下"] {
        let marked = layout([kan("與", kaeriten: marks), kan("矛")])
        #expect(marked.marks.count == 1)
        let mark = try #require(marked.marks.first)
        #expect(Ink(marked).isInked(rect(mark).insetBy(dx: 1, dy: 1)))
        #expect(inkIsInsideBounds(marked))
    }
    // 一レ overlaps its two strokes, so it is shorter than two marks.
    let pair = try #require(layout([kan("與", kaeriten: "一レ"), kan("矛")]).marks.first)
    #expect(pair.length < 30)
}

@Test func marksHangOnTheLastCharacterOfARun() throws {
    let marked = layout([kan("泰山", okurigana: "ニ", kaeriten: "一"), kan("。")])
    #expect(marked.marks.allSatisfy { $0.characterIndex == 1 })
    let second = try #require(marked.rects(for: 1..<2).first)
    #expect(marked.marks.allSatisfy { $0.y >= second.minY })
}

// MARK: Columns

@Test func marksStayInTheColumnOfTheirCharacter() throws {
    let runs = [kan("楚"), kan("人", okurigana: "ニ"), kan("有", okurigana: "リ", kaeriten: "下"), kan("鬻", okurigana: "グ", kaeriten: "二"),
                kan("盾", okurigana: "ト"), kan("與", okurigana: "ヲ", kaeriten: "一レ"), kan("矛"), kan("者", kaeriten: "上"), kan("。")]
    for maxHeight in stride(from: 90.0, through: 330.0, by: 40.0) {
        let wrapped = layout(runs, maxHeight: maxHeight)
        #expect(wrapped.marks.count == 9)
        for mark in wrapped.marks {
            let column = try #require(wrapped.columns.first { $0.range.contains(mark.characterIndex) })
            #expect(abs(mark.x - column.x) < 40, "a mark is not beside its column at \(maxHeight)")
            #expect(mark.y + mark.length <= wrapped.size.height + 0.5)
            #expect(mark.y + mark.length <= column.top + maxHeight + 0.5, "a mark hangs below the column at \(maxHeight)")
        }
        for column in wrapped.columns {
            #expect(column.length <= maxHeight + 0.01)
        }
        #expect(inkIsInsideBounds(wrapped))
    }
}

@Test func aMarkAtTheFootOfAColumnKeepsItsRoom() throws {
    // 讀 has a kaeriten and ends its column. The column is as long as the character and its mark.
    let broken = layout([kan("讀", kaeriten: "レ"), kan("書\n"), kan("登", kaeriten: "二")], maxHeight: 200)
    let last = try #require(broken.columns.last)
    #expect(abs(last.length - 60) <= 0.5)
    #expect(inkIsInsideBounds(broken))
    // A kaeriten at the foot of a column stays with its character, レ included.
    let wrapped = layout([kan("書"), kan("讀", kaeriten: "レ"), kan("書")], maxHeight: 105)
    try #require(wrapped.columns.count == 2 && wrapped.columns[0].range == 0..<2)
    let mark = try #require(wrapped.marks.first)
    #expect(abs(mark.x - wrapped.columns[0].x) < 40)
}

@Test func okuriganaOnTheFirstColumnWidenTheBounds() {
    let plain = layout([kan("人"), kan("有")])
    let marked = layout([kan("人", okurigana: "ニ"), kan("有")])
    #expect(marked.size.width - plain.size.width >= 18)
    #expect(inkIsInsideBounds(marked))
}

// MARK: With the rest of the library

@Test func theGapIsAddedToTheSpacingRules() {
    // 與 is followed by Latin text: the quarter of a character that separates them, and the room for the mark.
    let spaced = layout([kan("與", kaeriten: "二"), kan("A")])
    let unmarked = layout([kan("與"), kan("A")])
    #expect(abs(spaced.columns[0].length - unmarked.columns[0].length - 20) <= 0.5)
    #expect(abs(unmarked.columns[0].length - layout([kan("與"), kan("A")], spacing: .none).columns[0].length - 10) <= 0.5)
    // With the spacing rules off the gap is still there.
    let none = layout([kan("讀", kaeriten: "レ"), kan("書")], spacing: .none)
    #expect(abs(none.columns[0].length - 100) <= 0.5)
}

@Test func aCharacterBeforePunctuationKeepsItsMarks() throws {
    let marked = layout([kan("者", kaeriten: "上"), kan("。")])
    let stop = try #require(marked.rects(for: 1..<2).first)
    let mark = try #require(marked.marks.first)
    #expect(stop.minY >= rect(mark).maxY - 0.5)
    #expect(inkIsInsideBounds(marked))
}

@Test func aRunThatSharesItsReadingCannotMakeRoom() {
    // 遠方 has one reading over both characters. No gap can follow 方, and the layout says so.
    let crowded = layout([kan("遠方", kaeriten: "一", ruby: "ゑんぱう"), kan("來")])
    #expect(crowded.crowdedKuntenRuns == [0..<2])
    #expect(crowded.marks.count == 1)
    // A character of its own has no such trouble.
    let roomy = layout([kan("遠", ruby: "ゑん"), kan("方", kaeriten: "一", ruby: "ぱう"), kan("來")])
    #expect(roomy.crowdedKuntenRuns.isEmpty)
    #expect(layout([kan("人", okurigana: "ニ"), kan("有")]).crowdedKuntenRuns.isEmpty)
}

@Test func theTextIsOnlyTheCharacters() {
    let marked = layout([kan("讀", okurigana: "ム", kaeriten: "レ", ruby: "よ"), kan("書", okurigana: "ヲ"), kan("。")])
    #expect(marked.string as String == "讀書。")
    #expect(marked.boundaries == [0, 1, 2, 3])
    var selection = TategakiSelection()
    selection.selectAll(in: marked)
    #expect(selection.text(in: marked) == "讀書。")
}

@Test func aPointOnACharacterWithMarksFindsItsEdges() throws {
    let marked = layout([kan("有", okurigana: "リ", kaeriten: "下"), kan("鬻", okurigana: "グ", kaeriten: "二"), kan("盾")])
    let ink = Ink(marked)
    for index in 0..<3 {
        let rect = try #require(marked.rects(for: index..<index + 1).first)
        #expect(ink.isInked(rect.insetBy(dx: 1, dy: 1)))
        #expect(marked.index(at: CGPoint(x: rect.midX, y: rect.minY + 5)) == index)
        #expect(marked.index(at: CGPoint(x: rect.midX, y: rect.maxY - 5)) == index + 1)
    }
}

@Test func marksSkipALineBreakOrSpaceThatEndsTheRun() throws {
    for ending in ["\n", "　", " \n"] {
        let marked = layout([kan("讀", kaeriten: "レ"), kan("書" + ending, okurigana: "ヲ"), kan("登")])
        #expect(marked.marks.map(\.characterIndex) == [0, 1], "after \(ending.debugDescription)")
        #expect(inkIsInsideBounds(marked))
    }
    // A run of nothing but white space has nothing to hang marks on.
    #expect(layout([kan("書"), kan("\n", okurigana: "ヲ")]).marks.isEmpty)
}

@Test func okuriganaTakeThePlaceOfEmphasisMarks() {
    let both = layout([run("說", font: large, emphasis: .sesame, okurigana: "ブ"), kan("乎")])
    let okuriganaOnly = layout([kan("說", okurigana: "ブ"), kan("乎")])
    let drawnAlike = Ink(both).pixels == Ink(okuriganaOnly).pixels
    #expect(drawnAlike)
    // A kaeriten is on the other side, so emphasis marks stay.
    let marked = inkCount(layout([run("說", font: large, emphasis: .sesame, kaeriten: "一"), kan("乎")]))
    let unmarked = inkCount(layout([kan("說", kaeriten: "一"), kan("乎")]))
    #expect(marked > unmarked)
}

@Test func runsWithoutKuntenHaveNoMarks() {
    #expect(layout("山路を登りながら").marks.isEmpty)
    #expect(layout([kan("人", okurigana: ""), kan("有", kaeriten: "")]).marks.isEmpty)
}
