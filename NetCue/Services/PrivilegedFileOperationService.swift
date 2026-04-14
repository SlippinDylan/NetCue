//
//  PrivilegedFileOperationService.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/31.
//
//  ## 2026/01/08 重构
//  - 使用 NSWorkspace.Authorization + FileManager 原生 API
//  - 一次授权，多次操作，仅需输入一次密码
//  - 完全移除 AppleScript + Shell 调用
//

import Foundation
import AppKit

/// 特权文件操作服务（原生 API 实现）
///
/// ## 架构说明
/// 使用 Apple 官方推荐的 `NSWorkspace.Authorization` + `FileManager(authorization:)` 模式，
/// 实现一次授权、多次操作的特权文件管理。
///
/// ## 技术优势
/// - **原生 API**：使用 macOS 10.14+ 官方 API，非 Shell 调用
/// - **单次授权**：整个操作会话仅需一次密码输入
/// - **类型安全**：Swift 原生类型，编译时检查
///
/// ## 使用示例
/// ```swift
/// let service = PrivilegedFileOperationService()
///
/// // 1. 获取授权（弹出一次密码框）
/// let session = try await service.createAuthorizedSession()
///
/// // 2. 执行多个文件操作（无需再次输入密码）
/// try session.copyItem(from: source, to: destination)
/// try session.removeItem(at: path)
/// try session.moveItem(from: source, to: destination)
/// try session.setPermissions(at: path, permissions: 0o755)
/// ```
final class PrivilegedFileOperationService: Sendable {

    // MARK: - Public Methods

    /// 创建授权会话
    ///
    /// 请求用户授权后返回一个 `AuthorizedSession` 对象，
    /// 该对象可执行多个特权文件操作，仅需一次密码输入。
    ///
    /// - Returns: 授权会话对象
    /// - Throws: `PrivilegedOperationError`
    ///
    /// ## 授权类型
    /// 使用 `.replaceFile` 权限，这是最高级别的文件操作权限，
    /// 涵盖复制、移动、删除、替换等所有文件操作。
    @MainActor
    func createAuthorizedSession() async throws -> AuthorizedSession {
        AppLogger.info("请求特权文件操作授权...")

        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.requestAuthorization(to: .replaceFile) { authorization, error in
                if let error = error {
                    AppLogger.error("授权请求失败: \(error.localizedDescription)")
                    continuation.resume(throwing: PrivilegedOperationError.authorizationFailed(error.localizedDescription))
                    return
                }

                guard let authorization = authorization else {
                    AppLogger.error("授权请求失败: 未获取到授权对象")
                    continuation.resume(throwing: PrivilegedOperationError.authorizationFailed("未获取到授权对象"))
                    return
                }

                AppLogger.info("✅ 特权文件操作授权成功")
                let session = AuthorizedSession(authorization: authorization)
                continuation.resume(returning: session)
            }
        }
    }

    // MARK: - Legacy Support (向后兼容，逐步废弃)

    /// 以管理员权限复制文件（单次操作，会弹出密码框）
    ///
    /// - Warning: 此方法仅为向后兼容保留，建议使用 `createAuthorizedSession()` 批量操作。
    /// - Parameters:
    ///   - source: 源文件路径
    ///   - destination: 目标文件路径
    /// - Throws: PrivilegedOperationError
    @MainActor
    func copyFile(from source: String, to destination: String) async throws {
        let session = try await createAuthorizedSession()
        try session.copyItem(from: source, to: destination)
    }

    /// 以管理员权限删除文件（单次操作，会弹出密码框）
    ///
    /// - Warning: 此方法仅为向后兼容保留，建议使用 `createAuthorizedSession()` 批量操作。
    /// - Parameter path: 文件路径
    /// - Throws: PrivilegedOperationError
    @MainActor
    func removeFile(at path: String) async throws {
        let session = try await createAuthorizedSession()
        try session.removeItem(at: path)
    }

    /// 以管理员权限设置文件权限（单次操作，会弹出密码框）
    ///
    /// - Warning: **此方法不生效！** `setAttributes` 不在 `replaceFile` 授权范围内。
    ///   请在源文件（可写目录）中预先设置权限，复制时权限会被保留。
    /// - Parameters:
    ///   - path: 文件路径
    ///   - permissions: 权限值（例如：0o755）
    /// - Throws: PrivilegedOperationError
    @available(*, deprecated, message: "setAttributes 不在 replaceFile 授权范围内，请在复制前设置权限")
    @MainActor
    func setFilePermissions(at path: String, permissions: UInt16) async throws {
        let session = try await createAuthorizedSession()
        try session.setPermissions(at: path, permissions: permissions)
    }

    /// 以管理员权限移动文件（单次操作，会弹出密码框）
    ///
    /// - Warning: 此方法仅为向后兼容保留，建议使用 `createAuthorizedSession()` 批量操作。
    /// - Parameters:
    ///   - source: 源文件路径
    ///   - destination: 目标文件路径
    /// - Throws: PrivilegedOperationError
    @MainActor
    func moveFile(from source: String, to destination: String) async throws {
        let session = try await createAuthorizedSession()
        try session.moveItem(from: source, to: destination)
    }
}

