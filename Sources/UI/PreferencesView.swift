import SwiftUI

// MARK: - Preferences View

struct PreferencesView: View {
    @ObservedObject private var prefs = UserPreferences.shared
    @State private var selectedTab = 0
    @State private var showAPIKey = false

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            HStack(spacing: 2) {
                tabButton(title: "一般", icon: "gearshape", index: 0)
                tabButton(title: "後処理", icon: "wand.and.stars", index: 1)
            }
            .padding(3)
            .background(.quaternarySystemFill, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Content
            ScrollView {
                VStack(spacing: 16) {
                    if selectedTab == 0 {
                        generalContent
                    } else {
                        postProcessingContent
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 460, height: 400)
    }

    // MARK: - Tab Button

    private func tabButton(title: String, icon: String, index: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedTab = index }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                selectedTab == index
                    ? AnyShapeStyle(.background)
                    : AnyShapeStyle(.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: selectedTab == index ? .black.opacity(0.06) : .clear, radius: 1, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - General

    private var generalContent: some View {
        VStack(spacing: 16) {
            // Language
            settingsGroup(title: "言語", icon: "globe") {
                Picker("文字起こし言語", selection: $prefs.transcriptionLocale) {
                    Text("日本語").tag("ja-JP")
                    Text("English").tag("en-US")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            // Hotkey
            settingsGroup(title: "ホットキー", icon: "command.square") {
                HotkeyRecorderView(keyCode: $prefs.hotkeyCode)
            }

            // Behavior
            settingsGroup(title: "動作", icon: "slider.horizontal.3") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("結果の保持時間")
                            .font(.system(size: 13))
                        Spacer()
                        HStack(spacing: 4) {
                            TextField("", value: $prefs.readyToPasteTimeout, format: .number)
                                .frame(width: 50)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                            Text("秒")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Post-processing

    private var postProcessingContent: some View {
        VStack(spacing: 16) {
            // Mode
            settingsGroup(title: "後処理モード", icon: "cpu") {
                VStack(spacing: 8) {
                    modeRow(
                        title: "ローカル完結",
                        subtitle: "ルールベース処理のみ (無料)",
                        mode: .local
                    )
                    Divider()
                    modeRow(
                        title: "Claude Haiku API",
                        subtitle: "高品質な整形 (~$0.001/回)",
                        mode: .claudeAPI
                    )
                    Divider()
                    modeRow(
                        title: "Ollama",
                        subtitle: "ローカルLLMで整形 (無料)",
                        mode: .ollama
                    )
                }
            }

            // Text processing toggles
            settingsGroup(title: "テキスト整形", icon: "textformat") {
                VStack(spacing: 10) {
                    Toggle(isOn: $prefs.fillerRemovalEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("フィラー除去")
                                .font(.system(size: 13))
                            Text("えーと、あの、まあ 等を除去")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    Divider()

                    Toggle(isOn: $prefs.bulletPointsEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("箇条書きに変換")
                                .font(.system(size: 13))
                            Text("LLM使用時のみ有効")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
            }

            // API settings (conditional)
            if prefs.postProcessingMode == .claudeAPI {
                settingsGroup(title: "Claude API 設定", icon: "key") {
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Group {
                                if showAPIKey {
                                    TextField("sk-ant-...", text: $prefs.claudeApiKey)
                                } else {
                                    SecureField("API Key", text: $prefs.claudeApiKey)
                                }
                            }
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))

                            Button {
                                showAPIKey.toggle()
                            } label: {
                                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                    .font(.system(size: 12))
                                    .frame(width: 28, height: 22)
                            }
                            .buttonStyle(.bordered)
                        }
                        timeoutSlider
                    }
                }
            }

            if prefs.postProcessingMode == .ollama {
                settingsGroup(title: "Ollama 設定", icon: "server.rack") {
                    VStack(spacing: 12) {
                        HStack {
                            Text("エンドポイント")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 90, alignment: .trailing)
                            TextField("http://localhost:11434", text: $prefs.ollamaEndpoint)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        HStack {
                            Text("モデル名")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 90, alignment: .trailing)
                            TextField("llama3.2:3b", text: $prefs.ollamaModel)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        timeoutSlider
                    }
                }
            }
        }
    }

    // MARK: - Components

    private var timeoutSlider: some View {
        HStack(spacing: 8) {
            Text("タイムアウト")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Slider(value: $prefs.llmTimeout, in: 1...10, step: 1)
            Text("\(Int(prefs.llmTimeout))秒")
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 28, alignment: .trailing)
        }
    }

    private func modeRow(title: String, subtitle: String, mode: PostProcessingMode) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: prefs.postProcessingMode == mode ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(prefs.postProcessingMode == mode ? .blue : .gray.opacity(0.4))
        }
        .contentShape(Rectangle())
        .onTapGesture { prefs.postProcessingMode = mode }
    }

    private func settingsGroup<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Quaternary System Fill (compatibility)

extension ShapeStyle where Self == Color {
    static var quaternarySystemFill: Color {
        Color.gray.opacity(0.1)
    }
}
