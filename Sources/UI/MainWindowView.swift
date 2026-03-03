import SwiftUI
import AppKit

// MARK: - Sidebar Tab

enum SidebarTab: String, CaseIterable, Identifiable {
    case settings = "設定"
    case dictionary = "辞書"
    case replacements = "置換"
    case customInstructions = "カスタム指示"
    case history = "履歴"
    case stats = "統計"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .settings:           return "gearshape"
        case .dictionary:         return "character.book.closed"
        case .replacements:       return "arrow.right"
        case .customInstructions: return "doc.text"
        case .history:            return "clock.arrow.circlepath"
        case .stats:              return "chart.bar"
        }
    }
}

// MARK: - Main Window View

struct MainWindowView: View {
    @State private var selectedTab: SidebarTab = .settings

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebar
                .frame(width: 180)

            // Divider
            Rectangle()
                .fill(.gray.opacity(0.15))
                .frame(width: 0.5)

            // Content
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 700, height: 520)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            // App title
            VStack(alignment: .leading, spacing: 2) {
                Text("VoiceLog")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("v0.1.0")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Tab items
            ForEach(SidebarTab.allCases) { tab in
                sidebarItem(tab)
            }

            Spacer()
        }
        .frame(maxHeight: .infinity)
        .background(Color.gray.opacity(0.04))
    }

    private func sidebarItem(_ tab: SidebarTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.12)) { selectedTab = tab }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? Color.blue.opacity(0.08)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    // MARK: - Content Router

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .settings:
            SettingsContentView()
        case .dictionary:
            DictionaryContentView()
        case .replacements:
            ReplacementsContentView()
        case .customInstructions:
            CustomInstructionsContentView()
        case .history:
            HistoryContentView()
        case .stats:
            StatsContentView()
        }
    }
}

// MARK: - Settings Content

struct SettingsContentView: View {
    @ObservedObject private var prefs = UserPreferences.shared
    @State private var showAPIKey = false
    @State private var selectedSubTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabHeader(title: "設定", subtitle: "一般設定と後処理モードの設定")

