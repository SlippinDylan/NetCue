//
//  MihomoViewModel.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/30.
//

import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

/// Mihomo 管理视图模型
@MainActor
@Observable
final class MihomoViewModel {

    // MARK: - Published Properties

    // 状态
    var clashXMetaInstallStatus: ClashXMetaInstallStatus = .unknown
    var kernelStatus: KernelStatus?
    var iconStatus: IconStatus?
    var isClashXMetaRunning = false

    // 配置
    var config: MihomoConfig = .default

    // 加载状态
    var isLoading = false
    var isRefreshing = false

    // 内核下载状态
    var isDownloading = false
    var downloadProgress: Double = 0.0
    var downloadStatusText: String = ""

    // MARK: - Services

    private let fileService = MihomoFileService()
    private let downloadService = MihomoDownloadService()
    private let processService = MihomoProcessService()
    private let configService = MihomoConfigService()

    // MARK: - Initialization

    init() {
        loadConfig()
        refreshStatus()
    }

    // MARK: - 配置管理

    /// 加载配置
    func loadConfig() {
        AppLogger.debug("加载 Mihomo 配置")
        config = configService.loadConfig()
    }

    /// 保存配置
    func saveConfig() {
        AppLogger.debug("保存 Mihomo 配置")
        configService.saveConfig(config)
        Toast.success("配置已保存")
        AppLogger.info("Mihomo 配置保存成功")
    }

    /// 重置配置
    func resetConfig() {
        AppLogger.debug("重置 Mihomo 配置")
        configService.resetToDefault()
        config = .default
        Toast.success("配置已重置")
        AppLogger.info("Mihomo 配置重置成功")
    }

    // MARK: - 状态刷新

    /// 刷新所有状态
    func refreshStatus() {
        guard !isRefreshing else { return }

        isRefreshing = true
        AppLogger.debug("刷新 Mihomo 状态")

        Task {
            // 模拟短暂延迟，让用户看到加载动画
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3秒

            clashXMetaInstallStatus = fileService.checkClashXMetaInstallation()
            kernelStatus = fileService.getKernelStatus()
            iconStatus = fileService.getIconStatus()
            isClashXMetaRunning = processService.isClashXMetaRunning()

            isRefreshing = false
            AppLogger.info("Mihomo 状态刷新完成")
        }
    }

    // MARK: - 内核操作

    /// 备份内核
    func backupKernel() {
        AppLogger.debug("开始备份内核操作")
        isLoading = true

        Task {
            do {
                // 检查 ClashX.Meta 是否正在运行
                try processService.checkCanPerformSudoOperations()

                // 执行备份
                try fileService.backupKernel()

                // 刷新状态
                refreshStatus()

                Toast.success("内核备份成功")
                AppLogger.info("内核备份操作完成")
            } catch {
                handleError(error)
            }

            isLoading = false
        }
    }

