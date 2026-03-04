// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VoiceLog",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/exPHAT/SwiftWhisper.git", branch: "master"),
    ],
    targets: [
        .executableTarget(
            name: "VoiceLog",
            dependencies: ["SwiftWhisper"],
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Carbon"),
                .linkedFramework("Accelerate"),
            ]
        )
    ]
)
