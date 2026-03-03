import SwiftUI
import AppKit

// MARK: - HUD State

enum HUDState: Equatable {
    case recording
    case processing
    case readyToPaste
}

// MARK: - View Model

@MainActor
final class TranscriptViewModel: ObservableObject {
    @Published var state: HUDState = .recording
    @Published var finalText: String = ""
    @Published var partialText: String = ""
    @Published var cleanedText: String = ""
    @Published var isVisible: Bool = false
    @Published var isContinuous: Bool = false
    @Published var focusedAppName: String = ""
    @Published var isLLMProcessing: Bool = false

    /// Called when user taps the cancel button on the HUD
    var onCancel: (() -> Void)?

    private var recordingStart: Date?
    private var durationTimer: Timer?
    private var appTrackingTimer: Timer?
    @Published var durationLabel: String = "0:00"

    var indicatorColor: Color {
        switch state {
        case .recording:     return .red
        case .processing:    return .orange
        case .readyToPaste:  return .green
        }
    }

    var statusLabel: String {
        switch state {
        case .recording:     return "録音中..."
        case .processing:    return "整形中..."
        case .readyToPaste:  return "ペースト可能"
        }
    }

    var displayText: String {
        switch state {
        case .readyToPaste:
            return cleanedText.isEmpty ? finalText : cleanedText
        default:
            return finalText
        }
    }

    // MARK: - Actions

    func startRecording() {
        finalText = ""
        partialText = ""
        cleanedText = ""
        durationLabel = "0:00"
        state = .recording
        isVisible = true

        updateFocusedApp()

        recordingStart = Date()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.recordingStart else { return }
                let elapsed = Int(Date().timeIntervalSince(start))
                self.durationLabel = "\(elapsed / 60):\(String(format: "%02d", elapsed % 60))"
            }
        }

        appTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateFocusedApp()
            }
        }
    }

    private func updateFocusedApp() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            focusedAppName = ""
            return
        }
        focusedAppName = frontApp.localizedName ?? frontApp.bundleIdentifier ?? ""
    }

    func updateTranscript(final_: String, partial: String) {
        finalText = final_
        partialText = partial
    }

    func startProcessing(llm: Bool = false) {
        partialText = ""
        isLLMProcessing = llm
        state = .processing
        durationTimer?.invalidate()
        durationTimer = nil
        appTrackingTimer?.invalidate()
        appTrackingTimer = nil
    }

    func showResult(_ cleaned: String) {
        cleanedText = cleaned
        state = .readyToPaste
    }

    func hide() {
        isVisible = false
    }
}
