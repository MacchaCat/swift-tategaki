import AppKit
import SwiftUI
import Tategaki

@main
struct TategakiDemoApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        WindowGroup("Tategaki") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

/// Where the sample text is in the window, for the self-test to aim at.
@MainActor final class Probe {
    static let shared = Probe()
    var textFrame: CGRect = .zero
}

struct ContentView: View {
    @State private var pasted = ""

    var body: some View {
        VStack(alignment: .trailing, spacing: 16) {
            sample
                .selectable()
                .background(GeometryReader { proxy in
                    Color.clear.onAppear { Probe.shared.textFrame = proxy.frame(in: .global) }
                })
            TextField("Paste here to see what was copied", text: $pasted)
                .textFieldStyle(.roundedBorder)
                .frame(width: 360)
        }
        .padding(28)
    }

    private var sample: TategakiText {
        let body = TategakiFont.mincho(size: 22)
        func text(_ string: String) -> TategakiText.Run { .init(string, font: body) }
        func ruby(_ string: String, _ reading: String) -> TategakiText.Run { .init(string, font: body, ruby: reading) }
        func upright(_ string: String) -> TategakiText.Run { .init(string, font: body, tateChuYoko: true) }
        func marked(_ string: String) -> TategakiText.Run { .init(string, font: body, emphasis: .sesame) }
        return TategakiText(runs: [
            text("明治"), upright("39"), text("年"), upright("9"), text("月、"),
            ruby("山路", "やまみち"), text("を"), ruby("登", "のぼ"), text("りながら、こう"), ruby("考", "かんが"), text("えた。"),
            ruby("智", "ち"), text("に"), ruby("働", "はたら"), text("けば"), ruby("角", "かど"), text("が"), ruby("立", "た"), text("つ。"),
            ruby("情", "じょう"), text("に"), ruby("棹", "さお"), text("させば"), ruby("流", "なが"), text("される。"),
            marked("とかくに人の世は住みにくい"), text("。"),
        ], maxHeight: 330, columnGap: 6)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run from the command line there is no bundle, so ask to be an ordinary app with a window and a menu.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--self-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { SelfTest().run() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
