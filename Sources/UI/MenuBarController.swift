import AppKit
import AVFoundation
import CoreAudio
import SwiftUI

// MARK: - Menu Bar Controller

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var statusMenuItem: NSMenuItem?
    private var micMenuItem: NSMenuItem?
    private var transcriptMenuItem: NSMenuItem?

    var onOpenMainWindow: (() -> Void)?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon(.idle)
        buildMenu()
    }

    // MARK: - Icon State

    enum IconState {
        case idle, recording, processing, readyToPaste, error
    }

    func updateIcon(_ state: IconState) {
        guard let button = statusItem?.button else { return }

        let symbolName: String
        let isTemplate: Bool
        switch state {
        case .idle:
            symbolName = "waveform"
            button.contentTintColor = nil
            isTemplate = true
        case .recording:
            symbolName = "waveform.circle.fill"
            button.contentTintColor = .systemRed
            isTemplate = false
        case .processing:
            symbolName = "ellipsis.circle"
            button.contentTintColor = nil
            isTemplate = true
        case .readyToPaste:
            symbolName = "checkmark.circle.fill"
            button.contentTintColor = .systemGreen
            isTemplate = false
        case .error:
            symbolName = "exclamationmark.triangle.fill"
            button.contentTintColor = .systemYellow
            isTemplate = false
        }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "VoiceLog")?
            .withSymbolConfiguration(config)
        button.image?.isTemplate = isTemplate
    }

    func updateTranscriptPreview(_ text: String) {
        let maxLen = 30
        let oneLine = text.replacingOccurrences(of: "\n", with: " ")
        let preview = oneLine.prefix(maxLen)
        transcriptMenuItem?.title = preview.isEmpty ? "文字起こし結果なし" : String(preview) + (oneLine.count > maxLen ? "..." : "")
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "VoiceLog - 待機中", action: nil, keyEquivalent: "")
        statusMenuItem?.isEnabled = false
        menu.addItem(statusMenuItem!)

        micMenuItem = NSMenuItem(title: "🎙 \(Self.defaultInputDeviceName())", action: nil, keyEquivalent: "")
        micMenuItem?.isEnabled = false
        menu.addItem(micMenuItem!)

        menu.addItem(.separator())

        transcriptMenuItem = NSMenuItem(title: "文字起こし結果なし", action: nil, keyEquivalent: "")
        transcriptMenuItem?.isEnabled = false
        menu.addItem(transcriptMenuItem!)

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "VoiceLog を開く...", action: #selector(handleOpen(_:)), keyEquivalent: ",")
        openItem.target = self
        menu.addItem(openItem)

        let quitItem = NSMenuItem(title: "VoiceLog を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        menu.delegate = self
        self.menu = menu
        statusItem?.menu = menu
    }

    @objc private func handleOpen(_ sender: Any?) {
        onOpenMainWindow?()
    }

    func updateStatusText(_ text: String) {
        statusMenuItem?.title = "VoiceLog - \(text)"
    }

    // MARK: - NSMenuDelegate

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        let name = Self.defaultInputDeviceName()
        Task { @MainActor in
            self.micMenuItem?.title = "🎙 \(name)"
        }
    }

    // MARK: - Default Input Device

    nonisolated private static func defaultInputDeviceName() -> String {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            return "マイク未検出"
        }

        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var nameSize = UInt32(MemoryLayout<CFString?>.size)
        var nameStatus = AudioObjectGetPropertyDataSize(deviceID, &nameAddress, 0, nil, &nameSize)
        guard nameStatus == noErr else { return "マイク未検出" }

        var name: Unmanaged<CFString>?
        nameStatus = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(
                deviceID,
                &nameAddress,
                0, nil,
                &nameSize,
                ptr
            )
        }
        guard nameStatus == noErr, let cfName = name?.takeUnretainedValue() else {
            return "マイク未検出"
        }
        return cfName as String
    }
}
