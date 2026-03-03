#!/bin/bash
set -euo pipefail

APP_NAME="VoiceLog"
BUNDLE_ID="com.voicelog.app"
INSTALL_DIR="$HOME/Applications"
APP_PATH="$INSTALL_DIR/$APP_NAME.app"
CONTENTS="$APP_PATH/Contents"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Building $APP_NAME (release)..."
cd "$PROJECT_DIR"
swift build -c release --quiet

echo "Creating app bundle..."
rm -rf "$APP_PATH"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

cp ".build/release/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"

# Info.plist
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>VoiceLog</string>
    <key>CFBundleDisplayName</key>
    <string>VoiceLog</string>
    <key>CFBundleIdentifier</key>
    <string>com.voicelog.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleExecutable</key>
    <string>VoiceLog</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoiceLog needs microphone access for voice transcription.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>音声認識はすべてオンデバイスで処理され、Appleを含む外部にデータは送信されません。</string>
</dict>
</plist>
PLIST

# Touch to update Spotlight/LaunchServices
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH" 2>/dev/null || true

echo "Installed: $APP_PATH"
echo "Raycast should now find VoiceLog."
