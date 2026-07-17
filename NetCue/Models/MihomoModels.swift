//
//  MihomoModels.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/30.
//

import Foundation

// MARK: - Mihomo 配置模型

/// Mihomo 配置
///
/// ## 设计说明
/// 内核路径与关联应用身份均由用户显式选择，不对任何具体的 Clash/Mihomo
/// 客户端（ClashX.Meta、Clash Verge、clashbar 等）做路径假设。
struct MihomoConfig: Codable, Equatable {
    /// 内核文件路径（用户通过文件选择器指定）
    var kernelPath: String
    /// 关联应用的 Bundle 路径（如 /Applications/clashbar.app）
    var appBundlePath: String
    /// 关联应用的 Bundle Identifier（选择应用时自动读取）
    var appBundleIdentifier: String
    /// 关联应用的显示名称（选择应用时自动读取）
    var appDisplayName: String
    /// GitHub Releases URL
    var githubReleasesURL: String
    /// 内核文件名模板（例如：mihomo-darwin-arm64-alpha-smart）
    var kernelFilenameTemplate: String

    /// 默认配置：内核路径与关联应用均为空，需用户显式设置
    static let `default` = MihomoConfig(
        kernelPath: "",
        appBundlePath: "",
        appBundleIdentifier: "",
        appDisplayName: "",
        githubReleasesURL: "https://github.com/vernesong/mihomo/releases",
        kernelFilenameTemplate: "mihomo-darwin-arm64-alpha-smart"
    )

    /// 内核相关配置（路径、下载源）是否仍为默认值
    ///
    /// 与是否关联应用无关——关联应用的设置入口在"设置"页面，
    /// 不应受 Mihomo 页面"重置配置"按钮的影响，因此单独判断。
    var isKernelConfigDefault: Bool {
        kernelPath == Self.default.kernelPath &&
        githubReleasesURL == Self.default.githubReleasesURL &&
        kernelFilenameTemplate == Self.default.kernelFilenameTemplate
    }

    /// 是否已关联应用
    var hasAssociatedApp: Bool {
        !appBundlePath.isEmpty
    }

    // MARK: - Codable

    /// 自定义解码：兼容旧版本配置（缺少 appBundlePath/appBundleIdentifier/appDisplayName 字段）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kernelPath = try container.decodeIfPresent(String.self, forKey: .kernelPath) ?? ""
        appBundlePath = try container.decodeIfPresent(String.self, forKey: .appBundlePath) ?? ""
        appBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .appBundleIdentifier) ?? ""
        appDisplayName = try container.decodeIfPresent(String.self, forKey: .appDisplayName) ?? ""
        githubReleasesURL = try container.decodeIfPresent(String.self, forKey: .githubReleasesURL) ?? Self.default.githubReleasesURL
        kernelFilenameTemplate = try container.decodeIfPresent(String.self, forKey: .kernelFilenameTemplate) ?? Self.default.kernelFilenameTemplate
    }

    init(
        kernelPath: String,
        appBundlePath: String,
        appBundleIdentifier: String,
        appDisplayName: String,
        githubReleasesURL: String,
        kernelFilenameTemplate: String
    ) {
        self.kernelPath = kernelPath
        self.appBundlePath = appBundlePath
        self.appBundleIdentifier = appBundleIdentifier
        self.appDisplayName = appDisplayName
        self.githubReleasesURL = githubReleasesURL
        self.kernelFilenameTemplate = kernelFilenameTemplate
    }
}

// MARK: - Mihomo 状态模型

/// 关联应用安装状态
enum HostAppInstallStatus {
    case notConfigured      // 尚未关联应用
    case notInstalled       // 已关联，但该路径下找不到应用
    case installed          // 已关联且检测到应用
    case unknown            // 初始占位状态（刷新前）
}

/// 内核状态
struct KernelStatus {
    /// 内核文件是否存在
    let kernelExists: Bool
    /// 备份文件是否存在
    let backupExists: Bool
    /// 内核文件路径
    let kernelPath: String
    /// 备份文件路径
    let backupPath: String

    /// 当前状态描述
    var statusDescription: String {
        if kernelPath.isEmpty {
            return "尚未选择内核文件"
        } else if !kernelExists {
            return "内核文件不存在"
        } else if backupExists {
            return "内核已备份"
        } else {
            return "内核未备份"
        }
    }
}

// MARK: - Mihomo 错误定义

/// Mihomo 操作错误
enum MihomoError: LocalizedError {
    case hostAppIsRunning(String)       // 关联应用正在运行
    case appQuitTimeout                 // 等待应用退出超时
    case kernelPathNotConfigured        // 尚未选择内核文件路径
    case kernelFileNotFound             // 内核文件不存在
    case backupAlreadyExists            // 备份已存在
    case backupNotFound                 // 备份不存在
    case fileOperationFailed(String)    // 文件操作失败
    case permissionDenied               // 权限不足
    case invalidFilePath                // 无效的文件路径
    case shellCommandFailed(String)     // Shell 命令执行失败

    var errorDescription: String? {
        switch self {
        case .hostAppIsRunning(let displayName):
            return "\(displayName) 正在运行，请先退出应用"
        case .appQuitTimeout:
            return "等待应用退出超时，请手动确认应用已完全退出后重试"
        case .kernelPathNotConfigured:
            return "请先选择内核文件路径"
        case .kernelFileNotFound:
            return "内核文件不存在"
        case .backupAlreadyExists:
            return "备份文件已存在"
        case .backupNotFound:
            return "备份文件不存在"
        case .fileOperationFailed(let reason):
            return "文件操作失败: \(reason)"
        case .permissionDenied:
            return "权限不足，需要管理员权限"
        case .invalidFilePath:
            return "无效的文件路径"
        case .shellCommandFailed(let reason):
            return "命令执行失败: \(reason)"
        }
    }
}
