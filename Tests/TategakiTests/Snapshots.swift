import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Testing
import Tategaki

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

    let body = TategakiFont.mincho(size: 22)
    func text(_ string: String) -> TategakiText.Run { .init(string, font: body, color: .black) }
    func ruby(_ string: String, _ reading: String) -> TategakiText.Run { .init(string, font: body, color: .black, ruby: reading) }
    func upright(_ string: String) -> TategakiText.Run { .init(string, font: body, color: .black, tateChuYoko: true) }
    func marked(_ string: String, _ style: TategakiEmphasis = .sesame) -> TategakiText.Run { .init(string, font: body, color: .black, emphasis: style) }
    try write("typography.png", TategakiText(runs: [
        text("明治"), upright("39"), text("年"), upright("9"), text("月、"),
        ruby("山路", "やまみち"), text("を"), ruby("登", "のぼ"), text("りながら、こう"), ruby("考", "かんが"), text("えた。"),
        ruby("智", "ち"), text("に"), ruby("働", "はたら"), text("けば"), ruby("角", "かど"), text("が"), ruby("立", "た"), text("つ。"),
        ruby("情", "じょう"), text("に"), ruby("棹", "さお"), text("させば"), ruby("流", "なが"), text("される。"),
        marked("とかくに人の世は住みにくい"), text("。"),
        text("圏点は"), marked("黒丸", .dot), text("や"), marked("白丸", .circle), text("や"), marked("白胡麻", .openSesame), text("にもできる"), upright("!?"),
    ], maxHeight: 330, columnGap: 6))
}
