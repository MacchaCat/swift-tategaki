import AppKit

/// Drives the window as a person would, with mouse events and the Copy command, and reports what reached the
/// pasteboard. Run with `swift run TategakiDemo --self-test`. It puts back the text the pasteboard held.
@MainActor final class SelfTest {
    private var steps: [(delay: TimeInterval, action: () -> Void)] = []
    private var failures = 0
    private let saved = NSPasteboard.general.string(forType: .string)

    func run() {
        guard let window = NSApp.windows.first(where: \.isVisible), let content = window.contentView else {
            print("FAIL no window"); exit(1)
        }
        window.makeKeyAndOrderFront(nil)
        let frame = Probe.shared.textFrame
        print("text frame in window:", frame)
        // SwiftUI's window coordinates have y pointing down from the top of the content; AppKit's point up.
        func location(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: content.bounds.height - y) }
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint) {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            window.sendEvent(event)
        }
        func drag(from: NSPoint, to: NSPoint) {
            step(0.1) { mouse(.leftMouseDown, from) }
            for fraction in stride(from: 0.2, through: 1.0, by: 0.2) {
                step(0.05) { mouse(.leftMouseDragged, NSPoint(x: from.x + (to.x - from.x) * fraction, y: from.y + (to.y - from.y) * fraction)) }
            }
            step(0.05) { mouse(.leftMouseUp, to) }
        }
        func copyAndExpect(_ expected: String, _ what: String) {
            step(0.3) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("(nothing copied)", forType: .string)
                let handled = NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                print("copy handled:", handled)
            }
            step(0.3) {
                let got = NSPasteboard.general.string(forType: .string) ?? "(nil)"
                let ok = got == expected
                if !ok { self.failures += 1 }
                print(ok ? "PASS" : "FAIL", what, "→", got, ok ? "" : "(expected \(expected))")
            }
        }

        // The first column is the rightmost. Its ruby takes the 11 points at the text's right edge, and its
        // characters the 22 points left of that.
        let columnX = frame.maxX - 24
        // Drag down the first column from its top to just past its fourth cell: 明, 治, 39 and 年.
        drag(from: location(columnX, frame.minY + 2), to: location(columnX, frame.minY + 22 * 4 + 2))
        copyAndExpect("明治39年", "drag down the first column")

        // Drag from the first column into the second.
        drag(from: location(columnX, frame.minY + 22 * 2 + 2), to: location(columnX - 39, frame.minY + 22 + 2))
        step(0.2) {
            if let path = CommandLine.arguments.drop(while: { $0 != "--snapshot" }).dropFirst().first,
               let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
        }
        copyAndExpect("39年9月、山路を登りながら", "drag from the first column into the second")

        // Select All, by the command.
        step(0.2) { print("selectAll handled:", NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)) }
        copyAndExpect("明治39年9月、山路を登りながら、こう考えた。智に働けば角が立つ。情に棹させば流される。とかくに人の世は住みにくい。", "select all")

        // A plain click deselects, and then Copy must leave the pasteboard alone.
        step(0.1) { mouse(.leftMouseDown, location(columnX, frame.minY + 30)) }
        step(0.05) { mouse(.leftMouseUp, location(columnX, frame.minY + 30)) }
        copyAndExpect("(nothing copied)", "click, then copy")

        step(0.2) {
            NSPasteboard.general.clearContents()
            if let saved = self.saved { NSPasteboard.general.setString(saved, forType: .string) }
            print(self.failures == 0 ? "ALL PASSED" : "\(self.failures) FAILED")
            exit(self.failures == 0 ? 0 : 1)
        }
        runNext()
    }

    private func step(_ delay: TimeInterval, _ action: @escaping () -> Void) {
        steps.append((delay, action))
    }

    private func runNext() {
        guard !steps.isEmpty else { return }
        let next = steps.removeFirst()
        DispatchQueue.main.asyncAfter(deadline: .now() + next.delay) {
            next.action()
            self.runNext()
        }
    }
}
