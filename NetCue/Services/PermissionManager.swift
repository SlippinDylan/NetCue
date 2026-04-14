//
//  PermissionManager.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/29.
//

import Foundation
import AppKit
import ApplicationServices
import Observation

/// 权限类型
enum PermissionType {
    case accessibility      // 辅助功能权限（控制应用需要）
    case helperTool        // Helper Tool安装状态（修改DNS需要）

    var displayName: String {
        switch self {
        case .accessibility: return "辅助功能权限"
        case .helperTool: return "DNS Helper工具"
        }
    }

    var description: String {
        switch self {
        case .accessibility:
            return "用于自动控制应用的启动和退出"
        case .helperTool:
            return "用于修改系统DNS配置（需要管理员密码）"
        }
    }

    var guideText: String {
        switch self {
        case .accessibility:
            return "请前往：系统设置 > 隐私与安全性 > 辅助功能，添加 NetCue"
        case .helperTool:
            return "点击「安装 Helper」按钮，输入管理员密码完成安装"
        }
    }
}

/// 权限状态
struct PermissionStatus {
    let type: PermissionType
    var isGranted: Bool
    var isRequired: Bool  // 是否必需

    var statusText: String {
        isGranted ? "已授权" : "未授权"
    }

    var statusColor: NSColor {
        if !isRequired {
            return .systemGray
        }
        return isGranted ? .systemGreen : .systemOrange
    }
}

/// 统一的权限管理器
@MainActor
@Observable
final class PermissionManager {
    private final class ObserverBox: @unchecked Sendable {
        nonisolated(unsafe) var observer: NSObjectProtocol?
    }

    static let shared = PermissionManager()

    var permissions: [PermissionStatus] = []
    var allRequiredGranted: Bool = false

    @ObservationIgnored
    private let appDidBecomeActiveObserverBox = ObserverBox()

    private init() {
        // 初始化时在主线程检查权限
        Task { @MainActor in
            refresh()
        }

        setupActivationObserver()
    }

    /// 监听应用重新激活事件，回到前台时自动刷新权限状态
    private func setupActivationObserver() {
        appDidBecomeActiveObserverBox.observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    // MARK: - 权限刷新
    func refresh() {
        var statuses: [PermissionStatus] = []

        // 1. 辅助功能权限（网络控制功能需要）
        statuses.append(PermissionStatus(
            type: .accessibility,
            isGranted: checkAccessibility(),
            isRequired: true
        ))

        // 2. Helper Tool（DNS管理功能需要）
        statuses.append(PermissionStatus(
            type: .helperTool,
            isGranted: DNSManager.shared.isHelperInstalled,
            isRequired: true
        ))

        self.permissions = statuses
        self.allRequiredGranted = statuses
            .filter { $0.isRequired }
            .allSatisfy { $0.isGranted }
    }

    /// 兼容旧调用方，内部转发到 `refresh()`
    func checkAllPermissions() {
        refresh()
    }

    // MARK: - 检查辅助功能权限
    func checkAccessibility() -> Bool {
        return AXIsProcessTrusted()
    }

    /// 请求辅助功能权限（会弹出系统提示）
    func requestAccessibility() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)

        // 延迟检查（给用户时间去设置）
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            self.refresh()
        }
    }

    // MARK: - 打开系统偏好设置
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - 获取特定权限状态
    func getPermissionStatus(_ type: PermissionType) -> PermissionStatus? {
        return permissions.first { $0.type.displayName == type.displayName }
    }

    // MARK: - 打印权限状态（调试用）
    func printStatus() {
        AppLogger.info("=== NetCue 权限状态 ===")
        for permission in permissions {
            let required = permission.isRequired ? "[必需]" : "[可选]"
            let status = permission.isGranted ? "✅" : "❌"
            AppLogger.info("\(status) \(permission.type.displayName) \(required): \(permission.statusText)")
            if !permission.isGranted && permission.isRequired {
                AppLogger.warning("   💡 \(permission.type.guideText)")
            }
        }
        AppLogger.info("========================")
    }

    deinit {
        if let observer = appDidBecomeActiveObserverBox.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
