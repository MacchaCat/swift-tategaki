import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import Tategaki

// The font is 20 points, so a character is 20 tall, half of one 10 and a quarter 5.
private let faces: [TategakiFont] = [.mincho(size: 20), .gothic(size: 20)]

private func height(_ text: String, font: TategakiFont = mincho, spacing: TategakiSpacing = .standard) -> CGFloat {
    layout(text, font: font, spacing: spacing).columns[0].length
}

private func inkCount(_ layout: TategakiLayout) -> Int {
    Ink(layout).pixels.count(where: { $0 < 128 })
}

// MARK: Consecutive punctuation (JLREQ 3.1.4)

@Test func consecutivePunctuationIsClosedUpAsJLREQSays() {
    // Each pair is named in JLREQ 3.1.4. Two marks take one and a half characters, not two.
    let pairs = ["。」", "、」", "」。", "」、", "。「", "、「", "」「", "「「", "」」", "」・", "・「"]
    for font in faces {
        for pair in pairs {
            #expect(abs(height(pair, font: font) - 30) <= 0.5, "\(pair) is \(height(pair, font: font)) tall")
            #expect(abs(height(pair, font: font, spacing: .none) - 40) <= 0.5)
        }
    }
}

@Test func otherPairsAreLeftAlone() {
    // An opening bracket followed by a closing one has its blanks on the outside already, and JLREQ 3.1.4 says
    // nothing of the others.
    for pair in ["「」", "。。", "、、", "・・", "。、", "「。", "・」"] {
        #expect(abs(height(pair) - 40) <= 0.5, "\(pair) is \(height(pair)) tall")
    }
}

@Test func aMarkOnItsOwnKeepsItsBlank() {
    #expect(abs(height("あ。い") - 60) <= 0.5)
    #expect(abs(height("あ「い」う") - 100) <= 0.5)
    #expect(abs(height("あ・い") - 60) <= 0.5)
}

@Test func everyMarkTheRulesNameCanBeClosedUpInTheBuiltInFaces() {
    // A mark is closed up only if the half to remove is blank in the font. This finds out which marks pass.
    var failures: [String] = []
    for font in faces {
        guard case .named(let name, _) = font.storage else { continue }
        for mark in "「『（〔［｛〈《【｟〘〖〝" where abs(height("\(mark)\(mark)", font: font) - 30) > 0.5 { failures.append("\(name) opening \(mark)") }
        for mark in "」』）〕］｝〉》】｠〙〗〟" where abs(height("\(mark)\(mark)", font: font) - 30) > 0.5 { failures.append("\(name) closing \(mark)") }
        for mark in "、，。．" where abs(height("\(mark)」", font: font) - 30) > 0.5 { failures.append("\(name) stop \(mark)") }
        for mark in "・：；" where abs(height("」\(mark)", font: font) - 30) > 0.5 { failures.append("\(name) dot \(mark)") }
    }
    #expect(failures.isEmpty, "not closed up: \(failures.joined(separator: ", "))")
}

@Test func closingUpNeverMakesMarksOverlap() {
    // If two marks ran into each other, some of their ink would coincide and there would be less of it. The blank
    // removed is half a character, a whole number of pixels, so otherwise the ink is the same, moved.
    // The fonts are a Japanese one, a Chinese one that draws its commas and full stops in the middle of the square,
    // and a Western one that has none of the marks. A few marks stand for each class: the pairs number a hundred a
    // font, and laying out thousands is slow where fonts are not cached.
    let fonts = ["HiraMinProN-W3", "PingFangTC-Regular", "Helvetica"]
    let marks = "「（〝」）〟、。・："
    var overlaps: [String] = []
    for name in fonts {
        let font = TategakiFont.named(name, size: 20)
        guard CTFontCopyPostScriptName(font.ctFont) as String == name else { continue }
        for a in marks {
            for b in marks {
                let pair = "\(a)\(b)"
                if inkCount(layout(pair, font: font)) != inkCount(layout(pair, font: font, spacing: .none)) { overlaps.append("\(name) \(pair)") }
            }
        }
    }
    #expect(overlaps.isEmpty, "\(overlaps.count) overlap: \(overlaps.prefix(12).joined(separator: ", "))")
}

