//
//  NetCueApp.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/25.
//  Updated: 2026/01/27 - Certificate refresh
//

import SwiftUI

@main
struct NetCueApp: App {
    // MARK: - App Delegate

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - Shared Services

    /// 网络监控服务（应用级单例，注入到整个视图层级）
    ///
    /// ## 架构说明
    /// - 使用 @State 在 App 级别创建唯一实例
    /// - 通过 .environment() 注入到所有子视图
    /// - 生命周期由 SwiftUI 管理，应用退出时自动释放
    /// - 在 AppDelegate 中初始化和启动监控
    @State private var networkMonitor = NetworkMonitor()

    /// Mihomo 视图模型（应用级单例，确保切换 Tab 时状态不丢失）
    ///
    /// ## 架构说明
    /// - 使用 @State 在 App 级别创建唯一实例
    /// - 解决切换 Tab 后下载进度丢失的问题
    /// - 通过 .environment() 注入到 MihomoView
    @State private var mihomoViewModel = MihomoViewModel()

    /// 窗口协调器（应用级单例，管理窗口状态和操作）
    ///
    /// ## 架构说明
    /// - 使用 @State 包装单例，确保 SwiftUI 订阅其状态
    /// - 合并了原 AppCoordinator 和 WindowManager 的功能
    /// - 解决 P1-2 架构问题：消除职责重叠
    @State private var windowCoordinator = WindowCoordinator.shared

    // MARK: - Initialization

    init() {
        // 应用启动日志
        AppLogger.info("🚀 NetCue 应用已启动")
        AppLogger.debug("系统版本: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        AppLogger.debug("应用版本: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知")")
    }

    // MARK: - Scene

    var body: some Scene {
        // 菜单栏入口
        MenuBarExtra("NetCue", systemImage: "wifi.router") {
            MenuBarView()
                .environment(windowCoordinator)
                .task {
                    // ✅ 在 MenuBarView 加载时初始化监控
                    // MenuBarExtra 总是会在应用启动时创建，确保监控启动
                    await MainActor.run {
                        appDelegate.setNetworkMonitor(networkMonitor)
                    }
                }
        }

        // 主窗口
        WindowGroup(id: "main") {
            ContentView()
                .environment(networkMonitor)  // 注入网络监控器
                .environment(mihomoViewModel)  // 注入 Mihomo 视图模型
                .environment(windowCoordinator)  // 注入窗口协调器
                .navigationTitle("")
                .frame(minWidth: 960, minHeight: 696)
        }
        .defaultSize(width: 960, height: 696)
        .commandsRemoved()  // ✅ 移除 "File > New Window" 菜单（防止用户手动创建多窗口）
    }
}
