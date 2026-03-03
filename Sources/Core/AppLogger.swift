import os
import Foundation

enum AppLogger {
    private static let logger = Logger(subsystem: "com.voicelog.app", category: "general")

    private static let logFileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VoiceLog")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("debug.log")
    }()

    private static let queue = DispatchQueue(label: "com.voicelog.logger")

    private static func writeToFile(_ level: String, _ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] [\(level)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        queue.async {
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: logFileURL)
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: logFileURL.path
                )
            }
        }
    }

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        writeToFile("INFO", message)
    }

    static func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        writeToFile("WARN", message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        writeToFile("ERROR", message)
    }
}
