//
//  QuitConfirmationCoordinator.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/01/08.
//

import Foundation
import Observation

/// 退出确认协调器
///
/// ## 职责
/// - 管理"双击退出"的确认状态
/// - 控制确认提示的显示/隐藏
/// - 处理超时自动重置
///
/// ## 设计说明
/// - 使用 `@Observable` 宏实现响应式状态管理
/// - 使用 `Task` 实现非阻塞超时机制
/// - 线程安全：所有状态更新在 `@MainActor` 上执行
///
/// ## 使用方式
/// ```swift
/// // 在 App 级别创建并注入
/// @State private var quitCoordinator = QuitConfirmationCoordinator.shared
///
/// // 在视图中使用
/// @Environment(QuitConfirmationCoordinator.self) var quitCoordinator
/// ```
@MainActor
@Observable
final class QuitConfirmationCoordinator {

    // MARK: - Singleton

    /// 共享实例
    static let shared = QuitConfirmationCoordinator()

    // MARK: - Published State

    /// 是否显示确认提示
    var isShowingConfirmation: Bool = false

    /// 确认提示文字
    var confirmationMessage: String = "再按一次 ⌘Q 退出"

    // MARK: - Private Properties

    /// 确认超时时间（秒）
    private let confirmationTimeout: TimeInterval = 2.0

    /// 超时任务句柄（用于取消）
    private var timeoutTask: Task<Void, Never>?

    // MARK: - Initialization

    private init() {
        AppLogger.debug("QuitConfirmationCoordinator 已初始化")
    }

    // MARK: - Public Methods

    /// 请求退出
    ///
    /// ## 流程
    /// 1. 如果已显示确认提示 → 执行真正的退出
    /// 2. 如果未显示确认提示 → 显示提示，启动超时计时器
    ///
    /// - Returns: `true` 表示应该退出应用，`false` 表示仅显示提示
    func requestQuit() -> Bool {
        if isShowingConfirmation {
            // 第二次按下 → 真正退出
            AppLogger.info("用户确认退出（双击 Cmd+Q）")
            reset()
            return true
        } else {
            // 第一次按下 → 显示确认提示
            AppLogger.info("显示退出确认提示")
            showConfirmation()
            return false
        }
    }

    /// 重置状态（隐藏确认提示）
    func reset() {
        timeoutTask?.cancel()
        timeoutTask = nil
        isShowingConfirmation = false
    }

    // MARK: - Private Methods

    /// 显示确认提示并启动超时计时器
    private func showConfirmation() {
        // 取消之前的超时任务（如果有）
        timeoutTask?.cancel()

        // 显示提示
        isShowingConfirmation = true

        // 启动超时计时器
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(self?.confirmationTimeout ?? 2.0))
                // 超时后重置状态
                await MainActor.run {
                    self?.handleTimeout()
                }
            } catch {
                // Task 被取消，忽略
            }
        }
    }

    /// 处理超时
    private func handleTimeout() {
        guard isShowingConfirmation else { return }

        AppLogger.debug("退出确认超时，重置状态")
        isShowingConfirmation = false
        timeoutTask = nil
    }
}
