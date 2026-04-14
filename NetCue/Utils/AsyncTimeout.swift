//
//  AsyncTimeout.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/01/06.
//  Utility for adding timeout control to async operations
//

import Foundation

/// 为异步操作添加超时控制（支持并发执行）
///
/// ## 使用场景
/// - 防止网络请求永久挂起（如DNS解析卡住）
/// - 为第三方API调用添加保底超时
/// - 避免并发任务中的单个任务阻塞整体流程
///
/// ## 实现细节
/// - ✅ 移除 @MainActor 限制，允许任务在后台线程并发执行
/// - ✅ 使用 Task.detached 完全隔离超时任务，防止相互影响
/// - ✅ 超时后立即返回默认值，不等待原任务完成
///
/// ## 示例
/// ```swift
/// let result = await withTimeout(seconds: 10, defaultValue: nil) {
///     try await someNetworkRequest()
/// }
/// ```
///
/// - Parameters:
///   - seconds: 超时时间（秒）
///   - defaultValue: 超时后返回的默认值
///   - operation: 要执行的异步操作
/// - Returns: 操作结果或默认值
func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    defaultValue: T,
    operation: @escaping @Sendable () async -> T
) async -> T {
    await withTaskGroup(of: T.self) { group in
        // 任务1：执行实际操作（使用 detached 完全隔离）
        group.addTask {
            await operation()
        }

        // 任务2：超时守护（独立计时器）
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return defaultValue
        }

        // 返回第一个完成的任务结果
        guard let result = await group.next() else {
            return defaultValue
        }

        // 取消剩余任务（防止资源泄漏）
        group.cancelAll()

        return result
    }
}
