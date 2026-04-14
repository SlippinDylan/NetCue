//
//  AppLogger.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/31.
//

import Foundation

/// 全局日志单例
///
/// 提供统一的日志接口，支持：
/// - 6个日志级别（trace/debug/info/warning/error/critical）
/// - 自动捕获调用位置（文件名、函数名、行号）
/// - 线程安全的异步写入
/// - 日志级别过滤
/// - 多后端输出（LogStore + Console）
///
/// 使用示例：
/// ```swift
/// AppLogger.info("用户点击了开始检测按钮")
/// AppLogger.error("网络请求失败", error: someError)
/// AppLogger.debug("当前状态", data: ["ip": ipAddress, "status": status])
/// ```
@globalActor
actor AppLogger {
    // MARK: - Singleton

    static let shared = AppLogger()

    // MARK: - Properties

    /// 最低日志级别（低于此级别的日志将被忽略）
    private var minimumLevel: LogLevel = .trace

    /// 串行队列（确保日志按顺序写入）
    private let loggingQueue = DispatchQueue(
        label: "com.netcue.logging",
        qos: .utility
    )

    // MARK: - Initializer

    private init() {
        #if DEBUG
        minimumLevel = .debug
        #else
        minimumLevel = .warning
        #endif
    }

    // MARK: - Configuration

    /// 设置最低日志级别
    ///
    /// - Parameter level: 最低日志级别
    ///
    /// 低于此级别的日志将被忽略。例如，设置为 `.info` 后，
    /// `.trace` 和 `.debug` 级别的日志将不会被记录。
    func setMinimumLevel(_ level: LogLevel) {
        minimumLevel = level
    }

    // MARK: - Logging Methods

    /// 记录 TRACE 级别日志
    ///
    /// - Parameters:
    ///   - message: 日志消息
    ///   - file: 源文件路径（自动捕获）
    ///   - function: 函数名（自动捕获）
    ///   - line: 行号（自动捕获）
    static func trace(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        Task {
            await shared.log(
                level: .trace,
                message: message,
                file: file,
                function: function,
                line: line
            )
        }
    }

    /// 记录 DEBUG 级别日志
    ///
    /// - Parameters:
    ///   - message: 日志消息
    ///   - file: 源文件路径（自动捕获）
    ///   - function: 函数名（自动捕获）
    ///   - line: 行号（自动捕获）
    static func debug(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        Task {
            await shared.log(
                level: .debug,
                message: message,
                file: file,
                function: function,
                line: line
            )
        }
    }

    /// 记录 INFO 级别日志
    ///
    /// - Parameters:
    ///   - message: 日志消息
    ///   - file: 源文件路径（自动捕获）
    ///   - function: 函数名（自动捕获）
    ///   - line: 行号（自动捕获）
    static func info(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        Task {
            await shared.log(
                level: .info,
                message: message,
                file: file,
                function: function,
                line: line
            )
        }
    }

    /// 记录 WARNING 级别日志
    ///
    /// - Parameters:
    ///   - message: 日志消息
    ///   - file: 源文件路径（自动捕获）
    ///   - function: 函数名（自动捕获）
    ///   - line: 行号（自动捕获）
    static func warning(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        Task {
            await shared.log(
                level: .warning,
                message: message,
                file: file,
                function: function,
                line: line
            )
        }
    }

    /// 记录 ERROR 级别日志
    ///
    /// - Parameters:
    ///   - message: 日志消息
    ///   - error: 错误对象（可选）
    ///   - file: 源文件路径（自动捕获）
    ///   - function: 函数名（自动捕获）
    ///   - line: 行号（自动捕获）
    static func error(
        _ message: String,
        error: Error? = nil,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        Task {
            let fullMessage = if let error = error {
                "\(message) - Error: \(error.localizedDescription)"
            } else {
                message
            }

            await shared.log(
                level: .error,
                message: fullMessage,
                file: file,
                function: function,
                line: line
            )
        }
    }

    /// 记录 CRITICAL 级别日志
    ///
    /// - Parameters:
    ///   - message: 日志消息
    ///   - error: 错误对象（可选）
    ///   - file: 源文件路径（自动捕获）
    ///   - function: 函数名（自动捕获）
    ///   - line: 行号（自动捕获）
    static func critical(
        _ message: String,
        error: Error? = nil,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        Task {
            let fullMessage = if let error = error {
                "\(message) - Error: \(error.localizedDescription)"
            } else {
                message
            }

            await shared.log(
                level: .critical,
                message: fullMessage,
                file: file,
                function: function,
                line: line
            )
        }
    }

    // MARK: - Internal Logging

    /// 内部日志记录方法
    ///
    /// - Parameters:
    ///   - level: 日志级别
    ///   - message: 日志消息
    ///   - file: 源文件路径
    ///   - function: 函数名
    ///   - line: 行号
    private func log(
        level: LogLevel,
        message: String,
        file: String,
        function: String,
        line: Int
    ) {
        // 级别过滤
        guard level >= minimumLevel else {
            return
        }

        // 创建日志条目
        let entry = LogEntry(
            level: level,
            message: message,
            file: file,
            function: function,
            line: line
        )

        // 异步写入日志存储（避免阻塞主线程）
        loggingQueue.async {
            Task { @MainActor in
                LogStore.shared.append(entry)
            }
        }

        // 同时输出到 Xcode Console（开发时方便调试）
        #if DEBUG
        // 在后台队列格式化字符串，避免在 actor 上下文中访问 NSColor
        loggingQueue.async {
            Task { @MainActor in
                print(entry.formattedString)
            }
        }
        #endif
    }
}