            // Sub-tab selector
            HStack(spacing: 2) {
                subTabButton(title: "一般", index: 0)
                subTabButton(title: "後処理", index: 1)
            }
            .padding(3)
            .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 24)

            ScrollView {
                VStack(spacing: 16) {
                    if selectedSubTab == 0 {
                        generalContent
                    } else {
                        postProcessingContent
                    }
                }
                .padding(24)
            }
        }
    }

    private func subTabButton(title: String, index: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.12)) { selectedSubTab = index }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    selectedSubTab == index ? AnyShapeStyle(.background) : AnyShapeStyle(.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: selectedSubTab == index ? .black.opacity(0.06) : .clear, radius: 1, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var generalContent: some View {
        VStack(spacing: 16) {
            settingsGroup(title: "言語", icon: "globe") {
                Picker("文字起こし言語", selection: $prefs.transcriptionLocale) {
                    Text("日本語").tag("ja-JP")
                    Text("English").tag("en-US")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            settingsGroup(title: "ホットキー", icon: "command.square") {
                HotkeyRecorderView(keyCode: $prefs.hotkeyCode)
            }

            settingsGroup(title: "動作", icon: "slider.horizontal.3") {
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

    private var postProcessingContent: some View {
        VStack(spacing: 16) {
            settingsGroup(title: "後処理モード", icon: "cpu") {
                VStack(spacing: 8) {
                    modeRow("ローカル完結", "ルールベース処理のみ (無料)", .local)
                    Divider()
                    modeRow("Claude Haiku API", "高品質な整形 (~$0.001/回)", .claudeAPI)
                    Divider()
                    modeRow("Ollama", "ローカルLLMで整形 (無料)", .ollama)
                }
            }

            settingsGroup(title: "テキスト整形", icon: "textformat") {
                VStack(spacing: 10) {
                    Toggle(isOn: $prefs.fillerRemovalEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("フィラー除去").font(.system(size: 13))
                            Text("えーと、あの、まあ 等を除去").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    Divider()
                    Toggle(isOn: $prefs.bulletPointsEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("箇条書きに変換").font(.system(size: 13))
                            Text("LLM使用時のみ有効").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
            }

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
                            Button { showAPIKey.toggle() } label: {
                                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                    .font(.system(size: 12)).frame(width: 28, height: 22)
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
                            Text("エンドポイント").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
                            TextField("http://localhost:11434", text: $prefs.ollamaEndpoint).textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
                        }
                        HStack {
                            Text("モデル名").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
                            TextField("llama3.2:3b", text: $prefs.ollamaModel).textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
                        }
                        timeoutSlider
                    }
                }
            }
        }
    }

    private var timeoutSlider: some View {
        HStack(spacing: 8) {
            Text("タイムアウト").font(.system(size: 12)).foregroundStyle(.secondary)
            Slider(value: $prefs.llmTimeout, in: 1...10, step: 1)
            Text("\(Int(prefs.llmTimeout))秒").font(.system(size: 12, design: .monospaced)).frame(width: 28, alignment: .trailing)
        }
    }

    private func modeRow(_ title: String, _ subtitle: String, _ mode: PostProcessingMode) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: prefs.postProcessingMode == mode ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(prefs.postProcessingMode == mode ? .blue : .gray.opacity(0.4))
        }
        .contentShape(Rectangle())
        .onTapGesture { prefs.postProcessingMode = mode }
    }
}

// MARK: - Dictionary Content

struct DictionaryContentView: View {
    @ObservedObject private var data = CustomData.shared
    @State private var newWord = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabHeader(
                title: "辞書",
                subtitle: "固有名詞やカスタムワードを登録して認識精度を向上させます"
            ) {
                HStack(spacing: 4) {
                    Text("\(data.dictionaryWords.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("単語")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            // Add new word
            HStack(spacing: 8) {
                TextField("新しい単語を入力...", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addWord() }
                Button {
                    addWord()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("追加")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Divider()

            // Word list
            if data.dictionaryWords.isEmpty {
                emptyState(icon: "character.book.closed", message: "まだ単語が登録されていません", hint: "固有名詞や専門用語を追加すると認識精度が向上します")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(data.dictionaryWords) { word in
                            HStack {
                                Text(word.word)
                                    .font(.system(size: 14))
                                Spacer()
                                Button("削除") {
                                    withAnimation { data.removeWord(id: word.id) }
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(.red.opacity(0.7))
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            Divider().padding(.leading, 24)
                        }
                    }
                }
            }
        }
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        data.addWord(trimmed)
        newWord = ""
    }
}

// MARK: - Replacements Content

struct ReplacementsContentView: View {
    @ObservedObject private var data = CustomData.shared
    @State private var newTrigger = ""
    @State private var newReplacement = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabHeader(
                title: "置換",
                subtitle: "特定のフレーズを言うと、登録したテキストに自動置換されます"
            ) {
                HStack(spacing: 4) {
                    Text("\(data.replacementRules.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("ルール")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            // Add new rule
            HStack(spacing: 8) {
                TextField("トリガー", text: $newTrigger)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField("置換テキスト", text: $newReplacement)
                    .textFieldStyle(.roundedBorder)
                Button {
                    addRule()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("追加")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTrigger.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Divider()

            // Rules list
            if data.replacementRules.isEmpty {
                emptyState(
                    icon: "arrow.right",
                    message: "まだ置換ルールがありません",
                    hint: "例: 「住所」→「東京都渋谷区...」\n「メールアドレス」→「user@example.com」"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(data.replacementRules) { rule in
                            HStack(spacing: 12) {
                                Text(rule.trigger)
                                    .font(.system(size: 13, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))

                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.blue.opacity(0.6))

                                Text(rule.replacement)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)

                                Spacer()

                                Button("削除") {
                                    withAnimation { data.removeReplacement(id: rule.id) }
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(.red.opacity(0.7))
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            Divider().padding(.leading, 24)
                        }
                    }
                }
            }
        }
    }

    private func addRule() {
        let trigger = newTrigger.trimmingCharacters(in: .whitespaces)
        let replacement = newReplacement.trimmingCharacters(in: .whitespaces)
        guard !trigger.isEmpty else { return }
        data.addReplacement(trigger: trigger, replacement: replacement)
        newTrigger = ""
        newReplacement = ""
    }
}

// MARK: - Custom Instructions Content

struct CustomInstructionsContentView: View {
    @ObservedObject private var data = CustomData.shared
    @State private var savedToast = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabHeader(
                title: "カスタム指示",
                subtitle: "出力スタイルの好みや細かい指示を入力できます。LLM後処理時に適用されます。"
            )

            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $data.customInstructions)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.gray.opacity(0.15), lineWidth: 0.5)
                    )
                    .overlay(alignment: .topLeading) {
                        if data.customInstructions.isEmpty {
                            Text("例: 「カジュアルな文体で出力してください」「文章を段落に分けてください」「英語の固有名詞はそのまま残してください」")
                                .font(.system(size: 13))
                                .foregroundStyle(.gray.opacity(0.4))
                                .padding(16)
                                .allowsHitTesting(false)
                        }
                    }

                Button {
                    data.saveInstructions()
                    savedToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedToast = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: savedToast ? "checkmark" : "square.and.arrow.down")
                        Text(savedToast ? "保存しました" : "保存")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
            }
            .padding(24)

            Spacer()
        }
    }
}

// MARK: - History Content (wraps existing HistoryView)

struct HistoryContentView: View {
    @ObservedObject var history = TranscriptionHistory.shared
    @State private var selectedRecordID: UUID?
    @State private var showRaw = false
    @State private var copiedToast = false
    @State private var editingRecordID: UUID?
    @State private var editingText = ""

    private var groupedRecords: [(String, [TranscriptionRecord])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let grouped = Dictionary(grouping: history.records(lastDays: 10)) {
            formatter.string(from: $0.timestamp)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabHeader(title: "履歴", subtitle: "過去10日間の文字起こし結果") {
                Button {
                    copyAllAsMarkdown()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedToast ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(copiedToast ? "コピー済み" : "全件コピー")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .disabled(history.records(lastDays: 10).isEmpty)
            }

            Divider()

            if history.records(lastDays: 10).isEmpty {
                emptyState(icon: "text.bubble", message: "まだ文字起こし履歴がありません", hint: "ホットキーを長押しして録音を開始してください")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(groupedRecords, id: \.0) { dateKey, records in
                            dateSection(dateKey: dateKey, records: records)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func dateSection(dateKey: String, records: [TranscriptionRecord]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.system(size: 10)).foregroundStyle(.secondary)
                Text(formattedDateHeader(dateKey)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(records.count)件").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            VStack(spacing: 1) {
                ForEach(records.sorted(by: { $0.timestamp > $1.timestamp })) { record in
                    recordRow(record)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func recordRow(_ record: TranscriptionRecord) -> some View {
        let isExpanded = selectedRecordID == record.id
        let isEditing = editingRecordID == record.id
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Text(timeString(record.timestamp))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    if isExpanded {
                        HStack(spacing: 8) {
                            pillButton("整形後", active: !showRaw && !isEditing) {
                                showRaw = false; editingRecordID = nil
                            }
                            pillButton("原文", active: showRaw && !isEditing) {
                                showRaw = true; editingRecordID = nil
                            }
                            pillButton("編集", active: isEditing) {
                                editingRecordID = record.id
                                editingText = record.cleanedTranscript
                            }
                            Spacer()
                        }

                        if isEditing {
                            TextEditor(text: $editingText)
                                .font(.system(size: 13))
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .frame(minHeight: 80)
                                .background(Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
                                )
                                .padding(.top, 4)

                            HStack(spacing: 8) {
                                Spacer()
                                Button {
                                    editingRecordID = nil
                                } label: {
                                    Text("キャンセル")
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    history.updateRecord(id: record.id, cleaned: editingText)
                                    editingRecordID = nil
                                } label: {
                                    Text("保存")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 4)
                                        .background(.blue, in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.top, 4)
                        } else {
                            Text(showRaw ? record.rawTranscript : record.cleanedTranscript)
                                .font(.system(size: 13)).textSelection(.enabled).padding(.top, 4)
                        }
                    } else {
                        Text(record.cleanedTranscript).font(.system(size: 13)).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if isExpanded && !isEditing {
                    VStack(spacing: 6) {
                        smallIconButton("doc.on.doc") { copyRecord(record) }
                        smallIconButton("trash", tint: .red.opacity(0.7)) {
                            history.deleteRecord(id: record.id); selectedRecordID = nil
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(isEditing ? Color.blue.opacity(0.06) : isExpanded ? Color.blue.opacity(0.04) : Color.gray.opacity(0.04))
        .contentShape(Rectangle())
        .onTapGesture {
            guard editingRecordID == nil else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedRecordID = selectedRecordID == record.id ? nil : record.id
                if selectedRecordID != nil { showRaw = false }
            }
        }
    }

    private func pillButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(active ? Color.blue.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(active ? .blue : .secondary)
        }.buttonStyle(.plain)
    }

    private func smallIconButton(_ symbol: String, tint: Color = .blue, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain)
    }

    private func copyRecord(_ record: TranscriptionRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(TranscriptionHistory.exportMarkdown([record]), forType: .string)
    }

    private func copyAllAsMarkdown() {
        let records = history.records(lastDays: 10)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(TranscriptionHistory.exportMarkdown(records), forType: .string)
        copiedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedToast = false }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
    }

    private func formattedDateHeader(_ dateKey: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: dateKey) else { return dateKey }
        if Calendar.current.isDateInToday(date) { return "今日" }
        if Calendar.current.isDateInYesterday(date) { return "昨日" }
        let d = DateFormatter(); d.dateFormat = "M月d日 (E)"; d.locale = Locale(identifier: "ja_JP")
        return d.string(from: date)
    }
}

// MARK: - Stats Content

struct StatsContentView: View {
    @ObservedObject var history = TranscriptionHistory.shared

    private var allRecords: [TranscriptionRecord] {
        history.records(lastDays: 30)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabHeader(title: "統計", subtitle: "文字起こしの利用状況")

            ScrollView {
                VStack(spacing: 20) {
                    summaryRow
                    calendarSection
                    dailyList
                }
                .padding(24)
            }
        }
    }

    // MARK: - Summary Row

    private var summaryRow: some View {
        HStack(spacing: 10) {
            summaryCard(
                icon: "sun.max.fill",
                iconColor: .blue,
                label: "今日",
                chars: charCount(for: .day),
                count: recordCount(for: .day)
            )
            summaryCard(
                icon: "calendar.badge.clock",
                iconColor: .purple,
                label: "今週",
                chars: charCount(for: .weekOfYear),
                count: recordCount(for: .weekOfYear)
            )
            summaryCard(
                icon: "chart.line.uptrend.xyaxis",
                iconColor: .orange,
                label: "今月",
                chars: charCount(for: .month),
                count: recordCount(for: .month)
            )
        }
    }

    private func summaryCard(icon: String, iconColor: Color, label: String, chars: Int, count: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 20, height: 20)
                    .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.bottom, 10)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(fmtNum(chars))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("文字")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack {
                Text("\(count)回")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.gray.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Calendar Section

    private var calendarSection: some View {
        let days = last10Days()
        let charsByDay = charCountByDay()
        let maxChars = charsByDay.values.max() ?? 1

        return VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("10日間アクティビティ")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            } icon: {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
            }

            calendarGrid(days: days.reversed(), charsByDay: charsByDay, maxChars: maxChars)
        }
    }

    private func calendarGrid(days: [Date], charsByDay: [String: Int], maxChars: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(days, id: \.self) { day in
                calendarCell(day: day, charsByDay: charsByDay, maxChars: maxChars)
            }
        }
        .padding(12)
        .background(.gray.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.gray.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func calendarCell(day: Date, charsByDay: [String: Int], maxChars: Int) -> some View {
        let count = charsByDay[dayKey(day)] ?? 0
        let intensity = cellIntensity(count, max: maxChars)
        let isToday = Calendar.current.isDateInToday(day)

        return VStack(spacing: 5) {
            Text(shortDayLabel(day))
                .font(.system(size: 8, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? .primary : .tertiary)

            calendarCellBar(count: count, intensity: intensity)

            Text(shortDateLabel(day))
                .font(.system(size: 8, weight: isToday ? .semibold : .regular))
                .foregroundStyle(isToday ? AnyShapeStyle(.blue) : AnyShapeStyle(.tertiary))
        }
        .frame(maxWidth: .infinity)
    }

    private func calendarCellBar(count: Int, intensity: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(count > 0
                    ? Color.green.opacity(0.12 + intensity * 0.68)
                    : Color.gray.opacity(0.06))
                .frame(height: 44)

            if count > 0 {
                VStack(spacing: 1) {
                    Text(fmtNum(count))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                    Text("字")
                        .font(.system(size: 7))
                }
                .foregroundStyle(intensity > 0.5 ? .white.opacity(0.9) : .green)
            }
        }
    }

    // MARK: - Daily List

    private var dailyList: some View {
        let days = last10Days()
        let charsByDay = charCountByDay()
        let countByDay = recordCountByDay()
        let maxChars = charsByDay.values.max() ?? 1
        let activeDays = days.filter { (charsByDay[dayKey($0)] ?? 0) > 0 }

        return VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("日別詳細")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            } icon: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 2) {
                if activeDays.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 20))
                                .foregroundStyle(.gray.opacity(0.25))
                            Text("データがありません")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 20)
                        Spacer()
                    }
                } else {
                    ForEach(activeDays, id: \.self) { day in
                        let key = dayKey(day)
                        let chars = charsByDay[key] ?? 0
                        let count = countByDay[key] ?? 0
                        let ratio = CGFloat(chars) / CGFloat(maxChars)

                        HStack(spacing: 12) {
                            Text(dateDisplayLabel(day))
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 85, alignment: .leading)

                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        LinearGradient(
                                            colors: [.green.opacity(0.5), .green.opacity(0.25)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(4, geo.size.width * ratio))
                            }
                            .frame(height: 14)

                            Text("\(count)回")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(width: 32, alignment: .trailing)

                            Text(fmtNum(chars))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .frame(width: 52, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.gray.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func charCount(for component: Calendar.Component) -> Int {
        let cal = Calendar.current
        return allRecords
            .filter { cal.isDate($0.timestamp, equalTo: Date(), toGranularity: component) }
            .reduce(0) { $0 + $1.cleanedTranscript.count }
    }

    private func recordCount(for component: Calendar.Component) -> Int {
        let cal = Calendar.current
        return allRecords
            .filter { cal.isDate($0.timestamp, equalTo: Date(), toGranularity: component) }
            .count
    }

    private func last10Days() -> [Date] {
        let cal = Calendar.current
        return (0..<10).compactMap { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: Date())) }
    }

    private func dayKey(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }

    private func charCountByDay() -> [String: Int] {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        var result: [String: Int] = [:]
        for r in allRecords { result[f.string(from: r.timestamp), default: 0] += r.cleanedTranscript.count }
        return result
    }

    private func recordCountByDay() -> [String: Int] {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        var result: [String: Int] = [:]
        for r in allRecords { result[f.string(from: r.timestamp), default: 0] += 1 }
        return result
    }

    private func cellIntensity(_ count: Int, max: Int) -> Double {
        guard max > 0 else { return 0 }
        return Double(count) / Double(max)
    }

    private func shortDayLabel(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "E"; f.locale = Locale(identifier: "ja_JP")
        return f.string(from: date)
    }

    private func shortDateLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "今日" }
        let f = DateFormatter(); f.dateFormat = "M/d"; return f.string(from: date)
    }

    private func dateDisplayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "今日" }
        if Calendar.current.isDateInYesterday(date) { return "昨日" }
        let f = DateFormatter(); f.dateFormat = "M/d (E)"; f.locale = Locale(identifier: "ja_JP")
        return f.string(from: date)
    }

    private func fmtNum(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - Shared Components

private func tabHeader<Trailing: View>(
    title: String,
    subtitle: String,
    @ViewBuilder trailing: () -> Trailing
) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }
}

private func tabHeader(title: String, subtitle: String) -> some View {
    tabHeader(title: title, subtitle: subtitle) { EmptyView() }
}

private func emptyState(icon: String, message: String, hint: String) -> some View {
    VStack(spacing: 12) {
        Spacer()
        Image(systemName: icon)
            .font(.system(size: 36))
            .foregroundStyle(.gray.opacity(0.25))
        Text(message)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        Text(hint)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
        Spacer()
    }
    .frame(maxWidth: .infinity)
}

func settingsGroup<Content: View>(
    title: String,
    icon: String,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Label {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
        } icon: {
            Image(systemName: icon).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
        }
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}
