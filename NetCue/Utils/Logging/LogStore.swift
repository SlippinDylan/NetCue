//
//  LogStore.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/31.
//

import Foundation
import SwiftUI
import Observation

/// 日志存储管理器
///
/// 负责：
/// - 存储所有日志条目（内存+文件）
/// - 提供线程安全的读写接口
/// - 实现循环缓冲区（限制最大10,000条）
/// - 批量更新UI（优化性能）
/// - 持久化到文件（防止崩溃日志丢失）
/// - 导出到文件
@MainActor
@Observable
final class LogStore {
    // MARK: - Singleton

    static let shared = LogStore()

    // MARK: - Published Properties

    /// 所有日志条目（发布属性，用于 SwiftUI 绑定）
    private(set) var entries: [LogEntry] = []

    // MARK: - Private Properties

    /// 最大日志条目数（循环缓冲区）
    private let maxEntries: Int = 10_000

    /// 单个日志文件大小上限（10MB）
    private let maxLogFileSize = 10 * 1024 * 1024

    /// 日志保留天数
    private let logRetentionDays = 7

    /// 默认日志保留天数
    private static let defaultLogRetentionDays = 7

    /// 批量更新缓冲区
    private var pendingEntries: [LogEntry] = []

    /// 批量更新定时器任务（不参与观察，以便 deinit 访问）
    @ObservationIgnored
    private var batchUpdateTask: Task<Void, Never>?

    /// 批量更新间隔（秒）
    private let batchUpdateInterval: TimeInterval = 0.5

    /// 批量更新阈值（条目数）
    private let batchUpdateThreshold: Int = 10

    /// 日志文件路径
    private let logFileURL: URL

    /// 文件写入队列（串行，确保写入顺序）
    private let fileQueue = DispatchQueue(
        label: "com.netcue.logging.file",
        qos: .utility
    )

    /// 文件写入器（线程安全封装）
    private let fileWriter: LogFileWriter

    // MARK: - Initializer

    private init() {
        // 确定日志文件路径
        let logsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NetCue/Logs", isDirectory: true)

        // 创建日志目录
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        Self.cleanupExpiredLogFiles(in: logsDir)

        // 日志文件名包含日期（使用 ISO 8601 日期格式）
        let dateString = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
        logFileURL = logsDir.appendingPathComponent("netcue-\(dateString).log")

        // 初始化文件写入器
        fileWriter = LogFileWriter(
            fileURL: logFileURL,
            queue: fileQueue,
            maxFileSize: maxLogFileSize
        )

        // 私有初始化器，确保单例模式
        setupBatchUpdateTimer()
    }

    // MARK: - Public Methods

    /// 添加日志条目
    ///
    /// - Parameter entry: 日志条目
    ///
    /// ## 实现说明
    /// 1. 立即写入文件（防止崩溃丢失）
    /// 2. 加入内存缓冲区（批量更新UI）
    ///
    /// ## 性能优化
    /// - 文件写入在后台队列异步执行
    /// - UI更新使用批量机制（0.5秒或10条）
    func append(_ entry: LogEntry) {
        // ✅ 立即写入文件（防止崩溃丢失）
        writeToFile(entry)

        // 加入内存缓冲区
        pendingEntries.append(entry)

        // 如果缓冲区达到阈值，立即触发批量更新
        if pendingEntries.count >= batchUpdateThreshold {
            flushPendingEntries()
        }
    }

    /// 清空所有日志
    func clear() {
        entries.removeAll()
        pendingEntries.removeAll()
    }

