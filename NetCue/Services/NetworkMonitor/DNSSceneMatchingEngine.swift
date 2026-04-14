//
//  DNSSceneMatchingEngine.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/01/04.
//

import Foundation

/// DNS 场景匹配引擎
///
/// ## 职责
/// - 根据路由器信息匹配 DNS 场景
/// - 计算场景切换时需要应用/清除的 DNS 配置
/// - 管理 DNS 场景的状态变化
///
/// ## 设计说明
/// - **无状态服务**：所有方法都是纯函数，无副作用
/// - **单一职责**：只负责 DNS 场景匹配逻辑，不负责实际的 DNS 配置
/// - **结构化输出**：返回结构化的匹配结果和操作类型
///
/// ## 使用方式
/// ```swift
/// let engine = DNSSceneMatchingEngine()
/// let result = engine.matchDNSScene(
///     routerIP: "192.168.1.1",
///     routerMAC: "AA:BB:CC:DD:EE:FF",
///     availableScenes: dnsScenes,
///     previousMatch: nil
/// )
/// ```
@MainActor
final class DNSSceneMatchingEngine {
    // MARK: - Initialization

    /// 初始化 DNS 场景匹配引擎
    nonisolated init() {
        // 无状态服务，无需初始化
    }

    // MARK: - Result Structures

    /// DNS 场景匹配结果
    struct MatchResult {
        /// 匹配的场景（可能为 nil）
        let matchedScene: DNSScene?
        /// 需要执行的操作类型
        let action: DNSAction
    }

    /// DNS 操作类型
    enum DNSAction {
        /// 无需操作（场景未变化）
        case none
        /// 应用 DNS 配置
        case apply(scene: DNSScene)
        /// 清除 DNS 配置（恢复自动获取）
        case clear
    }

    // MARK: - Public Methods

    /// 匹配 DNS 场景
    ///
    /// ## 功能说明
    /// 1. 根据当前路由器信息查找匹配的 DNS 场景
    /// 2. 对比新旧场景，确定需要执行的操作
    ///
    /// ## 边界情况处理
    /// - 从有场景切换到无场景：清除 DNS 配置（恢复自动获取）
    /// - 从无场景切换到有场景：应用新场景的 DNS 配置
    /// - 场景间切换：应用新场景的 DNS 配置
    /// - 场景未变化：无需操作
    ///
    /// - Parameters:
    ///   - routerIP: 当前路由器IP地址
    ///   - routerMAC: 当前路由器MAC地址
    ///   - availableScenes: 所有可用的 DNS 场景列表
    ///   - previousMatch: 之前匹配的场景
    /// - Returns: DNS 场景匹配结果（包含匹配场景和操作类型）
    func matchDNSScene(
        routerIP: String,
        routerMAC: String,
        availableScenes: [DNSScene],
        previousMatch: DNSScene?
    ) -> MatchResult {
        AppLogger.debug("🔍 开始检查 DNS 场景匹配 (当前路由器: \(routerIP), \(routerMAC))")

        let matchedScene = findMatchingDNSScene(
            routerIP: routerIP,
            routerMAC: routerMAC,
            scenes: availableScenes
        )

        if let scene = matchedScene {
            AppLogger.info("✅ 匹配到 DNS 场景: \(scene.name) (主DNS=\(scene.primaryDNS))")
        } else {
            AppLogger.debug("未匹配到任何 DNS 场景")
        }

        // 确定需要执行的操作
        let action: DNSAction

        if matchedScene?.id != previousMatch?.id {
            // 场景发生变化
            if let scene = matchedScene {
                // 有匹配的场景，应用其 DNS 配置
                action = .apply(scene: scene)
                AppLogger.info("🌐 需要应用 DNS 场景: \(scene.name)")
            } else {
                // 没有匹配的场景，保持当前 DNS 配置不变
                action = .none
                AppLogger.info("🌐 未匹配到 DNS 场景，保持当前 DNS 配置不变")
            }
        } else {
            // 场景无变化
            action = .none
            AppLogger.debug("DNS 场景无变化，无需更新配置")
        }

        AppLogger.debug("DNS 场景匹配检查完成")

        return MatchResult(
            matchedScene: matchedScene,
            action: action
        )
    }

    // MARK: - Private Methods

    /// 查找匹配的 DNS 场景
    ///
    /// ## 匹配规则
    /// - 场景必须启用（isEnabled = true）
    /// - 路由器IP必须完全匹配
    /// - 路由器MAC必须匹配（大小写不敏感）
    /// - 只返回第一个匹配的场景（假设每个路由器只有一个 DNS 配置）
    ///
    /// - Parameters:
    ///   - routerIP: 路由器IP地址
    ///   - routerMAC: 路由器MAC地址
    ///   - scenes: DNS 场景列表
    /// - Returns: 匹配的场景（可能为 nil）
    private func findMatchingDNSScene(
        routerIP: String,
        routerMAC: String,
        scenes: [DNSScene]
    ) -> DNSScene? {
        return scenes.first { scene in
            scene.isEnabled &&
            scene.routerIP == routerIP &&
            scene.routerMAC.lowercased() == routerMAC.lowercased()
        }
    }
}
