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
/// - 所有方法均以参数形式接收路径，不自行读取持久化配置，
///   避免与调用方（ViewModel）内存中尚未保存的编辑状态不一致
///
/// ## 密码输入优化
/// 重构前：每次文件操作都弹出密码框（4-5次）
/// 重构后：整个操作流程仅弹出一次密码框
final class MihomoFileService: Sendable {
    private let fileManager = FileManager.default
    private let privilegedService = PrivilegedFileOperationService()

    // MARK: - 状态检查

    /// 检查关联应用的安装状态
    /// - Parameter appBundlePath: 关联应用的 Bundle 路径
    func checkHostAppInstallation(appBundlePath: String) -> HostAppInstallStatus {
        AppLogger.debug("检查关联应用安装状态")

        guard !appBundlePath.isEmpty else {
            AppLogger.debug("尚未关联应用")
            return .notConfigured
        }

        if fileManager.fileExists(atPath: appBundlePath) {
            AppLogger.info("关联应用已安装: \(appBundlePath)")
            return .installed
        } else {
            AppLogger.info("关联应用未找到: \(appBundlePath)")
            return .notInstalled
        }
    }

    /// 获取内核状态
    /// - Parameter kernelPath: 内核文件路径
    func getKernelStatus(kernelPath: String) -> KernelStatus {
        AppLogger.debug("获取内核状态")
        let backupPath = kernelPath.isEmpty ? "" : kernelPath + ".bak"

        let kernelExists = !kernelPath.isEmpty && fileManager.fileExists(atPath: kernelPath)
        let backupExists = !backupPath.isEmpty && fileManager.fileExists(atPath: backupPath)

        AppLogger.info("内核状态: 内核存在=\(kernelExists), 备份存在=\(backupExists)")
        return KernelStatus(
            kernelExists: kernelExists,
            backupExists: backupExists,
            kernelPath: kernelPath,
            backupPath: backupPath
        )
    }

    // MARK: - 内核操作

    /// 备份内核文件（无需特权，使用普通 FileManager）
    ///
    /// - Parameter kernelPath: 内核文件路径
    /// - Throws: MihomoError
    ///
    /// ## 说明
    /// 备份操作将内核文件复制到用户目录，无需管理员权限。
    func backupKernel(kernelPath: String) throws {
        AppLogger.debug("开始备份内核文件")

        guard !kernelPath.isEmpty else {
            AppLogger.error("备份内核失败: 尚未选择内核文件路径")
            throw MihomoError.kernelPathNotConfigured
        }

        // 校验路径安全性：kernelPath 来自用户选择或导入的配置文件，
        // 不能信任其指向系统关键目录
        try validateFilePath(kernelPath)

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
    /// - Parameters:
    ///   - newKernelPath: 新内核文件路径
    ///   - kernelPath: 当前生效的内核文件路径
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
    func replaceKernel(with newKernelPath: String, kernelPath: String) async throws {
        AppLogger.debug("开始替换内核文件（两阶段提交）: \(newKernelPath)")

        // 0. 验证路径安全性（新文件来源 + 当前生效路径都要校验，
        //    kernelPath 可能来自导入的配置文件，不能默认可信）
        try validateFilePath(newKernelPath)

        guard !kernelPath.isEmpty else {
            AppLogger.error("替换内核失败: 尚未选择内核文件路径")
            throw MihomoError.kernelPathNotConfigured
        }

        try validateFilePath(kernelPath)

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
                    try backupKernel(kernelPath: kernelPath)
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
                    try await restoreKernel(with: session, kernelPath: kernelPath)
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
    /// - Parameter kernelPath: 当前生效的内核文件路径
    /// - Throws: MihomoError
    @MainActor
    func restoreKernel(kernelPath: String) async throws {
        AppLogger.debug("开始恢复内核文件")

        // 获取授权
        let session = try await privilegedService.createAuthorizedSession()
        try await restoreKernel(with: session, kernelPath: kernelPath)
    }

    /// 使用已有授权会话恢复内核文件
    ///
    /// - Parameters:
    ///   - session: 授权会话
    ///   - kernelPath: 当前生效的内核文件路径
    /// - Throws: MihomoError
    private func restoreKernel(with session: AuthorizedSession, kernelPath: String) async throws {
        guard !kernelPath.isEmpty else {
            AppLogger.error("恢复内核失败: 尚未选择内核文件路径")
            throw MihomoError.kernelPathNotConfigured
        }

        try validateFilePath(kernelPath)

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
