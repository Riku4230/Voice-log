import SwiftUI

struct TranscriptHUDView: View {
    @ObservedObject var viewModel: TranscriptViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.indicatorColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: viewModel.indicatorColor.opacity(0.6), radius: 4)

                Text(viewModel.statusLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))

                if viewModel.state == .recording {
                    AudioLevelBar(level: viewModel.audioLevel)
                        .frame(height: 4)
                }

                Spacer()

                if viewModel.state == .recording {
                    Text(viewModel.durationLabel)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 0.5)

            // Transcript area
            if viewModel.state == .readyToPaste {
                TextEditor(text: $viewModel.cleanedText)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(maxHeight: 140)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                    )
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            if !viewModel.finalText.isEmpty {
                                Text(viewModel.finalText)
                                    .font(.system(size: 13))
                                    .foregroundColor(.white)
                            }
                            if !viewModel.partialText.isEmpty {
                                Text(viewModel.partialText)
                                    .font(.system(size: 13).italic())
                                    .foregroundColor(.white.opacity(0.45))
                            }
                            if viewModel.state == .processing {
                                if viewModel.isWhisperProcessing {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.mini)
                                            .scaleEffect(0.7)
                                        Text("Whisperで高精度認識中...")
                                            .font(.system(size: 11).italic())
                                            .foregroundColor(.green.opacity(0.6))
                                    }
                                    .padding(.top, 4)
                                } else if viewModel.isLLMProcessing {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.mini)
                                            .scaleEffect(0.7)
                                        Text("AIが整形中...")
                                            .font(.system(size: 11).italic())
                                            .foregroundColor(.cyan.opacity(0.6))
                                    }
                                    .padding(.top, 4)
                                }
                            }
                            if viewModel.state == .recording {
                                if viewModel.finalText.isEmpty && viewModel.partialText.isEmpty {
                                    Text("話してください...")
                                        .font(.system(size: 13).italic())
                                        .foregroundColor(.white.opacity(0.2))
                                } else if viewModel.partialText.isEmpty {
                                    // Text exists but no active partial — show listening indicator
                                    ListeningIndicator()
                                        .padding(.top, 6)
                                }
                            }
                            // Scroll anchor
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                    .onChange(of: viewModel.partialText) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: viewModel.finalText) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }

            // Footer
            footerView
        }
        .padding(14)
        .frame(width: 340)
        .background(Color(white: 0.08).opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
    }

    @ViewBuilder
    private var footerView: some View {
        HStack(spacing: 6) {
            switch viewModel.state {
            case .recording:
                Image(systemName: viewModel.isContinuous ? "mic.fill" : "hand.raised")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
                Text(viewModel.isContinuous ? "キーを押して終了" : "キーを離すと完了")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))

                Spacer()

                if !viewModel.focusedAppName.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "app.fill")
                            .font(.system(size: 8))
                        Text(viewModel.focusedAppName)
                            .font(.system(size: 10))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white.opacity(0.3))
                }

            case .processing:
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                Text(viewModel.isWhisperProcessing ? "Whisperで認識中..." : viewModel.isLLMProcessing ? "AIにより整形中..." : "整形中...")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))

            case .readyToPaste:
                Image(systemName: "pencil.line")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.35))
                Text("編集可 / 短押しでペースト")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))

                Spacer()

                Button {
                    viewModel.onCancel?()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                        Text("取り消し")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.red.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.red.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Audio Level Bar

struct AudioLevelBar: View {
    var level: Float  // 0.0 - 1.0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.1))

                Capsule()
                    .fill(barColor)
                    .frame(width: max(2, geo.size.width * CGFloat(level)))
                    .animation(.linear(duration: 0.066), value: level)
            }
        }
    }

    private var barColor: Color {
        if level > 0.8 { return .orange }
        if level > 0.5 { return .green }
        return .white.opacity(0.4)
    }
}

// MARK: - Listening Indicator

struct ListeningIndicator: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 3) {
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(.white.opacity(0.3))
                        .frame(width: 2, height: animate ? 10 : 4)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.15),
                            value: animate
                        )
                }
            }
            .frame(height: 12)

            Text("聞き取り中...")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.25))
        }
        .onAppear { animate = true }
    }
}
