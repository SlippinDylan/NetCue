//
//  EmailTestUseCase.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/31.
//  Refactored from IPQualityViewModel.swift - Email service testing logic
//
//  ⚠️ 2026/01/06 重构：修复 withCheckedContinuation 死锁问题
//  - 原问题：NWConnection 进入 .waiting 状态时，continuation 永不 resume
//  - 根因：checkAndSet() 在 default 分支被调用但不 resume，污染了超时机制
//  - 修复：重新设计状态机，确保所有路径都能正确 resume
//

import Foundation
import Network

/// 邮件服务测试用例 - 负责测试邮件端口和SMTP连接
///
/// ## 架构说明
/// - 使用 `NWConnection` 原生 API 测试 TCP 端口连通性
/// - 内置超时机制，防止网络阻塞导致任务卡死
/// - 线程安全的 continuation resume 保护
///
/// ## 2026/01/06 重构
/// - 修复了 `.waiting` 状态导致的死锁问题
/// - 重新设计了状态锁逻辑，确保 continuation 必定被 resume
@MainActor
final class EmailTestUseCase {

    /// 测试超时时间（秒）
    private let connectionTimeout: TimeInterval = 5.0

    // MARK: - Public API

    /// 测试邮件服务可用性
    /// - Parameter ip: 当前 IP 地址（保留参数，未来可能用于特定测试）
    /// - Returns: 邮件服务状态
    func testEmailServices(ip: String) async -> EmailStatus {
        AppLogger.debug("📧 开始邮件服务测试")

        // 并发测试两个端口，提高效率
        async let port25Task = testTCPConnection(
            host: "gmail-smtp-in.l.google.com",
            port: 25,
            label: "Port25"
        )

        async let smtpTask = testTCPConnection(
            host: "gmail-smtp-in.l.google.com",
            port: 25,
            label: "SMTP"
        )

        let (port25Open, smtpConnectable) = await (port25Task, smtpTask)

        AppLogger.debug("📧 邮件服务测试完成: Port25=\(port25Open), SMTP=\(smtpConnectable)")

        return EmailStatus(smtpConnectable: smtpConnectable, port25Open: port25Open)
    }

    // MARK: - Private Implementation

