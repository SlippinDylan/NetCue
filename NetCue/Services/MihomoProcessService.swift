//
//  MihomoProcessService.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/30.
//

import Foundation
import AppKit

/// Mihomo 关联应用的进程服务
///
/// ## 设计说明
/// 不写死任何具体客户端的 bundle identifier，所有方法都接收调用方
/// 传入的 `bundleIdentifier`/`displayName`（来自 `MihomoConfig` 中用户
/// 关联的应用）。若两者均为空（尚未关联应用），则视为"无法判断运行状态"，
/// 直接放行，不阻塞内核操作。
class MihomoProcessService {
    private final class TerminationWaitState: @unchecked Sendable {
        private let lock = NSLock()
        private let notificationCenter: NotificationCenter
        nonisolated(unsafe) private var hasFinished = false
        nonisolated(unsafe) var observer: NSObjectProtocol?
        nonisolated(unsafe) var continuation: CheckedContinuation<Void, Error>?

        init(notificationCenter: NotificationCenter) {
            self.notificationCenter = notificationCenter
        }

        nonisolated func finish(_ result: Result<Void, Error>) {
            lock.lock()
            guard !hasFinished else {
                lock.unlock()
                return
            }
            hasFinished = true
            let observerToRemove = observer
            observer = nil
            let continuationToResume = continuation
            continuation = nil
            lock.unlock()

            if let observerToRemove {
                notificationCenter.removeObserver(observerToRemove)
            }

            switch result {
            case .success:
                continuationToResume?.resume()
            case .failure(let error):
                continuationToResume?.resume(throwing: error)
            }
        }
    }

    // MARK: - 进程检测

    /// 检查关联应用是否正在运行
    /// - Parameters:
    ///   - bundleIdentifier: 关联应用的 Bundle Identifier
    ///   - displayName: 关联应用的显示名称
    /// - Returns: true 表示正在运行，false 表示未运行或尚未关联应用
    func isHostAppRunning(bundleIdentifier: String, displayName: String) -> Bool {
        guard !bundleIdentifier.isEmpty || !displayName.isEmpty else {
            return false
        }

        AppLogger.debug("检查关联应用运行状态: \(displayName)")
        let isRunning = findRunningHostApp(bundleIdentifier: bundleIdentifier, displayName: displayName) != nil

        if isRunning {
            AppLogger.info("关联应用正在运行: \(displayName)")
        } else {
            AppLogger.debug("关联应用未运行: \(displayName)")
        }

        return isRunning
    }


    // MARK: - 应用控制

    /// 请求用户退出关联应用
    ///
    /// 使用 async/await 模式替代阻塞式 `runModal()`
    ///
    /// - Parameters:
    ///   - bundleIdentifier: 关联应用的 Bundle Identifier
    ///   - displayName: 关联应用的显示名称
    /// - Returns: 用户选择的操作（退出或取消）
    func requestQuitHostApp(bundleIdentifier: String, displayName: String) async -> Bool {
        AppLogger.info("弹出对话框请求退出关联应用: \(displayName)")

        let alert = NSAlert()
        alert.messageText = "\(displayName) 正在运行"
        alert.informativeText = "执行此操作需要先退出 \(displayName)，是否继续？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "退出 \(displayName)")
        alert.addButton(withTitle: "取消")

        // 使用 withCheckedContinuation 将 runModal 包装为 async
        // 注意：runModal 会阻塞当前线程，但在 MainActor 上下文中是安全的
        let response = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let result = alert.runModal()
                continuation.resume(returning: result)
            }
        }

        if response == .alertFirstButtonReturn {
            // 用户选择退出
            AppLogger.info("用户选择退出关联应用: \(displayName)")
            quitHostApp(bundleIdentifier: bundleIdentifier, displayName: displayName)
            return true
        } else {
            // 用户取消
            AppLogger.info("用户取消退出关联应用: \(displayName)")
            return false
        }
    }

    /// 退出关联应用
    private func quitHostApp(bundleIdentifier: String, displayName: String) {
        AppLogger.info("尝试退出关联应用: \(displayName)")

        if let app = findRunningHostApp(bundleIdentifier: bundleIdentifier, displayName: displayName) {
            AppLogger.debug("找到关联应用进程，正在终止")
            app.terminate()
            AppLogger.info("已发送退出信号: \(displayName)")
        } else {
            AppLogger.warning("未找到正在运行的关联应用进程: \(displayName)")
        }
    }

    // MARK: - 事件驱动等待

    /// 等待关联应用退出，使用应用终止通知替代轮询
    /// - Parameters:
    ///   - bundleIdentifier: 关联应用的 Bundle Identifier
    ///   - displayName: 关联应用的显示名称
    ///   - maxWaitTime: 最大等待时间（秒）
    /// - Throws: MihomoError.appQuitTimeout
    func waitForHostAppToQuit(
        bundleIdentifier: String,
        displayName: String,
        maxWaitTime: TimeInterval = 10.0
    ) async throws {
        guard let runningApp = findRunningHostApp(bundleIdentifier: bundleIdentifier, displayName: displayName) else {
            return
        }

        let processIdentifier = runningApp.processIdentifier

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.awaitTerminationNotification(
                    bundleIdentifier: bundleIdentifier,
                    displayName: displayName,
                    processIdentifier: processIdentifier
                )
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(maxWaitTime * 1_000_000_000))
                throw MihomoError.appQuitTimeout
            }

            do {
                try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private func awaitTerminationNotification(
        bundleIdentifier: String,
        displayName: String,
        processIdentifier: pid_t
    ) async throws {
        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        let waitState = TerminationWaitState(notificationCenter: workspaceNotificationCenter)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waitState.continuation = continuation

                waitState.observer = workspaceNotificationCenter.addObserver(
                    forName: NSWorkspace.didTerminateApplicationNotification,
                    object: nil,
                    queue: .main
                ) { notification in
                    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          app.processIdentifier == processIdentifier else {
                        return
                    }

                    AppLogger.info("检测到关联应用已退出: \(displayName)")
                    waitState.finish(.success(()))
                }

                if self.findRunningHostApp(bundleIdentifier: bundleIdentifier, displayName: displayName, processIdentifier: processIdentifier) == nil {
                    waitState.finish(.success(()))
                }
            }
        } onCancel: {
            waitState.finish(.failure(CancellationError()))
        }
    }

    // MARK: - Private Helpers

    private func findRunningHostApp(
        bundleIdentifier: String,
        displayName: String,
        processIdentifier: pid_t? = nil
    ) -> NSRunningApplication? {
        guard !bundleIdentifier.isEmpty || !displayName.isEmpty else {
            return nil
        }

        return NSWorkspace.shared.runningApplications.first { app in
            let matchesTarget = (!bundleIdentifier.isEmpty && app.bundleIdentifier == bundleIdentifier) ||
                (!displayName.isEmpty && app.localizedName == displayName)

            guard matchesTarget else {
                return false
            }

            if let processIdentifier {
                return app.processIdentifier == processIdentifier
            }

            return true
        }
    }
}