@Test func aMarkTheFontDoesNotHaveIsLeftAlone() {
    // Helvetica has no Japanese punctuation, so the system draws these marks from another font. Which one can
    // depend on their neighbours, so they are not touched.
    let western = TategakiFont.named("Helvetica", size: 20)
    for pair in ["」「", "。「", "「「", "」」", "」・"] {
        #expect(abs(height(pair, font: western) - height(pair, font: western, spacing: .none)) <= 0.01, "\(pair) was closed up")
    }
    // The space between Japanese and Western text needs no mark's shape, and is still added.
    #expect(abs(height("語Swift", font: western) - height("語Swift", font: western, spacing: .none) - 5) <= 0.5)
}

@Test func westernPunctuationIsLeftAlone() {
    for text in ["a.(b", "(a),(b)", "x: y; z"] {
        #expect(abs(height(text) - height(text, spacing: .none)) <= 0.01)
    }
}

// MARK: Opening brackets at the top of a column (JLREQ 3.1.5)

@Test func anOpeningBracketAtTheTopOfAColumnIsFlush() throws {
    for font in faces {
        let flush = layout("ああああ「いい」うう", font: font, maxHeight: 85)
        let loose = layout("ああああ「いい」うう", font: font, maxHeight: 85, spacing: .none)
        try #require(flush.columns.count >= 2 && flush.columns[1].range.lowerBound == 4)
        func topIsInked(_ layout: TategakiLayout) -> Bool {
            let column = layout.columns[1]
            return Ink(layout).isInked(CGRect(x: column.x - column.halfLeft, y: 0, width: column.halfLeft + column.halfRight, height: 7))
        }
        #expect(topIsInked(flush))
        #expect(!topIsInked(loose))
        // The column starts half a character above the top, and the others where they did.
        #expect(abs(flush.columns[1].top - (flush.columns[0].top - 10)) <= 0.01)
        #expect(inkIsInsideBounds(flush))
    }
}

@Test func aTextThatStartsWithABracketIsHalfACharacterShorter() {
    let flush = layout("「あ」")
    #expect(abs(flush.size.height - 50) <= 1)
    #expect(abs(layout("「あ」", spacing: .none).size.height - 60) <= 1)
    #expect(inkIsInsideBounds(flush))
    #expect(inkIsInsideBounds(layout("「「あ」」")))
}

@Test func columnsThatStartWithOtherCharactersAreNotMoved() {
    let wrapped = layout("ああああいいいい」うう", maxHeight: 85)
    #expect(Set(wrapped.columns.map(\.top)).count == 1)
}

// MARK: Japanese and Western text (JLREQ 3.2.6)

@Test func aQuarterOfACharacterSeparatesJapaneseFromWesternText() {
    func added(_ text: String) -> CGFloat { height(text) - height(text, spacing: .none) }
    #expect(abs(added("日本語Swift言語") - 10) <= 0.5)
    #expect(abs(added("第12回") - 10) <= 0.5)
    #expect(abs(added("かなABC") - 5) <= 0.5)
    #expect(abs(added("カナé") - 5) <= 0.5)
}

@Test func noSpaceIsAddedWhereJLREQAddsNone() {
    func added(_ text: String) -> CGFloat { height(text) - height(text, spacing: .none) }
    #expect(abs(added("日本語 Swift 言語")) <= 0.01, "a typed space is enough")
    #expect(abs(added("（Swift）")) <= 0.01, "brackets carry their own blank")
    #expect(abs(added("漢字、Swift。漢字")) <= 0.01)
    #expect(abs(added("ＡＢＣ漢字１２３")) <= 0.01, "full-width letters are set as Japanese characters are")
    #expect(abs(added("Swift言語") - 5) <= 0.5, "none before the text starts")
}

@Test func aTateChuYokoRunIsSetSolid() {
    let upright = [run("第"), run("12", tateChuYoko: true), run("回")]
    #expect(abs(layout(upright).columns[0].length - layout(upright, spacing: .none).columns[0].length) <= 0.01)
}

// MARK: Column ends