    /// 测试 TCP 连接（带超时保护）
    ///
    /// ## 实现说明
    /// - 使用 `withTaskGroup` 实现超时控制
    /// - 正确处理所有 `NWConnection` 状态
    /// - 确保 continuation 在任何情况下都会被 resume
    ///
    /// - Parameters:
    ///   - host: 目标主机
    ///   - port: 目标端口
    ///   - label: 日志标签
    /// - Returns: 连接是否成功
    private func testTCPConnection(host: String, port: UInt16, label: String) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            AppLogger.error("[\(label)] 无效的端口号: \(port)")
            return false
        }

        // 使用 TaskGroup 实现超时控制
        return await withTaskGroup(of: Bool.self) { group in
            // 任务 1: 实际连接测试
            group.addTask {
                await self.performConnectionTest(host: host, port: nwPort, label: label)
            }

            // 任务 2: 超时守护
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(self.connectionTimeout * 1_000_000_000))
                return false // 超时返回失败
            }

            // 返回第一个完成的结果
            guard let result = await group.next() else {
                return false
            }

            // 取消剩余任务
            group.cancelAll()

            return result
        }
    }

    /// 执行实际的连接测试
    ///
    /// ## 状态机说明
    /// - `.setup` / `.preparing`: 初始状态，等待
    /// - `.ready`: 连接成功
    /// - `.waiting`: 等待网络条件（通常意味着连接失败）
    /// - `.failed`: 连接失败
    /// - `.cancelled`: 被取消
    ///
    /// ## 取消处理
    /// - 使用 `withTaskCancellationHandler` 确保任务被取消时 continuation 能正确 resume
    /// - 这是防止 TaskGroup.cancelAll() 导致死锁的关键
    ///
    /// - Parameters:
    ///   - host: 目标主机
    ///   - port: 目标端口
    ///   - label: 日志标签
    /// - Returns: 连接是否成功
    private func performConnectionTest(host: String, port: NWEndpoint.Port, label: String) async -> Bool {
        // 创建连接（在 continuation 外部创建，以便取消处理器可以访问）
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: port,
            using: .tcp
        )

        // 线程安全的 resume 保护器
        let resumeGuard = ContinuationResumeGuard()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                connection.stateUpdateHandler = { [weak connection] state in
                    switch state {
                    case .ready:
                        // ✅ 连接成功
                        if resumeGuard.tryResume() {
                            AppLogger.debug("[\(label)] 连接成功")
                            connection?.cancel()
                            continuation.resume(returning: true)
                        }

                    case .failed(let error):
                        // ❌ 连接失败
                        if resumeGuard.tryResume() {
                            AppLogger.debug("[\(label)] 连接失败: \(error.localizedDescription)")
                            connection?.cancel()
                            continuation.resume(returning: false)
                        }

                    case .waiting(let error):
                        // ⚠️ 等待状态（通常意味着端口被阻止）
                        // 不立即返回，等待超时或状态变化
                        AppLogger.debug("[\(label)] 等待中: \(error.localizedDescription)")

                    case .cancelled:
                        // 🛑 被取消（可能是超时触发的）
                        if resumeGuard.tryResume() {
                            AppLogger.debug("[\(label)] 连接已取消")
                            continuation.resume(returning: false)
                        }

                    case .setup, .preparing:
                        // 初始状态，不处理
                        break

                    @unknown default:
                        // 未知状态，视为失败
                        if resumeGuard.tryResume() {
                            AppLogger.warning("[\(label)] 未知连接状态")
                            connection?.cancel()
                            continuation.resume(returning: false)
                        }
                    }
                }

                // 启动连接（使用全局队列避免阻塞主线程）
                connection.start(queue: .global(qos: .userInitiated))
            }
        } onCancel: {
            // 任务被取消时，强制取消连接
            // 这会触发 .cancelled 状态，从而 resume continuation
            AppLogger.debug("[\(label)] 任务被取消，强制断开连接")
            connection.cancel()
        }
    }
}

// MARK: - Helper Types

/// Continuation Resume 保护器
///
/// 确保 `withCheckedContinuation` 的 continuation 只被 resume 一次。
/// 使用原子操作实现线程安全。
///
/// ## 设计说明
/// - 使用 `os_unfair_lock` 实现原子操作（比 NSLock 更轻量）
/// - 标记为 `@unchecked Sendable`，因为我们手动管理线程安全
/// - 使用 `nonisolated` 确保完全脱离 Actor 隔离系统
/// - 使用 `final class` 以便在 @MainActor 上下文中创建但在后台线程调用
private final class ContinuationResumeGuard: @unchecked Sendable {
    // nonisolated(unsafe) 表示我们手动管理线程安全（通过 os_unfair_lock）
    // 所有访问都在 os_unfair_lock 保护下，因此可以安全地跳过 Actor 隔离检查
    nonisolated(unsafe) private let state = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    nonisolated(unsafe) private let resumed = UnsafeMutablePointer<Bool>.allocate(capacity: 1)

    nonisolated init() {
        state.initialize(to: os_unfair_lock())
        resumed.initialize(to: false)
    }

    deinit {
        state.deinitialize(count: 1)
        state.deallocate()
        resumed.deinitialize(count: 1)
        resumed.deallocate()
    }

    /// 尝试获取 resume 权限
    /// - Returns: `true` 如果这是第一次调用，可以 resume；`false` 如果已经 resume 过了
    nonisolated func tryResume() -> Bool {
        os_unfair_lock_lock(state)
        defer { os_unfair_lock_unlock(state) }

        if resumed.pointee {
            return false
        }
        resumed.pointee = true
        return true
    }
}
