import AppKit
import SwiftUI
import Speech

// MARK: - App Coordinator

@MainActor
final class AppCoordinator {

    let stateMachine = StateMachine()
    let hotkeyManager = HotkeyManager()
    let audioRecorder = AudioRecorder()
    let postProcessor = PostProcessor()
    let menuBar = MenuBarController()

    let hudViewModel = TranscriptViewModel()
    private var hudWindow: TranscriptHUDWindow?
    private var mainWindow: NSWindow?

    private var speechRecognizer: SpeechRecognizer?
    private var transcriptionTask: Task<Void, Never>?

    /// Text confirmed (auto-saved after silence) — never lost
    private var accumulatedFinalText = ""
    /// Latest partial from the current recognition session (full session text)
    private var currentSessionText = ""
    /// How many chars of currentSessionText have already been flushed to accumulatedFinalText
    private var flushedSessionLength = 0
    /// Timer: auto-saves unflushed portion after 1s of no new partials
    private var autoSaveTimer: Timer?

    private var pasteTimeoutTask: Task<Void, Never>?
    private var hotkeyObserver: NSObjectProtocol?
    private var escMonitor: Any?

    /// Continuous recording mode (toggled by double-tap)
    private var isContinuousRecording = false

    /// Timer for polling audio level from recorder
    private var audioLevelTimer: Timer?

    // MARK: - Setup

    func start() {
        NSApp.setActivationPolicy(.accessory)

        menuBar.setup()
        menuBar.onOpenMainWindow = { [weak self] in
            self?.showMainWindow()
        }

        hudWindow = TranscriptHUDWindow(viewModel: hudViewModel)

        hudViewModel.onCancel = { [weak self] in
            self?.cancelResult()
        }

        setupEscMonitor()

        Task {
            await requestPermissions()
            setupHotkey()
        }
    }

    // MARK: - Permissions

    private func requestPermissions() async {
        let locale = UserPreferences.shared.transcriptionLocale
        let recognizer = SpeechRecognizer(locale: Locale(identifier: locale))
        let speechOK = await recognizer.requestPermission()
        if !speechOK {
            AppLogger.error("Speech recognition permission denied")
            menuBar.updateIcon(.error)
            menuBar.updateStatusText("音声認識の権限がありません")
        }

        let _ = PasteEngine.checkAccessibility()
    }

    // MARK: - ESC Key Monitor

    private func setupEscMonitor() {
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {  // ESC
                Task { @MainActor in
                    guard let self else { return }
                    if case .readyToPaste = self.stateMachine.state {
                        self.cancelResult()
                    }
                }
            }
        }
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        let prefs = UserPreferences.shared
        hotkeyManager.targetKeyCode = CGKeyCode(prefs.hotkeyCode)

        hotkeyManager.onLongPressStart = { [weak self] in
            guard let self else { return }
            if !self.isContinuousRecording {
                self.beginRecording(continuous: false)
            }
        }
        hotkeyManager.onLongPressEnd = { [weak self] in
            guard let self else { return }
            if !self.isContinuousRecording {
                self.endRecording()
            }
        }
        hotkeyManager.onShortPress = { [weak self] in
            self?.handleShortPress()
        }
        hotkeyManager.onDoubleTap = { [weak self] in
            self?.handleDoubleTap()
        }

