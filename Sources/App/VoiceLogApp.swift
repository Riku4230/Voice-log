import AppKit

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
    }
}

// MARK: - Entry Point

@main @MainActor
enum VoiceLogApp {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}
