import SwiftUI
import AppKit

// MARK: - History View

struct HistoryView: View {
    @ObservedObject var history = TranscriptionHistory.shared
    @State private var selectedRecordID: UUID?
    @State private var showRaw = false
    @State private var copiedToast = false

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
            // Toolbar
            toolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Rectangle()
                .fill(.gray.opacity(0.15))
                .frame(height: 0.5)

            // Content
            if history.records(lastDays: 10).isEmpty {
                emptyState
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
        .frame(width: 520, height: 480)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("文字起こし履歴")
                    .font(.system(size: 15, weight: .semibold))
                let count = history.records(lastDays: 10).count
                Text("過去10日間 (\(count)件)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

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
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "text.bubble")
                .font(.system(size: 36))
                .foregroundStyle(.gray.opacity(0.3))
            Text("まだ文字起こし履歴がありません")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("ホットキーを長押しして録音を開始してください")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Date Section

    private func dateSection(dateKey: String, records: [TranscriptionRecord]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Date header
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(formattedDateHeader(dateKey))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Text("\(records.count)件")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            // Records
            VStack(spacing: 1) {
                ForEach(records.sorted(by: { $0.timestamp > $1.timestamp })) { record in
                    recordRow(record)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Record Row

    private func recordRow(_ record: TranscriptionRecord) -> some View {
        let isExpanded = selectedRecordID == record.id

        return VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(alignment: .top, spacing: 10) {
                // Time
                Text(timeString(record.timestamp))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)

                // Text preview or full
                VStack(alignment: .leading, spacing: 4) {
                    if isExpanded {
                        // Toggle raw/cleaned
                        HStack(spacing: 8) {
                            tabPill("整形後", active: !showRaw) { showRaw = false }
                            tabPill("原文", active: showRaw) { showRaw = true }
                            Spacer()
                        }

                        Text(showRaw ? record.rawTranscript : record.cleanedTranscript)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .padding(.top, 4)
                    } else {
                        Text(record.cleanedTranscript)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                // Actions
                if isExpanded {
                    VStack(spacing: 6) {
                        iconButton("doc.on.doc") {
                            copyRecord(record)
                        }
                        iconButton("trash", tint: .red.opacity(0.7)) {
                            history.deleteRecord(id: record.id)
                            selectedRecordID = nil
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(isExpanded ? Color.blue.opacity(0.04) : Color.gray.opacity(0.04))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                if selectedRecordID == record.id {
                    selectedRecordID = nil
                } else {
                    selectedRecordID = record.id
                    showRaw = false
                }
            }
        }
    }

    // MARK: - Components

    private func tabPill(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(active ? Color.blue.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(active ? .blue : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ symbol: String, tint: Color = .blue, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func copyRecord(_ record: TranscriptionRecord) {
        let markdown = TranscriptionHistory.exportMarkdown([record])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    private func copyAllAsMarkdown() {
        let records = history.records(lastDays: 10)
        let markdown = TranscriptionHistory.exportMarkdown(records)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)

        copiedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedToast = false
        }
    }

    // MARK: - Formatters

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func formattedDateHeader(_ dateKey: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateKey) else { return dateKey }

        if Calendar.current.isDateInToday(date) { return "今日" }
        if Calendar.current.isDateInYesterday(date) { return "昨日" }

        let display = DateFormatter()
        display.dateFormat = "M月d日 (E)"
        display.locale = Locale(identifier: "ja_JP")
        return display.string(from: date)
    }
}
