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
///
/// Punctuation and Western text are spaced as Japanese typesetting spaces them; see ``TategakiSpacing``.
///
/// Build the text from ``Run``s to give parts of it their own font and colour, ruby, emphasis marks, or to set
/// digits upright:
///
/// ```swift
/// TategakiText(runs: [
///     .init("明治"), .init("39", tateChuYoko: true), .init("年、"),
///     .init("山路", ruby: "やまみち"), .init("を登る"),
/// ])
/// ```
public struct TategakiText: View {
    /// A stretch of text in one font and one colour, which may carry ruby or emphasis marks, or be set upright.
    public struct Run: Hashable, Sendable {
        public var text: String
        public var font: TategakiFont
        public var color: Color
        /// Ruby (furigana): small text to the right of the run that gives its reading. It is set over the run as
        /// a whole, and a run that would straddle the end of a column moves to the next one, so give each word its
        /// own run. A run with ruby that is longer than a column comes out a character to a column, and a warning
        /// that names it is logged.
        public var ruby: String?
        /// Emphasis marks, one to the right of each character. Spaces and punctuation take none. A run with ruby
        /// shows the ruby and no marks, because the two would share the same place.
        public var emphasis: TategakiEmphasis?
        /// Tate-chu-yoko (縦中横): sets the run upright, its characters side by side in the space of one, as the
        /// "12" of 12月 is set. It works for runs of one to four characters, and relies on the font having narrow
        /// forms of them; a longer run is set as it would be without this.
        public var isTateChuYoko: Bool

        public init(_ text: String, font: TategakiFont = .gothic(size: 17), color: Color = .primary,
                    ruby: String? = nil, emphasis: TategakiEmphasis? = nil, tateChuYoko: Bool = false) {
            self.text = text
            self.font = font
            self.color = color
            self.ruby = ruby
            self.emphasis = emphasis
            self.isTateChuYoko = tateChuYoko
        }
    }

    private var runs: [Run]
    private var maxHeight: CGFloat
    private var columnGap: CGFloat
    private var isSelectable = false
    private var spacingRules = TategakiSpacing.standard

    @Environment(\.self) private var environment

    /// Vertical text in one font and one colour.
    ///
    /// - Parameters:
    ///   - maxHeight: The longest a column may be. Text that doesn't fit continues in the next column to the left.
    ///   - columnGap: Space added between columns, on top of the spacing the font asks for. That spacing differs
    ///     from font to font: Hiragino's columns are one and a half times the font size apart before any gap.
    ///     Ruby and emphasis marks lie in the space between columns and don't widen it, so give them room here if
    ///     the font leaves little.
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

    /// Lets people select the text by dragging across it, and copy what they selected with the Copy command.
    /// Select All selects all of it once the text has been clicked.
    ///
    /// The copied text has no ruby and no emphasis marks. A selection starts and ends between characters, and
    /// takes a tate-chu-yoko group whole.
    ///
    /// Selection is off unless you ask for it, because a selectable text takes clicks and keyboard focus, which
    /// would get in the way inside a button or a list row.
    @available(iOS, unavailable, message: "Selection is implemented for macOS only.")
    public func selectable(_ isSelectable: Bool = true) -> TategakiText {
        var copy = self
        copy.isSelectable = isSelectable
        return copy
    }

    /// Chooses which of the spacing adjustments of Japanese typesetting are made. All of them are, unless you say
    /// otherwise; pass `.none` for the spacing Core Text gives.
    public func spacing(_ spacing: TategakiSpacing) -> TategakiText {
        var copy = self
        copy.spacingRules = spacing
        return copy
    }

    public var body: some View {
        let layout = TategakiLayoutCache.shared.layout(for: key)
        canvas(for: layout)
            .accessibilityElement()
            .accessibilityLabel(runs.map(\.text).joined())
            .accessibilityAddTraits(.isStaticText)
    }

    @ViewBuilder private func canvas(for layout: TategakiLayout) -> some View {
        #if os(macOS)
        if isSelectable {
            TategakiSelectableCanvas(layout: layout)
        } else {
            plainCanvas(for: layout)
        }
        #else
        plainCanvas(for: layout)
        #endif
    }

    private func plainCanvas(for layout: TategakiLayout) -> some View {
        Canvas { context, _ in
            context.withCGContext { layout.draw(in: $0) }
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }

    /// The colours are resolved here, in the view's environment, so they follow light and dark appearance.
    private var key: TategakiLayoutKey {
        TategakiLayoutKey(
            runs: runs.map {
                .init(text: $0.text, font: $0.font, color: $0.color.resolve(in: environment),
                      ruby: $0.ruby, emphasis: $0.emphasis, isTateChuYoko: $0.isTateChuYoko)
            },
            maxHeight: maxHeight,
            columnGap: columnGap,
            spacing: spacingRules
        )
    }
}
