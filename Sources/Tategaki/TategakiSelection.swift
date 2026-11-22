import SwiftUI

/// The selected stretch of a layout's text, and how pointing at the text changes it.
struct TategakiSelection: Equatable {
    /// Where the drag that is under way began. The selection runs from here to wherever the pointer is.
    private var anchor: Int?
    /// The selected characters, as a UTF-16 range in the layout's text.
    private(set) var range: Range<Int> = 0..<0

    var isEmpty: Bool { range.isEmpty }

    /// The pointer went down at a point: whatever was selected is deselected, and a new selection starts there.
    mutating func begin(at point: CGPoint, in layout: TategakiLayout) {
        let index = layout.index(at: point)
        anchor = index
        range = index..<index
    }

    /// The pointer moved to a point with the button held: the selection reaches from where it began to there.
    mutating func extend(to point: CGPoint, in layout: TategakiLayout) {
        guard let anchor else { return begin(at: point, in: layout) }
        let index = layout.index(at: point)
        range = min(anchor, index)..<max(anchor, index)
    }

    /// The button was released.
    mutating func end() {
        anchor = nil
    }

    mutating func selectAll(in layout: TategakiLayout) {
        anchor = nil
        range = 0..<layout.string.length
    }

    mutating func clear() {
        anchor = nil
        range = 0..<0
    }

    /// The selected text, without ruby or emphasis marks.
    func text(in layout: TategakiLayout) -> String {
        layout.text(in: range)
    }
}

#if os(macOS)
import AppKit

/// A layout drawn with a selection the pointer can drag out and the Copy command can copy.
struct TategakiSelectableCanvas: View {
    var layout: TategakiLayout

    @State private var selection = TategakiSelection()
    @State private var isDragging = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Canvas { context, _ in
            for rect in layout.rects(for: selection.range) {
                context.fill(Path(rect), with: .color(Color(nsColor: .selectedTextBackgroundColor)))
            }
            context.withCGContext { layout.draw(in: $0) }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if isDragging {
                        selection.extend(to: value.location, in: layout)
                    } else {
                        isDragging = true
                        isFocused = true
                        selection.begin(at: value.startLocation, in: layout)
                        selection.extend(to: value.location, in: layout)
                    }
                }
                .onEnded { _ in
                    isDragging = false
                    selection.end()
                }
        )
        // Focus is what routes the Copy and Select All commands here. It is asked for as a text field asks for it,
        // so that a click gives it whether or not the system's keyboard navigation is on.
        .focusable(true, interactions: .edit)
        .focused($isFocused)
        .focusEffectDisabled()
        // With nothing selected there is no Copy command at all. Answering it with nothing to copy would empty
        // the pasteboard.
        .onCopyCommand(perform: selection.isEmpty ? nil : {
            [NSItemProvider(object: selection.text(in: layout) as NSString)]
        })
        .onCommand(#selector(NSResponder.selectAll(_:))) {
            selection.selectAll(in: layout)
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { selection.clear() }
        }
        .onChange(of: layout.string) { _, _ in
            selection.clear()
        }
        .modifier(VerticalTextPointer())
    }
}

/// The I-beam that lies on its side, where the system has one.
private struct VerticalTextPointer: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(.verticalText)
        } else {
            content
        }
    }
}
#endif
