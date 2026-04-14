//
//  NetworkMonitor.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/26.
//

import Foundation
import SystemConfiguration
import AppKit
import CoreWLAN
import Observation
import Network
import UserNotifications

/// 网络监控服务（编排层）
///
/// ## 架构设计
/// - **编排层职责**: 协调各个服务，不包含具体实现逻辑
/// - **主线程隔离**: 所有状态更新在主线程，确保 UI 安全
/// - **后台处理**: 网络检测在后台队列执行，避免阻塞 UI
/// - **生命周期独立**: 通过 Environment 注入，生命周期由 App 管理
/// - **线程安全**: @MainActor 自动序列化所有状态访问
///
/// ## 依赖服务
/// - `RouterInfoService`: 路由器信息获取（IP/MAC/网络接口）
/// - `AppControlService`: 应用启动/退出控制
/// - `SceneMatchingEngine`: 网络场景匹配
/// - `DNSSceneMatchingEngine`: DNS 场景匹配
///
/// ## 使用方式
/// 1. 在 NetCueApp 中创建: `@State private var networkMonitor = NetworkMonitor()`
/// 2. 注入到视图层级: `.environment(networkMonitor)`
/// 3. 在 AppDelegate 中初始化: `networkMonitor.startMonitoring(...)`
@MainActor
@Observable
final class NetworkMonitor {
    // MARK: - Published State

    var currentRouterIP: String = "-"
    var currentRouterMAC: String = "-"
    var currentNetworkName: String = "-"
    var currentNetworkType: String = "-"
    var activeNetworks: [RouterInfoService.NetworkInfo] = []
    var matchedScenes: [NetworkScene] = []  // 当前匹配的场景列表

    // MARK: - Private Properties

    private var pathMonitor: NWPathMonitor?
    private var scenes: [NetworkScene] = []
    private var dnsScenes: [DNSScene] = []
    private var currentMatchedDNSScene: DNSScene?

    /// 上次通知的匹配场景 ID 集合（用于去重通知）
    ///
    /// ## 设计说明
    /// - 记录上一次发送"已匹配场景"通知时的场景 ID
    /// - 只有当匹配结果发生变化时才发送新通知
    /// - 避免 Tab 切换时重复发送相同内容的通知
    private var lastNotifiedMatchedSceneIDs: Set<UUID> = []

    // MARK: - Dependencies

    private let routerInfoService: RouterInfoService
    private let appControlService: AppControlService
    private let sceneMatchingEngine: SceneMatchingEngine
    private let dnsSceneMatchingEngine: DNSSceneMatchingEngine

    // MARK: - Initialization

    /// 轻量级初始化
    ///
    /// ## 设计说明
    /// - 不执行任何重度操作（如网络监听）
    /// - 实际监听在 `startMonitoring()` 中启动
    /// - 使用依赖注入模式，方便测试和解耦
    /// - Preview 环境中跳过服务初始化，避免超时
    ///
    /// - Parameters:
    ///   - routerInfoService: 路由器信息服务（默认创建新实例）
    ///   - appControlService: 应用控制服务
    ///   - sceneMatchingEngine: 场景匹配引擎（默认创建新实例）
    ///   - dnsSceneMatchingEngine: DNS 场景匹配引擎（默认创建新实例）
    init(
        routerInfoService: RouterInfoService = RouterInfoService(),
        appControlService: AppControlService? = nil,
        sceneMatchingEngine: SceneMatchingEngine = SceneMatchingEngine(),
        dnsSceneMatchingEngine: DNSSceneMatchingEngine = DNSSceneMatchingEngine()
    ) {
        self.routerInfoService = routerInfoService
        self.sceneMatchingEngine = sceneMatchingEngine
        self.dnsSceneMatchingEngine = dnsSceneMatchingEngine
        self.appControlService = appControlService ?? AppControlService(permissionManager: PermissionManager.shared)

        AppLogger.debug("NetworkMonitor 实例已创建（未启动监听）")
    }

    // MARK: - Public Methods - Scene Management

