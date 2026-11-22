import CoreGraphics
import CoreText
import Foundation
import SwiftUI
import Testing
@testable import Tategaki

// Hiragino Mincho ships with macOS. Its kanji are one em tall in vertical text, which makes the sizes below easy to
// predict.
private let mincho = TategakiFont.mincho(size: 20)
private let black = Color.Resolved(red: 0, green: 0, blue: 0, opacity: 1)

private func layout(_ text: String, font: TategakiFont = mincho, maxHeight: CGFloat = .infinity, columnGap: CGFloat = 5) -> TategakiLayout {
    TategakiLayout(TategakiLayoutKey(runs: [.init(text: text, font: font, color: black)], maxHeight: maxHeight, columnGap: columnGap))
}

@Test func theTestFontIsInstalled() {
    #expect(CTFontCopyPostScriptName(mincho.ctFont) as String == "HiraMinProN-W3")
}

@Test func emptyTextHasNoSize() {
    let empty = layout("")
    #expect(empty.columnCount == 0)
    #expect(empty.size == .zero)
}

@Test func unboundedTextIsOneColumnAsLongAsItsCharacters() {
    let one = layout("春夏秋冬")
    #expect(one.columnCount == 1)
    #expect(abs(one.size.height - 80) <= 1)
    #expect(abs(one.size.width - 20) <= 2)
}

@Test func textLongerThanMaxHeightContinuesInANewColumn() {
    // Twelve characters, four to a column.
    let wrapped = layout("春夏秋冬春夏秋冬春夏秋冬", maxHeight: 85)
    #expect(wrapped.columnCount == 3)
    #expect(abs(wrapped.size.height - 80) <= 1)
}

@Test func columnsStackRightToLeft() {
    let wrapped = layout("春夏秋冬春夏秋冬春夏秋冬", maxHeight: 85)
    #expect(wrapped.columnOrigins == wrapped.columnOrigins.sorted(by: >))
    #expect(Set(wrapped.columnOrigins).count == wrapped.columnOrigins.count)
}

@Test func aLineBreakStartsANewColumn() {
    #expect(layout("春夏\n秋冬").columnCount == 2)
}

@Test func columnGapMovesColumnsApart() {
    let tight = layout("春夏秋冬春夏秋冬", maxHeight: 85, columnGap: 0)
    let loose = layout("春夏秋冬春夏秋冬", maxHeight: 85, columnGap: 12)
    let tightPitch = tight.columnOrigins[0] - tight.columnOrigins[1]
    let loosePitch = loose.columnOrigins[0] - loose.columnOrigins[1]
    #expect(abs((loosePitch - tightPitch) - 12) <= 0.5)
    #expect(abs((loose.size.width - tight.size.width) - 12) <= 2)
}

@Test func theBoundsFitTheColumnsTightly() {
    let wrapped = layout("春夏秋冬春夏秋冬春夏秋冬", maxHeight: 85, columnGap: 0)
    let pitch = wrapped.columnOrigins[0] - wrapped.columnOrigins[1]
    // Three columns: two pitches between centre lines, plus half a column on either side.
    #expect(abs(wrapped.size.width - (2 * pitch + 20)) <= 2)
}

@Test func aColumnTooShortForOneCharacterStillHoldsOne() {
    // Core Text never leaves a line empty, so nothing is lost when maxHeight is smaller than the font.
    let cramped = layout("春夏秋冬", maxHeight: 5)
    #expect(cramped.columnCount == 4)
    #expect(abs(cramped.size.height - 20) <= 1)
}

@Test func runsShareAColumn() {
    let key = TategakiLayoutKey(runs: [
        .init(text: "春夏", font: mincho, color: black),
        .init(text: "秋冬", font: .named("HiraMinProN-W3", size: 30), color: black),
    ], maxHeight: .infinity, columnGap: 5)
    let mixed = TategakiLayout(key)
    #expect(mixed.columnCount == 1)
    #expect(abs(mixed.size.height - 100) <= 1)
}

