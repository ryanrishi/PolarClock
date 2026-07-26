// Renders the screen saver without going through System Settings, either as a PNG
// or in a window for watching the animation.
//
//   swiftc -o /tmp/polarclock PolarClock/PolarClockView.swift screenshot.swift
//   /tmp/polarclock out.png   # write a screenshot
//   /tmp/polarclock           # open a window

import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PolarClock Preview"
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentView = NSHostingView(rootView: PolarClockContentView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct PolarClockPreview {
    static let screenshotSize = CGSize(width: 1600, height: 1000)

    @MainActor
    static func main() {
        if let path = CommandLine.arguments.dropFirst().first {
            writeScreenshot(to: path)
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }

    // TimelineView doesn't tick outside a running app, so render the clock face directly
    @MainActor
    static func writeScreenshot(to path: String) {
        let content = ZStack {
            Color.black
            ClockFace(
                date: Date(),
                size: screenshotSize,
                animationState: ClockAnimationState(),
                isPreview: false
            )
        }
        .frame(width: screenshotSize.width, height: screenshotSize.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("failed to render")
        }

        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        } catch {
            fatalError("failed to write \(path): \(error)")
        }
    }
}
