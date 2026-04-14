//
//  AppControlService.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/01/04.
//

import Foundation
import AppKit

/// 应用控制服务
///
/// ## 职责
/// - 启动应用（通过应用名称或 Bundle ID）
/// - 退出应用（优雅退出 + 强制退出）
/// - 检查应用运行状态
///
/// ## 设计说明
/// - **无状态服务**：所有方法都是纯函数，无副作用
/// - **依赖权限**：退出应用需要辅助功能权限
/// - **异步等待**：启动应用使用 Swift Concurrency 等待回调（最多5秒）
/// - **结构化结果**：返回 `AppControlResult`（成功/失败 + 原因）
///
/// ## 使用方式
/// ```swift
/// let service = AppControlService()
/// let result = await service.launch("ClashX.Meta")
/// if result.success {
///     print("启动成功")
/// } else {
///     print("启动失败: \(result.message ?? "未知错误")")
/// }
/// ```
@MainActor
final class AppControlService {
    // MARK: - Result Structure

    /// 应用控制结果
    struct AppControlResult {
        /// 是否成功
        let success: Bool
        /// 失败原因或状态描述
        let message: String?
    }

    // MARK: - Dependencies

    private let permissionManager: PermissionManager?

    // MARK: - Initialization

    /// 初始化应用控制服务
    ///
    /// - Parameter permissionManager: 权限管理器（可选，Preview 环境传入 nil）
    nonisolated init(permissionManager: PermissionManager?) {
        self.permissionManager = permissionManager
    }

    // MARK: - Public Methods - App Launch

    /// 启动应用
    ///
    /// ## 实现说明
    /// - 检查应用是否已经在运行（通过名称或 Bundle ID 匹配）
    /// - 如果已运行 → 返回成功（幂等性）
    /// - 如果未运行 → 查找应用路径并启动
    /// - 使用 Swift Concurrency 等待启动结果（最多 5 秒）
    ///
    /// ## 查找策略（按优先级）
    /// 1. 通过 Bundle ID 查找（如 "com.west2online.ClashX.Meta"）
    /// 2. 通过 "com.apple.<appName>" 查找（系统应用）
    /// 3. 通过应用名称在 /Applications 目录查找
    /// 4. 通过应用名称在 ~/Applications 目录查找
    ///
    /// ## 错误处理
    /// - 找不到应用 → 返回失败 + "找不到应用"
    /// - 启动超时 → 返回失败 + 错误信息
    /// - 已在运行 → 返回成功 + "已在运行"
    ///
    /// - Parameter appName: 应用名称或 Bundle ID
    /// - Returns: 控制结果（成功/失败 + 原因）
    func launch(_ appName: String) async -> AppControlResult {
        let runningApps = NSWorkspace.shared.runningApplications

        // 检查应用是否已经在运行
        let isRunning = runningApps.contains { app in
            app.localizedName == appName || app.bundleIdentifier?.contains(appName) == true
        }

        // 如果没有运行，则启动应用
        if !isRunning {
            // 尝试查找应用路径
            if let appURL = findApplicationURL(appName) {
                AppLogger.debug("找到应用路径: \(appURL.path)")
                return await withTaskGroup(of: AppControlResult.self) { group in
                    group.addTask { @MainActor in
                        await self.openApplication(at: appURL, appName: appName)
                    }

                    group.addTask {
                        try? await Task.sleep(for: .seconds(5))
                        return AppControlResult(success: false, message: "启动超时")
                    }

                    let result = await group.next() ?? AppControlResult(success: false, message: "启动失败")
                    group.cancelAll()
                    return result
                }
            } else {
                let message = "找不到应用"
                AppLogger.warning("找不到应用: \(appName)")
                return AppControlResult(success: false, message: message)
            }
        } else {
            AppLogger.debug("应用 \(appName) 已在运行，跳过启动")
            // 应用已运行也视为成功（目标已达成）
            return AppControlResult(success: true, message: "已在运行")
        }
    }

    // MARK: - Private Methods

