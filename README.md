# VoiceLog

macOS 向け Push-to-Talk 音声文字起こしツール。ホットキーの長押しで録音 + リアルタイム文字起こしを行い、短押しでカーソル位置にペーストします。

音声認識はすべて Apple の on-device Speech Recognition で処理され、外部にデータは送信されません。

## 機能

- ホットキー長押しで録音開始、離すと自動で文字起こし
- フローティング HUD にリアルタイムでテキスト表示
- 整形後のテキストをその場で編集可能
- 短押しでカーソル位置にペースト (Cmd+V シミュレーション)
- フィラー除去 (えーと、あの、まあ 等)
- LLM による後処理 (Claude Haiku API / Ollama 対応)
- 音声コマンド (「全部消して」で全消去)
- 文字起こし履歴の保存・閲覧 (過去10日分)
- 統計ダッシュボード (カレンダーヒートマップ、文字数推移)
- 辞書登録 (固有名詞の認識精度向上)
- テキスト置換ルール
- カスタム指示 (LLM への追加プロンプト)

## 必要環境

- macOS 14.0 (Sonoma) 以上
- Xcode (Command Line Tools)
- Swift 5.9+

## セットアップ

### 1. Xcode Command Line Tools

```bash
xcode-select --install
# または App Store から Xcode をインストール後:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### 2. ビルド

```bash
git clone <repository-url>
cd voice-log
swift build
```

### 3. 起動

#### 方法 A: swift run (開発向け / 推奨)

```bash
swift run
```

ターミナルから直接起動します。ログがターミナルに表示されるのでデバッグに便利です。

#### 方法 B: .app バンドル (Raycast / Spotlight から起動したい場合)

```bash
bash scripts/bundle.sh
```

`~/Applications/VoiceLog.app` にインストールされます。Raycast や Spotlight から "VoiceLog" で検索して起動できます。

> **注意**: .app バンドルはバイナリが異なるため、権限設定 (Input Monitoring, Accessibility) を別途許可する必要があります。

### 4. 権限設定 (初回のみ)

初回起動時に以下の権限ダイアログが表示されます:

| 権限 | 用途 | 設定場所 |
|------|------|----------|
| マイク | 録音 | 自動ダイアログ |
| 音声認識 | on-device 文字起こし | 自動ダイアログ |
| Input Monitoring | ホットキー検知 | システム設定 > プライバシーとセキュリティ > 入力監視 |
| Accessibility | ペースト (Cmd+V シミュレーション) | システム設定 > プライバシーとセキュリティ > アクセシビリティ |

`swift run` で起動する場合はターミナルアプリ (Terminal.app / iTerm2 等) に対して権限を付与してください。

## 使い方

| 操作 | 動作 |
|------|------|
| ホットキー長押し (デフォルト: Fn) | 録音開始 — HUD にリアルタイム表示 |
| ホットキーを離す | 録音停止 → テキスト整形 → HUD で編集可能 |
| ホットキー短押し | カーソル位置にペースト |
| ESC | 録音/ペースト待ちをキャンセル |

### 音声コマンド

録音中に以下のフレーズを話すと、特定の操作が実行されます:

| フレーズ | 動作 |
|---------|------|
| 「全部消して」「全て消去」 | テキスト全消去 |

## 設定

メニューバーのアイコン > 「VoiceLog を開く...」から設定画面を開けます。

### タブ一覧

| タブ | 内容 |
|------|------|
| 設定 | 後処理モード、ホットキー、言語、タイムアウト |
| 辞書 | 認識精度向上のための固有名詞登録 |
| 置換 | 特定フレーズの自動置換ルール |
| カスタム指示 | LLM への追加プロンプト |
| 履歴 | 過去の文字起こし結果の閲覧・編集・マークダウンコピー |
| 統計 | カレンダーヒートマップ、日別・週別・月別の文字数 |

### 後処理モード

| モード | 説明 |
|--------|------|
| ローカル | ルールベースのフィラー除去のみ (無料、高速) |
| Claude Haiku | Anthropic API で自然な日本語に整形 (API キー必要) |
| Ollama | ローカル LLM で整形 (Ollama サーバー必要) |

## プロジェクト構成

```
Sources/
├── App/
│   ├── VoiceLogApp.swift          # エントリポイント
│   └── AppCoordinator.swift       # 状態管理・イベント統合
├── Core/
│   ├── HotkeyManager.swift        # グローバルホットキー (CGEventTap)
│   ├── AudioRecorder.swift        # マイク録音 (AVAudioEngine)
│   ├── SpeechRecognizer.swift     # 音声認識 (SFSpeechRecognizer)
│   ├── PostProcessor.swift        # LLM 後処理 (Claude / Ollama)
│   ├── PasteEngine.swift          # ペースト (CGEvent Cmd+V)
│   ├── StateMachine.swift         # 状態遷移
│   ├── TranscriptionHistory.swift # 履歴の永続化 (JSON)
│   ├── KeychainHelper.swift       # API キーの安全な保存
│   └── AppLogger.swift            # ログ出力
├── Preferences/
│   ├── UserPreferences.swift      # ユーザー設定
│   └── CustomData.swift           # 辞書・置換ルール・カスタム指示
├── UI/
│   ├── MenuBarController.swift    # メニューバーアイコン
│   ├── MainWindowView.swift       # 設定ウィンドウ (SwiftUI)
│   ├── PreferencesView.swift      # 設定タブ
│   ├── HistoryView.swift          # 履歴タブ
│   ├── HotkeyRecorderView.swift   # ホットキー設定
│   └── TranscriptHUD/             # フローティング HUD
scripts/
└── bundle.sh                      # .app バンドル作成スクリプト
```

## データ保存先

| ファイル | パス | 内容 |
|---------|------|------|
| 履歴 | `~/Library/Application Support/VoiceLog/history.json` | 文字起こし履歴 |
| カスタムデータ | `~/Library/Application Support/VoiceLog/custom_data.json` | 辞書・置換ルール |
| ログ | `~/Library/Application Support/VoiceLog/debug.log` | デバッグログ |
| API キー | macOS Keychain | Claude API キー (暗号化保存) |
| 設定 | UserDefaults | 後処理モード、ホットキー等 |

## ライセンス

MIT
