import CoreGraphics

/// Emphasis marks (圏点, 傍点): a small mark to the right of each character, the way vertical Japanese text stresses
/// a word instead of setting it in italics.
public struct TategakiEmphasis: Hashable, Sendable {
    var mark: String
    /// The size of the mark as a fraction of the font size.
    var scale: CGFloat

    /// A filled sesame mark, ﹅. The usual mark in vertical text.
    public static let sesame = TategakiEmphasis(mark: "﹅", scale: 0.5)
    /// An open sesame mark, ﹆.
    public static let openSesame = TategakiEmphasis(mark: "﹆", scale: 0.5)
    /// A filled dot.
    public static let dot = TategakiEmphasis(mark: "●", scale: 0.25)
    /// An open circle.
    public static let circle = TategakiEmphasis(mark: "○", scale: 0.3)

    /// A mark of your own choosing, drawn in the text's font at `scale` times its size.
    public static func custom(_ mark: Character, scale: CGFloat = 0.5) -> TategakiEmphasis {
        TategakiEmphasis(mark: String(mark), scale: scale)
    }
}
