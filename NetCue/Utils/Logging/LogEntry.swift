//
//  LogEntry.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/31.
//

import Foundation
import AppKit

/// 日志条目数据模型
///
/// 表示单条日志记录，包含：
/// - 唯一标识符（UUID）
/// - 时间戳（精确到毫秒）
/// - 日志级别
/// - 消息内容
/// - 源文件名
/// - 函数名
/// - 行号
struct LogEntry: Identifiable, Sendable {
    // MARK: - Properties

    /// 唯一标识符
    let id: UUID

    /// 日志时间戳（精确到毫秒）
    let timestamp: Date

    /// 日志级别
    let level: LogLevel

    /// 日志消息
    let message: String

    /// 源文件名（不含路径）
    let file: String

    /// 函数名
    let function: String

    /// 行号
    let line: Int

    // MARK: - Initializer

    /// 创建日志条目
    ///
    /// - Parameters:
    ///   - level: 日志级别
    ///   - message: 日志消息
    ///   - file: 源文件路径（默认使用 #fileID）
    ///   - function: 函数名（默认使用 #function）
    ///   - line: 行号（默认使用 #line）
    ///
    /// 标记为 nonisolated：初始化器只是创建值类型实例，不涉及actor隔离
    /// 使用 Swift 标准库的字符串操作替代 NSString，避免 AppKit 依赖
    nonisolated init(
        level: LogLevel,
        message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.message = message

        // 使用 Swift 标准库提取文件名，替代 NSString.lastPathComponent
        // 这样可以避免 AppKit 依赖，确保在任何隔离域都可以安全调用
        if let lastComponent = file.split(separator: "/").last {
            self.file = String(lastComponent)
        } else {
            self.file = file
        }

        self.function = function
        self.line = line
    }

    // MARK: - Formatted Output

    /// 格式化为终端样式的字符串（带ANSI颜色）
    ///
    /// 格式：`[2025-12-31 12:34:56.789] [INFO] ℹ️ message (File.swift:42 functionName())`
    var formattedString: String {
        let timestampStr = Self.formatTimestamp(timestamp)
        let locationStr = "\(file):\(line) \(function)"
        return "\(level.ansiColorCode)[\(timestampStr)] [\(level.displayName)] \(level.emoji) \(message) (\(locationStr))\u{001B}[0m"
    }

    /// 格式化为纯文本字符串（不带ANSI颜色）
    ///
    /// 格式：`[2025-12-31 12:34:56.789] [INFO] ℹ️ message (File.swift:42 functionName())`
    var plainTextString: String {
        let timestampStr = Self.formatTimestamp(timestamp)
        let locationStr = "\(file):\(line) \(function)"
        return "[\(timestampStr)] [\(level.displayName)] \(level.emoji) \(message) (\(locationStr))"
    }

    /// 格式化为NSAttributedString（用于 macOS UI）
    ///
    /// 特性：
    /// - 时间戳：灰色
    /// - 日志级别：根据 level.nsColor 着色
    /// - emoji + 消息：黑色/白色（跟随系统深色模式）
    /// - 位置信息：浅灰色
    var attributedString: NSAttributedString {
        let result = NSMutableAttributedString()

        // 基础字体：SF Mono 12pt（macOS 终端标准字体）
        let baseFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        // 时间戳（灰色）
        let timestampStr = Self.formatTimestamp(timestamp)
        result.append(NSAttributedString(
            string: "[\(timestampStr)] ",
            attributes: [
                .font: baseFont,
                .foregroundColor: NSColor.systemGray
            ]
        ))

        // 日志级别（根据级别着色）
        result.append(NSAttributedString(
            string: "[\(level.displayName)] ",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: level.nsColor
            ]
        ))

        // emoji + 消息（主文本颜色）
        result.append(NSAttributedString(
            string: "\(level.emoji) \(message) ",
            attributes: [
                .font: baseFont,
                .foregroundColor: NSColor.labelColor  // 自动适配深色模式
            ]
        ))

        // 位置信息（浅灰色）
        let locationStr = "(\(file):\(line) \(function))"
        result.append(NSAttributedString(
            string: locationStr,
            attributes: [
                .font: baseFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        ))

        return result
    }

    // MARK: - Private Helpers

    /// 格式化时间戳（精确到毫秒）
    ///
    /// 使用 macOS 15+ 的 `.formatted()` API 替代 DateFormatter
    private static func formatTimestamp(_ date: Date) -> String {
        // 使用 ISO 8601 格式的日期部分 + 自定义时间格式
        let dateStr = date.formatted(
            .dateTime
            .year()
            .month(.twoDigits)
            .day(.twoDigits)
            .hour(.twoDigits(amPM: .omitted))
            .minute(.twoDigits)
            .second(.twoDigits)
            .locale(Locale(identifier: "en_US_POSIX"))
        )
        // 添加毫秒（.formatted() 不支持毫秒，需要手动计算）
        let milliseconds = Int((date.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)) * 1000)
        return "\(dateStr).\(String(format: "%03d", milliseconds))"
    }
}

// MARK: - Equatable

extension LogEntry: Equatable {
    static func == (lhs: LogEntry, rhs: LogEntry) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension LogEntry: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
