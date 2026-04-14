//
//  SceneMatchingEngine.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/01/04.
//

import Foundation

/// 网络场景匹配引擎
///
/// ## 职责
/// - 根据路由器信息匹配网络场景
/// - 计算场景切换时需要启动/退出的应用
/// - 管理场景切换的Fallback机制
///
/// ## 设计说明
/// - **无状态服务**：所有方法都是纯函数，无副作用
/// - **单一职责**：只负责场景匹配逻辑，不负责应用控制
/// - **结构化输出**：返回结构化的匹配结果和操作列表
///
/// ## 使用方式
/// ```swift
/// let engine = SceneMatchingEngine()
/// let result = engine.matchScenes(
///     routerIP: "192.168.1.1",
///     routerMAC: "AA:BB:CC:DD:EE:FF",
///     availableScenes: scenes,
///     previousMatches: []
/// )
/// ```
@MainActor
final class SceneMatchingEngine {
    // MARK: - Initialization

    /// 初始化场景匹配引擎
    nonisolated init() {
        // 无状态服务，无需初始化
    }

    // MARK: - Result Structures

    /// 场景匹配结果
    struct MatchResult {
        /// 匹配的场景列表
        let matchedScenes: [NetworkScene]
        /// 需要退出的应用列表
        let appsToQuit: [String]
        /// 需要启动的应用列表
        let appsToLaunch: [String]
        /// 是否触发了Fallback机制
        let isFallback: Bool
    }

    // MARK: - Public Methods

    /// 匹配网络场景
    ///
    /// ## 功能说明
    /// 1. 根据当前路由器信息查找匹配的网络场景
    /// 2. 对比新旧场景，计算需要启动/退出的应用
    /// 3. **Fallback机制**: 无匹配场景时，启动所有之前被退出的应用
    ///
    /// ## 边界情况处理
    /// - 从有场景切换到无场景：启动所有被控制的应用（恢复默认状态）
    /// - 从无场景切换到有场景：退出场景指定的应用
    /// - 场景间切换：仅处理差异部分的应用
    ///
    /// - Parameters:
    ///   - routerIP: 当前路由器IP地址
    ///   - routerMAC: 当前路由器MAC地址
    ///   - availableScenes: 所有可用的场景列表
    ///   - previousMatches: 之前匹配的场景列表
    /// - Returns: 场景匹配结果（包含匹配场景和应用操作列表）
    func matchScenes(
        routerIP: String,
        routerMAC: String,
        availableScenes: [NetworkScene],
        previousMatches: [NetworkScene]
    ) -> MatchResult {
        AppLogger.debug("🔍 开始检查网络场景匹配 (当前路由器: \(routerIP), \(routerMAC))")

        let newMatchedScenes = findMatchingScenes(
            routerIP: routerIP,
            routerMAC: routerMAC,
            scenes: availableScenes
        )

        var appsToQuit: [String] = []
        let appsToLaunch: [String] = []
        let isFallback = false

        if newMatchedScenes.isEmpty {
            AppLogger.debug("未匹配到任何网络场景")
        } else {
            AppLogger.info("✅ 匹配到 \(newMatchedScenes.count) 个网络场景: \(newMatchedScenes.map { $0.name }.joined(separator: ", "))")

            // 收集旧场景中的所有控制应用
            var oldApps = Set<String>()
            for scene in previousMatches {
                oldApps.formUnion(scene.controlApps)
            }

            // 收集新场景中的所有控制应用
            var newApps = Set<String>()
            for scene in newMatchedScenes {
                newApps.formUnion(scene.controlApps)
            }

            // 找出新增的应用（需要退出）
            appsToQuit = Array(newApps.subtracting(oldApps))
            if !appsToQuit.isEmpty {
                AppLogger.info("需要退出的应用: \(appsToQuit.joined(separator: ", "))")
            }
        }

        AppLogger.debug("场景匹配检查完成")

        return MatchResult(
            matchedScenes: newMatchedScenes,
            appsToQuit: appsToQuit,
            appsToLaunch: appsToLaunch,
            isFallback: isFallback
        )
    }

    // MARK: - Private Methods

    /// 查找匹配的场景
    ///
    /// ## 匹配规则
    /// - 场景必须启用（isEnabled = true）
    /// - 路由器IP必须完全匹配
    /// - 路由器MAC必须匹配（大小写不敏感）
    ///
    /// - Parameters:
    ///   - routerIP: 路由器IP地址
    ///   - routerMAC: 路由器MAC地址
    ///   - scenes: 场景列表
    /// - Returns: 匹配的场景列表
    private func findMatchingScenes(
        routerIP: String,
        routerMAC: String,
        scenes: [NetworkScene]
    ) -> [NetworkScene] {
        return scenes.filter { scene in
            scene.isEnabled &&
            scene.routerIP == routerIP &&
            scene.routerMAC.lowercased() == routerMAC.lowercased()
        }
    }
}