    /// 查找应用 URL
    ///
    /// ## 查找策略（按优先级）
    /// 1. 通过 Bundle ID 查找
    /// 2. 通过 "com.apple.<appName>" 查找（系统应用）
    /// 3. 在 /Applications 目录查找 <appName>.app
    /// 4. 在 ~/Applications 目录查找 <appName>.app
    ///
    /// - Parameter appName: 应用名称或 Bundle ID
    /// - Returns: 应用 URL，找不到返回 nil
    private func findApplicationURL(_ appName: String) -> URL? {
        let workspace = NSWorkspace.shared

        // 1. 通过 Bundle ID 查找
        if let url = workspace.urlForApplication(withBundleIdentifier: appName) {
            return url
        }

        // 2. 通过 "com.apple.<appName>" 查找（系统应用）
        if let url = workspace.urlForApplication(withBundleIdentifier: "com.apple.\(appName)") {
            return url
        }

        // 3. 在 /Applications 目录查找
        let systemAppsPath = "/Applications/\(appName).app"
        if FileManager.default.fileExists(atPath: systemAppsPath) {
            return URL(fileURLWithPath: systemAppsPath)
        }

        // 4. 在 ~/Applications 目录查找
        let userAppsPath = NSHomeDirectory() + "/Applications/\(appName).app"
        if FileManager.default.fileExists(atPath: userAppsPath) {
            return URL(fileURLWithPath: userAppsPath)
        }

        return nil
    }

    /// 使用 async/await 包装 `NSWorkspace.openApplication` 回调
    private func openApplication(at appURL: URL, appName: String) async -> AppControlResult {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(
                at: appURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, error in
                if let error = error {
                    AppLogger.error("启动应用失败: \(appName)", error: error)
                    continuation.resume(returning: AppControlResult(
                        success: false,
                        message: error.localizedDescription
                    ))
                } else {
                    AppLogger.info("✅ 成功启动应用: \(appName)")
                    continuation.resume(returning: AppControlResult(success: true, message: nil))
                }
            }
        }
    }

    // MARK: - Public Methods - App Quit

    /// 退出应用
    ///
    /// ## 实现说明
    /// - 检查辅助功能权限（必需）
    /// - 查找运行中的应用（通过名称或 Bundle ID 匹配）
    /// - 如果未运行 → 返回成功（幂等性）
    /// - 如果在运行 → 优雅退出（`terminate()`）
    ///
    /// ## 权限要求
    /// - 必须有辅助功能权限，否则返回失败
    ///
    /// ## 错误处理
    /// - 缺少权限 → 返回失败 + "缺少辅助功能权限"
    /// - 应用未运行 → 返回成功 + "应用未运行"
    /// - 退出失败 → 返回失败 + "terminate()返回false"
    ///
    /// - Parameter appName: 应用名称或 Bundle ID
    /// - Returns: 控制结果（成功/失败 + 原因）
    func quit(_ appName: String) -> AppControlResult {
        // 检查是否有辅助功能权限（Preview 环境中跳过权限检查）
        if let manager = permissionManager {
            guard manager.checkAccessibility() else {
                let message = "缺少辅助功能权限"
                AppLogger.warning("无法退出应用 \(appName)：\(message)")
                return AppControlResult(success: false, message: message)
            }
        }

        let runningApps = NSWorkspace.shared.runningApplications

        for app in runningApps {
            // 通过应用名称或 Bundle Identifier 匹配
            if app.localizedName == appName || app.bundleIdentifier?.contains(appName) == true {
                AppLogger.info("正在退出应用: \(appName)")
                // 优雅退出，会自动处理所有子进程和 Helper 进程
                let success = app.terminate()
                if !success {
                    let message = "terminate()返回false"
                    AppLogger.warning("退出应用失败: \(appName) - \(message)")
                    return AppControlResult(success: false, message: message)
                } else {
                    return AppControlResult(success: true, message: nil)
                }
            }
        }

        // 循环结束未找到应用，说明应用未运行
        let message = "应用未运行"
        AppLogger.debug("应用 \(appName) 未在运行")
        // 应用未运行也视为成功（目标已达成）
        return AppControlResult(success: true, message: message)
    }

    // MARK: - Public Methods - App Status

    /// 检查应用是否正在运行
    ///
    /// ## 实现说明
    /// - 遍历所有运行中的应用
    /// - 通过名称或 Bundle ID 匹配
    ///
    /// - Parameter appName: 应用名称或 Bundle ID
    /// - Returns: true 表示正在运行，false 表示未运行
    func isRunning(_ appName: String) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { app in
            app.localizedName == appName || app.bundleIdentifier?.contains(appName) == true
        }
    }
}
