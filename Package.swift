// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VoiceLog",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VoiceLog",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Carbon"),
            ]
        )
    ]
)
