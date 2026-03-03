#!/bin/bash
set -e

BUILD_DIR=".build"
PRODUCT="VoiceLog"
ENTITLEMENTS="VoiceLog.entitlements"
SDK=$(xcrun --show-sdk-path)

SOURCES=(
    Sources/Core/AppLogger.swift
    Sources/Core/StateMachine.swift
    Sources/Core/HotkeyManager.swift
    Sources/Core/AudioRecorder.swift
    Sources/Core/SpeechRecognizer.swift
    Sources/Core/PostProcessor.swift
    Sources/Core/PasteEngine.swift
    Sources/Preferences/UserPreferences.swift
    Sources/UI/TranscriptHUD/TranscriptViewModel.swift
    Sources/UI/TranscriptHUD/TranscriptHUDView.swift
    Sources/UI/TranscriptHUD/TranscriptHUDWindow.swift
    Sources/UI/MenuBarController.swift
    Sources/UI/PreferencesView.swift
    Sources/App/AppCoordinator.swift
    Sources/App/VoiceLogApp.swift
)

FRAMEWORKS=(
    -framework AppKit
    -framework AVFoundation
    -framework Speech
    -framework CoreGraphics
    -framework Carbon
)

mkdir -p "$BUILD_DIR"

echo "Building $PRODUCT..."

swiftc \
    -o "$BUILD_DIR/$PRODUCT" \
    -target arm64-apple-macosx14.0 \
    -sdk "$SDK" \
    -swift-version 5 \
    -O \
    "${FRAMEWORKS[@]}" \
    "${SOURCES[@]}" \
    2>&1

echo "Build succeeded: $BUILD_DIR/$PRODUCT"

if [ -f "$ENTITLEMENTS" ]; then
    echo "Signing with entitlements..."
    codesign --entitlements "$ENTITLEMENTS" -fs - "$BUILD_DIR/$PRODUCT" 2>&1
    echo "Signed."
fi

echo ""
echo "Run: ./$BUILD_DIR/$PRODUCT"
echo ""
echo "Required permissions (grant on first run):"
echo "  - Microphone"
echo "  - Speech Recognition"
echo "  - Input Monitoring (System Settings > Privacy & Security)"
echo "  - Accessibility (System Settings > Privacy & Security)"
