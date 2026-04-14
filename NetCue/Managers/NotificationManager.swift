//
//  NotificationManager.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/31.
//

import Foundation
import UserNotifications
import AppKit

/// 通知管理器
///
/// 职责：
/// - 封装 UNUserNotificationCenter API
/// - 处理通知权限请求
/// - 提供统一的通知发送接口
/// - 管理通知的添加和移除
///
/// 设计要点：
/// - 使用 async/await 符合 Swift 6 最佳实践
/// - @MainActor 确保 UI 操作线程安全
/// - 实现 UNUserNotificationCenterDelegate 处理前台通知
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    // MARK: - Singleton

    /// 全局单例
    static let shared = NotificationManager()

    // MARK: - Properties

    /// 通知中心
    private let center = UNUserNotificationCenter.current()

    /// 当前授权状态
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Initialization

    private override init() {
        super.init()
        AppLogger.debug("NotificationManager 已初始化")
    }

    // MARK: - Setup

    /// 配置通知中心（应在 AppDelegate 中调用）
    func configure() {
        center.delegate = self
        AppLogger.info("通知中心 Delegate 已设置")

        // 获取当前授权状态
        Task {
            await updateAuthorizationStatus()
        }
    }

    // MARK: - Authorization

    /// 请求通知权限
    ///
    /// - Returns: 是否授权成功
    ///
    /// 符合 Swift 6 最佳实践：使用 async/await
    func requestAuthorization() async -> Bool {
        AppLogger.info("请求通知权限")

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])

            if granted {
                AppLogger.info("✅ 通知权限已授予")
                authorizationStatus = .authorized
            } else {
                AppLogger.warning("❌ 用户拒绝了通知权限")
                authorizationStatus = .denied
            }

            return granted
        } catch {
            AppLogger.error("请求通知权限失败", error: error)
            return false
        }
    }

    /// 更新授权状态
    private func updateAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        let statusText = switch authorizationStatus {
        case .notDetermined: "未确定"
        case .denied: "已拒绝"
        case .authorized: "已授权"
        case .provisional: "临时授权"
        case .ephemeral: "临时（应用片段）"
        @unknown default: "未知"
        }

        AppLogger.debug("通知授权状态: \(statusText)")
    }

    /// 检查是否已授权
    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    /// 打开系统通知设置
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
            AppLogger.info("打开系统通知设置")
        }
    }

    // MARK: - Send Notification

    /// 发送本地通知
    ///
    /// - Parameters:
    ///   - identifier: 通知标识符（相同标识符会替换旧通知）
    ///   - title: 标题
    ///   - body: 正文
    ///   - interruptionLevel: 中断级别
    ///
    /// 符合 HIG 规范：
    /// - 标题简洁明了
    /// - 正文不超过 2 行
    /// - 使用适当的中断级别
    func sendNotification(
        identifier: String,
        title: String,
        body: String,
        interruptionLevel: UNNotificationInterruptionLevel = .active
    ) async {
        // 检查授权状态
        guard isAuthorized else {
            AppLogger.warning("通知未授权，无法发送: \(title)")
            return
        }

        AppLogger.info("发送通知: \(title)")

        // 创建通知内容
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = interruptionLevel

        // 创建通知请求（立即触发）
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil  // nil = 立即显示
        )

        do {
            try await center.add(request)
            AppLogger.debug("通知已添加到队列: \(identifier)")
        } catch {
            AppLogger.error("发送通知失败", error: error)
        }
    }

    // MARK: - Remove Notification

    /// 移除待发送的通知
    ///
    /// - Parameter identifier: 通知标识符
    func removeNotification(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        AppLogger.debug("已移除待发送通知: \(identifier)")
    }

    /// 移除所有待发送的通知
    func removeAllNotifications() {
        center.removeAllPendingNotificationRequests()
        AppLogger.info("已移除所有待发送通知")
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// 应用在前台时如何显示通知
    ///
    /// 返回 [.banner, .sound, .list] 确保前台也能看到通知并保留在通知中心
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // 前台显示横幅、声音和列表
        return [.banner, .sound, .list]
    }

    /// 用户点击通知后的响应
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier

        await MainActor.run {
            AppLogger.info("用户点击了通知: \(identifier)")
        }

        // 可以在这里根据 identifier 执行特定操作
        // 例如：打开主窗口并切换到对应 Tab
    }
}