// MARK: - Authorized Session

/// 授权会话
///
/// 封装 `NSWorkspace.Authorization` 和 `FileManager(authorization:)`，
/// 提供类型安全的特权文件操作接口。
///
/// ## 线程安全
/// 此类的所有方法都是同步的，但底层 FileManager 操作是线程安全的。
/// 建议在后台线程调用以避免阻塞主线程。
final class AuthorizedSession: @unchecked Sendable {

    // MARK: - Properties

    /// 授权对象（系统管理生命周期）
    private let authorization: NSWorkspace.Authorization

    /// 授权的 FileManager 实例
    private let fileManager: FileManager

    // MARK: - Initialization

    /// 初始化授权会话
    /// - Parameter authorization: NSWorkspace 授权对象
    init(authorization: NSWorkspace.Authorization) {
        self.authorization = authorization
        self.fileManager = FileManager(authorization: authorization)
    }

    // MARK: - File Operations

    /// 复制文件
    ///
    /// - Parameters:
    ///   - source: 源文件路径
    ///   - destination: 目标文件路径
    /// - Throws: PrivilegedOperationError
    func copyItem(from source: String, to destination: String) throws {
        AppLogger.debug("复制文件: \(source) → \(destination)")

        let sourceURL = URL(fileURLWithPath: source)
        let destinationURL = URL(fileURLWithPath: destination)

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            AppLogger.info("✅ 文件复制成功")
        } catch {
            AppLogger.error("文件复制失败: \(error.localizedDescription)")
            throw PrivilegedOperationError.fileOperationFailed("复制失败: \(error.localizedDescription)")
        }
    }

    /// 移动文件
    ///
    /// - Parameters:
    ///   - source: 源文件路径
    ///   - destination: 目标文件路径
    /// - Throws: PrivilegedOperationError
    func moveItem(from source: String, to destination: String) throws {
        AppLogger.debug("移动文件: \(source) → \(destination)")

        let sourceURL = URL(fileURLWithPath: source)
        let destinationURL = URL(fileURLWithPath: destination)

        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            AppLogger.info("✅ 文件移动成功")
        } catch {
            AppLogger.error("文件移动失败: \(error.localizedDescription)")
            throw PrivilegedOperationError.fileOperationFailed("移动失败: \(error.localizedDescription)")
        }
    }

    /// 删除文件
    ///
    /// - Parameter path: 文件路径
    /// - Throws: PrivilegedOperationError
    func removeItem(at path: String) throws {
        AppLogger.debug("删除文件: \(path)")

        let url = URL(fileURLWithPath: path)

        do {
            try fileManager.removeItem(at: url)
            AppLogger.info("✅ 文件删除成功")
        } catch {
            AppLogger.error("文件删除失败: \(error.localizedDescription)")
            throw PrivilegedOperationError.fileOperationFailed("删除失败: \(error.localizedDescription)")
        }
    }

    /// 设置文件权限
    ///
    /// - Warning: **此方法在 `FileManager(authorization:)` 中不生效！**
    ///   `NSWorkspace.AuthorizationType.replaceFile` 的授权范围不包括 `setAttributes`。
    ///   请在源文件（可写目录）中预先设置权限，复制时权限会被保留。
    ///
    /// - Parameters:
    ///   - path: 文件路径
    ///   - permissions: POSIX 权限值（例如：0o755 表示 rwxr-xr-x）
    /// - Throws: PrivilegedOperationError
    ///
    /// ## 常用权限值
    /// - `0o755`：可执行文件（rwxr-xr-x）
    /// - `0o644`：普通文件（rw-r--r--）
    /// - `0o600`：私有文件（rw-------）
    func setPermissions(at path: String, permissions: UInt16) throws {
        AppLogger.debug("设置文件权限: \(path) → \(String(permissions, radix: 8))")

        let attributes: [FileAttributeKey: Any] = [
            .posixPermissions: NSNumber(value: permissions)
        ]

        do {
            try fileManager.setAttributes(attributes, ofItemAtPath: path)
            AppLogger.info("✅ 文件权限设置成功")
        } catch {
            AppLogger.error("文件权限设置失败: \(error.localizedDescription)")
            throw PrivilegedOperationError.fileOperationFailed("权限设置失败: \(error.localizedDescription)")
        }
    }

    /// 检查文件是否存在
    ///
    /// - Parameter path: 文件路径
    /// - Returns: 文件是否存在
    func fileExists(at path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }
}

// MARK: - Error Types

/// 特权操作错误
enum PrivilegedOperationError: LocalizedError {
    /// 授权失败
    case authorizationFailed(String)

    /// 用户取消授权
    case userCancelled

    /// 文件操作失败
    case fileOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .authorizationFailed(let message):
            return "授权失败: \(message)"
        case .userCancelled:
            return "操作已取消"
        case .fileOperationFailed(let message):
            return "文件操作失败: \(message)"
        }
    }
}