    /// 替换内核（从 GitHub 自动下载最新预发布版本）
    ///
    /// ## 流程
    /// 1. 检查 ClashX.Meta 是否运行（运行则请求退出）
    /// 2. 从 GitHub 获取最新预发布版本
    /// 3. 下载匹配的内核文件（.gz 格式）
    /// 4. 解压并重命名
    /// 5. 执行替换操作
    func replaceKernel() {
        AppLogger.info("开始下载并替换内核")
        isDownloading = true
        downloadProgress = 0.0
        downloadStatusText = "正在获取版本信息..."

        Task {
            do {
                // 检查 ClashX.Meta 是否正在运行
                if processService.isClashXMetaRunning() {
                    AppLogger.debug("ClashX.Meta 正在运行，请求退出")
                    let shouldContinue = await processService.requestQuitClashXMeta()
                    if !shouldContinue {
                        AppLogger.info("用户取消退出 ClashX.Meta，操作中止")
                        isDownloading = false
                        downloadStatusText = ""
                        return
                    }
                    downloadStatusText = "等待应用退出..."
                    try await waitForAppToQuit()
                }

                // 下载内核
                downloadStatusText = "正在下载内核..."
                let targetFilename = "com.metacubex.ClashX.ProxyConfigHelper.meta"

                let downloadedPath = try await downloadService.downloadLatestKernel(
                    releasesURL: config.githubReleasesURL,
                    filenameTemplate: config.kernelFilenameTemplate,
                    targetFilename: targetFilename
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.downloadProgress = progress
                        if progress < 1.0 {
                            self.downloadStatusText = "正在下载... \(Int(progress * 100))%"
                        } else {
                            self.downloadStatusText = "正在解压..."
                        }
                    }
                }

                AppLogger.info("内核下载完成: \(downloadedPath)")
                downloadStatusText = "正在替换内核..."

                // 执行替换
                try await fileService.replaceKernel(with: downloadedPath)

                // 清理临时文件
                downloadService.cleanupTemporaryFiles()

                // 刷新状态
                refreshStatus()

                isDownloading = false
                downloadProgress = 0.0
                downloadStatusText = ""
                Toast.success("内核替换成功")
                AppLogger.info("内核替换操作完成")
            } catch {
                isDownloading = false
                downloadProgress = 0.0
                downloadStatusText = ""
                downloadService.cleanupTemporaryFiles()
                handleError(error)
            }
        }
    }

    /// 恢复内核
    func restoreKernel() {
        AppLogger.debug("开始恢复内核操作")
        isLoading = true

        Task {
            do {
                // 检查 ClashX.Meta 是否正在运行
                if processService.isClashXMetaRunning() {
                    AppLogger.debug("ClashX.Meta 正在运行，请求退出")
                    let shouldContinue = await processService.requestQuitClashXMeta()
                    if !shouldContinue {
                        AppLogger.info("用户取消退出 ClashX.Meta，操作中止")
                        isLoading = false
                        return
                    }
                    try await waitForAppToQuit()
                }

                // 执行恢复
                try await fileService.restoreKernel()

                // 刷新状态
                refreshStatus()

                Toast.success("内核恢复成功")
                AppLogger.info("内核恢复操作完成")
            } catch {
                handleError(error)
            }

            isLoading = false
        }
    }

    // MARK: - 图标操作

    /// 备份图标
    func backupIcon() {
        AppLogger.debug("开始备份图标操作")
        isLoading = true

        Task {
            do {
                // 检查 ClashX.Meta 是否正在运行
                try processService.checkCanPerformSudoOperations()

                // 执行备份
                try fileService.backupIcon()

                // 刷新状态
                refreshStatus()

                Toast.success("图标备份成功")
                AppLogger.info("图标备份操作完成")
            } catch {
                handleError(error)
            }

            isLoading = false
        }
    }

    /// 替换图标（先选择文件，再执行替换）
    ///
    /// 使用 macOS 12+ 的 `panel.begin()` async API 替代阻塞式 `runModal()`
    func replaceIcon() {
        AppLogger.debug("打开图标文件选择对话框")

        Task {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowedContentTypes = [.png]
            panel.message = "选择图标文件（PNG格式）"
            panel.prompt = "选择并替换"

            let response = await panel.begin()
            guard response == .OK, let url = panel.url else {
                AppLogger.debug("取消选择图标文件")
                return
            }

            let iconPath = url.path
            AppLogger.info("已选择图标文件: \(iconPath)")
            AppLogger.debug("开始替换图标操作: \(iconPath)")
            isLoading = true

            do {
                // 检查 ClashX.Meta 是否正在运行
                if processService.isClashXMetaRunning() {
                    AppLogger.debug("ClashX.Meta 正在运行，请求退出")
                    let shouldContinue = await processService.requestQuitClashXMeta()
                    if !shouldContinue {
                        AppLogger.info("用户取消退出 ClashX.Meta，操作中止")
                        isLoading = false
                        return
                    }
                    try await waitForAppToQuit()
                }

                // 执行替换
                try await fileService.replaceIcon(with: iconPath)

                // 刷新状态
                refreshStatus()

                Toast.success("图标替换成功")
                AppLogger.info("图标替换操作完成")
            } catch {
                handleError(error)
            }

            isLoading = false
        }
    }

    /// 恢复图标
    func restoreIcon() {
        AppLogger.debug("开始恢复图标操作")
        isLoading = true

        Task {
            do {
                // 检查 ClashX.Meta 是否正在运行
                if processService.isClashXMetaRunning() {
                    AppLogger.debug("ClashX.Meta 正在运行，请求退出")
                    let shouldContinue = await processService.requestQuitClashXMeta()
                    if !shouldContinue {
                        AppLogger.info("用户取消退出 ClashX.Meta，操作中止")
                        isLoading = false
                        return
                    }
                    try await waitForAppToQuit()
                }

                // 执行恢复
                try await fileService.restoreIcon()

                // 刷新状态
                refreshStatus()

                Toast.success("图标恢复成功")
                AppLogger.info("图标恢复操作完成")
            } catch {
                handleError(error)
            }

            isLoading = false
        }
    }

    // MARK: - 辅助方法

    /// 等待 ClashX.Meta 应用退出
    /// - Parameter maxWaitTime: 最大等待时间（秒），默认10秒
    /// - Throws: MihomoError.appQuitTimeout 如果超时
    private func waitForAppToQuit(maxWaitTime: TimeInterval = 10.0) async throws {
        try await processService.waitForClashXMetaToQuit(maxWaitTime: maxWaitTime)
    }

    /// 打开 GitHub Releases 页面
    func openGitHubReleases() {
        AppLogger.debug("打开 GitHub Releases 页面: \(config.githubReleasesURL)")
        if let url = URL(string: config.githubReleasesURL) {
            NSWorkspace.shared.open(url)
            AppLogger.info("已打开 GitHub Releases 页面")
        } else {
            AppLogger.error("打开 GitHub Releases 失败: URL 无效")
        }
    }

    /// 处理错误
    private func handleError(_ error: Error) {
        let message: String
        if let mihomoError = error as? MihomoError {
            message = mihomoError.errorDescription ?? "未知错误"
        } else if error is CancellationError {
            message = "操作已取消"
        } else {
            message = error.localizedDescription
        }
        Toast.error(message)
        AppLogger.error("操作失败: \(message)")
    }
}
