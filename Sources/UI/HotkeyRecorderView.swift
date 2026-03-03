import SwiftUI
import Carbon

// MARK: - Hotkey Recorder View

struct HotkeyRecorderView: View {
    @Binding var keyCode: Int
    @State private var isRecording = false

    var body: some View {
        HStack {
            Text(isRecording ? "キーを押してください..." : keyCodeDisplayName(keyCode))
                .frame(minWidth: 140, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                )

            Button(isRecording ? "キャンセル" : "変更") {
                isRecording.toggle()
            }
            .buttonStyle(.borderless)

            if keyCode != 63 {
                Button("リセット") {
                    keyCode = 63
                    isRecording = false
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }
        }
        .background(
            // Invisible NSView to capture key events when recording
            HotkeyRecorderNSView(isRecording: $isRecording, keyCode: $keyCode)
                .frame(width: 0, height: 0)
        )
    }
}

// MARK: - Key Code Display Name

func keyCodeDisplayName(_ code: Int) -> String {
    switch code {
    // Modifier keys
    case 61:  return "Right Option (⌥)"
    case 58:  return "Left Option (⌥)"
    case 60:  return "Right Shift (⇧)"
    case 56:  return "Left Shift (⇧)"
    case 62:  return "Right Control (⌃)"
    case 59:  return "Left Control (⌃)"
    case 63:  return "Fn"
    case 55:  return "Right Command (⌘)"
    case 54:  return "Left Command (⌘)"
    // Function keys
    case 122: return "F1"
    case 120: return "F2"
    case 99:  return "F3"
    case 118: return "F4"
    case 96:  return "F5"
    case 97:  return "F6"
    case 98:  return "F7"
    case 100: return "F8"
    case 101: return "F9"
    case 109: return "F10"
    case 103: return "F11"
    case 111: return "F12"
    // Common keys
    case 49:  return "Space"
    case 36:  return "Return"
    case 48:  return "Tab"
    case 51:  return "Delete"
    case 53:  return "Escape"
    default:
        // Try to get character from key code
        if let char = characterForKeyCode(code) {
            return char.uppercased()
        }
        return "Key \(code)"
    }
}

private func characterForKeyCode(_ keyCode: Int) -> String? {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
        return nil
    }
    let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self)
    let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)

    var deadKeyState: UInt32 = 0
    var chars = [UniChar](repeating: 0, count: 4)
    var length: Int = 0

    let status = UCKeyTranslate(
        keyboardLayout,
        UInt16(keyCode),
        UInt16(kUCKeyActionDisplay),
        0, // no modifiers
        UInt32(LMGetKbdType()),
        UInt32(kUCKeyTranslateNoDeadKeysBit),
        &deadKeyState,
        chars.count,
        &length,
        &chars
    )

    guard status == noErr, length > 0 else { return nil }
    return String(utf16CodeUnits: chars, count: length)
}

// MARK: - NSView for capturing key events

struct HotkeyRecorderNSView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var keyCode: Int

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onKeyCapture = { capturedCode in
            DispatchQueue.main.async {
                self.keyCode = capturedCode
                self.isRecording = false
            }
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.isCapturing = isRecording
        if isRecording {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class KeyCaptureView: NSView {
    var isCapturing = false
    var onKeyCapture: ((Int) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else { super.keyDown(with: event); return }
        onKeyCapture?(Int(event.keyCode))
    }

    override func flagsChanged(with event: NSEvent) {
        guard isCapturing else { super.flagsChanged(with: event); return }
        let code = Int(event.keyCode)
        // Only capture on key-down (flag set), ignore key-up
        let isDown: Bool
        switch code {
        case 61, 58:  isDown = event.modifierFlags.contains(.option)
        case 60, 56:  isDown = event.modifierFlags.contains(.shift)
        case 62, 59:  isDown = event.modifierFlags.contains(.control)
        case 55, 54:  isDown = event.modifierFlags.contains(.command)
        case 63:      isDown = event.modifierFlags.contains(.function)
        default:      isDown = false
        }
        if isDown {
            onKeyCapture?(code)
        }
    }
}
