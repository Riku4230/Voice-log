import AppKit
import CoreGraphics

// MARK: - Paste Engine
//
// Pattern from LocalWhisper/VoiceScribe:
//   1. Copy to clipboard
//   2. Wait 100ms for clipboard to settle
//   3. Simulate Cmd+V via CGEvent at .cghidEventTap
//   4. Wait 50ms between key down/up

enum PasteEngine {

    static func paste(_ text: String) throws {
        let pasteboard = NSPasteboard.general

        // 1. Save existing clipboard contents
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> (NSPasteboard.PasteboardType, Data)? in
            guard let type = item.types.first, let data = item.data(forType: type) else { return nil }
            return (type, data)
        } ?? []

        // 2. Set clipboard to our text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. Wait for clipboard
        usleep(100_000)  // 100ms (LocalWhisper pattern)

        // 4. Simulate Cmd+V
        let vKeyCode: CGKeyCode = 9

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else {
            throw PasteError.eventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        usleep(50_000)  // 50ms gap (VoiceScribe pattern)
        keyUp.post(tap: .cghidEventTap)

        AppLogger.info("PasteEngine: pasted \(text.count) chars")

        // 5. Restore clipboard after a delay (let paste complete first)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !savedItems.isEmpty {
                pasteboard.clearContents()
                for (type, data) in savedItems {
                    pasteboard.setData(data, forType: type)
                }
            }
        }
    }

    static func checkAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

enum PasteError: Error, LocalizedError {
    case eventCreationFailed

    var errorDescription: String? {
        "Failed to create CGEvent for paste simulation."
    }
}
