import AppKit
import SwiftUI

// MARK: - HUD Window

final class TranscriptHUDWindow: NSPanel {

    private let viewModel: TranscriptViewModel

    init(viewModel: TranscriptViewModel) {
        self.viewModel = viewModel
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false  // SwiftUI handles shadow
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(rootView: TranscriptHUDView(viewModel: viewModel))
        contentView = hostingView
    }

    override var canBecomeKey: Bool { true }

    // MARK: - Show / Hide

    func showHUD() {
        // Position at bottom-center of the main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - frame.width / 2
            let y = screenFrame.minY + 80
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        orderFrontRegardless()
    }

    func hideHUD() {
        orderOut(nil)
    }
}