@Test func spaceAddedAfterTheLastCharacterOfAColumnIsNotCounted() throws {
    // The column breaks between あ and S. The quarter that would separate them is not part of either column.
    let broken = layout("あああSwift", maxHeight: 66)
    try #require(broken.columns[0].range == 0..<3)
    #expect(abs(broken.columns[0].length - 60) <= 0.01)
    #expect(abs(broken.columns[1].length - layout("Swift").columns[0].length) <= 0.01)
    // Core Text does count it when it decides where to break, so a column that had room for exactly three
    // characters takes two.
    #expect(layout("あああSwift", maxHeight: 62).columns[0].range == 0..<2)
}

@Test func noColumnIsLongerThanMaxHeight() {
    let text = "「山路」を登りながら、Swiftで「こう」考えた。（注）「智」に働けば12回、角が立つ。『情』に棹させばABC流される。"
    for maxHeight in stride(from: 45.0, through: 205.0, by: 10.0) {
        let wrapped = layout(text, maxHeight: maxHeight)
        for column in wrapped.columns {
            #expect(column.length <= maxHeight + 0.01, "a column is \(column.length) at \(maxHeight)")
            #expect(column.top + column.length <= wrapped.size.height + 0.01)
        }
        #expect(wrapped.columns.last?.range.upperBound == (text as NSString).length)
        #expect(inkIsInsideBounds(wrapped))
    }
}

@Test func aBreakBetweenTwoMarksPutsEachAtItsEdge() throws {
    // 。 ends the first column and 「 starts the second. The blank after 。 was closed up, so the column ends with
    // the mark itself; the second column is flush.
    let broken = layout("ああああ。「いい」", maxHeight: 105)
    try #require(broken.columns[0].range == 0..<5)
    #expect(abs(broken.columns[0].length - 90) <= 0.01)
    #expect(abs(broken.columns[1].top - (broken.columns[0].top - 10)) <= 0.01)
    #expect(inkIsInsideBounds(broken))
}

// MARK: Geometry after spacing

@Test func eachCharactersRectangleStillCoversItsInk() throws {
    for text in ["あ「「い", "あ」・「い", "あ。「い」」う", "「「あ」」", "日本語Swift言語", "あ」「い"] {
        let spaced = layout(text)
        let ink = Ink(spaced)
        let count = (text as NSString).length
        var previous: CGRect?
        for index in 0..<count {
            let rect = try #require(spaced.rects(for: index..<index + 1).first, "\(text) has no rectangle at \(index)")
            #expect(ink.isInked(rect.insetBy(dx: 1, dy: 1)), "\(text): no ink in the rectangle of character \(index)")
            if let previous {
                #expect(abs(rect.minY - previous.maxY) <= 0.01, "\(text): character \(index) does not start where \(index - 1) ends")
            }
            previous = rect
        }
        // The rectangles hold all the ink between them.
        let all = spaced.rects(for: 0..<count)
        let union = all.dropFirst().reduce(all[0]) { $0.union($1) }
        #expect(union.insetBy(dx: -1, dy: -1).contains(ink.bounds), "\(text): ink outside the characters' rectangles")
    }
}

@Test func aPointOnACharacterFindsItsEdgesAfterSpacing() throws {
    // The top half of each character's visible extent leads to the boundary before it, the bottom half to the one
    // after: closed-up marks and a bracket flush with the top included.
    for text in ["「はい」", "あ「「い", "あ」・「い", "あ。「い」」う", "「「あ」」", "日本語Swift言語"] {
        let spaced = layout(text)
        let count = (text as NSString).length
        let bounds = CGRect(origin: .zero, size: spaced.size)
        for index in 0..<count {
            let rect = try #require(spaced.rects(for: index..<index + 1).first).intersection(bounds)
            #expect(spaced.index(at: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.25)) == index, "\(text): upper part of character \(index)")
            #expect(spaced.index(at: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.75)) == index + 1, "\(text): lower part of character \(index)")
        }
    }
}

@Test func aDragFromABracketAtTheTopOfAColumnSelectsTheBracket() {
    let quoted = layout("「はい」")
    let column = quoted.columns[0]
    var selection = TategakiSelection()
    // The bracket's ink is in the first half character below the top.
    selection.begin(at: CGPoint(x: column.x, y: 2), in: quoted)
    selection.extend(to: CGPoint(x: column.x, y: quoted.size.height - 1), in: quoted)
    #expect(selection.text(in: quoted) == "「はい」")
}

