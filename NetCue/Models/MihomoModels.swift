//
//  MihomoModels.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/30.
//

import Foundation

// MARK: - Mihomo 配置模型

/// Mihomo 配置
struct MihomoConfig: Codable, Equatable {
    /// 内核文件路径
    var kernelPath: String
    /// 应用图标路径
    var iconPath: String
    /// GitHub Releases URL
    var githubReleasesURL: String
    /// 内核文件名模板（例如：mihomo-darwin-arm64-alpha-smart）
    var kernelFilenameTemplate: String

    /// 默认配置
    static let `default` = MihomoConfig(
        kernelPath: "\(NSHomeDirectory())/Library/Application Support/com.metacubex.ClashX.meta/com.metacubex.ClashX.ProxyConfigHelper.meta",
        iconPath: "/Applications/ClashX Meta.app/Contents/Resources/menu_icon@2x.png",
        githubReleasesURL: "https://github.com/vernesong/mihomo/releases",
        kernelFilenameTemplate: "mihomo-darwin-arm64-alpha-smart"
    )

    /// 是否为默认配置
    var isDefault: Bool {
        self == Self.default
    }
}

// MARK: - Mihomo 状态模型

/// ClashX.Meta 安装状态
enum ClashXMetaInstallStatus {
    case notInstalled       // 未安装
    case installed          // 已安装
    case unknown            // 未知
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
        if !kernelExists {
            return "内核文件不存在"
        } else if backupExists {
            return "内核已备份"
        } else {
            return "内核未备份"
        }
    }
}

/// 图标状态
struct IconStatus {
    /// 应用图标是否存在
    let iconExists: Bool
    /// 备份图标是否存在
    let backupExists: Bool
    /// 新图标是否存在
    let newIconExists: Bool
    /// 应用图标路径
    let iconPath: String
    /// 备份图标路径
    let backupPath: String
    /// 新图标路径
    let newIconPath: String

    /// 当前状态描述
    var statusDescription: String {
        if !iconExists {
            return "应用图标不存在"
        } else if backupExists {
            return "图标已备份"
        } else {
            return "图标未备份"
        }
    }
}

// MARK: - Mihomo 错误定义

/// Mihomo 操作错误
enum MihomoError: LocalizedError {
    case clashXMetaNotInstalled         // ClashX.Meta 未安装
    case clashXMetaIsRunning            // ClashX.Meta 正在运行
    case appQuitTimeout                 // 应用退出超时
    case kernelFileNotFound             // 内核文件不存在
    case iconFileNotFound               // 图标文件不存在
    case backupAlreadyExists            // 备份已存在
    case backupNotFound                 // 备份不存在
    case fileOperationFailed(String)    // 文件操作失败
    case permissionDenied               // 权限不足
    case invalidFilePath                // 无效的文件路径
    case shellCommandFailed(String)     // Shell 命令执行失败

    var errorDescription: String? {
        switch self {
        case .clashXMetaNotInstalled:
            return "ClashX.Meta 未安装"
        case .clashXMetaIsRunning:
            return "ClashX.Meta 正在运行，请先退出应用"
        case .appQuitTimeout:
            return "等待应用退出超时，请手动确认应用已完全退出后重试"
        case .kernelFileNotFound:
            return "内核文件不存在"
        case .iconFileNotFound:
            return "图标文件不存在"
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

// MARK: - Mihomo 路径常量

/// Mihomo 相关路径
enum MihomoPaths {
    /// ClashX.Meta 应用路径
    static let clashXMetaApp = "/Applications/ClashX Meta.app"

    /// 内核文件路径
    static let kernelFile = "\(NSHomeDirectory())/Library/Application Support/com.metacubex.ClashX.meta/com.metacubex.ClashX.ProxyConfigHelper.meta"

    /// 内核备份路径
    static let kernelBackup = "\(NSHomeDirectory())/Library/Application Support/com.metacubex.ClashX.meta/com.metacubex.ClashX.ProxyConfigHelper.meta.bak"

    /// 应用图标路径
    static let appIcon = "/Applications/ClashX Meta.app/Contents/Resources/menu_icon@2x.png"

    static var netcueSupportDir: String {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let base = urls.first?.path ?? "\(NSHomeDirectory())/Library/Application Support"
        return "\(base)/NetCue"
    }

    /// 图标备份路径
    static var iconBackup: String {
        "\(netcueSupportDir)/Mihomo/menu_icon@2x_bak.png"
    }

    /// 新图标路径
    static var newIcon: String {
        "\(netcueSupportDir)/Mihomo/menu_icon@2x.png"
    }

    /// 配置目录
    static var configDirectory: String {
        "\(netcueSupportDir)/Mihomo"
    }
}
