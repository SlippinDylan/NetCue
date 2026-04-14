//
//  NotificationDebouncer.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/31.
//

import Foundation

/// 通知防抖器
///
/// 职责：
/// - 防止短时间内重复发送相同类型的通知
/// - 延迟执行通知发送，如果在延迟期间再次触发，则取消旧任务
///
/// 使用场景：
/// - 网络频繁变化时，避免通知轰炸
/// - 多次场景匹配，只发送最后一次的通知
///
/// 技术实现：
/// - 使用 Swift 6 的 Task 和 Duration
/// - @MainActor 确保线程安全
@MainActor
final class NotificationDebouncer {
    // MARK: - Properties

    /// 存储每个标识符对应的任务
    private var tasks: [String: Task<Void, Never>] = [:]

    // MARK: - Initialization

    init() {
        AppLogger.debug("NotificationDebouncer 已初始化")
    }

    // MARK: - Public Methods

    /// 防抖执行
    ///
    /// - Parameters:
    ///   - identifier: 唯一标识符，相同标识符的任务会互相取消
    ///   - delay: 延迟时间，默认 2 秒
    ///   - action: 延迟后执行的操作
    ///
    /// 工作原理：
    /// 1. 如果已有相同 identifier 的任务，取消它
    /// 2. 创建新任务，延迟 delay 秒后执行 action
    /// 3. 如果在延迟期间再次调用，旧任务被取消，只执行最新的
    func debounce(
        identifier: String,
        delay: Duration = .seconds(2),
        action: @escaping @MainActor () async -> Void
    ) {
        // 取消旧任务
        if let existingTask = tasks[identifier] {
            existingTask.cancel()
            AppLogger.debug("取消旧的防抖任务: \(identifier)")
        }

        // 创建新任务
        let task = Task {
            do {
                try await Task.sleep(for: delay)

                // 如果任务未被取消，执行操作
                if !Task.isCancelled {
                    AppLogger.debug("执行防抖任务: \(identifier)")
                    await action()
                }
            } catch {
                // Task.sleep 被取消会抛出 CancellationError
                AppLogger.debug("防抖任务被取消: \(identifier)")
            }

            // 任务完成后从字典中移除
            tasks[identifier] = nil
        }

        // 存储任务
        tasks[identifier] = task
        AppLogger.debug("创建新的防抖任务: \(identifier)，延迟 \(delay.components.seconds) 秒")
    }

    /// 取消指定标识符的任务
    ///
    /// - Parameter identifier: 任务标识符
    func cancel(identifier: String) {
        if let task = tasks[identifier] {
            task.cancel()
            tasks[identifier] = nil
            AppLogger.debug("手动取消防抖任务: \(identifier)")
        }
    }

    /// 取消所有任务
    func cancelAll() {
        AppLogger.info("取消所有防抖任务，共 \(tasks.count) 个")

        for (_, task) in tasks {
            task.cancel()
        }

        tasks.removeAll()
    }

    // MARK: - Cleanup

    deinit {
        // 清理时取消所有任务
        for (_, task) in tasks {
            task.cancel()
        }
    }
}
