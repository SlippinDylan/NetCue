//
//  ToastManager.swift
//  NetCue
//
//  Created by Claude on 2026/01/09.
//
//  ## 设计说明
//  - 全局 Toast 通知管理器
//  - 支持成功/错误/信息三种类型
//  - 自动消失机制（可配置时长）
//  - 队列机制确保多个 Toast 按序显示
//
//  ## 架构参考
//  - 复用 QuitConfirmationCoordinator 的设计模式
//  - 使用 @Observable 实现响应式状态管理
//

import Foundation
import SwiftUI

// MARK: - Toast Type

/// Toast 类型枚举
///
/// 定义不同类型的 Toast 及其视觉样式
enum ToastType: Equatable {
    case success
    case error
    case info

    /// 图标名称
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    /// 图标颜色
    var color: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        }
    }
}

// MARK: - Toast Item

/// Toast 数据模型
///
/// 表示单个 Toast 通知的完整信息
struct ToastItem: Identifiable, Equatable {
    let id: UUID
    let message: String
    let type: ToastType
    let duration: TimeInterval

    init(
        message: String,
        type: ToastType,
        duration: TimeInterval = 3.0
    ) {
        self.id = UUID()
        self.message = message
        self.type = type
        self.duration = duration
    }
}

// MARK: - Toast Manager

/// 全局 Toast 管理器
///
/// ## 职责
/// - 管理 Toast 的显示/隐藏状态
/// - 处理 Toast 队列（FIFO）
/// - 控制自动消失计时
///
/// ## 设计说明
/// - 使用 `@Observable` 宏实现响应式状态管理
/// - 使用 `Task` 实现非阻塞超时机制
/// - 线程安全：所有状态更新在 `@MainActor` 上执行
///
/// ## 使用方式
/// ```swift
/// // 显示成功 Toast
/// ToastManager.shared.show("操作成功", type: .success)
///
/// // 显示错误 Toast（自定义时长）
/// ToastManager.shared.show("操作失败", type: .error, duration: 5.0)
///
/// // 便捷方法
/// Toast.success("内核替换成功")
/// Toast.error("操作失败")
/// ```
@MainActor
@Observable
final class ToastManager {

    // MARK: - Singleton

    /// 共享实例
    static let shared = ToastManager()

    // MARK: - Published State

    /// 当前显示的 Toast（nil 表示无 Toast）
    var currentToast: ToastItem?

    /// 是否正在显示 Toast
    var isShowing: Bool {
        currentToast != nil
    }

    // MARK: - Private Properties

    /// 待显示的 Toast 队列
    private var queue: [ToastItem] = []

    /// 自动消失任务句柄
    private var dismissTask: Task<Void, Never>?

    /// 是否正在处理过渡动画
    private var isTransitioning: Bool = false

    // MARK: - Initialization

    private init() {
        AppLogger.debug("ToastManager 已初始化")
    }

    // MARK: - Public Methods

    /// 显示 Toast
    ///
    /// - Parameters:
    ///   - message: 显示的消息文本
    ///   - type: Toast 类型（success/error/info）
    ///   - duration: 显示时长（秒），默认 3 秒
    ///
    /// ## 行为说明
    /// - 如果当前有 Toast 显示，新 Toast 会加入队列
    /// - 队列按 FIFO 顺序处理
    /// - 每个 Toast 显示指定时长后自动消失
    func show(_ message: String, type: ToastType, duration: TimeInterval = 3.0) {
        let toast = ToastItem(message: message, type: type, duration: duration)

        AppLogger.info("📢 Toast 请求: [\(type)] \(message)")

        if currentToast == nil && !isTransitioning {
            // 没有正在显示的 Toast，直接显示
            present(toast)
        } else {
            // 加入队列等待
            queue.append(toast)
            AppLogger.debug("Toast 加入队列，当前队列长度: \(queue.count)")
        }
    }

    /// 立即关闭当前 Toast
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil

        guard currentToast != nil else { return }

        AppLogger.debug("Toast 关闭")

        isTransitioning = true
        currentToast = nil

        // 延迟处理下一个 Toast（等待退出动画完成）
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            isTransitioning = false
            processQueue()
        }
    }

    /// 清空所有待显示的 Toast
    func clearQueue() {
        queue.removeAll()
        AppLogger.debug("Toast 队列已清空")
    }

    // MARK: - Private Methods

    /// 显示指定的 Toast
    private func present(_ toast: ToastItem) {
        currentToast = toast

        AppLogger.debug("Toast 显示: \(toast.message)，时长: \(toast.duration)秒")

        // 启动自动消失计时器
        dismissTask?.cancel()
        dismissTask = Task { [weak self, duration = toast.duration] in
            do {
                try await Task.sleep(for: .seconds(duration))
                self?.dismiss()
            } catch {
                // Task 被取消，忽略
            }
        }
    }

    /// 处理队列中的下一个 Toast
    private func processQueue() {
        guard !queue.isEmpty, currentToast == nil, !isTransitioning else {
            return
        }

        let next = queue.removeFirst()
        AppLogger.debug("处理队列中的 Toast，剩余: \(queue.count)")
        present(next)
    }
}

// MARK: - Convenience API

/// Toast 便捷 API
///
/// 提供简洁的静态方法，无需直接访问 ToastManager
///
/// ## 使用示例
/// ```swift
/// Toast.success("保存成功")
/// Toast.error("操作失败")
/// Toast.info("正在处理...")
/// ```
enum Toast {

    /// 显示成功 Toast
    ///
    /// - Parameters:
    ///   - message: 消息文本
    ///   - duration: 显示时长（默认 3 秒）
    @MainActor
    static func success(_ message: String, duration: TimeInterval = 3.0) {
        ToastManager.shared.show(message, type: .success, duration: duration)
    }

    /// 显示错误 Toast
    ///
    /// - Parameters:
    ///   - message: 消息文本
    ///   - duration: 显示时长（默认 4 秒，错误信息需要更长阅读时间）
    @MainActor
    static func error(_ message: String, duration: TimeInterval = 4.0) {
        ToastManager.shared.show(message, type: .error, duration: duration)
    }

    /// 显示信息 Toast
    ///
    /// - Parameters:
    ///   - message: 消息文本
    ///   - duration: 显示时长（默认 3 秒）
    @MainActor
    static func info(_ message: String, duration: TimeInterval = 3.0) {
        ToastManager.shared.show(message, type: .info, duration: duration)
    }
}
