//
//  MihomoFileService.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/30.
//
//  ## 2026/01/08 重构
//  - 使用 NSWorkspace.Authorization + FileManager 原生 API
//  - 一次授权，多次操作，仅需输入一次密码
//  - 完全移除 Shell 调用
//

import Foundation

/// Mihomo 文件操作服务
///
/// ## 架构说明
/// - 状态检查：使用普通 FileManager（无需特权）
/// - 备份操作：使用普通 FileManager（用户目录无需特权）
/// - 替换/恢复操作：使用 AuthorizedSession（一次授权，多次操作）
///
/// ## 密码输入优化
/// 重构前：每次文件操作都弹出密码框（4-5次）
/// 重构后：整个操作流程仅弹出一次密码框
final class MihomoFileService: Sendable {
    private let fileManager = FileManager.default
    private let configService = MihomoConfigService()
    private let privilegedService = PrivilegedFileOperationService()

    // MARK: - 状态检查

    /// 检查 ClashX.Meta 是否已安装
    func checkClashXMetaInstallation() -> ClashXMetaInstallStatus {
        AppLogger.debug("检查 ClashX.Meta 安装状态")
        if fileManager.fileExists(atPath: MihomoPaths.clashXMetaApp) {
            AppLogger.info("ClashX.Meta 已安装")
            return .installed
        } else {
            AppLogger.info("ClashX.Meta 未安装")
            return .notInstalled
        }
    }

    /// 获取内核状态
    func getKernelStatus() -> KernelStatus {
        AppLogger.debug("获取内核状态")
        let config = configService.loadConfig()
        let kernelPath = config.kernelPath
        let backupPath = kernelPath + ".bak"

        let kernelExists = fileManager.fileExists(atPath: kernelPath)
        let backupExists = fileManager.fileExists(atPath: backupPath)

        AppLogger.info("内核状态: 内核存在=\(kernelExists), 备份存在=\(backupExists)")
        return KernelStatus(
            kernelExists: kernelExists,
            backupExists: backupExists,
            kernelPath: kernelPath,
            backupPath: backupPath
        )
    }

    /// 获取图标状态
    func getIconStatus() -> IconStatus {
        AppLogger.debug("获取图标状态")
        let config = configService.loadConfig()
        let iconPath = config.iconPath

        let iconExists = fileManager.fileExists(atPath: iconPath)
        let backupExists = fileManager.fileExists(atPath: MihomoPaths.iconBackup)
        let newIconExists = fileManager.fileExists(atPath: MihomoPaths.newIcon)

        AppLogger.info("图标状态: 图标存在=\(iconExists), 备份存在=\(backupExists), 新图标存在=\(newIconExists)")
        return IconStatus(
            iconExists: iconExists,
            backupExists: backupExists,
            newIconExists: newIconExists,
            iconPath: iconPath,
            backupPath: MihomoPaths.iconBackup,
            newIconPath: MihomoPaths.newIcon
        )
    }

    // MARK: - 内核操作

    /// 备份内核文件（无需特权，使用普通 FileManager）
    ///
    /// - Throws: MihomoError
    ///
    /// ## 说明
    /// 备份操作将内核文件复制到用户目录，无需管理员权限。
    func backupKernel() throws {
        AppLogger.debug("开始备份内核文件")
        let config = configService.loadConfig()
        let kernelPath = config.kernelPath
        let backupPath = kernelPath + ".bak"

        // 1. 检查内核文件是否存在
        guard fileManager.fileExists(atPath: kernelPath) else {
            AppLogger.error("备份内核失败: 内核文件不存在")
            throw MihomoError.kernelFileNotFound
        }

        // 2. 检查备份是否已存在
        if fileManager.fileExists(atPath: backupPath) {
            AppLogger.warning("备份内核失败: 备份文件已存在")
            throw MihomoError.backupAlreadyExists
        }

        // 3. 执行备份
        do {
            let sourceURL = URL(fileURLWithPath: kernelPath)
            let destinationURL = URL(fileURLWithPath: backupPath)

            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            try preserveFilePermissions(from: sourceURL, to: destinationURL)
            AppLogger.info("内核文件备份成功")
        } catch let error as NSError {
            AppLogger.error("备份内核失败: \(error.localizedDescription)")
            throw MihomoError.fileOperationFailed("备份内核失败: \(error.localizedDescription)")
        }
    }

