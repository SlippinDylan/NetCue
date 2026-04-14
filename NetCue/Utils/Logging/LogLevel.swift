//
//  LogLevel.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/31.
//

import Foundation
import AppKit

/// 日志级别枚举
///
/// 定义了6个日志级别，从低到高依次为：
/// - trace: 最详细的调试信息（如函数进入/退出）
/// - debug: 调试信息（如变量值、中间状态）
/// - info: 一般信息（如操作成功、状态变化）
/// - warning: 警告信息（如非致命错误、降级服务）
/// - error: 错误信息（如操作失败、异常情况）
/// - critical: 严重错误（如系统崩溃、数据损坏）
enum LogLevel: Int, Comparable, CaseIterable, Codable, Sendable {
    case trace = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case critical = 5

    // MARK: - Display Properties

    /// 日志级别的显示名称（大写，4字符对齐）
    ///
    /// 标记为 nonisolated：这是纯计算属性，不涉及状态修改，可以在任何隔离域安全调用
    nonisolated var displayName: String {
        switch self {
        case .trace:    return "TRACE"
        case .debug:    return "DEBUG"
        case .info:     return "INFO "
        case .warning:  return "WARN "
        case .error:    return "ERROR"
        case .critical: return "CRIT "
        }
    }

    /// 日志级别的emoji图标
    ///
    /// 标记为 nonisolated：emoji 是静态字符串，可以在任何隔离域安全调用
    nonisolated var emoji: String {
        switch self {
        case .trace:    return "🔍"
        case .debug:    return "🐛"
        case .info:     return "ℹ️"
        case .warning:  return "⚠️"
        case .error:    return "❌"
        case .critical: return "🔥"
        }
    }

    /// ANSI 颜色代码（用于终端输出）
    ///
    /// 标记为 nonisolated：ANSI 代码是静态字符串，可以在任何隔离域安全调用
    nonisolated var ansiColorCode: String {
        switch self {
        case .trace:    return "\u{001B}[0;37m"  // 灰色
        case .debug:    return "\u{001B}[0;36m"  // 青色
        case .info:     return "\u{001B}[0;32m"  // 绿色
        case .warning:  return "\u{001B}[0;33m"  // 黄色
        case .error:    return "\u{001B}[0;31m"  // 红色
        case .critical: return "\u{001B}[1;35m"  // 亮紫色
        }
    }

    /// NSColor 颜色（用于 macOS UI）
    ///
    /// 注意：NSColor 是主线程隔离的 AppKit 类型，但系统颜色（如 .systemGray）是静态常量，
    /// 访问它们是线程安全的。标记为 nonisolated 允许在非主线程上下文中安全获取颜色值。
    @MainActor
    var nsColor: NSColor {
        switch self {
        case .trace:    return .systemGray
        case .debug:    return .systemCyan
        case .info:     return .systemGreen
        case .warning:  return .systemOrange
        case .error:    return .systemRed
        case .critical: return .systemPurple
        }
    }

    // MARK: - Comparable

    nonisolated static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}
