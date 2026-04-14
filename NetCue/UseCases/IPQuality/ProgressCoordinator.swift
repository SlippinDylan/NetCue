//
//  ProgressCoordinator.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/31.
//  Refactored from IPQualityViewModel.swift - Progress management logic
//

import Foundation
import SwiftUI
import Observation

/// 进度协调器 - 负责平滑进度更新和任务状态管理
///
/// ## 架构说明
/// - 使用 SwiftUI 原生动画系统（`withAnimation`）实现进度平滑过渡
/// - 避免手动实现帧动画（Task.sleep）导致的CPU浪费和复杂性
/// - 符合 Swift 6+ 并发最佳实践
@MainActor
@Observable
final class ProgressCoordinator {
    // MARK: - Published Properties

    /// 当前进度值 (0.0-1.0)
    ///
    /// 通过 `withAnimation` 修改此属性，SwiftUI 会自动处理动画插值
    var progress: Double = 0.0

    /// 当前任务描述
    var currentTask: String = ""

    // MARK: - Public Methods

    /// 平滑更新进度到目标值（异步版本，不阻塞主线程）
    ///
    /// - Parameters:
    ///   - target: 目标进度值 (0.0-1.0)
    ///   - duration: 动画时长（秒），默认 0.3 秒
    ///   - curve: 动画曲线，默认使用 easeInOut
    ///
    /// ## 实现说明
    /// - 使用 Task.detached 将动画调度到下一个 RunLoop 周期
    /// - 避免在 async 上下文中同步调用 withAnimation 导致的死锁
    /// - 确保动画在主线程的下一帧执行
    ///
    /// ## 性能优势
    /// - ✅ 零死锁风险（异步调度）
    /// - ✅ GPU 加速动画
    /// - ✅ 自动适配屏幕刷新率（60Hz/120Hz）
    func smoothUpdateProgress(
        to target: Double,
        duration: TimeInterval = 0.3,
        curve: Animation = .easeInOut
    ) {
        // 边界检查：确保进度值在合法范围内
        let clampedTarget = min(max(target, 0.0), 1.0)

        // ✅ 使用 Task 异步调度，避免阻塞当前线程
        Task { @MainActor in
            withAnimation(curve.speed(1.0 / duration)) {
                progress = clampedTarget
            }
        }
    }

    /// 重置进度和任务状态
    ///
    /// 不使用动画，立即重置到初始状态
    func reset() {
        progress = 0.0
        currentTask = ""
    }

    /// 更新当前任务描述
    ///
    /// - Parameter task: 任务描述文本
    func updateTask(_ task: String) {
        currentTask = task
    }
}