    /// 替换内核文件（两阶段提交，单次授权）
    ///
    /// - Parameter newKernelPath: 新内核文件路径
    /// - Throws: MihomoError
    ///
    /// ## 实现说明
    /// 使用两阶段提交（Two-Phase Commit）保证原子性：
    ///
    /// ### 阶段 1：准备（Prepare）
    /// 1. **获取授权**（弹出一次密码框）
    /// 2. 验证新文件存在
    /// 3. 备份原文件 → `{kernel}.bak`
    /// 4. 写入新文件 → `{kernel}.new`（临时）
    /// 5. 验证新文件完整性
    ///
    /// ### 阶段 2：提交（Commit）
    /// 6. 删除旧内核
    /// 7. 原子重命名：`.new` → 实际路径
    ///
    /// ## 关键优势
    /// - ✅ **单次授权**：整个流程仅需一次密码输入
    /// - ✅ **原子性**：`rename()` 是原子操作
    /// - ✅ **崩溃安全**：任何阶段失败都可回滚
    @MainActor
    func replaceKernel(with newKernelPath: String) async throws {
        AppLogger.debug("开始替换内核文件（两阶段提交）: \(newKernelPath)")

        // 0. 验证路径安全性
        try validateFilePath(newKernelPath)

        let config = configService.loadConfig()
        let kernelPath = config.kernelPath
        let backupPath = kernelPath + ".bak"
        let tempPath = kernelPath + ".new"

        // === 获取授权（仅此一次弹出密码框）===
        AppLogger.info("请求管理员授权...")
        let session: AuthorizedSession
        do {
            session = try await privilegedService.createAuthorizedSession()
        } catch {
            AppLogger.error("获取授权失败: \(error.localizedDescription)")
            throw MihomoError.fileOperationFailed("获取授权失败: \(error.localizedDescription)")
        }

        // === 阶段 1：准备（Prepare）===
        AppLogger.debug("阶段 1/2: 准备新内核文件")

        do {
            // 1.1 验证新内核文件存在
            guard fileManager.fileExists(atPath: newKernelPath) else {
                AppLogger.error("新内核文件不存在: \(newKernelPath)")
                throw MihomoError.invalidFilePath
            }

            // 1.2 备份原内核（如果尚未备份）
            if fileManager.fileExists(atPath: kernelPath) {
                if !fileManager.fileExists(atPath: backupPath) {
                    AppLogger.debug("备份原内核 → \(backupPath)")
                    try backupKernel()
                } else {
                    AppLogger.debug("备份已存在，跳过备份")
                }
            }

            // 1.3 清理残留临时文件（如果存在）
            if fileManager.fileExists(atPath: tempPath) {
                AppLogger.warning("临时文件已存在（可能是上次操作失败残留），删除: \(tempPath)")
                try session.removeItem(at: tempPath)
            }

            // 1.4 在源文件位置预设权限（临时目录可写，无需授权）
            //     复制时权限会被保留，避免在受保护目录中调用 setAttributes
            AppLogger.debug("预设源文件权限: 0o755")
            try setPermissionsBeforeCopy(at: newKernelPath, permissions: 0o755)

            // 1.5 复制新内核到临时路径（权限已随文件复制）
            AppLogger.debug("复制新内核到临时路径: \(tempPath)")
            try session.copyItem(from: newKernelPath, to: tempPath)

            // 1.6 验证新文件完整性
            let newFileSize = try fileManager.attributesOfItem(atPath: newKernelPath)[.size] as? UInt64 ?? 0
            let tempFileSize = try fileManager.attributesOfItem(atPath: tempPath)[.size] as? UInt64 ?? 0

            guard newFileSize == tempFileSize, newFileSize > 0 else {
                AppLogger.error("临时文件完整性验证失败: 原始大小=\(newFileSize), 临时大小=\(tempFileSize)")
                try? session.removeItem(at: tempPath)
                throw MihomoError.fileOperationFailed("新内核文件完整性验证失败")
            }

            AppLogger.info("阶段 1 完成: 新内核准备就绪（大小=\(tempFileSize) bytes）")

            // === 阶段 2：提交（Commit）===
            AppLogger.debug("阶段 2/2: 原子替换内核文件")

            // 2.1 删除旧内核（如果存在）
            if fileManager.fileExists(atPath: kernelPath) {
                AppLogger.debug("删除旧内核: \(kernelPath)")
                try session.removeItem(at: kernelPath)
            }

            // 2.2 原子重命名：.new → 实际路径
            AppLogger.debug("原子重命名: \(tempPath) → \(kernelPath)")
            try session.moveItem(from: tempPath, to: kernelPath)

            AppLogger.info("✅ 内核文件替换成功（两阶段提交完成）")

        } catch {
            // 失败回滚
            AppLogger.error("内核替换失败，开始回滚: \(error.localizedDescription)")

            if fileManager.fileExists(atPath: tempPath) {
                AppLogger.debug("清理临时文件: \(tempPath)")
                try? session.removeItem(at: tempPath)
            }

            // 如果原文件已被删除但临时文件移动失败，尝试从备份恢复
            if !fileManager.fileExists(atPath: kernelPath) && fileManager.fileExists(atPath: backupPath) {
                AppLogger.warning("原文件已丢失，尝试从备份恢复")
                do {
                    try await restoreKernel(with: session)
                    AppLogger.info("已从备份恢复原内核")
                } catch {
                    AppLogger.error("备份恢复失败: \(error.localizedDescription)")
                }
            }

            // 重新抛出原始错误
            if let mihomoError = error as? MihomoError {
                throw mihomoError
            } else if let privError = error as? PrivilegedOperationError {
                throw MihomoError.fileOperationFailed("替换内核失败: \(privError.localizedDescription)")
            } else {
                throw MihomoError.fileOperationFailed("替换内核失败: \(error.localizedDescription)")
            }
        }
    }

