import Foundation

/// Tiny stderr logger. No files, no network, no telemetry — by design.
enum Log {
    static func info(_ m: @autoclosure () -> String)  { emit("INFO", m()) }
    static func warn(_ m: @autoclosure () -> String)  { emit("WARN", m()) }
    static func error(_ m: @autoclosure () -> String) { emit("ERR ", m()) }

    private static func emit(_ level: String, _ m: String) {
        FileHandle.standardError.write(Data("[lodestar \(level)] \(m)\n".utf8))
    }
}
