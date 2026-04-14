//
//  MihomoProcessService.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/30.
//

import Foundation
import AppKit

/// Mihomo 进程服务
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

    private let clashXMetaBundleIdentifier = "com.metacubex.ClashX.meta"
    private let clashXMetaDisplayName = "ClashX Meta"

    // MARK: - 进程检测

    /// 检查 ClashX.Meta 是否正在运行
    /// - Returns: true 表示正在运行，false 表示未运行
    func isClashXMetaRunning() -> Bool {
        AppLogger.debug("检查 ClashX.Meta 运行状态")
        let isRunning = findRunningClashXMeta() != nil

        if isRunning {
            AppLogger.info("ClashX.Meta 正在运行")
        } else {
            AppLogger.debug("ClashX.Meta 未运行")
        }

        return isRunning
    }

    /// 检查是否可以执行需要 sudo 的操作
    /// - Returns: true 表示 ClashX.Meta 未运行，可以执行操作
    /// - Throws: MihomoError.clashXMetaIsRunning 如果应用正在运行
    func checkCanPerformSudoOperations() throws {
        AppLogger.debug("检查是否可以执行 sudo 操作")
        if isClashXMetaRunning() {
            AppLogger.warning("ClashX.Meta 正在运行，无法执行 sudo 操作")
            throw MihomoError.clashXMetaIsRunning
        }
        AppLogger.debug("可以执行 sudo 操作")
    }

    // MARK: - 应用控制

    /// 打开 ClashX.Meta 应用
    func openClashXMeta() {
        let appPath = MihomoPaths.clashXMetaApp
        AppLogger.info("尝试打开 ClashX.Meta - 路径: \(appPath)")

        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: appPath),
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error = error {
                AppLogger.error("打开 ClashX.Meta 失败", error: error)
            } else {
                AppLogger.info("ClashX.Meta 已成功打开")
            }
        }
    }

    /// 请求用户退出 ClashX.Meta
    ///
    /// 使用 async/await 模式替代阻塞式 `runModal()`
    ///
    /// - Returns: 用户选择的操作（退出或取消）
    func requestQuitClashXMeta() async -> Bool {
        AppLogger.info("弹出对话框请求退出 ClashX.Meta")

        let alert = NSAlert()
        alert.messageText = "ClashX.Meta 正在运行"
        alert.informativeText = "执行此操作需要先退出 ClashX.Meta，是否继续？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "退出 ClashX.Meta")
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
            AppLogger.info("用户选择退出 ClashX.Meta")
            quitClashXMeta()
            return true
        } else {
            // 用户取消
            AppLogger.info("用户取消退出 ClashX.Meta")
            return false
        }
    }

    /// 退出 ClashX.Meta 应用
    private func quitClashXMeta() {
        AppLogger.info("尝试退出 ClashX.Meta")

        if let clashApp = findRunningClashXMeta() {
            AppLogger.debug("找到 ClashX.Meta 进程，正在终止")
            clashApp.terminate()
            AppLogger.info("已发送退出信号到 ClashX.Meta")
        } else {
            AppLogger.warning("未找到正在运行的 ClashX.Meta 进程")
        }
    }

    // MARK: - 事件驱动等待

    /// 等待 ClashX.Meta 退出，使用应用终止通知替代轮询
    /// - Parameter maxWaitTime: 最大等待时间（秒）
    /// - Throws: MihomoError.appQuitTimeout
    func waitForClashXMetaToQuit(maxWaitTime: TimeInterval = 10.0) async throws {
        guard let runningApp = findRunningClashXMeta() else {
            return
        }

        let processIdentifier = runningApp.processIdentifier

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.awaitTerminationNotification(for: processIdentifier)
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

    private func awaitTerminationNotification(for processIdentifier: pid_t) async throws {
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

                    AppLogger.info("检测到 ClashX.Meta 已退出")
                    waitState.finish(.success(()))
                }

                if self.findRunningClashXMeta(processIdentifier: processIdentifier) == nil {
                    waitState.finish(.success(()))
                }
            }
        } onCancel: {
            waitState.finish(.failure(CancellationError()))
        }
    }

    // MARK: - Private Helpers

    private func findRunningClashXMeta(processIdentifier: pid_t? = nil) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            let matchesTarget = app.bundleIdentifier == clashXMetaBundleIdentifier ||
                app.localizedName == clashXMetaDisplayName

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
