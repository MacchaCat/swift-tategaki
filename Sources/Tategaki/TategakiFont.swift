import CoreText
import Foundation

/// The font of a run of vertical text.
///
/// Vertical text is laid out by Core Text, so a font is named the way Core Text names it: by PostScript name, or as
/// a `CTFont` you built yourself. A SwiftUI `Font` can't be used, because it can't be turned into a `CTFont`.
public struct TategakiFont: Hashable, Sendable {
    enum Storage: Hashable, @unchecked Sendable {
        case named(String, CGFloat)
        // A CTFont is immutable, so sharing one between threads is safe.
        case font(CTFont)
    }

    var storage: Storage

    /// Hiragino Sans, the sans-serif Japanese face that Apple's systems use.
    ///
    /// The system font itself isn't offered: for Japanese it falls back to an interface face whose glyphs are
    /// narrower than their size and whose columns Core Text sets far apart.
    public static func gothic(size: CGFloat) -> TategakiFont {
        .named("HiraginoSans-W3", size: size)
    }

    /// Hiragino Mincho, the serif face that printed vertical text is usually set in.
    public static func mincho(size: CGFloat) -> TategakiFont {
        .named("HiraMinProN-W3", size: size)
    }

    /// A font by PostScript name, such as `"HiraMinProN-W3"`.
    ///
    /// If no font has that name, Core Text substitutes one of its own choosing rather than failing.
    public static func named(_ postScriptName: String, size: CGFloat) -> TategakiFont {
        TategakiFont(storage: .named(postScriptName, size))
    }

    /// A font you created with Core Text, for anything a name and a size can't express.
    public init(_ font: CTFont) {
        storage = .font(font)
    }

    init(storage: Storage) {
        self.storage = storage
    }

    var ctFont: CTFont {
        switch storage {
        case .named(let name, let size):
            CTFontCreateWithName(name as CFString, size, nil)
        case .font(let font):
            font
        }
    }
}