    /// 导出日志到文件
    ///
    /// - Parameter url: 导出文件路径
    /// - Throws: 文件写入错误
    func exportToFile(url: URL) throws {
        // 先刷新待处理条目
        flushPendingEntries()

        let content = entries.map { $0.plainTextString }.joined(separator: "\n")
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Private Methods - File Operations

    /// 写入日志到文件
    ///
    /// - Parameter entry: 日志条目
    ///
    /// ## 实现说明
    /// - 在后台队列异步执行
    /// - 使用 FileHandle 追加写入（性能优于重写整个文件）
    /// - 每条日志立即写入，确保崩溃时不丢失
    private func writeToFile(_ entry: LogEntry) {
        let logLine = entry.plainTextString + "\n"
        let shouldSync = entry.level >= .error
        fileWriter.write(logLine, synchronize: shouldSync)
    }

    private static func cleanupExpiredLogFiles(in directory: URL) {
        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -defaultLogRetentionDays,
            to: Date()
        ) ?? .distantPast
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for fileURL in fileURLs where fileURL.pathExtension == "log" {
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            let modifiedAt = values?.contentModificationDate ?? .distantPast
            if modifiedAt < cutoffDate {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    /// 设置批量更新定时任务
    private func setupBatchUpdateTimer() {
        batchUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled else { break }
                self?.flushPendingEntries()
            }
        }
    }

    /// 刷新待处理的日志条目（批量更新）
    private func flushPendingEntries() {
        guard !pendingEntries.isEmpty else {
            return
        }

        // 将待处理的条目添加到主存储
        entries.append(contentsOf: pendingEntries)

        // 实现循环缓冲区：如果超过最大容量，删除最旧的条目
        if entries.count > maxEntries {
            let excessCount = entries.count - maxEntries
            entries.removeFirst(excessCount)
        }

        // 清空缓冲区
        pendingEntries.removeAll()
    }

    // MARK: - Deinitializer

    deinit {
        // 取消批量更新任务
        batchUpdateTask?.cancel()

        // 关闭文件写入器（确保数据完整写入）
        fileWriter.close()
    }
}

// MARK: - Helper Extensions

extension LogStore {
    /// 获取统计信息
    var statistics: LogStatistics {
        let counts = Dictionary(grouping: entries, by: { $0.level })
            .mapValues { $0.count }

        return LogStatistics(
            total: entries.count,
            trace: counts[.trace] ?? 0,
            debug: counts[.debug] ?? 0,
            info: counts[.info] ?? 0,
            warning: counts[.warning] ?? 0,
            error: counts[.error] ?? 0,
            critical: counts[.critical] ?? 0
        )
    }
}

// MARK: - Statistics Model

/// 日志统计信息
struct LogStatistics {
    let total: Int
    let trace: Int
    let debug: Int
    let info: Int
    let warning: Int
    let error: Int
    let critical: Int
}

// MARK: - Log File Writer

/// 线程安全的日志文件写入器
///
/// 此类独立于 MainActor，解决 Swift 6 的并发隔离问题。
/// 所有文件操作都在指定的串行队列上执行。
private final class LogFileWriter: @unchecked Sendable {
    private let fileURL: URL
    private let queue: DispatchQueue
    private let maxFileSize: Int
    private var fileHandle: FileHandle?

    init(fileURL: URL, queue: DispatchQueue, maxFileSize: Int) {
        self.fileURL = fileURL
        self.queue = queue
        self.maxFileSize = maxFileSize

        // 在队列上初始化文件句柄
        queue.sync {
            // 如果文件不存在，创建它
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }

            // 打开文件句柄（追加模式）
            do {
                self.fileHandle = try FileHandle(forWritingTo: fileURL)
                self.fileHandle?.seekToEndOfFile()
            } catch {
                print("❌ 无法打开日志文件: \(error.localizedDescription)")
            }
        }
    }

    /// 写入日志行
    /// - Parameters:
    ///   - logLine: 日志内容
    ///   - synchronize: 是否立即同步到磁盘
    func write(_ logLine: String, synchronize: Bool) {
        queue.async { [weak self] in
            guard let self,
                  let handle = self.fileHandle,
                  let data = logLine.data(using: .utf8) else { return }

            self.trimFileIfNeeded(forAppending: data)
            handle.write(data)

            if synchronize {
                try? handle.synchronize()
            }
        }
    }

    private func trimFileIfNeeded(forAppending data: Data) {
        guard let handle = fileHandle else { return }

        let currentSize = (try? handle.offset()) ?? 0
        let incomingSize = UInt64(data.count)
        guard currentSize + incomingSize > UInt64(maxFileSize) else {
            return
        }

        let existingData = (try? Data(contentsOf: fileURL)) ?? Data()
        let targetKeepSize = max(maxFileSize - data.count, 0)
        let recentData = existingData.suffix(targetKeepSize)

        let trimmedData: Data
        if let newlineIndex = recentData.firstIndex(of: 0x0A) {
            trimmedData = Data(recentData.suffix(from: recentData.index(after: newlineIndex)))
        } else {
            trimmedData = Data()
        }

        let newPayload: Data
        if data.count >= maxFileSize {
            newPayload = Data(data.suffix(maxFileSize))
        } else {
            newPayload = trimmedData + data
        }

        do {
            try newPayload.write(to: fileURL, options: .atomic)
            try handle.close()
            fileHandle = try FileHandle(forWritingTo: fileURL)
            fileHandle?.seekToEndOfFile()
        } catch {
            print("❌ 日志文件截断失败: \(error.localizedDescription)")
        }
    }

    /// 关闭文件句柄
    nonisolated func close() {
        queue.sync {
            if let handle = fileHandle {
                try? handle.synchronize()
                try? handle.close()
                fileHandle = nil
            }
        }
    }
}
