import CoreGraphics
import Carbon
import Foundation

// MARK: - Hotkey Manager
//
// Uses CGEventTap for modifier-key hold detection.
//
// Flow:
//   Key down → start 200ms timer
//   Timer fires → long press started (recording)
//   Key up (after long press) → long press ended (stop recording)
//   Key up (before timer, single) → short press (paste) [350ms delay for double-tap check]
//   Key up (before timer, double within 350ms) → double tap (continuous recording)

final class HotkeyManager: @unchecked Sendable {

    var targetKeyCode: CGKeyCode = 61  // Right Option

    // Callbacks (delivered on main queue)
    var onLongPressStart: (() -> Void)?
    var onLongPressEnd: (() -> Void)?
    var onShortPress: (() -> Void)?
    var onDoubleTap: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var lock = os_unfair_lock_s()
    private var keyDownTime: Date?
    private var isInLongPress = false
    private var longPressWorkItem: DispatchWorkItem?

    private let longPressThreshold: TimeInterval = 0.2
    private let doubleTapThreshold: TimeInterval = 0.35

    /// Pending short press (delayed to allow double-tap detection)
    private var pendingShortPress: DispatchWorkItem?

    // MARK: - Start / Stop

    func start() throws {
        guard CGPreflightListenEventAccess() else {
            CGRequestListenEventAccess()
            throw HotkeyError.inputMonitoringRequired
        }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passRetained(self)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: hotkeyCallback,
            userInfo: selfPtr.toOpaque()
        ) else {
            selfPtr.release()
            throw HotkeyError.tapCreationFailed
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        AppLogger.info("HotkeyManager started (keyCode=\(targetKeyCode))")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
    }

    deinit {
        stop()
    }

    // MARK: - Key Events

    fileprivate func handleKeyDown(_ keyCode: CGKeyCode) {
        guard keyCode == targetKeyCode else { return }

        os_unfair_lock_lock(&lock)
        guard keyDownTime == nil else {
            os_unfair_lock_unlock(&lock)
            return
        }
        keyDownTime = Date()
        isInLongPress = false
        os_unfair_lock_unlock(&lock)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            os_unfair_lock_lock(&self.lock)
            self.isInLongPress = true
            os_unfair_lock_unlock(&self.lock)

            // Cancel pending short press — this is a long press, not a double-tap
            DispatchQueue.main.async {
                self.pendingShortPress?.cancel()
                self.pendingShortPress = nil
                self.onLongPressStart?()
            }
        }

        os_unfair_lock_lock(&lock)
        longPressWorkItem = workItem
        os_unfair_lock_unlock(&lock)

        DispatchQueue.main.asyncAfter(deadline: .now() + longPressThreshold, execute: workItem)
    }

    fileprivate func handleKeyUp(_ keyCode: CGKeyCode) {
        guard keyCode == targetKeyCode else { return }

        os_unfair_lock_lock(&lock)
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        let wasLongPress = isInLongPress
        keyDownTime = nil
        isInLongPress = false
        os_unfair_lock_unlock(&lock)

        DispatchQueue.main.async {
            if wasLongPress {
                self.pendingShortPress?.cancel()
                self.pendingShortPress = nil
                self.onLongPressEnd?()
            } else {
                // Short press — check for double-tap
                if let pending = self.pendingShortPress {
                    // Second tap within threshold → double-tap
                    pending.cancel()
                    self.pendingShortPress = nil
                    self.onDoubleTap?()
                } else {
                    // First tap — wait for possible second
                    let workItem = DispatchWorkItem { [weak self] in
                        self?.pendingShortPress = nil
                        self?.onShortPress?()
                    }
                    self.pendingShortPress = workItem
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + self.doubleTapThreshold,
                        execute: workItem
                    )
                }
            }
        }
    }

    fileprivate func handleFlagsChanged(_ event: CGEvent) {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == targetKeyCode else { return }

        let flags = event.flags
        let isDown: Bool
        switch keyCode {
        case 61, 58:  isDown = flags.contains(.maskAlternate)
        case 60, 56:  isDown = flags.contains(.maskShift)
        case 62, 59:  isDown = flags.contains(.maskControl)
        case 55, 54:  isDown = flags.contains(.maskCommand)
        case 63:      isDown = flags.contains(.maskSecondaryFn)
        default: return
        }

        if isDown {
            handleKeyDown(keyCode)
        } else {
            handleKeyUp(keyCode)
        }
    }
}

// MARK: - C Callback

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let ptr = userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

    switch type {
    case .keyDown:      manager.handleKeyDown(keyCode)
    case .keyUp:        manager.handleKeyUp(keyCode)
    case .flagsChanged: manager.handleFlagsChanged(event)
    default: break
    }

    return Unmanaged.passUnretained(event)
}

// MARK: - Errors

enum HotkeyError: Error, LocalizedError {
    case inputMonitoringRequired
    case tapCreationFailed

    var errorDescription: String? {
        switch self {
        case .inputMonitoringRequired:
            return "Input Monitoring permission required. Enable in System Settings > Privacy & Security > Input Monitoring."
        case .tapCreationFailed:
            return "Failed to create keyboard event tap."
        }
    }
}
