import Foundation

// MARK: - State

enum AppState: Sendable {
    case idle
    case recording(startedAt: Date)
    case processing(rawTranscript: String)
    case readyToPaste(cleaned: String, raw: String)
}

// MARK: - State Machine

@MainActor
final class StateMachine: ObservableObject {
    @Published private(set) var state: AppState = .idle

    /// Last cleaned result (persists across state changes for re-paste)
    @Published private(set) var lastResult: (cleaned: String, raw: String)?

    @discardableResult
    func transition(to newState: AppState) -> Bool {
        guard isValid(from: state, to: newState) else {
            AppLogger.warning("Invalid transition: \(label(state)) → \(label(newState))")
            return false
        }
        AppLogger.info("State: \(label(state)) → \(label(newState))")
        state = newState

        if case .readyToPaste(let cleaned, let raw) = newState {
            lastResult = (cleaned, raw)
        }
        return true
    }

    // MARK: - Validation

    private func isValid(from: AppState, to: AppState) -> Bool {
        switch (from, to) {
        case (.idle, .recording):            return true
        case (.idle, .readyToPaste):          return lastResult != nil
        case (.recording, .processing):      return true
        case (.recording, .idle):            return true  // empty transcript
        case (.processing, .readyToPaste):   return true
        case (.processing, .idle):           return true  // fallback paste
        case (.readyToPaste, .idle):         return true
        case (.readyToPaste, .recording):    return true
        default:                             return false
        }
    }

    private func label(_ s: AppState) -> String {
        switch s {
        case .idle:          return "IDLE"
        case .recording:     return "RECORDING"
        case .processing:    return "PROCESSING"
        case .readyToPaste:  return "READY_TO_PASTE"
        }
    }
}
