//
//  MihomoViewModel.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/30.
//

import Foundation
import Observation
import AppKit

/// Mihomo 管理视图模型
@MainActor
@Observable
final class MihomoViewModel {

    // MARK: - Published Properties

    // 状态
    var hostAppInstallStatus: HostAppInstallStatus = .unknown
    var kernelStatus: KernelStatus?
    var isHostAppRunning = false

    // 配置
    var config: MihomoConfig = .default

    // 加载状态
    var isLoading = false
    var isRefreshing = false

    // 内核下载状态
    var isDownloading = false
    var downloadProgress: Double = 0.0
    var downloadStatusText: String = ""

    // 选择器防重入
    var isSelectingHostApp = false
    var isSelectingKernelFile = false

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
        refreshStatus()
    }

    /// 重置配置
    ///
    /// 仅重置内核路径、下载源等"配置"卡片管理的字段，不影响在"设置"页面
    /// 关联的应用（那是另一个入口管理的状态，语义上不应被这里的重置波及）。
    func resetConfig() {
        AppLogger.debug("重置 Mihomo 配置")

        var updated = configService.loadConfig()
        updated.kernelPath = MihomoConfig.default.kernelPath
        updated.githubReleasesURL = MihomoConfig.default.githubReleasesURL
        updated.kernelFilenameTemplate = MihomoConfig.default.kernelFilenameTemplate
        configService.saveConfig(updated)

        config.kernelPath = updated.kernelPath
        config.githubReleasesURL = updated.githubReleasesURL
        config.kernelFilenameTemplate = updated.kernelFilenameTemplate

        Toast.success("配置已重置")
        AppLogger.info("Mihomo 配置重置成功")
        refreshStatus()
    }

    // MARK: - 关联应用

    /// 选择关联应用（弹出访达，自动读取 Bundle Identifier 与显示名）
    ///
    /// 只持久化关联应用的三个字段，不会连带保存 `config` 中其它
    /// 尚未点击"保存配置"确认的编辑（如内核路径草稿）。
    func selectHostApp() {
        guard !isSelectingHostApp else { return }
        isSelectingHostApp = true
        AppLogger.debug("打开应用选择对话框")

        Task {
            defer { isSelectingHostApp = false }

            let urls = await FilePanelHelper.selectApplications(
                allowMultiple: false,
                message: "选择关联的 Clash/Mihomo 客户端"
            )

            guard let url = urls.first else {
                AppLogger.debug("取消选择关联应用")
                return
            }

            guard let bundle = Bundle(url: url), let bundleIdentifier = bundle.bundleIdentifier else {
                Toast.error("无法读取该应用的信息，请确认选择的是有效的 App")
                AppLogger.error("读取应用 Bundle 信息失败: \(url.path)")
                return
            }

            let displayName = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent

            var persisted = configService.loadConfig()
            persisted.appBundlePath = url.path
            persisted.appBundleIdentifier = bundleIdentifier
            persisted.appDisplayName = displayName
            configService.saveConfig(persisted)

            config.appBundlePath = persisted.appBundlePath
            config.appBundleIdentifier = persisted.appBundleIdentifier
            config.appDisplayName = persisted.appDisplayName

            Toast.success("已关联 \(displayName)")
            AppLogger.info("已关联应用: \(displayName) (\(bundleIdentifier))")

            refreshStatus()
        }
    }

    /// 取消关联应用
    ///
    /// 同样只清空持久化配置里的关联应用字段，不动其它未保存的草稿。
    func clearHostApp() {
        AppLogger.debug("取消关联应用")

        var persisted = configService.loadConfig()
        persisted.appBundlePath = ""
        persisted.appBundleIdentifier = ""
        persisted.appDisplayName = ""
        configService.saveConfig(persisted)

        config.appBundlePath = ""
        config.appBundleIdentifier = ""
        config.appDisplayName = ""

        Toast.success("已取消关联")
        AppLogger.info("已取消关联应用")

        refreshStatus()
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

            hostAppInstallStatus = fileService.checkHostAppInstallation(appBundlePath: config.appBundlePath)
            kernelStatus = fileService.getKernelStatus(kernelPath: config.kernelPath)
            isHostAppRunning = processService.isHostAppRunning(
                bundleIdentifier: config.appBundleIdentifier,
                displayName: config.appDisplayName
            )

            isRefreshing = false
            AppLogger.info("Mihomo 状态刷新完成")
        }
    }

    // MARK: - 内核操作

    /// 备份内核
    ///
    /// 与替换/恢复内核使用同一套"软确认"策略：关联应用未配置则跳过检查，
    /// 已配置且正在运行则弹窗请求退出，而不是像旧版那样直接硬性拒绝操作。
    func backupKernel() {
        AppLogger.debug("开始备份内核操作")
        isLoading = true

        // 在启动异步流程前拍下配置快照，避免用户在操作进行期间于界面上
        // 修改内核路径/关联应用，导致同一次操作里读到两份不一致的配置。
        let snapshot = config

        Task {
            do {
                let canProceed = try await ensureHostAppQuitIfRunning(
                    bundleIdentifier: snapshot.appBundleIdentifier,
                    displayName: snapshot.appDisplayName
                )
                guard canProceed else {
                    isLoading = false
                    return
                }

                try fileService.backupKernel(kernelPath: snapshot.kernelPath)
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
    /// 1. 检查内核文件路径是否已配置
    /// 2. 检查关联应用是否运行（运行则请求退出）
    /// 3. 从 GitHub 获取最新预发布版本并下载、替换
    func replaceKernel() {
        guard !config.kernelPath.isEmpty else {
            Toast.error("请先在下方配置内核文件路径")
            return
        }

        AppLogger.info("开始下载并替换内核")
        isDownloading = true
        downloadProgress = 0.0
        downloadStatusText = "正在获取版本信息..."

        // 拍下快照：下载耗时可能长达数秒，期间界面上的内核路径/下载源等
        // 字段仍可编辑，必须固定用同一份配置贯穿整个流程，不能中途改读。
        let snapshot = config

        Task {
            do {
                let canProceed = try await ensureHostAppQuitIfRunning(
                    bundleIdentifier: snapshot.appBundleIdentifier,
                    displayName: snapshot.appDisplayName,
                    onWaiting: { [weak self] in self?.downloadStatusText = "等待应用退出..." }
                )
                guard canProceed else {
                    isDownloading = false
                    downloadStatusText = ""
                    return
                }

                try await downloadAndReplaceKernel(config: snapshot)
                downloadService.cleanupTemporaryFiles()
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

    /// 从 GitHub 下载最新预发布内核并替换当前内核文件
    /// - Parameter config: 操作开始时拍下的配置快照（而非实时读取 `self.config`）
    private func downloadAndReplaceKernel(config: MihomoConfig) async throws {
        downloadStatusText = "正在下载内核..."
        let targetFilename = URL(fileURLWithPath: config.kernelPath).lastPathComponent

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
        try await fileService.replaceKernel(with: downloadedPath, kernelPath: config.kernelPath)
    }

    /// 恢复内核
    func restoreKernel() {
        AppLogger.debug("开始恢复内核操作")
        isLoading = true

        let snapshot = config

        Task {
            do {
                let canProceed = try await ensureHostAppQuitIfRunning(
                    bundleIdentifier: snapshot.appBundleIdentifier,
                    displayName: snapshot.appDisplayName
                )
                guard canProceed else {
                    isLoading = false
                    return
                }

                try await fileService.restoreKernel(kernelPath: snapshot.kernelPath)
                refreshStatus()

                Toast.success("内核恢复成功")
                AppLogger.info("内核恢复操作完成")
            } catch {
                handleError(error)
            }

            isLoading = false
        }
    }

    /// 若关联应用正在运行，弹窗请求用户退出并等待其退出
    ///
    /// - Parameters:
    ///   - bundleIdentifier: 关联应用的 Bundle Identifier（快照值，非实时读取）
    ///   - displayName: 关联应用的显示名称（快照值，非实时读取）
    ///   - onWaiting: 用户同意退出、开始等待前的回调（用于更新调用方特定的提示文案）
    /// - Returns: true 表示可以继续后续操作（未运行，或已确认退出并等到）；false 表示用户取消
    private func ensureHostAppQuitIfRunning(
        bundleIdentifier: String,
        displayName: String,
        onWaiting: (() -> Void)? = nil
    ) async throws -> Bool {
        guard processService.isHostAppRunning(bundleIdentifier: bundleIdentifier, displayName: displayName) else {
            return true
        }

        AppLogger.debug("关联应用正在运行，请求退出")
        let shouldContinue = await processService.requestQuitHostApp(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName
        )
        guard shouldContinue else {
            AppLogger.info("用户取消退出关联应用，操作中止")
            return false
        }

        onWaiting?()
        try await processService.waitForHostAppToQuit(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName
        )
        return true
    }

    // MARK: - 内核路径选择

    /// 选择内核文件路径（弹出访达）
    func selectKernelFile() {
        guard !isSelectingKernelFile else { return }
        isSelectingKernelFile = true
        AppLogger.debug("打开内核文件选择对话框")

        Task {
            defer { isSelectingKernelFile = false }

            let defaultDirectory = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
            let urls = await FilePanelHelper.selectFiles(
                allowedTypes: [],
                allowMultiple: false,
                directoryURL: defaultDirectory,
                message: "选择内核文件"
            )

            guard let url = urls.first else {
                AppLogger.debug("取消选择内核文件")
                return
            }

            config.kernelPath = url.path
            AppLogger.info("已选择内核文件: \(url.path)")
        }
    }

    // MARK: - 辅助方法

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
