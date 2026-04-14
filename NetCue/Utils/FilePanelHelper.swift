//
//  FilePanelHelper.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/01/06.
//  P2-6 修复：优化文件选择面板
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 文件选择面板辅助工具
///
/// ## 设计说明
///
/// ### 为什么使用 NSOpenPanel 而不是 SwiftUI .fileImporter？
///
/// **技术限制**：
/// - `.fileImporter` 无法设置初始目录（Apple API 限制）
/// - 本项目需要默认打开 `/Applications` 目录以优化用户体验
/// - 应用选择场景下，用户期望直接看到应用列表
///
/// **架构优势**：
/// - 通过 `async/await` 包装消除阻塞问题
/// - 使用 `panel.begin()` 替代 `panel.runModal()`（非阻塞）
/// - 符合 Swift 6 并发安全规范（@MainActor 隔离）
/// - 类型安全的错误处理
///
/// ## 使用示例
///
/// ```swift
/// // 选择单个应用
/// let urls = await FilePanelHelper.selectApplications(allowMultiple: false)
///
/// // 选择多个应用
/// let urls = await FilePanelHelper.selectApplications(
///     allowMultiple: true,
///     message: "选择要控制的应用"
/// )
///
/// // 自定义文件类型选择
/// let files = await FilePanelHelper.selectFiles(
///     allowedTypes: [.json, .xml],
///     allowMultiple: true,
///     directoryURL: FileManager.default.homeDirectoryForCurrentUser
/// )
/// ```
///
/// ## 最佳实践
///
/// - 所有方法都是 `async` 的，确保不阻塞主线程
/// - 用户取消选择时返回空数组（而非抛出错误）
/// - 使用 `@MainActor` 确保 UI 操作在主线程
@MainActor
enum FilePanelHelper {

    // MARK: - Public Methods

    /// 选择应用程序
    ///
    /// ## 功能说明
    /// - 默认打开 `/Applications` 目录
    /// - 仅允许选择 `.app` 文件
    /// - 支持单选/多选
    ///
    /// ## 参数
    /// - allowMultiple: 是否允许多选（默认 true）
    /// - message: 面板提示信息
    ///
    /// ## 返回值
    /// - 选中的应用 URL 数组
    /// - 用户取消时返回空数组
    ///
    /// ## 使用场景
    /// - 场景配置中选择控制应用
    /// - 启动项管理
    /// - 应用白名单配置
    static func selectApplications(
        allowMultiple: Bool = true,
        message: String = "选择要控制的应用"
    ) async -> [URL] {
        return await selectFiles(
            allowedTypes: [.application],
            allowMultiple: allowMultiple,
            directoryURL: URL(fileURLWithPath: "/Applications"),
            message: message
        )
    }

    /// 通用文件选择方法
    ///
    /// ## 功能说明
    /// - 支持任意文件类型
    /// - 支持自定义初始目录
    /// - 非阻塞式异步调用
    ///
    /// ## 参数
    /// - allowedTypes: 允许的文件类型数组（如 [.json, .xml]）
    /// - allowMultiple: 是否允许多选（默认 false）
    /// - directoryURL: 初始目录（默认用户主目录）
    /// - message: 面板提示信息（可选）
    ///
    /// ## 返回值
    /// - 选中的文件 URL 数组
    /// - 用户取消时返回空数组
    ///
    /// ## 使用场景
    /// - 导入配置文件
    /// - 选择数据库文件
    /// - 任意文件选择需求
    static func selectFiles(
        allowedTypes: [UTType],
        allowMultiple: Bool = false,
        directoryURL: URL? = nil,
        message: String? = nil
    ) async -> [URL] {
        return await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()

            // 基础配置
            panel.allowsMultipleSelection = allowMultiple
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowedContentTypes = allowedTypes

            // 可选配置
            if let directory = directoryURL {
                panel.directoryURL = directory
            }

            if let msg = message {
                panel.message = msg
            }

            // 非阻塞式调用
            panel.begin { response in
                if response == .OK {
                    continuation.resume(returning: panel.urls)
                } else {
                    // 用户取消或错误，返回空数组
                    continuation.resume(returning: [])
                }
            }
        }
    }

    /// 选择目录
    ///
    /// ## 功能说明
    /// - 仅允许选择目录（不允许选择文件）
    /// - 支持单选/多选
    ///
    /// ## 参数
    /// - allowMultiple: 是否允许多选（默认 false）
    /// - directoryURL: 初始目录（可选）
    /// - message: 面板提示信息（可选）
    ///
    /// ## 返回值
    /// - 选中的目录 URL 数组
    /// - 用户取消时返回空数组
    ///
    /// ## 使用场景
    /// - 选择导出目录
    /// - 选择工作目录
    /// - 目录路径配置
    static func selectDirectory(
        allowMultiple: Bool = false,
        directoryURL: URL? = nil,
        message: String? = nil
    ) async -> [URL] {
        return await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()

            // 目录选择配置
            panel.allowsMultipleSelection = allowMultiple
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true

            // 可选配置
            if let directory = directoryURL {
                panel.directoryURL = directory
            }

            if let msg = message {
                panel.message = msg
            }

            // 非阻塞式调用
            panel.begin { response in
                if response == .OK {
                    continuation.resume(returning: panel.urls)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("FilePanelHelper 使用示例") {
    VStack(spacing: 16) {
        Text("FilePanelHelper 演示")
            .font(.title)

        Button("选择单个应用") {
            Task {
                let urls = await FilePanelHelper.selectApplications(allowMultiple: false)
                print("选中应用: \(urls.map { $0.lastPathComponent })")
            }
        }
        .buttonStyle(.borderedProminent)

        Button("选择多个应用") {
            Task {
                let urls = await FilePanelHelper.selectApplications()
                print("选中应用: \(urls.map { $0.lastPathComponent })")
            }
        }
        .buttonStyle(.borderedProminent)

        Button("选择 JSON 文件") {
            Task {
                let urls = await FilePanelHelper.selectFiles(
                    allowedTypes: [.json],
                    message: "选择配置文件"
                )
                print("选中文件: \(urls.map { $0.lastPathComponent })")
            }
        }
        .buttonStyle(.borderedProminent)

        Button("选择目录") {
            Task {
                let urls = await FilePanelHelper.selectDirectory(
                    message: "选择导出目录"
                )
                print("选中目录: \(urls.map { $0.path })")
            }
        }
        .buttonStyle(.borderedProminent)
    }
    .padding()
    .frame(width: 400, height: 400)
}
