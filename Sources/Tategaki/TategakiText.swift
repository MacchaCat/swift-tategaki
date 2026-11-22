import SwiftUI

/// Text written vertically: columns run top to bottom and stack right to left.
///
/// SwiftUI has no vertical text of its own, so a `TategakiText` lays its text out with Core Text and draws it in a
/// view of exactly the size the columns need.
///
/// ```swift
/// TategakiText("吾輩は猫である。名前はまだ無い。", font: .mincho(size: 20), maxHeight: 240)
/// ```
///
/// The view doesn't take its height from the space it's offered. A column is as long as its text unless you give
/// `maxHeight`, and then the text continues in a new column to the left.
public struct TategakiText: View {
    /// A stretch of text in one font and one colour.
    public struct Run: Hashable, Sendable {
        public var text: String
        public var font: TategakiFont
        public var color: Color

        public init(_ text: String, font: TategakiFont = .gothic(size: 17), color: Color = .primary) {
            self.text = text
            self.font = font
            self.color = color
        }
    }

    private var runs: [Run]
    private var maxHeight: CGFloat
    private var columnGap: CGFloat

    @Environment(\.self) private var environment

    /// Vertical text in one font and one colour.
    ///
    /// - Parameters:
    ///   - maxHeight: The longest a column may be. Text that doesn't fit continues in the next column to the left.
    ///   - columnGap: Space added between columns, on top of the spacing the font asks for. That spacing differs
    ///     from font to font: Hiragino's columns are one and a half times the font size apart before any gap.
    public init(_ text: String, font: TategakiFont = .gothic(size: 17), color: Color = .primary,
                maxHeight: CGFloat = .infinity, columnGap: CGFloat = 5) {
        self.init(runs: [Run(text, font: font, color: color)], maxHeight: maxHeight, columnGap: columnGap)
    }

    /// Vertical text whose runs each have their own font and colour. The runs follow one another in the same
    /// column, as words do in a sentence.
    public init(runs: [Run], maxHeight: CGFloat = .infinity, columnGap: CGFloat = 5) {
        self.runs = runs
        self.maxHeight = maxHeight
        self.columnGap = columnGap
    }

    public var body: some View {
        let layout = TategakiLayoutCache.shared.layout(for: key)
        Canvas { context, _ in
            context.withCGContext { layout.draw(in: $0) }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .accessibilityElement()
        .accessibilityLabel(runs.map(\.text).joined())
        .accessibilityAddTraits(.isStaticText)
    }

    /// The colours are resolved here, in the view's environment, so they follow light and dark appearance.
    private var key: TategakiLayoutKey {
        TategakiLayoutKey(
            runs: runs.map { .init(text: $0.text, font: $0.font, color: $0.color.resolve(in: environment)) },
            maxHeight: maxHeight,
            columnGap: columnGap
        )
    }
}