@Test func theBuiltInFacesAreInstalledAndFullWidth() {
    for font in [TategakiFont.gothic(size: 20), .mincho(size: 20)] {
        guard case .named(let name, _) = font.storage else { continue }
        #expect(CTFontCopyPostScriptName(font.ctFont) as String == name)
        #expect(abs(layout("春夏秋冬", font: font).size.height - 80) <= 1)
    }
}

/// Draws a layout the way the view's Canvas does, top left origin with y pointing down, and returns which cells of
/// a grid over its bounds have ink in them. A cell is one column pitch wide and one character tall.
private func inkedCells(of layout: TategakiLayout, pitch: CGFloat, character: CGFloat = 20) -> Set<[Int]> {
    let width = Int(layout.size.width), height = Int(layout.size.height)
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    layout.draw(in: context)

    let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
    var cells = Set<[Int]>()
    for y in 0..<height {
        for x in 0..<width where pixels[y * context.bytesPerRow + x] < 128 {
            cells.insert([Int(CGFloat(x) / pitch), Int(CGFloat(y) / character)])
        }
    }
    return cells
}

@Test func everyCharacterIsDrawnInsideTheBounds() throws {
    // 田 fills its square, so each of the twelve character cells must have ink. A wrong flip or offset would leave
    // cells empty, because the ink would land outside the bitmap.
    let wrapped = layout("田田田田田田田田田田田田", maxHeight: 85, columnGap: 0)
    try #require(wrapped.columnCount == 3)
    let pitch = wrapped.columnOrigins[0] - wrapped.columnOrigins[1]
    let cells = inkedCells(of: wrapped, pitch: pitch)
    for column in 0..<3 {
        for row in 0..<4 {
            #expect(cells.contains([column, row]), "no ink in column \(column), row \(row)")
        }
    }
}

@Test func theFirstCharacterIsAtTheTopRight() throws {
    // Two columns of four cells, the rest full-width spaces: the first character must be the top of the right
    // column, and the last the bottom of the left one.
    let wrapped = layout("田　　　\n　　　田", columnGap: 0)
    try #require(wrapped.columnCount == 2)
    let pitch = wrapped.columnOrigins[0] - wrapped.columnOrigins[1]
    let cells = inkedCells(of: wrapped, pitch: pitch)
    #expect(cells.contains([1, 0]))
    #expect(cells.contains([0, 3]))
    #expect(!cells.contains([0, 0]))
    #expect(!cells.contains([1, 3]))
}

@MainActor @Test func equalInputsShareOneLayout() {
    let key = TategakiLayoutKey(runs: [.init(text: "春夏秋冬", font: mincho, color: black)], maxHeight: 100, columnGap: 5)
    let cache = TategakiLayoutCache.shared
    #expect(cache.layout(for: key) === cache.layout(for: key))
}

/// Renders the view to PNG files for looking at, when TATEGAKI_SNAPSHOT_DIR names a folder to put them in.
@MainActor @Test func snapshots() throws {
    guard let folder = ProcessInfo.processInfo.environment["TATEGAKI_SNAPSHOT_DIR"] else { return }
    let sample = "山路を登りながら、こう考えた。智に働けば角が立つ。情に棹させば流される。意地を通せば窮屈だ。とかくに人の世は住みにくい。"

    func write(_ name: String, _ view: some View) throws {
        let renderer = ImageRenderer(content: view.padding(24).background(Color.white))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let url = URL(fileURLWithPath: folder).appendingPathComponent(name)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    try write("mincho.png", TategakiText(sample, font: .mincho(size: 22), color: .black, maxHeight: 300, columnGap: 8))
    try write("gothic.png", TategakiText(sample, font: .gothic(size: 22), color: .black, maxHeight: 300, columnGap: 8))
    try write("default-dark.png", TategakiText(sample, maxHeight: 200).padding(20).background(Color.black).environment(\.colorScheme, .dark))
    try write("runs.png", TategakiText(runs: [
        .init("草枕", font: .named("HiraMinProN-W6", size: 34), color: .black),
        .init("　夏目漱石\n", font: .mincho(size: 16), color: .gray),
        .init("「智に働けば角が立つ」――1906年、Tokyo。", font: .mincho(size: 20), color: Color(red: 0.7, green: 0.2, blue: 0.15)),
    ], maxHeight: 260, columnGap: 8))
}
