import CoreGraphics
import Foundation
import Testing
@testable import Tategaki

// Twelve characters, four to a column, three columns from right to left. Each is 20 points tall.
private let wrapped = layout("一二三四五六七八九十百千", maxHeight: 85, columnGap: 0)

private func point(column: Int, down: CGFloat) -> CGPoint {
    CGPoint(x: wrapped.columns[column].x, y: wrapped.columns[column].top + down)
}

@Test func aClickSelectsNothing() {
    var selection = TategakiSelection()
    selection.begin(at: point(column: 0, down: 30), in: wrapped)
    selection.end()
    #expect(selection.isEmpty)
    #expect(selection.text(in: wrapped) == "")
}

@Test func draggingDownAColumnSelectsWhatItPasses() {
    var selection = TategakiSelection()
    selection.begin(at: point(column: 0, down: 22), in: wrapped)
    selection.extend(to: point(column: 0, down: 58), in: wrapped)
    #expect(selection.text(in: wrapped) == "二三")
}

@Test func draggingIntoTheNextColumnSelectsToTheEndOfTheFirst() {
    var selection = TategakiSelection()
    selection.begin(at: point(column: 0, down: 42), in: wrapped)
    selection.extend(to: point(column: 1, down: 22), in: wrapped)
    #expect(selection.text(in: wrapped) == "三四五")
    #expect(wrapped.rects(for: selection.range).count == 2)
}

@Test func draggingBackwardsSelectsTheSameText() {
    var selection = TategakiSelection()
    selection.begin(at: point(column: 1, down: 22), in: wrapped)
    selection.extend(to: point(column: 0, down: 42), in: wrapped)
    #expect(selection.text(in: wrapped) == "三四五")
    // Dragging back past where the drag began turns the selection around.
    selection.extend(to: point(column: 2, down: 38), in: wrapped)
    #expect(selection.text(in: wrapped) == "六七八九十")
}

@Test func aNewDragReplacesTheSelection() {
    var selection = TategakiSelection()
    selection.begin(at: point(column: 0, down: 2), in: wrapped)
    selection.extend(to: point(column: 0, down: 78), in: wrapped)
    selection.end()
    #expect(selection.text(in: wrapped) == "一二三四")
    selection.begin(at: point(column: 2, down: 2), in: wrapped)
    selection.extend(to: point(column: 2, down: 22), in: wrapped)
    #expect(selection.text(in: wrapped) == "九")
}

@Test func selectAllTakesEverythingAndClearTakesNothing() {
    var selection = TategakiSelection()
    selection.selectAll(in: wrapped)
    #expect(selection.text(in: wrapped) == "一二三四五六七八九十百千")
    selection.clear()
    #expect(selection.isEmpty)
}

@Test func aSelectionTakesATateChuYokoGroupWhole() {
    let dated = layout([run("平成"), run("12", tateChuYoko: true), run("年")])
    let column = dated.columns[0]
    var selection = TategakiSelection()
    // From the middle of 成 to the middle of the group: the nearest boundaries are after 成 and one side of "12".
    selection.begin(at: CGPoint(x: column.x, y: column.top + 22), in: dated)
    selection.extend(to: CGPoint(x: column.x, y: column.top + 58), in: dated)
    #expect(selection.text(in: dated) == "成12")
}

@Test func theSelectedTextHasNoRubyOrMarks() {
    let annotated = layout([run("山路", ruby: "やまみち"), run("を"), run("登る", emphasis: .sesame)])
    var selection = TategakiSelection()
    selection.selectAll(in: annotated)
    #expect(selection.text(in: annotated) == "山路を登る")
}
