import Foundation
import os

/// Lightweight performance monitoring utility
/// Usage: PerformanceMonitor.measure("operation-name") { /* code */ }
enum PerformanceMonitor {
    private static let logger = Logger(subsystem: "cn.yohoia.rimo", category: "performance")
    private static let enabled = ProcessInfo.processInfo.environment["RIMO_PERF_MONITOR"] != nil

    /// Measure execution time of a code block
    /// Only logs when RIMO_PERF_MONITOR environment variable is set
    static func measure<T>(_ label: String, operation: () throws -> T) rethrows -> T {
        guard enabled else { return try operation() }

        let start = Date()
        defer {
            let duration = Date().timeIntervalSince(start)
            if duration > 0.016 { // Log if slower than one frame (60fps)
                logger.warning("⚠️ \(label, privacy: .public): \(String(format: "%.1fms", duration * 1000), privacy: .public)")
            } else {
                logger.debug("✓ \(label, privacy: .public): \(String(format: "%.1fms", duration * 1000), privacy: .public)")
            }
        }

        return try operation()
    }

    /// Measure async operation
    static func measure<T>(_ label: String, operation: () async throws -> T) async rethrows -> T {
        guard enabled else { return try await operation() }

        let start = Date()
        defer {
            let duration = Date().timeIntervalSince(start)
            if duration > 0.016 {
                logger.warning("⚠️ \(label, privacy: .public): \(String(format: "%.1fms", duration * 1000), privacy: .public)")
            } else {
                logger.debug("✓ \(label, privacy: .public): \(String(format: "%.1fms", duration * 1000), privacy: .public)")
            }
        }

        return try await operation()
    }

    /// Mark a point in time for relative measurements
    static func mark(_ label: String) {
        guard enabled else { return }
        logger.info("📍 \(label, privacy: .public)")
    }
}