@Test func marksOfDifferentSizesAreClosedUpByTheBlankThatGoes() throws {
    let small = TategakiFont.mincho(size: 20), large = TategakiFont.mincho(size: 40)
    // 」 then a larger 「: the small mark's blank goes, 10 of 60.
    let closingFirst = [run("」", font: small), run("「", font: large)]
    #expect(abs(layout(closingFirst).columns[0].length - 50) <= 0.5)
    // 「 then a larger 「, mid-column: the large mark's blank goes, 20 of 80.
    let openingFirst = [run("あ"), run("「", font: small), run("「", font: large), run("あ", font: large)]
    #expect(abs(layout(openingFirst).columns[0].length - (layout(openingFirst, spacing: .none).columns[0].length - 20)) <= 0.5)
    // A large bracket at the top of a column is raised by half its own size.
    let top = layout([run("ああああ"), run("「", font: large), run("い」", font: large)], maxHeight: 85)
    try #require(top.columns.count >= 2 && top.columns[1].range.lowerBound == 4)
    #expect(abs(top.columns[1].top - (top.columns[0].top - 20)) <= 0.01)
    for sample in [closingFirst, openingFirst] {
        #expect(inkCount(layout(sample)) == inkCount(layout(sample, spacing: .none)))
        #expect(inkIsInsideBounds(layout(sample)))
        let spaced = layout(sample), ink = Ink(spaced)
        for index in 0..<spaced.string.length {
            let rect = try #require(spaced.rects(for: index..<index + 1).first)
            #expect(ink.isInked(rect.insetBy(dx: 1, dy: 1)), "no ink in the rectangle of character \(index)")
        }
    }
    #expect(inkIsInsideBounds(top))
}

@Test func theTextIsUnchangedBySpacing() {
    let text = "「山路」を、Swiftで（注）12回。"
    #expect(layout(text).string as String == text)
    #expect(layout(text).boundaries == layout(text, spacing: .none).boundaries)
}

@Test func spacingMovesInkButNeverAddsOrRemovesAny() {
    // Ruby set twice, or marks that ran together, would change how much ink there is.
    let samples: [[TategakiLayoutKey.Run]] = [
        [run("山路", ruby: "やまみち"), run("Swift"), run("重要", emphasis: .sesame), run("ABC"), run("言語", ruby: "げんご"), run("12")],
        [run("山", ruby: "やま"), run("Swift"), run("語", ruby: "ご"), run("12")],
        [run("「"), run("草枕", ruby: "くさまくら"), run("」「"), run("39", tateChuYoko: true), run("」、「"), run("注", emphasis: .dot), run("」")],
        [run("Swift"), run("言語", ruby: "げんご"), run("。「"), run("重要", emphasis: .sesame), run("」・「ABC」")],
    ]
    for sample in samples {
        #expect(inkCount(layout(sample)) == inkCount(layout(sample, spacing: .none)))
        #expect(inkIsInsideBounds(layout(sample)))
    }
}

@Test func spaceIsNotAddedAfterARunThatSharesItsRuby() {
    // 山路 has one reading over both characters, so no space can follow 路 without breaking it up.
    let shared = [run("山路", ruby: "やまみち"), run("Swift")]
    #expect(abs(layout(shared).columns[0].length - layout(shared, spacing: .none).columns[0].length) <= 0.01)
    // A single character with ruby can take the space, and so can Western text before a run with ruby.
    let single = [run("山", ruby: "やま"), run("Swift")]
    #expect(abs(layout(single).columns[0].length - layout(single, spacing: .none).columns[0].length - 5) <= 0.5)
    let before = [run("Swift"), run("山路", ruby: "やまみち")]
    #expect(abs(layout(before).columns[0].length - layout(before, spacing: .none).columns[0].length - 5) <= 0.5)
}

@Test func rubyAndMarksNextToWesternTextStayInsideTheBounds() {
    #expect(inkIsInsideBounds(layout([run("山路", ruby: "やまみち"), run("Swift"), run("重要", emphasis: .sesame), run("ABC")])))
    #expect(inkIsInsideBounds(layout([run("「", emphasis: .sesame), run("山", ruby: "やま"), run("」「"), run("12", tateChuYoko: true), run("」")])))
}
