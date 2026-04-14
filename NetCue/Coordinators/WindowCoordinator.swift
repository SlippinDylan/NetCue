//
//  WindowCoordinator.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/01/03.
//

import AppKit
import SwiftUI
import Observation

/// 窗口协调器 - 统一管理窗口状态
///
/// ## 架构设计（精简版）
/// - **单一职责**: 仅管理窗口状态（Tab 选择、Dock 图标）
/// - **不操作窗口**: 窗口的显示/隐藏由 MenuBarView 处理
/// - **@MainActor**: 所有操作在主线程，确保线程安全
/// - **Observable**: SwiftUI 可观察对象，状态自动触发刷新
///
/// ## 关键改进
/// - ✅ 移除通知机制（过度设计，引入时序问题）
/// - ✅ 移除 NSApp.windows 操作（违反职责单一原则）
/// - ✅ 纯状态管理（符合 SwiftUI 单向数据流）
///
/// ## 使用方式
/// ```swift
/// // 在 View 中使用
/// @Environment(WindowCoordinator.self) var windowCoordinator
///
/// // 在非 View 层使用（如 AppDelegate）
/// WindowCoordinator.shared.requestShow(tab: 0)
/// ```
@MainActor
@Observable
final class WindowCoordinator {
    // MARK: - Singleton

    /// 全局单例
    static let shared = WindowCoordinator()

    // MARK: - Published State

    /// 当前选中的 Tab 索引 (0-7)
    var selectedTab: Int = 0

    /// 是否请求显示窗口（触发标志，由 MenuBarView 监听）
    var shouldShowWindow: Bool = false

    /// 是否请求隐藏窗口（触发标志，由 MenuBarView 监听）
    var shouldHideWindow: Bool = false

    /// 待处理的显示请求（用于 MenuBarView 尚未挂载时的请求缓存）
    ///
    /// ## 设计说明
    /// 应用启动时，AppDelegate 可能在 MenuBarView 完成挂载前就调用 requestShow()。
    /// 此时 .onChange 监听器尚未生效，请求会丢失。
    /// 通过此标记，MenuBarView 在 .onAppear 时可以检查并执行待处理的请求。
    var hasPendingShowRequest: Bool = false

    /// 待处理请求的目标 Tab
    var pendingTab: Int = 0

    // MARK: - Initialization

    private init() {
        AppLogger.debug("WindowCoordinator 实例已创建")
    }

    /// 为 Preview 创建独立实例（避免使用 shared 单例）
    static func forPreview() -> WindowCoordinator {
        return WindowCoordinator()
    }

    // MARK: - Public Methods - State Management

    /// 请求显示主窗口并切换到指定 Tab
    ///
    /// - Parameter tab: Tab 索引 (0-7)
    ///
    /// ## 实现说明
    /// 1. 更新状态 (selectedTab, shouldShowWindow)
    /// 2. 设置待处理请求标记（确保 MenuBarView 挂载后能处理）
    /// 3. 显示 Dock 图标
    /// 4. 激活应用
    /// 5. MenuBarView 通过 @Environment 监听 shouldShowWindow 变化
    func requestShow(tab: Int) {
        guard tab >= 0 && tab <= 7 else {
            AppLogger.warning("尝试切换到无效的 Tab 索引: \(tab)")
            return
        }

        AppLogger.info("请求显示主窗口，切换到 Tab \(tab)")

        // 1. 更新状态
        selectedTab = tab
        shouldShowWindow = true

        // 2. 设置待处理请求（确保 MenuBarView.onAppear 时能处理）
        hasPendingShowRequest = true
        pendingTab = tab

        // 3. 激活应用
        NSApp.activate(ignoringOtherApps: true)

        AppLogger.debug("主窗口显示请求已设置: Tab=\(tab), hasPendingShowRequest=true")
    }

    /// 请求隐藏主窗口
    ///
    /// ## 实现说明
    /// 1. 更新状态 (shouldHideWindow)
    /// 2. 隐藏 Dock 图标
    /// 3. MenuBarView 通过 @Environment 监听 shouldHideWindow 变化
    func requestHide() {
        AppLogger.info("请求隐藏主窗口")

        // 1. 更新状态
        shouldHideWindow = true

        // 2. 隐藏 Dock 图标
        NSApp.setActivationPolicy(.accessory)

        AppLogger.debug("主窗口隐藏请求已设置")
    }

    /// 切换主窗口可见性
    ///
    /// ## 功能说明
    /// 根据窗口当前状态自动切换（需要 MenuBarView 提供当前状态）
    func toggle() {
        // 查找主窗口
        if let mainWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }),
           mainWindow.isVisible {
            requestHide()
        } else {
            requestShow(tab: selectedTab)
        }
    }

    /// 切换到指定 Tab（窗口已显示时）
    ///
    /// - Parameter tab: Tab 索引 (0-7)
    ///
    /// ## 功能说明
    /// 仅更新 selectedTab 状态，不改变窗口可见性
    func switchTab(_ tab: Int) {
        guard tab >= 0 && tab <= 7 else {
            AppLogger.warning("尝试切换到无效的 Tab 索引: \(tab)")
            return
        }

        AppLogger.info("切换到 Tab \(tab)")
        selectedTab = tab
    }

    /// 重置触发标志
    ///
    /// ## 功能说明
    /// MenuBarView 处理完窗口操作后调用，重置触发标志
    func resetFlags() {
        shouldShowWindow = false
        shouldHideWindow = false
        hasPendingShowRequest = false
    }
}
