//
//  PlatformVersion.swift
//  NetCue
//
//  Created for macOS 15+ / macOS 26+ dual-version support.
//

import Foundation

/// 平台版本检测工具
///
/// ## 设计说明
/// 提供运行时版本检测，用于在 macOS 15 和 macOS 26 之间动态切换功能和 UI。
///
/// ## 使用场景
/// - UI 组件需要根据系统版本使用不同的样式
/// - 某些 API 仅在特定版本可用时的条件调用
///
/// ## 注意事项
/// - 所有检测都是运行时检测（`#available`），不是编译时检测
/// - 编译时需要将 Deployment Target 设置为 macOS 15.0
enum PlatformVersion {

    // MARK: - Version Checks

    /// 是否运行在 macOS 26 (Tahoe) 或更高版本
    ///
    /// macOS 26 引入了 Liquid Glass 设计语言和多项新 API：
    /// - `.glassEffect()` 材质
    /// - `.buttonStyle(.glass)` 和 `.buttonStyle(.glassProminent)`
    /// - 原生 SwiftUI WebView
    /// - 原生富文本编辑器
    /// - List/ScrollView 性能提升
    static var isTahoeOrLater: Bool {
        if #available(macOS 26, *) {
            return true
        }
        return false
    }

    /// 是否运行在 macOS 15 (Sequoia) 或更高版本
    ///
    /// macOS 15 是本项目的最低支持版本。
    /// 此检测主要用于防御性编程，确保不会在更低版本运行。
    static var isSequoiaOrLater: Bool {
        if #available(macOS 15, *) {
            return true
        }
        return false
    }

    // MARK: - Debug Info

    /// 当前系统版本描述（用于日志和调试）
    static var currentVersionDescription: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"

        if isTahoeOrLater {
            return "macOS \(versionString) (Tahoe+)"
        } else {
            return "macOS \(versionString) (Sequoia)"
        }
    }
}