    /// 更新网络场景列表
    ///
    /// ## 设计说明
    /// - **变化检测**：比较新旧场景列表，只有真正变化时才触发场景匹配检查
    /// - **避免重复通知**：Tab 切换时加载相同数据不会触发通知
    ///
    /// - Parameter newScenes: 新的场景列表
    func updateScenes(_ newScenes: [NetworkScene]) {
        // 变化检测：比较新旧场景列表
        guard scenes != newScenes else {
            AppLogger.debug("📝 网络场景列表未变化，跳过检查")
            return
        }

        AppLogger.info("📝 更新网络场景列表: \(newScenes.count) 个场景")
        AppLogger.debug("场景详情: \(newScenes.map { "[\($0.name): \($0.isEnabled ? "启用" : "禁用")]" }.joined(separator: ", "))")

        self.scenes = newScenes
        // 场景配置变化，触发检查（可能需要发送通知）
        Task {
            await checkAndHandleSceneMatch(triggeredByNetworkChange: false)
        }

        AppLogger.info("✅ 网络场景列表更新完成")
    }

    /// 更新 DNS 场景列表
    ///
    /// ## 设计说明
    /// - **变化检测**：比较新旧 DNS 场景列表，只有真正变化时才触发场景匹配检查
    /// - **避免重复操作**：Tab 切换时加载相同数据不会触发 DNS 配置
    ///
    /// - Parameter newScenes: 新的 DNS 场景列表
    func updateDNSScenes(_ newScenes: [DNSScene]) {
        // 变化检测：比较新旧 DNS 场景列表
        guard dnsScenes != newScenes else {
            AppLogger.debug("📝 DNS 场景列表未变化，跳过检查")
            return
        }

        AppLogger.info("📝 更新 DNS 场景列表: \(newScenes.count) 个场景")
        AppLogger.debug("DNS场景详情: \(newScenes.map { "[\($0.name): \($0.isEnabled ? "启用" : "禁用"), DNS=\($0.primaryDNS)]" }.joined(separator: ", "))")

        self.dnsScenes = newScenes
        // DNS 场景更新后重新检查匹配
        checkAndHandleDNSSceneMatch()

        AppLogger.info("✅ DNS 场景列表更新完成")
    }

    // MARK: - Public Methods - Monitoring Control

    /// 启动网络监控（应在 App 启动时调用一次）
    ///
    /// ## 参数
    /// - scenes: 网络场景配置列表
    /// - dnsScenes: DNS 场景配置列表
    ///
    /// ## 设计说明
    /// - 初始化网络监听器（NWPathMonitor）
    /// - 加载场景配置
    /// - 执行首次网络检测
    /// - **线程安全**: 在主线程执行，更新所有 @Published 属性
    ///
    /// ## 调用时机
    /// 建议在 `AppDelegate.applicationDidFinishLaunching` 中调用，
    /// 确保应用启动（包括作为登录项启动）时立即开始监控。
    func startMonitoring(scenes: [NetworkScene] = [], dnsScenes: [DNSScene] = []) {
        AppLogger.info("🚀 启动网络监控")
        AppLogger.debug("配置: 网络场景=\(scenes.count), DNS场景=\(dnsScenes.count)")

        // 加载场景配置
        self.scenes = scenes
        self.dnsScenes = dnsScenes

        // 设置网络监听器
        setupNetworkMonitoring()

        // 立即执行首次检测
        Task {
            await updateNetworkInfoAsync()
        }

        AppLogger.info("✅ 网络监控已启动")
    }

    /// 停止网络监控
    func stopMonitoring() {
        AppLogger.info("🛑 停止网络监控")

        pathMonitor?.cancel()
        pathMonitor = nil

        AppLogger.info("✅ 网络监控已停止")
    }

    // MARK: - Private Methods - Network Monitoring

    /// 设置网络监听器
    ///
    /// ## 实现说明
    /// - 使用 NWPathMonitor 监听网络状态变化
    /// - 监听器运行在专用后台队列（避免阻塞主线程）
    /// - 网络变化时触发异步更新
    private func setupNetworkMonitoring() {
        pathMonitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.netcue.networkmonitor", qos: .userInitiated)

        pathMonitor?.pathUpdateHandler = { [weak self] _ in
            guard let self = self else { return }

            // 网络状态变化，触发异步更新
            Task {
                await self.updateNetworkInfoAsync()
            }
        }

        pathMonitor?.start(queue: queue)
        AppLogger.debug("NWPathMonitor 已启动在后台队列")
    }

