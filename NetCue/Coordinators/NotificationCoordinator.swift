//
//  NotificationCoordinator.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/31.
//

import Foundation
import UserNotifications

/// 通知标识符
///
/// 使用反向域名命名规范
/// 相同标识符的通知会自动替换旧通知，实现去重
enum NotificationID {
    static let sceneMatch = "studio.slippindylan.netcue.notification.scene-match"
    static let appManagement = "studio.slippindylan.netcue.notification.app-management"
    static let dnsChange = "studio.slippindylan.netcue.notification.dns-change"
}

/// 通知业务协调器
///
/// 职责：
/// - 提供业务级别的通知发送接口
/// - 封装通知文案生成逻辑
/// - 集成防抖机制
/// - 遵循 HIG 通知设计规范
///
/// 设计要点：
/// - @Observable 支持 SwiftUI 响应式
/// - @MainActor 确保线程安全
/// - 文案优化：>3个应用时简化显示
@MainActor
@Observable
final class NotificationCoordinator {
    // MARK: - Singleton

    /// 全局单例
    static let shared = NotificationCoordinator()

    // MARK: - Dependencies

    private let manager = NotificationManager.shared
    private let debouncer = NotificationDebouncer()

    // MARK: - Initialization

    private init() {
        AppLogger.debug("NotificationCoordinator 已初始化")
    }

    // MARK: - Public Methods

    /// 通知：场景匹配但无操作
    ///
    /// - Parameter sceneNames: 匹配的场景名称列表
    ///
    /// 使用场景：匹配到场景，但控制的应用均未运行
    func notifySceneMatchedNoAction(sceneNames: [String]) {
        guard !sceneNames.isEmpty else { return }

        debouncer.debounce(identifier: NotificationID.sceneMatch) { [weak self] in
            guard let self else { return }

            let names = sceneNames.joined(separator: "、")
            let title = "已匹配场景"
            let body = "当前网络匹配「\(names)」，控制的应用未在运行"

            AppLogger.info("发送场景匹配通知（无操作）: \(names)")
            await manager.sendNotification(
                identifier: NotificationID.sceneMatch,
                title: title,
                body: body,
                interruptionLevel: .active  // 普通优先级，有声音
            )
        }
    }

    /// 通知：场景切换成功
    ///
    /// - Parameters:
    ///   - quitApps: 已退出的应用列表
    ///   - launchApps: 已启动的应用列表
    ///
    /// 符合 HIG 规范：
    /// - 标题简洁：「场景切换成功」
    /// - 正文分行：退出应用、启动应用
    /// - 多应用时简化显示
    func notifySceneSwitchSuccess(quitApps: [String] = [], launchApps: [String] = []) {
        guard !quitApps.isEmpty || !launchApps.isEmpty else { return }

        debouncer.debounce(identifier: NotificationID.sceneMatch) { [weak self] in
            guard let self else { return }

            let title = "场景切换成功"
            var bodyParts: [String] = []

            if !quitApps.isEmpty {
                let appsText = formatAppList(quitApps)
                bodyParts.append("已退出 \(appsText)")
            }

            if !launchApps.isEmpty {
                let appsText = formatAppList(launchApps)
                bodyParts.append("已启动 \(appsText)")
            }

            let body = bodyParts.joined(separator: "\n")

            AppLogger.info("发送场景切换成功通知")
            await manager.sendNotification(
                identifier: NotificationID.sceneMatch,
                title: title,
                body: body,
                interruptionLevel: .active  // 普通优先级，有声音
            )
        }
    }

