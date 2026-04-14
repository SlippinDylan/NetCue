//
//  DNSBenchmarkService.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/01/04.
//

import Foundation
import Network

/// DNS 性能测试服务
///
/// ## 职责
/// - 使用 UDP DNS 查询测试指定 DNS 服务器的解析速度
/// - 复刻 `test_dns.sh` 的测试逻辑（10轮测试，0.5秒间隔）
/// - 提供进度流式更新，支持 UI 实时刷新
///
/// ## 设计说明
/// - **无状态服务**: 所有方法都是纯函数，无副作用
/// - **并发安全**: 使用 `nonisolated` 方法，允许后台执行
/// - **错误处理**: 完整的超时保护和异常捕获
/// - **结构化结果**: 返回 `DNSTestResult` 结构体，避免异常
///
/// ## 使用方式
/// ```swift
/// let service = DNSBenchmarkService()
/// for await progress in service.testDNS(server: "223.5.5.5", domains: sites) {
///     print(progress.description)
/// }
/// let results = await service.getResults()
/// ```
actor DNSBenchmarkService {
    // MARK: - Constants

    /// 每个域名的测试轮数（复刻 bash 脚本的 ROUNDS=10）
    nonisolated private static let testRounds = 10

    /// 每轮测试的间隔时间（秒）（复刻 bash 脚本的 sleep 0.5）
    nonisolated private static let intervalSeconds: TimeInterval = 0.5

    /// 单次 DNS 查询超时时间（秒）
    nonisolated private static let queryTimeout: TimeInterval = 3.0

    // MARK: - Properties

    /// 测试结果存储
    private var results: [DNSTestResult] = []

    /// 取消标志
    private var isCancelled = false

    // MARK: - Initialization

    /// 初始化 DNS 测试服务
    init() {
        // 无状态服务，无需初始化
    }

    // MARK: - Cancellation

    /// 取消当前测试
    func cancel() {
        isCancelled = true
        AppLogger.info("DNSBenchmarkService: 收到取消信号")
    }

    /// 重置取消状态
    private func resetCancellation() {
        isCancelled = false
    }

    /// 检查是否已取消
    private func checkCancelled() -> Bool {
        isCancelled
    }

    // MARK: - Public Methods

    /// 测试 DNS 服务器性能
    ///
    /// ## 实现说明
    /// - 完全复刻 `test_dns.sh` 的逻辑
    /// - 对每个域名执行 10 轮测试
    /// - 每轮间隔 0.5 秒
    /// - 计算 Average/Max/Min
    /// - 提供进度流式更新
    ///
    /// ## 错误处理
    /// - 单次查询失败 → 跳过该轮，继续下一轮
    /// - 超时保护 → 单次查询最多等待 3 秒
    /// - 解析失败 → 跳过该轮，记录失败次数
    ///
    /// - Parameters:
    ///   - server: DNS 服务器地址（如 "223.5.5.5"）
    ///   - domains: 要测试的域名列表
    /// - Returns: 进度流（AsyncStream），每次更新都会发送进度信息
    nonisolated func testDNS(server: String, domains: [String]) -> AsyncStream<DNSTestProgress> {
        AsyncStream { continuation in
            Task {
                // 重置取消状态
                await self.resetCancellation()

                // 清空上次的结果
                await self.clearResults()

                let totalDomains = domains.count

                for (index, domain) in domains.enumerated() {
                    // ✅ 检查任务是否被取消（检查内部标志和Task状态）
                    let cancelled = await self.checkCancelled()
                    guard !Task.isCancelled && !cancelled else {
                        AppLogger.info("DNS 测试已被取消，停止执行")
                        continuation.finish()
                        return
                    }

                    var totalTime = 0
                    var maxTime = 0
                    var minTime = Int.max
                    var successCount = 0

                    // 对当前域名执行 10 轮测试
                    for round in 1...Self.testRounds {
                        // ✅ 每轮都检查是否被取消（检查内部标志和Task状态）
                        let cancelled = await self.checkCancelled()
                        guard !Task.isCancelled && !cancelled else {
                            AppLogger.info("DNS 测试已被取消，停止执行")
                            continuation.finish()
                            return
                        }

                        // 发送进度更新
                        let progress = DNSTestProgress(
                            currentDomain: domain,
                            currentRound: round,
                            completedDomains: index,
                            totalDomains: totalDomains
                        )
                        continuation.yield(progress)

                        // 执行指定 DNS 服务器的 UDP 查询
                        if let queryTime = await Self.executeDNSQuery(server: server, domain: domain) {
                            totalTime += queryTime
                            maxTime = max(maxTime, queryTime)
                            minTime = min(minTime, queryTime)
                            successCount += 1

                            AppLogger.debug("[\(domain)] Round \(round): \(queryTime) ms")
                        } else {
                            AppLogger.warning("[\(domain)] Round \(round): Failed")
                        }

                        // 间隔 0.5 秒（复刻 bash 脚本的 sleep 0.5）
                        if round < Self.testRounds {
                            try? await Task.sleep(nanoseconds: UInt64(Self.intervalSeconds * 1_000_000_000))
                        }
                    }

                    // 计算平均时间
                    let averageTime = successCount > 0 ? Double(totalTime) / Double(successCount) : 0.0

                    // 创建测试结果
                    let result = DNSTestResult(
                        domain: domain,
                        averageTime: averageTime,
                        maxTime: maxTime,
                        minTime: minTime == Int.max ? 0 : minTime,
                        successCount: successCount,
                        totalCount: Self.testRounds
                    )

                    await self.addResult(result)

                    AppLogger.info("✅ [\(domain)] 平均: \(String(format: "%.2f", averageTime)) ms, 最高: \(maxTime) ms, 最低: \(minTime) ms, 成功率: \(successCount)/\(Self.testRounds)")
                }

                continuation.finish()
            }
        }
    }

    /// 获取测试结果
    ///
    /// - Returns: 测试结果列表
    func getResults() -> [DNSTestResult] {
        results
    }

    // MARK: - Private Methods - DNS Query Execution

    /// 执行 DNS 查询并测量时间
    ///
    /// ## 实现说明
    /// - 使用 `NWConnection(host:port:using:.udp)` 直接向指定 DNS 服务器发送查询报文
    /// - 手动构造最小 DNS A Record 查询报文
    /// - 收到合法响应后，以响应往返时间作为延迟指标
    ///
    /// ## 错误处理
    /// - 解析失败 → 返回 nil
    /// - 超时保护 → 3 秒内未收到合法响应则返回 nil
    ///
    /// - Parameters:
    ///   - server: DNS 服务器地址（IPv4/IPv6 字符串）
    ///   - domain: 域名
    /// - Returns: 查询时间（毫秒），失败时返回 nil
    nonisolated private static func executeDNSQuery(server: String, domain: String) async -> Int? {
        await withTaskGroup(of: Int?.self) { group in
            group.addTask {
                await Self.performUDPDNSQuery(server: server, domain: domain)
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(Self.queryTimeout * 1_000_000_000))
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    /// 向指定 DNS 服务器发送单次 UDP 查询
    nonisolated private static func performUDPDNSQuery(server: String, domain: String) async -> Int? {
        let transactionID = UInt16.random(in: UInt16.min...UInt16.max)

        guard let query = buildDNSQuery(domain: domain, transactionID: transactionID) else {
            AppLogger.warning("DNS 查询报文构造失败: \(domain)")
            return nil
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(server),
            port: 53,
            using: .udp
        )

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let resumeLock = NSLock()
                var hasResumed = false

                func finish(_ result: Int?) {
                    resumeLock.lock()
                    defer { resumeLock.unlock() }
                    guard !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(returning: result)
                }

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        let startTime = CFAbsoluteTimeGetCurrent()

                        connection.send(content: query, completion: .contentProcessed { error in
                            guard error == nil else {
                                AppLogger.warning("DNS 查询发送失败: \(domain), 错误: \(error!.localizedDescription)")
                                connection.cancel()
                                finish(nil)
                                return
                            }

                            connection.receiveMessage { data, _, _, error in
                                guard error == nil, let data else {
                                    if let error {
                                        AppLogger.warning("DNS 查询接收失败: \(domain), 错误: \(error.localizedDescription)")
                                    }
                                    connection.cancel()
                                    finish(nil)
                                    return
                                }

                                let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
                                let isValid = Self.validateDNSResponse(
                                    data,
                                    transactionID: transactionID
                                )

                                connection.cancel()
                                finish(isValid ? elapsed : nil)
                            }
                        })

                    case .failed(let error):
                        AppLogger.warning("DNS 连接失败: \(domain), 错误: \(error.localizedDescription)")
                        finish(nil)

                    case .cancelled:
                        finish(nil)

                    case .setup, .preparing, .waiting:
                        break

                    @unknown default:
                        finish(nil)
                    }
                }

                connection.start(queue: .global(qos: .userInitiated))
            }
        } onCancel: {
            connection.cancel()
        }
    }

    /// 构造最小 DNS A Record 查询报文
    nonisolated private static func buildDNSQuery(domain: String, transactionID: UInt16) -> Data? {
        guard let qname = Self.encodeDomainName(domain) else {
            return nil
        }

        var data = Data()
        Self.appendUInt16(transactionID, to: &data)   // ID
        Self.appendUInt16(0x0100, to: &data)          // 标准递归查询
        Self.appendUInt16(1, to: &data)               // QDCOUNT
        Self.appendUInt16(0, to: &data)               // ANCOUNT
        Self.appendUInt16(0, to: &data)               // NSCOUNT
        Self.appendUInt16(0, to: &data)               // ARCOUNT
        data.append(qname)                       // QNAME
        Self.appendUInt16(1, to: &data)               // QTYPE = A
        Self.appendUInt16(1, to: &data)               // QCLASS = IN
        return data
    }

    /// 校验 DNS 响应是否合法，并确认至少返回一个 A Record
    nonisolated private static func validateDNSResponse(_ data: Data, transactionID: UInt16) -> Bool {
        guard data.count >= 12 else { return false }

        let responseID = Self.readUInt16(from: data, at: 0)
        let flags = Self.readUInt16(from: data, at: 2)
        let questionCount = Int(Self.readUInt16(from: data, at: 4))
        let answerCount = Int(Self.readUInt16(from: data, at: 6))
        let responseCode = flags & 0x000F
        let isResponse = (flags & 0x8000) != 0

        guard responseID == transactionID, isResponse, responseCode == 0, questionCount == 1, answerCount > 0 else {
            return false
        }

        var offset = 12

        for _ in 0..<questionCount {
            guard let nextOffset = Self.skipDNSName(in: data, from: offset),
                  nextOffset + 4 <= data.count else {
                return false
            }
            offset = nextOffset + 4
        }

        for _ in 0..<answerCount {
            guard let nextOffset = Self.skipDNSName(in: data, from: offset),
                  nextOffset + 10 <= data.count else {
                return false
            }

            let type = Self.readUInt16(from: data, at: nextOffset)
            let recordClass = Self.readUInt16(from: data, at: nextOffset + 2)
            let dataLength = Int(Self.readUInt16(from: data, at: nextOffset + 8))
            let rdataOffset = nextOffset + 10

            guard rdataOffset + dataLength <= data.count else {
                return false
            }

            if type == 1, recordClass == 1, dataLength == 4 {
                return true
            }

            offset = rdataOffset + dataLength
        }

        return false
    }

    /// 将域名编码为 DNS wire format
    nonisolated private static func encodeDomainName(_ domain: String) -> Data? {
        let normalized = domain.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        guard !normalized.isEmpty else { return nil }

        var data = Data()
        for label in normalized.split(separator: ".", omittingEmptySubsequences: true) {
            let bytes = Array(label.utf8)
            guard !bytes.isEmpty, bytes.count <= 63 else {
                return nil
            }
            data.append(UInt8(bytes.count))
            data.append(contentsOf: bytes)
        }
        data.append(0)
        return data
    }

    nonisolated private static func skipDNSName(in data: Data, from offset: Int) -> Int? {
        var currentOffset = offset

        while currentOffset < data.count {
            let length = data[currentOffset]

            if length == 0 {
                return currentOffset + 1
            }

            if (length & 0xC0) == 0xC0 {
                guard currentOffset + 1 < data.count else { return nil }
                return currentOffset + 2
            }

            let labelLength = Int(length)
            currentOffset += 1

            guard currentOffset + labelLength <= data.count else { return nil }
            currentOffset += labelLength
        }

        return nil
    }

    nonisolated private static func readUInt16(from data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    nonisolated private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    // MARK: - Private Methods - Result Management

    /// 清空测试结果
    private func clearResults() {
        results = []
    }

    /// 添加测试结果
    ///
    /// - Parameter result: 测试结果
    private func addResult(_ result: DNSTestResult) {
        results.append(result)
    }
}