    /// 异步更新网络信息（nonisolated 允许后台执行）
    ///
    /// ## 实现说明
    /// - **后台执行**: 在后台队列执行重度网络检测操作
    /// - **主线程更新**: 通过 MainActor.run 将结果传递到主线程
    /// - **线程安全**: 避免阻塞 UI，确保 @Published 属性更新在主线程
    nonisolated private func updateNetworkInfoAsync() async {
        AppLogger.debug("🔄 开始更新网络信息（后台队列）")

        // ✅ 修正：将耗时且带有阻塞 Shell 调用的方法移出 MainActor.run
        // 这些方法本身标记为 nonisolated，可以在后台并发池安全执行
        let routerIP = routerInfoService.getRouterIP()
        let routerMAC = routerInfoService.getRouterMAC()
        let networks = routerInfoService.getAllActiveNetworks()

        AppLogger.debug("网络信息获取完成: 路由器IP=\(routerIP), MAC=\(routerMAC), 活跃网络=\(networks.count)个")

        // 仅在赋值状态和触发 UI 逻辑时传递到主线程
        await MainActor.run {
            self.currentRouterIP = routerIP
            self.currentRouterMAC = routerMAC
            self.activeNetworks = networks

            // 更新显示用的网络名称和类型
            self.updateDisplayInfo()

            AppLogger.info("✅ 网络信息已更新: \(self.currentNetworkType), 路由器=\(routerIP)")

            // 网络信息更新后检查场景匹配（网络变化触发，需要发送通知）
            Task {
                await self.checkAndHandleSceneMatch(triggeredByNetworkChange: true)
            }

            // 检查 DNS 场景匹配
            self.checkAndHandleDNSSceneMatch()
        }
    }

    /// 更新显示信息
    private func updateDisplayInfo() {
        if activeNetworks.isEmpty {
            currentNetworkName = "-"
            currentNetworkType = "-"
        } else {
            // 网络类型显示所有接口的完整名称，用 + 分隔
            let types = activeNetworks.map { $0.displayName }.joined(separator: " + ")
            currentNetworkType = types

            // 网络名称不再使用，设置为空
            currentNetworkName = ""
        }
    }

    // MARK: - Private Methods - Scene Matching

    /// 检查并处理网络场景匹配
    ///
    /// ## 功能说明
    /// 1. 使用 SceneMatchingEngine 匹配场景
    /// 2. 使用 AppControlService 执行应用控制操作
    /// 3. 发送用户通知反馈结果
    ///
    /// ## 通知策略
    /// - **网络变化触发**：始终发送通知（用户需要知道网络环境变化）
    /// - **场景配置变化触发**：只在匹配结果变化时发送通知
    ///
    /// - Parameter triggeredByNetworkChange: 是否由网络变化触发（决定通知策略）
    private func checkAndHandleSceneMatch(triggeredByNetworkChange: Bool) async {
        // ✅ 使用 SceneMatchingEngine 匹配场景
        let result = sceneMatchingEngine.matchScenes(
            routerIP: currentRouterIP,
            routerMAC: currentRouterMAC,
            availableScenes: scenes,
            previousMatches: matchedScenes
        )

        // 收集应用控制结果
        var quitSuccessApps: [String] = []
        var quitFailedApps: [String] = []
        var launchSuccessApps: [String] = []
        var launchFailedApps: [String] = []

        // ✅ 使用 AppControlService 退出应用
        for appName in result.appsToQuit {
            let controlResult = appControlService.quit(appName)
            if controlResult.success {
                quitSuccessApps.append(appName)
            } else {
                quitFailedApps.append(appName)
            }
        }

        // ✅ 使用 AppControlService 启动应用
        for appName in result.appsToLaunch {
            if result.isFallback {
                AppLogger.info("🚀 [Fallback] 启动应用: \(appName)")
            }
            let controlResult = await appControlService.launch(appName)
            if controlResult.success {
                launchSuccessApps.append(appName)
            } else {
                launchFailedApps.append(appName)
            }
        }

        // 更新匹配的场景列表
        matchedScenes = result.matchedScenes

        // 📣 发送用户通知（带变化检测）
        sendAppControlNotification(
            matchedScenes: result.matchedScenes,
            quitSuccess: quitSuccessApps,
            quitFailed: quitFailedApps,
            launchSuccess: launchSuccessApps,
            launchFailed: launchFailedApps,
            triggeredByNetworkChange: triggeredByNetworkChange
        )
    }