        do {
            try hotkeyManager.start()
        } catch {
            AppLogger.error("Hotkey setup failed: \(error.localizedDescription)")
            menuBar.updateIcon(.error)
            menuBar.updateStatusText("Input Monitoring 権限が必要です")
        }

        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let newCode = CGKeyCode(UserPreferences.shared.hotkeyCode)
                if self.hotkeyManager.targetKeyCode != newCode {
                    self.hotkeyManager.targetKeyCode = newCode
                    AppLogger.info("Hotkey changed to keyCode=\(newCode)")
                }
            }
        }
    }

    // MARK: - Auto-save

    /// Flush current session text into accumulated (called by timer after 2s silence)
    private func flushCurrentSession() {
        guard currentSessionText.count > flushedSessionLength else { return }
        let newPortion = String(currentSessionText.dropFirst(flushedSessionLength))
        let (processed, shouldClear) = applyVoiceCommands(newPortion)
        if shouldClear {
            accumulatedFinalText = ""
            flushedSessionLength = currentSessionText.count
            AppLogger.info("AUTOSAVE+CLEAR: voice command reset")
        } else {
            accumulatedFinalText += processed
            flushedSessionLength = currentSessionText.count
            AppLogger.info("AUTOSAVE: +\(processed.count)chars → total=\(accumulatedFinalText.count)")
        }
        hudViewModel.updateTranscript(final_: accumulatedFinalText, partial: "")
    }

    // MARK: - Voice Commands

    /// Process voice commands in finalized session text.
    /// Returns processed text and whether to clear all accumulated text.
    private func applyVoiceCommands(_ text: String) -> (text: String, shouldClear: Bool) {
        // "取り消し" clears all accumulated text
        if text.contains("取り消し") {
            AppLogger.info("Voice command: 取り消し")
            return ("", true)
        }

        var result = text
        // "改行" → newline
        result = result.replacingOccurrences(of: "改行", with: "\n")
        // "まる" → period (in case recognizer didn't auto-punctuate)
        result = result.replacingOccurrences(of: "まる", with: "。")

        return (result, false)
    }

    /// Extract trailing voice instruction from transcript for LLM post-processing.
    /// e.g., "今日のミーティング内容は〜〜。メール文にして" → content + instruction
    private func extractVoiceInstruction(_ text: String) -> (content: String, instruction: String?) {
        let suffixes = [
            "メール文にしてください", "メール文にして", "メールにして",
            "箇条書きにしてください", "箇条書きにして",
            "敬語にしてください", "敬語にして",
            "カジュアルにしてください", "カジュアルにして",
            "丁寧にしてください", "丁寧にして", "丁寧語にして",
            "要約してください", "要約して",
            "英語にしてください", "英語にして", "英訳してください", "英訳して",
            "整形してください", "整形して",
            "まとめてください", "まとめて",
            "議事録にして", "議事録にしてください",
            "報告書にして", "報告書にしてください",
        ]

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in suffixes {
            if trimmed.hasSuffix(suffix) {
                let content = String(trimmed.dropLast(suffix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "。、,. "))
                AppLogger.info("Voice instruction detected: \(suffix)")
                return (content, suffix)
            }
        }
        return (text, nil)
    }

    // MARK: - Recording

    private func beginRecording(continuous: Bool) {
        guard stateMachine.transition(to: .recording(startedAt: Date())) else { return }
        pasteTimeoutTask?.cancel()
        isContinuousRecording = continuous

        menuBar.updateIcon(.recording)
        menuBar.updateStatusText(continuous ? "常時録音中..." : "録音中...")

        accumulatedFinalText = ""
        currentSessionText = ""
        flushedSessionLength = 0
        autoSaveTimer?.invalidate()
        hudViewModel.isContinuous = continuous
        hudViewModel.startRecording()
        hudWindow?.showHUD()

        let locale = UserPreferences.shared.transcriptionLocale
        let recognizer = SpeechRecognizer(locale: Locale(identifier: locale))
        self.speechRecognizer = recognizer

        do {
            let contextualStrings = CustomData.shared.dictionaryWords.map { $0.word }
            // Replay recent audio on session rotation to fill the gap
            recognizer.onSessionRotation = { [weak self] in
                guard let self else { return }
                let buffers = self.audioRecorder.recentBuffers()
                recognizer.replayBuffers(buffers)
            }

            let stream = try recognizer.startRecognition(contextualStrings: contextualStrings)

            let prefs = UserPreferences.shared
            audioRecorder.updateSensitivity(prefs.inputSensitivity)
            try audioRecorder.startRecording(voiceProcessing: prefs.voiceProcessingEnabled) { buffer in
                recognizer.appendBuffer(buffer)
            }

            // Poll audio level at ~15Hz for HUD display
            audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.hudViewModel.audioLevel = self.audioRecorder.currentAudioLevel
                }
            }

            transcriptionTask = Task { [weak self] in
                for await update in stream {
                    guard let self = self else { return }
                    switch update {
                    case .partial(let sessionText):
                        // If session text is shorter than flushed length, session rotated — reset
                        if sessionText.count < self.flushedSessionLength {
                            self.flushedSessionLength = 0
                        }
                        self.currentSessionText = sessionText
                        let unflushed = String(sessionText.dropFirst(self.flushedSessionLength))
                        self.hudViewModel.updateTranscript(
                            final_: self.accumulatedFinalText,
                            partial: unflushed
                        )
                        // Reset auto-save timer: if no new partial for 2s, save to accumulated
                        self.autoSaveTimer?.invalidate()
                        self.autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                            Task { @MainActor [weak self] in
                                self?.flushCurrentSession()
                            }
                        }

                    case .final_(let sessionText):
                        // Session ended — save only the unflushed delta
                        self.autoSaveTimer?.invalidate()
                        let text = sessionText.isEmpty ? self.currentSessionText : sessionText
                        if text.count > self.flushedSessionLength {
                            let newPortion = String(text.dropFirst(self.flushedSessionLength))
                            let (processed, shouldClear) = self.applyVoiceCommands(newPortion)
                            if shouldClear {
                                self.accumulatedFinalText = ""
                                AppLogger.info("CLEAR: voice command reset")
                            } else {
                                self.accumulatedFinalText += processed
                                AppLogger.info("FINAL: +\(processed.count)chars → total=\(self.accumulatedFinalText.count)")
                            }
                        }
                        self.currentSessionText = ""
                        self.flushedSessionLength = 0
                        self.hudViewModel.updateTranscript(
                            final_: self.accumulatedFinalText,
                            partial: ""
                        )
                    }
                }
            }
        } catch {
            AppLogger.error("Recording failed: \(error.localizedDescription)")
            stateMachine.transition(to: .idle)
            menuBar.updateIcon(.error)
            hudWindow?.hideHUD()
            isContinuousRecording = false
        }
    }

    private func endRecording() {
        isContinuousRecording = false
        audioRecorder.stopRecording()
        speechRecognizer?.stopRecognition()
        autoSaveTimer?.invalidate()
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil

        // Wait briefly for recognizer to process remaining audio, then finalize
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1s
            self.transcriptionTask?.cancel()

            // Flush any unsaved session text (delta only)
            if self.currentSessionText.count > self.flushedSessionLength {
                let remaining = String(self.currentSessionText.dropFirst(self.flushedSessionLength))
                let (processed, shouldClear) = self.applyVoiceCommands(remaining)
                if shouldClear {
                    self.accumulatedFinalText = ""
                } else {
                    self.accumulatedFinalText += processed
                }
            }
            self.currentSessionText = ""
            self.flushedSessionLength = 0

            self.finalizeRecording()
        }
    }

    private func finalizeRecording() {
        var rawTranscript = accumulatedFinalText
        // Apply voice commands to the full output
        let (processed, shouldClear) = applyVoiceCommands(rawTranscript)
        rawTranscript = shouldClear ? "" : processed
        AppLogger.info("END: total=\(rawTranscript.count)chars")

        guard !rawTranscript.isEmpty else {
            stateMachine.transition(to: .idle)
            menuBar.updateIcon(.idle)
            menuBar.updateStatusText("待機中")
            hudWindow?.hideHUD()
            return
        }

        // Extract trailing voice instruction (e.g., "メール文にして")
        let (content, voiceInstruction) = extractVoiceInstruction(rawTranscript)

        let prefs = UserPreferences.shared

        // Combine custom instructions with voice instruction
        var allInstructions = CustomData.shared.customInstructions
        if let vi = voiceInstruction {
            if !allInstructions.isEmpty { allInstructions += "\n" }
            allInstructions += "ユーザーの音声指示: \(vi)"
        }

        let textForProcessing = voiceInstruction != nil ? content : rawTranscript
        let usesLLM = (prefs.postProcessingMode != .local || voiceInstruction != nil)
            && !(voiceInstruction != nil && prefs.postProcessingMode == .local && prefs.claudeApiKey.isEmpty)

        stateMachine.transition(to: .processing(rawTranscript: rawTranscript))
        menuBar.updateIcon(.processing)
        menuBar.updateStatusText(usesLLM ? "AIにより整形中..." : "整形中...")
        hudViewModel.startProcessing(llm: usesLLM)

        if prefs.postProcessingMode == .local && voiceInstruction == nil {
            var cleaned = textForProcessing
            if prefs.fillerRemovalEnabled {
                cleaned = PostProcessor.removeFillers(cleaned)
            }
            finishProcessing(cleaned: cleaned, raw: rawTranscript)
        } else if voiceInstruction != nil && prefs.postProcessingMode == .local && prefs.claudeApiKey.isEmpty {
            var cleaned = textForProcessing
            if prefs.fillerRemovalEnabled {
                cleaned = PostProcessor.removeFillers(cleaned)
            }
            finishProcessing(cleaned: cleaned, raw: rawTranscript)
        } else {
            postProcessor.process(
                rawTranscript: textForProcessing,
                preferences: prefs,
                customInstructions: allInstructions
            )
            Task {
                let fallback = prefs.fillerRemovalEnabled
                    ? PostProcessor.removeFillers(textForProcessing)
                    : textForProcessing
                let cleaned = await postProcessor.getResult(
                    rawFallback: fallback,
                    timeout: prefs.llmTimeout
                )
                finishProcessing(cleaned: cleaned, raw: rawTranscript)
            }
        }
    }

    private func finishProcessing(cleaned: String, raw: String) {
        let finalText = CustomData.applyReplacements(cleaned, rules: CustomData.shared.replacementRules)
        let cleaned = finalText
        TranscriptionHistory.shared.save(raw: raw, cleaned: cleaned)
        stateMachine.transition(to: .readyToPaste(cleaned: cleaned, raw: raw))
        menuBar.updateIcon(.readyToPaste)
        menuBar.updateStatusText("ペースト可能")
        menuBar.updateTranscriptPreview(cleaned)
        hudViewModel.showResult(cleaned)

        let timeout = UserPreferences.shared.readyToPasteTimeout
        pasteTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            stateMachine.transition(to: .idle)
            menuBar.updateIcon(.idle)
            menuBar.updateStatusText("待機中")
            hudWindow?.hideHUD()
        }
    }

    // MARK: - Short Press (Paste)

    private func handleShortPress() {
        if isContinuousRecording {
            endRecording()
            return
        }

        switch stateMachine.state {
        case .readyToPaste:
            pasteTimeoutTask?.cancel()
            performPaste(hudViewModel.cleanedText)

        case .processing(let raw):
            Task {
                let prefs = UserPreferences.shared
                let fallback = prefs.fillerRemovalEnabled
                    ? PostProcessor.removeFillers(raw)
                    : raw
                let result = await postProcessor.getResult(rawFallback: fallback, timeout: 1.0)
                performPaste(result)
            }

        case .idle:
            if let last = stateMachine.lastResult {
                performPaste(last.cleaned)
            }

        default:
            break
        }
    }

    // MARK: - Double Tap (Continuous Recording)

    private func handleDoubleTap() {
        switch stateMachine.state {
        case .idle, .readyToPaste:
            pasteTimeoutTask?.cancel()
            beginRecording(continuous: true)
        case .recording:
            endRecording()
        default:
            break
        }
    }

    private func cancelResult() {
        pasteTimeoutTask?.cancel()
        stateMachine.transition(to: .idle)
        menuBar.updateIcon(.idle)
        menuBar.updateStatusText("取り消しました")
        hudWindow?.hideHUD()
        AppLogger.info("Result cancelled by user")
    }

    private func performPaste(_ text: String) {
        hudWindow?.hideHUD()
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            do {
                try PasteEngine.paste(text)
            } catch {
                AppLogger.error("Paste failed: \(error.localizedDescription)")
            }
            stateMachine.transition(to: .idle)
            menuBar.updateIcon(.idle)
            menuBar.updateStatusText("待機中")
        }
    }

    // MARK: - Main Window

    private func showMainWindow() {
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "VoiceLog"
            window.contentView = NSHostingView(rootView: MainWindowView())
            window.center()
            window.minSize = NSSize(width: 600, height: 400)
            mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
