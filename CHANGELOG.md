# Changelog

This project follows [Semantic Versioning](https://semver.org). Until 1.0, a minor version may change the API.

## 0.3.0

- Spacing that follows three clauses of JLREQ: consecutive punctuation is closed up (3.1.4), an opening bracket at
  the top of a column is set flush (3.1.5), and a quarter of a character separates Japanese text from Latin
  letters and digits (3.2.6).
- **This changes how existing text is laid out.** Text with two punctuation marks in a row, a column that starts
  with an opening bracket, or Latin letters next to Japanese is now shorter or longer than in 0.2. Call
  `.spacing(.none)` for the layout of 0.2, which is unchanged byte for byte in the sample images.
- `TategakiSpacing` chooses which of the three adjustments are made.

## 0.2.0

- Ruby (furigana): `Run(_:ruby:)` sets a reading to the right of a run.
- Tate-chu-yoko: `Run(_:tateChuYoko:)` sets a run of one to four characters upright in the space of one.
- Emphasis marks: `Run(_:emphasis:)` sets a mark beside each character, in the styles of `TategakiEmphasis`.
- Selection on macOS: `selectable()` lets people drag across the text and copy it.
- A warning is logged when a run with ruby is longer than a column and has to be broken.
- Columns are now placed by the library instead of by a Core Text frame. Text without ruby or marks keeps its
  column positions. The view now also makes room for ink that reaches past a glyph's own box, so it can be a point
  wider or taller than it was in 0.1.

## 0.1.0

The first release.

- `TategakiText`, a SwiftUI view that sets text in vertical columns, top to bottom and right to left.
- `maxHeight` to continue long text in further columns, and `columnGap` to space them.
- Runs with their own font and colour in one text.
- `TategakiFont`: Hiragino Sans, Hiragino Mincho, any font by PostScript name, or a `CTFont`.