    /// 发送应用控制结果通知
    ///
    /// - Parameters:
    ///   - matchedScenes: 匹配的场景列表
    ///   - quitSuccess: 成功退出的应用列表
    ///   - quitFailed: 退出失败的应用列表
    ///   - launchSuccess: 成功启动的应用列表
    ///   - launchFailed: 启动失败的应用列表
    ///   - triggeredByNetworkChange: 是否由网络变化触发
    ///
    /// ## 通知策略
    /// - **有应用操作时**：始终发送通知（用户需要知道应用被启动/退出）
    /// - **无应用操作但有匹配场景时**：
    ///   - 网络变化触发：发送通知（用户需要知道网络环境变化）
    ///   - 场景配置变化触发：只在匹配结果变化时发送通知（避免重复）
    /// - **无匹配场景且无操作**：不发送通知
    ///
    /// ## 优化说明
    /// - 使用 NotificationCoordinator 统一管理通知
    /// - 内置 2 秒防抖机制，短时间内多次触发只发送最后一次
    /// - 使用 .active 级别确保有声音提示
    /// - **匹配结果变化检测**：记录上次通知的场景 ID，避免重复通知
    private func sendAppControlNotification(
        matchedScenes: [NetworkScene],
        quitSuccess: [String],
        quitFailed: [String],
        launchSuccess: [String],
        launchFailed: [String],
        triggeredByNetworkChange: Bool
    ) {
        let totalOperations = quitSuccess.count + quitFailed.count + launchSuccess.count + launchFailed.count

        // 没有任何应用操作
        if totalOperations == 0 {
            // 如果有匹配的场景，检查是否需要发送通知
            if !matchedScenes.isEmpty {
                let currentSceneIDs = Set(matchedScenes.map { $0.id })

                // 变化检测：比较当前匹配结果与上次通知的结果
                let hasMatchChanged = currentSceneIDs != lastNotifiedMatchedSceneIDs

                // 决定是否发送通知
                // 1. 网络变化触发 + 匹配结果变化 → 发送通知
                // 2. 场景配置变化触发 + 匹配结果变化 → 发送通知
                // 3. 匹配结果未变化 → 不发送通知（避免重复）
                if hasMatchChanged {
                    let sceneNames = matchedScenes.map { $0.name }
                    NotificationCoordinator.shared.notifySceneMatchedNoAction(sceneNames: sceneNames)

                    // 更新上次通知的匹配结果
                    lastNotifiedMatchedSceneIDs = currentSceneIDs

                    AppLogger.debug("📣 发送场景匹配通知（匹配结果变化）: \(sceneNames.joined(separator: ", "))")
                } else {
                    AppLogger.debug("📣 跳过场景匹配通知（匹配结果未变化）")
                }
            } else {
                // 无匹配场景，清空上次通知记录
                if !lastNotifiedMatchedSceneIDs.isEmpty {
                    lastNotifiedMatchedSceneIDs = []
                    AppLogger.debug("📣 清空场景匹配通知记录（无匹配场景）")
                }
            }
            return
        }

        // 有应用操作，始终发送通知
        let failedCount = quitFailed.count + launchFailed.count
        let successCount = quitSuccess.count + launchSuccess.count

        // 更新上次通知的匹配结果
        lastNotifiedMatchedSceneIDs = Set(matchedScenes.map { $0.id })

        if failedCount == 0 {
            // ✅ 全部成功
            NotificationCoordinator.shared.notifySceneSwitchSuccess(
                quitApps: quitSuccess,
                launchApps: launchSuccess
            )
        } else {
            // ⚠️ 部分或全部失败
            NotificationCoordinator.shared.notifySceneSwitchFailure(
                quitFailed: quitFailed,
                launchFailed: launchFailed,
                successCount: successCount
            )
        }
    }

    // MARK: - Public Methods - DNS Scene Refresh

    /// 手动触发 DNS 场景匹配
    ///
    /// ## 使用场景
    /// - Helper 安装成功后，主动触发一次 DNS 场景匹配
    /// - 确保已开启的 DNS 场景能够立即生效
    func refreshDNSSceneMatching() {
        AppLogger.info("🔄 手动触发 DNS 场景匹配")
        checkAndHandleDNSSceneMatch()
    }

    // MARK: - Private Methods - DNS Scene Matching