    /// 恢复内核文件（单次授权）
    ///
    /// - Throws: MihomoError
    @MainActor
    func restoreKernel() async throws {
        AppLogger.debug("开始恢复内核文件")

        // 获取授权
        let session = try await privilegedService.createAuthorizedSession()
        try await restoreKernel(with: session)
    }

    /// 使用已有授权会话恢复内核文件
    ///
    /// - Parameter session: 授权会话
    /// - Throws: MihomoError
    private func restoreKernel(with session: AuthorizedSession) async throws {
        let config = configService.loadConfig()
        let kernelPath = config.kernelPath
        let backupPath = kernelPath + ".bak"

        // 1. 检查备份是否存在
        guard fileManager.fileExists(atPath: backupPath) else {
            AppLogger.error("恢复内核失败: 备份文件不存在")
            throw MihomoError.backupNotFound
        }

        // 2. 恢复内核
        do {
            // 移除当前内核
            if fileManager.fileExists(atPath: kernelPath) {
                AppLogger.debug("删除当前内核")
                try session.removeItem(at: kernelPath)
            }

            // 在备份文件位置预设权限（用户目录可写，无需授权）
            AppLogger.debug("预设备份文件权限: 0o755")
            try setPermissionsBeforeCopy(at: backupPath, permissions: 0o755)

            // 复制备份文件（权限已随文件复制）
            AppLogger.debug("恢复备份内核")
            try session.copyItem(from: backupPath, to: kernelPath)

            AppLogger.info("内核文件恢复成功")
        } catch let error as PrivilegedOperationError {
            AppLogger.error("恢复内核失败: \(error.localizedDescription)")
            throw MihomoError.fileOperationFailed("恢复内核失败: \(error.localizedDescription)")
        } catch {
            AppLogger.error("恢复内核失败: \(error.localizedDescription)")
            throw MihomoError.fileOperationFailed("恢复内核失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 图标操作

    /// 备份图标文件（无需特权）
    ///
    /// - Throws: MihomoError
    func backupIcon() throws {
        AppLogger.debug("开始备份图标文件")
        let config = configService.loadConfig()
        let iconPath = config.iconPath

        // 1. 检查应用图标是否存在
        guard fileManager.fileExists(atPath: iconPath) else {
            AppLogger.error("备份图标失败: 图标文件不存在")
            throw MihomoError.iconFileNotFound
        }

        // 2. 检查备份是否已存在
        if fileManager.fileExists(atPath: MihomoPaths.iconBackup) {
            AppLogger.warning("备份图标失败: 备份文件已存在")
            throw MihomoError.backupAlreadyExists
        }

        // 3. 确保配置目录存在
        try createConfigDirectoryIfNeeded()

        // 4. 执行备份
        do {
            let sourceURL = URL(fileURLWithPath: iconPath)
            let destinationURL = URL(fileURLWithPath: MihomoPaths.iconBackup)

            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            try preserveFilePermissions(from: sourceURL, to: destinationURL)
            AppLogger.info("图标文件备份成功")
        } catch let error as NSError {
            AppLogger.error("备份图标失败: \(error.localizedDescription)")
            throw MihomoError.fileOperationFailed("备份图标失败: \(error.localizedDescription)")
        }
    }

    /// 替换图标文件（两阶段提交，单次授权）
    ///
    /// - Parameter newIconPath: 新图标文件路径
    /// - Throws: MihomoError
    @MainActor
    func replaceIcon(with newIconPath: String) async throws {
        AppLogger.debug("开始替换图标文件（两阶段提交）: \(newIconPath)")

        // 0. 验证路径安全性
        try validateFilePath(newIconPath)

        let config = configService.loadConfig()
        let iconPath = config.iconPath
        let backupPath = MihomoPaths.iconBackup
        let tempPath = iconPath + ".new"

        // === 获取授权（仅此一次弹出密码框）===
        AppLogger.info("请求管理员授权...")
        let session: AuthorizedSession
        do {
            session = try await privilegedService.createAuthorizedSession()
        } catch {
            AppLogger.error("获取授权失败: \(error.localizedDescription)")
            throw MihomoError.fileOperationFailed("获取授权失败: \(error.localizedDescription)")
        }

        // === 阶段 1：准备（Prepare）===
        AppLogger.debug("阶段 1/2: 准备新图标文件")

        do {
            // 1.1 验证新图标文件存在
            guard fileManager.fileExists(atPath: newIconPath) else {
                AppLogger.error("新图标文件不存在: \(newIconPath)")
                throw MihomoError.invalidFilePath
            }

            // 1.2 备份原图标（如果尚未备份）
            if fileManager.fileExists(atPath: iconPath) {
                if !fileManager.fileExists(atPath: backupPath) {
                    AppLogger.debug("备份原图标 → \(backupPath)")
                    try backupIcon()
                } else {
                    AppLogger.debug("备份已存在，跳过备份")
                }
            }

            // 1.3 清理残留临时文件
            if fileManager.fileExists(atPath: tempPath) {
                AppLogger.warning("临时文件已存在（可能是上次操作失败残留），删除: \(tempPath)")
                try session.removeItem(at: tempPath)
            }

            // 1.4 在源文件位置预设权限（用户选择的文件，通常可写）
            //     复制时权限会被保留，避免在受保护目录中调用 setAttributes
            AppLogger.debug("预设源文件权限: 0o644")
            try setPermissionsBeforeCopy(at: newIconPath, permissions: 0o644)

            // 1.5 复制新图标到临时路径（权限已随文件复制）
            AppLogger.debug("复制新图标到临时路径: \(tempPath)")
            try session.copyItem(from: newIconPath, to: tempPath)

            // 1.6 验证新文件完整性
            let newFileSize = try fileManager.attributesOfItem(atPath: newIconPath)[.size] as? UInt64 ?? 0
            let tempFileSize = try fileManager.attributesOfItem(atPath: tempPath)[.size] as? UInt64 ?? 0

            guard newFileSize == tempFileSize, newFileSize > 0 else {
                AppLogger.error("临时文件完整性验证失败: 原始大小=\(newFileSize), 临时大小=\(tempFileSize)")
                try? session.removeItem(at: tempPath)
                throw MihomoError.fileOperationFailed("新图标文件完整性验证失败")
            }

            AppLogger.info("阶段 1 完成: 新图标准备就绪（大小=\(tempFileSize) bytes）")

            // === 阶段 2：提交（Commit）===
            AppLogger.debug("阶段 2/2: 原子替换图标文件")

            // 2.1 删除旧图标（如果存在）
            if fileManager.fileExists(atPath: iconPath) {
                AppLogger.debug("删除旧图标: \(iconPath)")
                try session.removeItem(at: iconPath)
            }

            // 2.2 原子重命名：.new → 实际路径
            AppLogger.debug("原子重命名: \(tempPath) → \(iconPath)")
            try session.moveItem(from: tempPath, to: iconPath)

            AppLogger.info("✅ 图标文件替换成功（两阶段提交完成）")

        } catch {
            // 失败回滚
            AppLogger.error("图标替换失败，开始回滚: \(error.localizedDescription)")

            if fileManager.fileExists(atPath: tempPath) {
                AppLogger.debug("清理临时文件: \(tempPath)")
                try? session.removeItem(at: tempPath)
            }

            // 如果原文件已被删除但临时文件移动失败，尝试从备份恢复
            if !fileManager.fileExists(atPath: iconPath) && fileManager.fileExists(atPath: backupPath) {
                AppLogger.warning("原文件已丢失，尝试从备份恢复")
                do {
                    try await restoreIcon(with: session)
                    AppLogger.info("已从备份恢复原图标")
                } catch {
                    AppLogger.error("备份恢复失败: \(error.localizedDescription)")
                }
            }

            // 重新抛出原始错误
            if let mihomoError = error as? MihomoError {
                throw mihomoError
            } else if let privError = error as? PrivilegedOperationError {
                throw MihomoError.fileOperationFailed("替换图标失败: \(privError.localizedDescription)")
            } else {
                throw MihomoError.fileOperationFailed("替换图标失败: \(error.localizedDescription)")
            }
        }
    }

    /// 恢复图标文件（单次授权）
    ///
    /// - Throws: MihomoError
    @MainActor
    func restoreIcon() async throws {
        AppLogger.debug("开始恢复图标文件")

        // 获取授权
        let session = try await privilegedService.createAuthorizedSession()
        try await restoreIcon(with: session)
    }

    /// 使用已有授权会话恢复图标文件
    ///
    /// - Parameter session: 授权会话
    /// - Throws: MihomoError
    private func restoreIcon(with session: AuthorizedSession) async throws {
        let config = configService.loadConfig()
        let iconPath = config.iconPath

        // 1. 检查备份是否存在
        guard fileManager.fileExists(atPath: MihomoPaths.iconBackup) else {
            AppLogger.error("恢复图标失败: 备份文件不存在")
            throw MihomoError.backupNotFound
        }

        // 2. 恢复图标
        do {
            // 移除当前图标
            if fileManager.fileExists(atPath: iconPath) {
                AppLogger.debug("删除当前图标")
                try session.removeItem(at: iconPath)
            }

            // 在备份文件位置预设权限（用户目录可写，无需授权）
            AppLogger.debug("预设备份文件权限: 0o644")
            try setPermissionsBeforeCopy(at: MihomoPaths.iconBackup, permissions: 0o644)

            // 复制备份文件（权限已随文件复制）
            AppLogger.debug("恢复备份图标")
            try session.copyItem(from: MihomoPaths.iconBackup, to: iconPath)

            AppLogger.info("图标文件恢复成功")
        } catch let error as PrivilegedOperationError {
            AppLogger.error("恢复图标失败: \(error.localizedDescription)")
            throw MihomoError.fileOperationFailed("恢复图标失败: \(error.localizedDescription)")
        } catch {
            AppLogger.error("恢复图标失败: \(error.localizedDescription)")
            throw MihomoError.fileOperationFailed("恢复图标失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 私有辅助方法

    /// 验证文件路径安全性
    ///
    /// - Parameter path: 文件路径
    /// - Throws: MihomoError.invalidFilePath
    private func validateFilePath(_ path: String) throws {
        // 1. 检查路径是否为空
        guard !path.isEmpty else {
            throw MihomoError.invalidFilePath
        }

        // 2. 解析为标准路径（处理 ~、相对路径等）
        let expandedPath = NSString(string: path).expandingTildeInPath
        let standardPath = NSString(string: expandedPath).standardizingPath

        // 3. 检查是否包含目录遍历攻击特征 (..)
        if standardPath.contains("..") {
            throw MihomoError.invalidFilePath
        }

        // 4. 检查路径是否在允许的目录内
        let allowedPrefixes = [
            NSHomeDirectory(),
            "/Applications",
            NSTemporaryDirectory()
        ]

        let isAllowed = allowedPrefixes.contains { prefix in
            standardPath.hasPrefix(prefix)
        }

        guard isAllowed else {
            throw MihomoError.invalidFilePath
        }

        // 5. 检查路径是否指向系统关键目录（禁止访问）
        let forbiddenPrefixes = [
            "/etc",
            "/var/root",
            "/System",
            "/private/etc"
        ]

        for forbidden in forbiddenPrefixes {
            if standardPath.hasPrefix(forbidden) {
                throw MihomoError.invalidFilePath
            }
        }
    }

    /// 创建配置目录（如果不存在）
    private func createConfigDirectoryIfNeeded() throws {
        let configDir = MihomoPaths.configDirectory
        if !fileManager.fileExists(atPath: configDir) {
            do {
                try fileManager.createDirectory(
                    atPath: configDir,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                throw MihomoError.fileOperationFailed("创建配置目录失败: \(error.localizedDescription)")
            }
        }
    }

    /// 保持原文件权限
    ///
    /// - Parameters:
    ///   - source: 源文件 URL
    ///   - destination: 目标文件 URL
    /// - Throws: Error
    private func preserveFilePermissions(from source: URL, to destination: URL) throws {
        let attributes = try fileManager.attributesOfItem(atPath: source.path)
        if let permissions = attributes[.posixPermissions] {
            try fileManager.setAttributes(
                [.posixPermissions: permissions],
                ofItemAtPath: destination.path
            )
        }
    }

    /// 在复制前预设源文件权限
    ///
    /// ## 设计说明
    /// `FileManager(authorization:)` 的 `setAttributes` 不支持授权操作，
    /// 因此需要在源文件所在的可写目录中预先设置权限，复制时权限会被保留。
    ///
    /// - Parameters:
    ///   - path: 源文件路径（必须在可写目录中，如临时目录或用户目录）
    ///   - permissions: POSIX 权限值（如 0o755）
    /// - Throws: MihomoError
    private func setPermissionsBeforeCopy(at path: String, permissions: UInt16) throws {
        let attributes: [FileAttributeKey: Any] = [
            .posixPermissions: NSNumber(value: permissions)
        ]

        do {
            try fileManager.setAttributes(attributes, ofItemAtPath: path)
        } catch {
            AppLogger.error("预设文件权限失败: \(error.localizedDescription)")
            throw MihomoError.fileOperationFailed("预设文件权限失败: \(error.localizedDescription)")
        }
    }
}