    /// 通知：场景切换失败
    ///
    /// - Parameters:
    ///   - quitFailed: 退出失败的应用列表
    ///   - launchFailed: 启动失败的应用列表
    ///   - successCount: 成功操作数量
    func notifySceneSwitchFailure(
        quitFailed: [String] = [],
        launchFailed: [String] = [],
        successCount: Int = 0
    ) {
        guard !quitFailed.isEmpty || !launchFailed.isEmpty else { return }

        debouncer.debounce(identifier: NotificationID.sceneMatch) { [weak self] in
            guard let self else { return }

            let totalFailed = quitFailed.count + launchFailed.count
            let title = successCount == 0 ? "场景切换失败" : "场景切换部分失败"
            var bodyParts: [String] = []

            if !quitFailed.isEmpty {
                let appsText = formatAppList(quitFailed)
                bodyParts.append("退出失败 \(appsText)")
            }

            if !launchFailed.isEmpty {
                let appsText = formatAppList(launchFailed)
                bodyParts.append("启动失败 \(appsText)")
            }

            if successCount > 0 {
                bodyParts.append("(\(successCount)个操作成功)")
            }

            let body = bodyParts.joined(separator: "\n")

            AppLogger.info("发送场景切换失败通知: \(totalFailed)个失败")
            await manager.sendNotification(
                identifier: NotificationID.sceneMatch,
                title: title,
                body: body,
                interruptionLevel: .timeSensitive  // 高优先级，可突破专注模式
            )
        }
    }

    /// 通知：启动应用
    ///
    /// - Parameter apps: 应用列表
    func notifyAppsLaunched(apps: [String]) {
        guard !apps.isEmpty else { return }

        debouncer.debounce(identifier: NotificationID.appManagement) { [weak self] in
            guard let self else { return }

            let title = "网络状态发生变化"
            let appsText = formatAppList(apps)
            let body = "已启动 \(appsText)"

            AppLogger.info("发送应用启动通知")
            await manager.sendNotification(
                identifier: NotificationID.appManagement,
                title: title,
                body: body
            )
        }
    }

    /// 通知：退出应用
    ///
    /// - Parameter apps: 应用列表
    func notifyAppsQuit(apps: [String]) {
        guard !apps.isEmpty else { return }

        debouncer.debounce(identifier: NotificationID.appManagement) { [weak self] in
            guard let self else { return }

            let title = "网络状态发生变化"
            let appsText = formatAppList(apps)
            let body = "已退出 \(appsText)"

            AppLogger.info("发送应用退出通知")
            await manager.sendNotification(
                identifier: NotificationID.appManagement,
                title: title,
                body: body
            )
        }
    }

    /// 通知：DNS 切换
    ///
    /// - Parameter server: DNS 服务器地址（可选）
    func notifyDNSChanged(server: String? = nil) {
        debouncer.debounce(identifier: NotificationID.dnsChange) { [weak self] in
            guard let self else { return }

            let title = "网络状态发生变化"
            let body = if let server = server, !server.isEmpty {
                "已切换至 DNS 服务器 \(server)"
            } else {
                "已切换 DNS 服务器"
            }

            AppLogger.info("发送 DNS 切换通知")
            await manager.sendNotification(
                identifier: NotificationID.dnsChange,
                title: title,
                body: body
            )
        }
    }

    /// 通知：恢复默认 DNS
    func notifyDNSRestored() {
        debouncer.debounce(identifier: NotificationID.dnsChange) { [weak self] in
            guard let self else { return }

            let title = "网络状态发生变化"
            let body = "已恢复默认的 DNS 服务器"

            AppLogger.info("发送 DNS 恢复通知")
            await manager.sendNotification(
                identifier: NotificationID.dnsChange,
                title: title,
                body: body
            )
        }
    }

    // MARK: - Private Methods

    /// 格式化应用列表
    ///
    /// - Parameter apps: 应用名称列表
    /// - Returns: 格式化后的字符串
    ///
    /// 规则：
    /// - ≤3个：完整显示，用顿号分隔
    /// - >3个：显示前2个 + "等N个应用"
    ///
    /// 示例：
    /// - ["微信"] → "微信"
    /// - ["微信", "钉钉"] → "微信、钉钉"
    /// - ["微信", "钉钉", "Slack"] → "微信、钉钉、Slack"
    /// - ["微信", "钉钉", "Slack", "企业微信", "飞书"] → "微信、钉钉 等5个应用"
    private func formatAppList(_ apps: [String]) -> String {
        guard !apps.isEmpty else { return "" }

        if apps.count <= 3 {
            return apps.joined(separator: "、")
        } else {
            let first = apps.prefix(2).joined(separator: "、")
            return "\(first) 等\(apps.count)个应用"
        }
    }
}