    /// 检查并处理 DNS 场景匹配
    private func checkAndHandleDNSSceneMatch() {
        // ✅ 使用 DNSSceneMatchingEngine 匹配场景
        let result = dnsSceneMatchingEngine.matchDNSScene(
            routerIP: currentRouterIP,
            routerMAC: currentRouterMAC,
            availableScenes: dnsScenes,
            previousMatch: currentMatchedDNSScene
        )

        // 根据操作类型执行相应的 DNS 配置
        switch result.action {
        case .none:
            // 无需操作
            break

        case .apply(let scene):
            // 应用 DNS 配置
            applyDNSConfiguration(scene)
            currentMatchedDNSScene = scene

        case .clear:
            // 清除 DNS 配置
            clearDNSConfiguration()
            currentMatchedDNSScene = nil
        }
    }

    /// 应用 DNS 配置
    ///
    /// - Parameter scene: DNS 场景
    private func applyDNSConfiguration(_ scene: DNSScene) {
        AppLogger.info("🌐 开始应用 DNS 场景: \(scene.name)")
        AppLogger.info("DNS 配置: 主DNS=\(scene.primaryDNS), 备DNS=\(scene.secondaryDNS.isEmpty ? "无" : scene.secondaryDNS)")

        guard !activeNetworks.isEmpty else {
            AppLogger.warning("⚠️ 没有活跃的网络接口，跳过 DNS 配置")
            return
        }

        // 使用 DispatchGroup 协调多个异步操作
        let group = DispatchGroup()
        var successCount = 0
        let totalCount = activeNetworks.count

        AppLogger.debug("开始为 \(totalCount) 个网络接口配置 DNS: \(activeNetworks.map { $0.displayName }.joined(separator: ", "))")

        // 为所有活动网络接口设置 DNS
        for network in activeNetworks {
            let interface = network.displayName

            group.enter()
            DNSManager.shared.setDNS(
                interface: interface,
                primaryDNS: scene.primaryDNS,
                secondaryDNS: scene.secondaryDNS.isEmpty ? nil : scene.secondaryDNS
            ) { success, error in
                if success {
                    successCount += 1
                    AppLogger.info("✅ DNS 已应用到 \(interface)")
                } else {
                    AppLogger.error("❌ DNS 应用失败 (\(interface)): \(error ?? "未知错误")")
                }
                group.leave()
            }
        }

        // 所有接口配置完成后刷新缓存
        group.notify(queue: .main) {
            if successCount > 0 {
                AppLogger.debug("🔄 开始刷新 DNS 缓存...")
                DNSManager.shared.flushDNSCache()
                AppLogger.info("✅ DNS 缓存已刷新 (\(successCount)/\(totalCount) 个接口配置成功)")
            } else {
                AppLogger.error("⚠️ 所有接口 DNS 配置失败，跳过缓存刷新")
            }
        }
    }

    /// 清除 DNS 配置
    private func clearDNSConfiguration() {
        AppLogger.info("🌐 开始清除 DNS 配置，恢复自动获取")

        guard !activeNetworks.isEmpty else {
            AppLogger.warning("⚠️ 没有活跃的网络接口，跳过 DNS 清除")
            return
        }

        // 使用 DispatchGroup 协调多个异步操作
        let group = DispatchGroup()
        var successCount = 0
        let totalCount = activeNetworks.count

        AppLogger.debug("开始为 \(totalCount) 个网络接口清除 DNS: \(activeNetworks.map { $0.displayName }.joined(separator: ", "))")

        // 为所有活动网络接口清除 DNS
        for network in activeNetworks {
            let interface = network.displayName

            group.enter()
            DNSManager.shared.clearDNS(interface: interface) { success, error in
                if success {
                    successCount += 1
                    AppLogger.info("✅ DNS 已清除 (\(interface))")
                } else {
                    AppLogger.error("❌ DNS 清除失败 (\(interface)): \(error ?? "未知错误")")
                }
                group.leave()
            }
        }

        // 所有接口清除完成后刷新缓存
        group.notify(queue: .main) {
            if successCount > 0 {
                AppLogger.debug("🔄 开始刷新 DNS 缓存...")
                DNSManager.shared.flushDNSCache()
                AppLogger.info("✅ DNS 缓存已刷新 (\(successCount)/\(totalCount) 个接口清除成功)")
            } else {
                AppLogger.error("⚠️ 所有接口 DNS 清除失败，跳过缓存刷新")
            }
        }
    }
}
