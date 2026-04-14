//
//  IPDetectionUseCase.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/31.
//  Refactored from IPQualityViewModel.swift - Main IP detection orchestration logic
//

import Foundation

/// IP检测用例 - 主编排层，协调所有UseCase完成完整的IP检测流程
@MainActor
class IPDetectionUseCase {
    private let progressCoordinator: ProgressCoordinator
    private let ipDataFetchingUseCase: IPDataFetchingUseCase
    private let streamingTestUseCase: StreamingTestUseCase
    private let emailTestUseCase: EmailTestUseCase
    private let multiSourceAggregationUseCase: MultiSourceAggregationUseCase

    init(
        progressCoordinator: ProgressCoordinator,
        ipDataFetchingUseCase: IPDataFetchingUseCase,
        streamingTestUseCase: StreamingTestUseCase,
        emailTestUseCase: EmailTestUseCase,
        multiSourceAggregationUseCase: MultiSourceAggregationUseCase
    ) {
        self.progressCoordinator = progressCoordinator
        self.ipDataFetchingUseCase = ipDataFetchingUseCase
        self.streamingTestUseCase = streamingTestUseCase
        self.emailTestUseCase = emailTestUseCase
        self.multiSourceAggregationUseCase = multiSourceAggregationUseCase
    }

    /// 执行完整的IP检测流程
    ///
    /// ## 2026/01/07 重构
    /// - 删除了重复的 API 调用（原 Step 2-4）
    /// - 所有 IP 数据源现在通过 MultiSourceAggregationUseCase 统一调用
    /// - 减少了 API 请求次数，提高了检测效率
    ///
    /// - Returns: 检测结果
    /// - Throws: 检测过程中的错误
    func executeDetection() async throws -> IPQualityResult {
        // Step 1: Get IP Address (5%)
        progressCoordinator.updateTask("获取IP地址...")
        let ip = try await ipDataFetchingUseCase.getIPAddress()
        progressCoordinator.smoothUpdateProgress(to: 0.05)

        var tempResult = IPQualityResult()
        tempResult.ip = ip
        tempResult.ipVersion = ip.contains(":") ? 6 : 4

        // Step 2: 多数据源检测（35%）
        // ✅ 2026/01/07 重构：合并原 Step 2-4 的单独调用
        // 现在 MultiSourceAggregationUseCase 会同时填充基础信息和多数据源对比数据
        progressCoordinator.updateTask("多数据源分析...")
        await multiSourceAggregationUseCase.fetchMultiSourceData(ip: ip, into: &tempResult)
        progressCoordinator.smoothUpdateProgress(to: 0.35)

        // Step 3: Test streaming services (65%)
        progressCoordinator.updateTask("检测流媒体解锁...")
        AppLogger.debug("🔍 开始流媒体并发测试（7个服务）")

        // ✅ 使用 TaskGroup + 超时控制，防止单个任务卡死
        let streamingResults = await withTaskGroup(of: (String, StreamingStatus).self) { group in
            // 为每个流媒体测试设置独立的超时任务
            let services = [
                ("tiktok", { await self.streamingTestUseCase.testTikTok(ip: ip) }),
                ("disney", { await self.streamingTestUseCase.testDisney(ip: ip) }),
                ("netflix", { await self.streamingTestUseCase.testNetflix(ip: ip) }),
                ("youtube", { await self.streamingTestUseCase.testYouTube(ip: ip) }),
                ("amazon", { await self.streamingTestUseCase.testAmazonPrime(ip: ip) }),
                ("spotify", { await self.streamingTestUseCase.testSpotify(ip: ip) }),
                ("chatgpt", { await self.streamingTestUseCase.testChatGPT(ip: ip) })
            ]

            for (name, test) in services {
                group.addTask {
                    AppLogger.debug("▶️ [\(name.uppercased())] 测试开始")
                    let result = await withTimeout(
                        seconds: 15,
                        defaultValue: StreamingStatus(available: false, region: nil, unlockType: nil)
                    ) {
                        await test()
                    }
                    AppLogger.debug("✅ [\(name.uppercased())] 测试完成")
                    return (name, result)
                }
            }

            var results: [String: StreamingStatus] = [:]
            for await (key, status) in group {
                results[key] = status
            }
            AppLogger.debug("🎯 所有流媒体测试完成，共收集 \(results.count)/7 个结果")
            return results
        }

        // 使用默认值避免 Force Unwrap 崩溃
        let defaultStatus = StreamingStatus(available: false, region: nil, unlockType: nil)
        tempResult.tiktok = streamingResults["tiktok"] ?? defaultStatus
        tempResult.disney = streamingResults["disney"] ?? defaultStatus
        tempResult.netflix = streamingResults["netflix"] ?? defaultStatus
        tempResult.youtube = streamingResults["youtube"] ?? defaultStatus
        tempResult.amazonPrime = streamingResults["amazon"] ?? defaultStatus
        tempResult.spotify = streamingResults["spotify"] ?? defaultStatus
        tempResult.chatGPT = streamingResults["chatgpt"] ?? defaultStatus
        progressCoordinator.smoothUpdateProgress(to: 0.65)

        // Step 4: Test email services (80%)
        progressCoordinator.updateTask("检测邮件服务...")
        tempResult.emailStatus = await emailTestUseCase.testEmailServices(ip: ip)
        progressCoordinator.smoothUpdateProgress(to: 0.80)

        // Complete
        tempResult.detectedAt = Date()
        progressCoordinator.smoothUpdateProgress(to: 1.0)
        progressCoordinator.updateTask("检测完成")

        return tempResult
    }
}
