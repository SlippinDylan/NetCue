//
//  LoginItemManager.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/31.
//

import Foundation
import ServiceManagement
import Observation

/// 开机自启动管理器
///
/// 职责：
/// - 管理应用的开机自启动状态
/// - 提供启用/禁用开机自启动的接口
/// - 实时反映系统中的登录项状态
///
/// 技术实现：
/// - 使用 SMAppService.mainApp（macOS 13+ 标准 API）
/// - 符合 macOS 26 最佳实践
@MainActor
@Observable
final class LoginItemManager {
    // MARK: - Singleton

    /// 全局单例
    static let shared = LoginItemManager()

    // MARK: - Computed Properties

    /// 开机自启动是否已启用
    var isEnabled: Bool = false

    /// 当前登录项状态的详细描述
    var statusDescription: String {
        let status = SMAppService.mainApp.status
        switch status {
        case .enabled:
            return "已启用"
        case .notRegistered:
            return "未注册"
        case .requiresApproval:
            return "需要用户批准"
        case .notFound:
            return "未找到"
        @unknown default:
            return "未知状态 (\(status.rawValue))"
        }
    }

    // MARK: - Initialization

    private init() {
        AppLogger.debug("LoginItemManager 已初始化")
        refreshStatus()
    }

    // MARK: - Public Methods

    /// 刷新当前状态（可用于应用激活时同步系统设置的变更）
    func refreshStatus() {
        let status = SMAppService.mainApp.status
        self.isEnabled = (status == .enabled)
        AppLogger.debug("查询开机自启动状态: \(self.isEnabled ? "已启用" : "未启用") (系统状态: \(status.rawValue))")
    }

    /// 切换开机自启动状态
    ///
    /// - Throws: 注册或注销失败时抛出错误
    func toggle() throws {
        if isEnabled {
            try disable()
        } else {
            try enable()
        }
    }

    /// 启用开机自启动
    ///
    /// - Throws: 注册失败时抛出错误
    func enable() throws {
        AppLogger.info("尝试启用开机自启动")

        // 检查是否已经启用
        if SMAppService.mainApp.status == .enabled {
            AppLogger.info("开机自启动已处于启用状态，无需重复注册")
            self.isEnabled = true
            return
        }

        do {
            try SMAppService.mainApp.register()
            self.isEnabled = true
            AppLogger.info("✅ 成功启用开机自启动")
        } catch {
            AppLogger.error("❌ 启用开机自启动失败", error: error)
            throw error
        }
    }

    /// 禁用开机自启动
    ///
    /// - Throws: 注销失败时抛出错误
    func disable() throws {
        AppLogger.info("尝试禁用开机自启动")

        // 检查是否已经禁用
        let status = SMAppService.mainApp.status
        if status == .notRegistered || status == .notFound {
            AppLogger.info("开机自启动已处于禁用状态，无需重复注销")
            self.isEnabled = false
            return
        }

        do {
            try SMAppService.mainApp.unregister()
            self.isEnabled = false
            AppLogger.info("✅ 成功禁用开机自启动")
        } catch {
            AppLogger.error("❌ 禁用开机自启动失败", error: error)
            throw error
        }
    }

    /// 打开系统设置中的登录项面板
    ///
    /// 允许用户手动管理登录项
    func openSystemSettings() {
        AppLogger.info("打开系统设置 - 登录项")
        SMAppService.openSystemSettingsLoginItems()
    }
}
