//
//  AppDelegate.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/31.
//

import AppKit

/// 应用生命周期委托
///
/// 职责：
/// - 拦截窗口关闭事件，防止应用退出
/// - 检测应用启动方式（手动启动 vs 开机自启动）
/// - 管理应用生命周期回调
/// - **初始化网络监控服务**（应用启动时立即开始监控）
///
/// 关键实现：
/// - applicationShouldTerminateAfterLastWindowClosed 返回 false
///   确保关闭窗口时应用不退出，只隐藏窗口
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties

    /// 网络监控服务（从 NetCueApp 传递）
    private var networkMonitor: NetworkMonitor?

    // MARK: - Public Methods

    /// 设置网络监控服务
    ///
    /// - Parameter monitor: NetworkMonitor 实例
    ///
    /// ## 设计说明
    /// 由于 @NSApplicationDelegateAdaptor 在 @StateObject 之前创建，
    /// 需要通过此方法将 NetworkMonitor 实例传递给 AppDelegate。
    ///
    /// ## 防御性设计
    /// - 可以安全地多次调用（幂等性）
    /// - 只在首次调用时启动监控
    func setNetworkMonitor(_ monitor: NetworkMonitor) {
        // 防止重复初始化
        guard self.networkMonitor == nil else {
            AppLogger.debug("NetworkMonitor 已设置，跳过重复初始化")
            return
        }

        self.networkMonitor = monitor

        // 立即启动监控（确保在应用启动时就开始监控）
        Task { @MainActor in
            let scenes = SceneStorage.loadScenes()
            let dnsScenes = DNSSceneStorage.shared.loadScenes()

            AppLogger.info("从存储加载场景: 网络场景=\(scenes.count), DNS场景=\(dnsScenes.count)")

            monitor.startMonitoring(scenes: scenes, dnsScenes: dnsScenes)
        }
    }

    // MARK: - Application Lifecycle

    /// 应用启动完成
    ///
    /// - Parameter notification: 启动通知
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.info("应用启动完成")

        // 必须在主线程同步配置，确保代理提早设置完毕
        NotificationManager.shared.configure()

        Task { @MainActor in
            // 请求通知权限
            let granted = await NotificationManager.shared.requestAuthorization()
            if granted {
                AppLogger.info("通知权限请求成功")
            } else {
                AppLogger.warning("通知权限请求被拒绝")
            }
        }

        // 检测是否为开机自启动
        if wasLaunchedAsLoginItem() {
            AppLogger.info("应用通过开机自启动启动，不显示主窗口")
            // ✅ 开机自启动 → 不显示窗口
            WindowCoordinator.shared.requestHide()
        } else {
            AppLogger.info("应用手动启动，请求显示主窗口")
            // ✅ 手动启动 → 立即请求显示窗口
            // 窗口协调器会设置 hasPendingShowRequest 标记
            // MenuBarView.onAppear 时会检查并执行此请求
            // 无需延迟，因为请求会被缓存直到 MenuBarView 准备好
            WindowCoordinator.shared.requestShow(tab: 0)
        }
    }

    /// 最后一个窗口关闭时是否退出应用
    ///
    /// - Parameter sender: NSApplication 实例
    /// - Returns: false - 不退出应用，只隐藏窗口
    ///
    /// 这是核心逻辑：关闭窗口时，应用继续在菜单栏运行
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        AppLogger.info("最后一个窗口已关闭，隐藏窗口但不退出应用")
        // ✅ 使用 WindowCoordinator 请求隐藏窗口
        WindowCoordinator.shared.requestHide()
        return false
    }

    /// 应用即将退出
    ///
    /// - Parameter notification: 退出通知
    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.info("应用即将退出")
    }

    /// 拦截应用退出请求（实现双击 Cmd+Q 退出）
    ///
    /// - Parameter sender: NSApplication 实例
    /// - Returns: 退出响应类型
    ///
    /// 技术实现：
    /// - 第一次按 Cmd+Q：显示确认提示，返回 .terminateCancel 阻止退出
    /// - 第二次按 Cmd+Q（2秒内）：返回 .terminateNow 允许退出
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let shouldQuit = QuitConfirmationCoordinator.shared.requestQuit()
        if shouldQuit {
            AppLogger.info("用户确认退出应用（双击 Cmd+Q）")
            return .terminateNow
        } else {
            AppLogger.debug("等待用户确认退出（再按一次 Cmd+Q）")
            return .terminateCancel
        }
    }

    // MARK: - Private Methods

    /// 检测应用是否通过开机自启动启动
    ///
    /// - Returns: true 表示开机自启动，false 表示手动启动
    ///
    /// 技术实现：
    /// - 通过 Apple Event 检测启动来源
    /// - kAEOpenApplication + keyAELaunchedAsLogInItem 表示开机自启动
    private func wasLaunchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            return false
        }

        let isLoginItem = event.eventID == kAEOpenApplication &&
                         event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem

        return isLoginItem
    }
}
